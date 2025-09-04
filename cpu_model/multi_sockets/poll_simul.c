#define _GNU_SOURCE // For syscall

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <signal.h>
#include <unistd.h>
#include <pthread.h>
#include <x86intrin.h>      // for __rdtsc()
#include <sched.h>          // for sched_yield()
#include <inttypes.h>       // for PRIu64, SCNu64
#include <time.h>           // for clock_gettime, timespec, nanosleep
#include <math.h>           // for ceil, floor, isnan, NAN
#include <string.h>         // for memcpy, strerror, memset
#include <stdatomic.h>      // for _Atomic types
#include <errno.h>          // for errno
#include <stdbool.h>        // for bool type
#include <limits.h>         // for PATH_MAX
#include <sys/syscall.h>    // For SYS_gettid
#include <fcntl.h>          // For open(), O_WRONLY

// --- Configuration Constants ---
#define RESERVOIR_K 1000000              // Size of latency sample reservoir per poller
#define REPORTER_SAMPLE_SIZE_PER_POLLER 5000 // Max latency samples reporter processes per selected poller
#define REPORTER_POLLER_SAMPLE_COUNT 32 // How many pollers to randomly sample each report interval
#define RAPL_BASE_PATH "/sys/class/powercap/" // Base path for RAPL powercap interface
#define RAPL_SOCKET_INDEX 1             // Define socket index to monitor
#define POLLER_TARGET_CGROUP "poller_test"      // Target cgroup name for pollers
#define REPORTER_TARGET_CGROUP "reporter_test"  // Target cgroup name for reporter
#define POLLER_TICKS_PER_BURST 3        // Number of polls before yielding
#define THREADS_PER_CORE 3              // How many threads to launch per core specified
#define POLLERS_PER_THREAD 1            // MUST BE 1 for latency sensitivity

#if POLLERS_PER_THREAD != 1
#error "POLLERS_PER_THREAD must be 1 for latency measurement to be sensitive to scheduling delays."
#endif

// --- Utility Macros ---
#define MIN(a, b)  (((a) < (b)) ? (a) : (b))
#define MAX(a, b)  (((a) > (b)) ? (a) : (b))
#define NSEC_PER_SEC 1000000000L
#define UJ_PER_J     1000000.0

// --- Data Structures ---
typedef struct {
    uint64_t  last_ts;
    uint64_t  reservoir[RESERVOIR_K];
    _Atomic size_t seen;
} PollerCtx;

typedef struct { int poller_idx; } PollerThreadArgs;

typedef struct {
    int active_cores_label, bandwidth_label, rapl_limit_label;
    double cycles_per_usec;
} ReporterArgs;

typedef struct {
    char energy_path[PATH_MAX];
    char max_energy_path[PATH_MAX];
    uint64_t max_energy_uj;
    bool available;
} RaplInfo;

// --- Global Variables ---
static PollerCtx *pollers = NULL;
static volatile sig_atomic_t stop_flag = 0;
static int n_pollers = 0;
static int total_poller_threads = 0;

// --- Function Implementations ---

int cmp_uint64(const void *a, const void *b) {
    uint64_t arg1 = *(const uint64_t *)a;
    uint64_t arg2 = *(const uint64_t *)b;
    return (arg1 > arg2) - (arg1 < arg2);
}

void signal_handler(int signo) {
    if (signo == SIGINT || signo == SIGALRM) { stop_flag = 1; }
}

double calibrate_tsc(void) {
    struct timespec start_ts, end_ts, sleep_duration = {0, 200000000L}; // 200 ms
    uint64_t start_cycles, end_cycles;

    clock_gettime(CLOCK_MONOTONIC_RAW, &start_ts); // Error check removed for brevity
    start_cycles = __rdtsc();
    nanosleep(&sleep_duration, NULL);
    end_cycles = __rdtsc();
    clock_gettime(CLOCK_MONOTONIC_RAW, &end_ts); // Error check removed for brevity

    long long elapsed_ns = (end_ts.tv_sec - start_ts.tv_sec) * NSEC_PER_SEC + (end_ts.tv_nsec - start_ts.tv_nsec);
    double local_cycles_per_usec = 2500.0; // Fallback

    if (elapsed_ns > 1000L) {
        local_cycles_per_usec = (double)(end_cycles - start_cycles) * 1000.0 / (double)elapsed_ns;
    }
    // Fatal error check for unrealistic frequency retained
    if (local_cycles_per_usec <= 100.0 || local_cycles_per_usec > 10000.0) {
       fprintf(stderr, "FATAL: TSC calibration resulted in unrealistic frequency (%.2f MHz).\n", local_cycles_per_usec);
       exit(EXIT_FAILURE);
    }
    return local_cycles_per_usec;
}

static bool read_uint64_from_file(const char *path, uint64_t *value) {
    FILE *f = fopen(path, "r");
    if (!f) return false;
    bool success = (fscanf(f, "%" SCNu64, value) == 1);
    fclose(f);
    return success;
}

static bool init_rapl_info(RaplInfo *info, int socket_index) {
    memset(info, 0, sizeof(RaplInfo));
    snprintf(info->energy_path, PATH_MAX, "%sintel-rapl:%d/energy_uj", RAPL_BASE_PATH, socket_index);
    snprintf(info->max_energy_path, PATH_MAX, "%sintel-rapl:%d/max_energy_range_uj", RAPL_BASE_PATH, socket_index);
    info->energy_path[PATH_MAX - 1] = '\0';
    info->max_energy_path[PATH_MAX - 1] = '\0';

    uint64_t dummy_energy;
    info->available = (read_uint64_from_file(info->max_energy_path, &info->max_energy_uj) &&
                       read_uint64_from_file(info->energy_path, &dummy_energy));
    return info->available;
}

static void calculate_latency_stats_sampled(const PollerCtx *pollers_arr, int num_pollers,
                                            double cycles_per_usec, uint64_t *temp_reservoir,
                                            double *p50_us, double *p99_us)
{
    *p50_us = NAN; *p99_us = NAN;
    if (!pollers_arr || !temp_reservoir || num_pollers <= 0 || cycles_per_usec <= 0) return;

    uint64_t max_p50_latency_cycles = 0;
    uint64_t max_p99_latency_cycles = 0;
    size_t overall_total_samples = 0;
    size_t pollers_to_sample = MIN((size_t)num_pollers, (size_t)REPORTER_POLLER_SAMPLE_COUNT);
    if (pollers_to_sample == 0) return;

    for (size_t k = 0; k < pollers_to_sample; ++k) {
        int poller_idx = rand() % num_pollers;
        size_t current_seen = atomic_load_explicit(&pollers_arr[poller_idx].seen, memory_order_acquire);
        size_t count_to_process = MIN(MIN(current_seen, RESERVOIR_K), REPORTER_SAMPLE_SIZE_PER_POLLER);

        if (count_to_process > 0) {
            memcpy(temp_reservoir, pollers_arr[poller_idx].reservoir, count_to_process * sizeof(uint64_t));
            qsort(temp_reservoir, count_to_process, sizeof(uint64_t), cmp_uint64);

            size_t p50_idx = (count_to_process > 1) ? (size_t)floor(0.50 * count_to_process) : 0;
            size_t p99_idx = (count_to_process > 1) ? (size_t)ceil(0.99 * count_to_process) - 1 : 0;
            if (p99_idx >= count_to_process) p99_idx = (count_to_process > 0) ? count_to_process - 1 : 0;

            max_p50_latency_cycles = MAX(max_p50_latency_cycles, temp_reservoir[p50_idx]);
            max_p99_latency_cycles = MAX(max_p99_latency_cycles, temp_reservoir[p99_idx]);
            overall_total_samples += count_to_process;
        }
    }

    if (overall_total_samples > 0) {
        *p50_us = (double)max_p50_latency_cycles / cycles_per_usec;
        *p99_us = (double)max_p99_latency_cycles / cycles_per_usec;
    }
}

// Moves thread to cgroup using cgroup.threads (cgroup v2 threaded mode assumed)
static void move_current_thread_to_cgroup(const char *cgroup_name, const char *thread_type) {
    pid_t tid = syscall(SYS_gettid);
    if (tid == -1) return; // Fail silently

    char path_buf[PATH_MAX];
    char tid_str[32];
    int tid_len = snprintf(tid_str, sizeof(tid_str), "%d", tid);
    if (tid_len <= 0 || (size_t)tid_len >= sizeof(tid_str)) return; // Fail silently

    snprintf(path_buf, sizeof(path_buf), "/sys/fs/cgroup/%s/cgroup.threads", cgroup_name);
    path_buf[PATH_MAX - 1] = '\0'; // Ensure null termination

    int fd = open(path_buf, O_WRONLY);
    if (fd != -1) {
        ssize_t written = write(fd, tid_str, tid_len);
        close(fd);
        if (written != tid_len) {
             fprintf(stderr, "Warning [%s]: Failed write to %s (errno %d)\n", thread_type, path_buf, errno);
        }
    } else {
         fprintf(stderr, "Warning [%s]: Failed open %s (errno %d)\n", thread_type, path_buf, errno);
    }
}

void *poller_thread(void *arg) {
    PollerThreadArgs *t = (PollerThreadArgs *)arg;
    move_current_thread_to_cgroup(POLLER_TARGET_CGROUP, "Poller");

    unsigned int seed = time(NULL) ^ (unsigned int)pthread_self() ^ syscall(SYS_gettid);
    PollerCtx *ctx = &pollers[t->poller_idx]; // Use pointer for slightly cleaner access
    ctx->last_ts = __rdtsc();
    atomic_init(&ctx->seen, 0);

    while (!stop_flag) {
        uint64_t burst_start_ts = __rdtsc();
        uint64_t delta = burst_start_ts - ctx->last_ts;
        size_t count = atomic_fetch_add_explicit(&ctx->seen, 1, memory_order_relaxed);

        if (count < RESERVOIR_K) {
            ctx->reservoir[count] = delta;
        } else {
            ctx->reservoir[rand_r(&seed) % RESERVOIR_K] = delta;
        }
        ctx->last_ts = burst_start_ts;

        for (int tick = 0; tick < POLLER_TICKS_PER_BURST; ++tick) {
            if (stop_flag) break;
            __sync_synchronize(); // Memory barrier
            volatile uint64_t dummy_read __attribute__((unused)) = __rdtsc(); // Prevent optimizing out
        }
        if (stop_flag) break;
        sched_yield();
    }
    return NULL;
}

void *reporter_thread(void *arg) {
    move_current_thread_to_cgroup(REPORTER_TARGET_CGROUP, "Reporter");

    ReporterArgs *rargs = (ReporterArgs *)arg;
    uint64_t *temp_reservoir = malloc(REPORTER_SAMPLE_SIZE_PER_POLLER * sizeof(uint64_t));
    if (!temp_reservoir) {
        fprintf(stderr, "FATAL [Reporter]: Failed temp_reservoir allocation.\n");
        stop_flag = 1; return NULL;
    }

    RaplInfo rapl_info;
    struct timespec start_time = {0,0}, end_time = {0,0};
    uint64_t start_energy_uj = 0, end_energy_uj = 0;
    double avg_socket_power_watts = NAN;
    double p50_us = NAN, p99_us = NAN;

    init_rapl_info(&rapl_info, RAPL_SOCKET_INDEX);
    srand(time(NULL) ^ syscall(SYS_gettid));

    // Get initial RAPL state only if available
    if (rapl_info.available && (clock_gettime(CLOCK_MONOTONIC_RAW, &start_time) != 0 ||
        !read_uint64_from_file(rapl_info.energy_path, &start_energy_uj))) {
        fprintf(stderr, "Warning [Reporter]: Failed initial RAPL read. Power reporting disabled.\n");
        rapl_info.available = false;
    }

    // Wait for stop_flag
    struct timespec wait_sleep = {0, 100000000L}; // 100ms
    while (!stop_flag) { nanosleep(&wait_sleep, NULL); }

    // Calculate power if possible
    if (rapl_info.available && clock_gettime(CLOCK_MONOTONIC_RAW, &end_time) == 0 &&
        read_uint64_from_file(rapl_info.energy_path, &end_energy_uj))
    {
        double total_elapsed_sec = (end_time.tv_sec - start_time.tv_sec) + (end_time.tv_nsec - start_time.tv_nsec) / (double)NSEC_PER_SEC;
        if (total_elapsed_sec > 0.001) {
            uint64_t delta_energy_uj = (end_energy_uj >= start_energy_uj) ?
                (end_energy_uj - start_energy_uj) :
                (rapl_info.max_energy_uj - start_energy_uj + end_energy_uj); // Handle wrap-around
            avg_socket_power_watts = (delta_energy_uj / UJ_PER_J) / total_elapsed_sec;
        } // else: duration too short, power remains NAN
    } // else: failed final read or clock error, power remains NAN

    // Calculate latency
    calculate_latency_stats_sampled(pollers, n_pollers, rargs->cycles_per_usec,
                                    temp_reservoir, &p50_us, &p99_us);

    // Final output
    printf("%d,%d,%d,%.2f,%.2f,%.2f\n",
           rargs->active_cores_label, rargs->bandwidth_label, rargs->rapl_limit_label,
           isnan(avg_socket_power_watts) ? 0.0 : avg_socket_power_watts,
           isnan(p50_us) ? 0.0 : p50_us,
           isnan(p99_us) ? 0.0 : p99_us);
    fflush(stdout);

    free(temp_reservoir);
    return NULL;
}

int main(int argc, char **argv) {
    if (argc != 6) {
        fprintf(stderr, "Usage: %s <cores> <secs> <cores_lbl> <bw_lbl> <rapl_lbl>\n", argv[0]);
        return EXIT_FAILURE;
    }

    int num_cores = atoi(argv[1]);
    int seconds = atoi(argv[2]);
    if (num_cores <= 0 || seconds < 0) {
        fprintf(stderr, "Error: cores > 0, secs >= 0\n");
        return EXIT_FAILURE;
    }
    total_poller_threads = num_cores * THREADS_PER_CORE;
    n_pollers = total_poller_threads * POLLERS_PER_THREAD;

    pthread_t *poller_tids = NULL;
    PollerThreadArgs *poller_args = NULL;
    ReporterArgs *reporter_args = NULL;
    pthread_t reporter_tid = 0;
    int exit_code = EXIT_SUCCESS;

    pollers = calloc(n_pollers, sizeof(PollerCtx));
    poller_tids = calloc(total_poller_threads, sizeof(pthread_t));
    poller_args = malloc(total_poller_threads * sizeof(PollerThreadArgs));
    reporter_args = malloc(sizeof(ReporterArgs));

    if (!pollers || !poller_tids || !poller_args || !reporter_args) {
        fprintf(stderr, "FATAL: Memory allocation failed.\n");
        exit_code = EXIT_FAILURE; goto cleanup_main; // Skip cleanup of already failed allocations
    }

    reporter_args->active_cores_label = atoi(argv[3]);
    reporter_args->bandwidth_label = atoi(argv[4]);
    reporter_args->rapl_limit_label = atoi(argv[5]);
    reporter_args->cycles_per_usec = calibrate_tsc();

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = signal_handler;
    sigaction(SIGINT, &sa, NULL); // Error check removed for brevity
    sigaction(SIGALRM, &sa, NULL); // Error check removed for brevity

    // Launch Reporter
    if (pthread_create(&reporter_tid, NULL, reporter_thread, reporter_args) != 0) {
        fprintf(stderr, "FATAL: Failed to create reporter thread\n");
        stop_flag = 1; exit_code = EXIT_FAILURE; // Fall through to join pollers
    }

    // Launch Pollers
    for (int i = 0; i < total_poller_threads; i++) {
        poller_args[i].poller_idx = i;
        if (pthread_create(&poller_tids[i], NULL, poller_thread, &poller_args[i]) != 0) {
             fprintf(stderr, "FATAL: Failed to create poller thread %d\n", i);
             stop_flag = 1; exit_code = EXIT_FAILURE; goto join_threads; // Go join already created threads
        }
    }


    // Wait for completion
    if (exit_code == EXIT_SUCCESS) {
        if (seconds > 0) alarm(seconds);
        if (reporter_tid != 0) pthread_join(reporter_tid, NULL); // Wait for reporter (which waits for signal/alarm)
        stop_flag = 1; // Ensure flag is set after reporter finishes
    }

join_threads:
    stop_flag = 1; // Ensure flag is set
    for (int i = 0; i < total_poller_threads; i++) {
        if (poller_tids[i] != 0) pthread_join(poller_tids[i], NULL);
    }

cleanup_main:
    free(reporter_args);
    free(poller_args);
    free(poller_tids);
    free(pollers);
    return exit_code;
}
