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
#include <limits.h>         // for PATH_MAX, UINT64_MAX
#include <sys/syscall.h>    // For SYS_gettid
#include <fcntl.h>          // For open(), O_WRONLY
#include <sys/wait.h>       // For system() call status check

// --- Configuration Constants ---
#define RESERVOIR_K 1000000              // Size of latency sample reservoir per poller
#define REPORTER_SAMPLE_SIZE_PER_POLLER 50000 // Max latency samples main thread processes per selected poller (limits memory)
#define RAPL_BASE_PATH "/sys/class/powercap/" // Base path for RAPL powercap interface
#define RAPL_SOCKET_INDEX 0             // Primary socket index to monitor/control
#define POLLER_TARGET_CGROUP "poller_test"      // Target cgroup name for pollers
#define POLLER_TICKS_PER_BURST 10        // Number of busy-wait ticks per poller activation
#define POLLERS_PER_THREAD_CONFIG 3     // Target pollers per *total* core (used to calculate total pollers)
#define EXTERNAL_RAPL_SCRIPT "./init_cgroup_rapl.sh" // Path to the external script

// --- Utility Macros ---
#define MIN(a, b)  (((a) < (b)) ? (a) : (b))
#define MAX(a, b)  (((a) > (b)) ? (a) : (b))
#define NSEC_PER_SEC 1000000000L
#define UJ_PER_J     1000000.0

// --- Data Structures ---
typedef struct {
    uint64_t  last_ts; // Timestamp when this poller last finished running
    uint64_t  reservoir[RESERVOIR_K];
    _Atomic size_t seen;
} PollerCtx;

typedef struct {
    int start_poller_index;     // Index of the first poller this thread manages
    int num_pollers_for_thread; // How many pollers this thread manages
} PollerThreadArgs;

typedef struct {
    char energy_path[PATH_MAX];
    char max_energy_path[PATH_MAX];
    char power_limit_path[PATH_MAX]; // Path to power_limit_uw (kept for init check if needed)
    uint64_t max_energy_uj;
    bool available;           // Is RAPL readable?
    bool limit_settable;      // Is power_limit_uw writable? (kept for info)
} RaplInfo;

// --- Global Variables ---
static PollerCtx *pollers = NULL;
static _Atomic sig_atomic_t stop_flag = 0; // Use atomic for signal safety
static int n_pollers = 0; // Total number of pollers across all threads
static int active_poller_threads = 0; // Number of threads to launch (== active_cores)

// --- Function Implementations ---

// Comparison function for qsort
int cmp_uint64(const void *a, const void *b) {
    uint64_t arg1 = *(const uint64_t *)a;
    uint64_t arg2 = *(const uint64_t *)b;
    return (arg1 > arg2) - (arg1 < arg2);
}

// Signal handler to set the stop flag
void signal_handler(int signo) {
    if (signo == SIGINT || signo == SIGALRM) {
        atomic_store_explicit(&stop_flag, 1, memory_order_relaxed);
    }
}

// Calibrates the Time Stamp Counter (TSC) frequency. Exits on failure.
double calibrate_tsc(void) {
    struct timespec start_ts, end_ts, sleep_duration = {0, 200000000L}; // 200 ms
    uint64_t start_cycles, end_cycles;

    if (clock_gettime(CLOCK_MONOTONIC_RAW, &start_ts) != 0) {
        perror("FATAL calibrate_tsc: clock_gettime start failed");
        exit(EXIT_FAILURE);
    }
    start_cycles = __rdtsc();
    nanosleep(&sleep_duration, NULL);
    end_cycles = __rdtsc();
    if (clock_gettime(CLOCK_MONOTONIC_RAW, &end_ts) != 0) {
        perror("FATAL calibrate_tsc: clock_gettime end failed");
        exit(EXIT_FAILURE);
    }

    long long elapsed_ns = (end_ts.tv_sec - start_ts.tv_sec) * NSEC_PER_SEC + (end_ts.tv_nsec - start_ts.tv_nsec);
    double local_cycles_per_usec = 2500.0; // Fallback

    if (elapsed_ns > 1000L) {
        local_cycles_per_usec = (double)(end_cycles - start_cycles) * 1000.0 / (double)elapsed_ns;
    }
    if (local_cycles_per_usec <= 100.0 || local_cycles_per_usec > 10000.0) {
       fprintf(stderr, "FATAL: TSC calibration resulted in unrealistic frequency (%.2f MHz).\n", local_cycles_per_usec);
       exit(EXIT_FAILURE);
    }
    return local_cycles_per_usec;
}

// Reads a uint64 value from a file. Returns true on success.
static bool read_uint64_from_file(const char *path, uint64_t *value) {
    FILE *f = fopen(path, "r");
    if (!f) return false;
    bool success = (fscanf(f, "%" SCNu64, value) == 1);
    fclose(f);
    return success;
}

// Writes a uint64 value to a file. Returns true on success.
// (Kept in case needed elsewhere, but not used for RAPL limit setting now)
/*
static bool write_uint64_to_file(const char *path, uint64_t value) {
    int fd = open(path, O_WRONLY);
    if (fd == -1) {
        return false;
    }
    char buffer[32];
    int len = snprintf(buffer, sizeof(buffer), "%" PRIu64, value);
    bool success = false;
    if (len > 0 && (size_t)len < sizeof(buffer)) {
        ssize_t written = write(fd, buffer, len);
        success = (written == len);
    }
    close(fd);
    return success;
}
*/

// Attempts to set the RAPL power limit for a given socket.
// (Function definition kept but commented out as it's no longer called)
/*
static bool set_rapl_power_limit_microwatts(const RaplInfo *info, uint64_t limit_uw) {
    if (!info || !info->limit_settable) {
        return false;
    }
    if (!write_uint64_to_file(info->power_limit_path, limit_uw)) {
        fprintf(stderr, "Warning: Failed to write power limit %" PRIu64 " to %s (errno %d: %s)\n",
                limit_uw, info->power_limit_path, errno, strerror(errno));
        return false;
    }
    return true;
}
*/

// Initializes RAPL paths and checks permissions. Does not read start energy.
static bool init_rapl_info(RaplInfo *info, int socket_index) {
    memset(info, 0, sizeof(RaplInfo));
    snprintf(info->energy_path, PATH_MAX, "%sintel-rapl:%d/energy_uj", RAPL_BASE_PATH, socket_index);
    snprintf(info->max_energy_path, PATH_MAX, "%sintel-rapl:%d/max_energy_range_uj", RAPL_BASE_PATH, socket_index);
    snprintf(info->power_limit_path, PATH_MAX, "%sintel-rapl:%d/constraint_0_power_limit_uw", RAPL_BASE_PATH, socket_index);
    info->energy_path[PATH_MAX - 1] = '\0';
    info->max_energy_path[PATH_MAX - 1] = '\0';
    info->power_limit_path[PATH_MAX - 1] = '\0';

    uint64_t dummy_energy;
    info->available = (read_uint64_from_file(info->max_energy_path, &info->max_energy_uj) &&
                       read_uint64_from_file(info->energy_path, &dummy_energy));

    // Check writability of power limit file (for informational purposes)
    int fd_test = open(info->power_limit_path, O_WRONLY);
    if (fd_test != -1) {
        info->limit_settable = true;
        close(fd_test);
    } else {
        info->limit_settable = false;
    }

    return info->available;
}

// Calculates p50/p99 latency across ALL pollers.
static void calculate_latency_stats_all(const PollerCtx *pollers_arr, int num_pollers_total,
                                        double cycles_per_usec, uint64_t *all_samples, size_t max_all_samples_count,
                                        double *p50_us, double *p99_us)
{
    *p50_us = NAN; *p99_us = NAN;
    if (!pollers_arr || !all_samples || num_pollers_total <= 0 || cycles_per_usec <= 0 || max_all_samples_count == 0) return;

    size_t overall_total_samples = 0;

    // Iterate through ALL pollers
    for (int poller_idx = 0; poller_idx < num_pollers_total; ++poller_idx) {
        size_t current_seen = atomic_load_explicit(&pollers_arr[poller_idx].seen, memory_order_acquire);
        size_t count_to_process = MIN(MIN(current_seen, RESERVOIR_K), REPORTER_SAMPLE_SIZE_PER_POLLER);

        if (count_to_process > 0) {
            if (overall_total_samples + count_to_process <= max_all_samples_count) {
                memcpy(all_samples + overall_total_samples, pollers_arr[poller_idx].reservoir, count_to_process * sizeof(uint64_t));
                overall_total_samples += count_to_process;
            } else {
                size_t remaining_space = max_all_samples_count - overall_total_samples;
                if (remaining_space > 0) {
                     memcpy(all_samples + overall_total_samples, pollers_arr[poller_idx].reservoir, remaining_space * sizeof(uint64_t));
                     overall_total_samples += remaining_space;
                }
                fprintf(stderr, "Warning: Latency sample buffer full (%zu samples). Some samples discarded.\n", max_all_samples_count);
                break;
            }
        }
    }

    if (overall_total_samples > 0) {
        qsort(all_samples, overall_total_samples, sizeof(uint64_t), cmp_uint64);

        size_t p50_idx = (overall_total_samples > 1) ? (size_t)floor(0.50 * overall_total_samples) : 0;
        size_t p99_idx = (overall_total_samples > 1) ? (size_t)ceil(0.99 * overall_total_samples) - 1 : 0;
        if (p99_idx >= overall_total_samples) p99_idx = (overall_total_samples > 0) ? overall_total_samples - 1 : 0;

        *p50_us = (double)all_samples[p50_idx] / cycles_per_usec;
        *p99_us = (double)all_samples[p99_idx] / cycles_per_usec;
    }
}

// Moves the calling thread to the specified cgroup (v2 assumed).
static void move_current_thread_to_cgroup(const char *cgroup_name, const char *thread_type) {
    pid_t tid = syscall(SYS_gettid);
    if (tid == -1) {
        fprintf(stderr, "Warning [%s]: Failed to get tid (errno %d)\n", thread_type, errno);
        return;
    }
    char path_buf[PATH_MAX];
    snprintf(path_buf, sizeof(path_buf), "/sys/fs/cgroup/%s/cgroup.threads", cgroup_name);
    path_buf[PATH_MAX - 1] = '\0';

    int fd = open(path_buf, O_WRONLY);
    if (fd != -1) {
        char tid_str[32];
        int tid_len = snprintf(tid_str, sizeof(tid_str), "%d", tid);
        if (tid_len > 0 && (size_t)tid_len < sizeof(tid_str)) {
             ssize_t written = write(fd, tid_str, tid_len);
             if (written != tid_len) {
                fprintf(stderr, "Warning [%s]: Failed write tid %d to %s (written %zd, errno %d: %s)\n",
                        thread_type, tid, path_buf, written, errno, strerror(errno));
             }
        } else {
             fprintf(stderr, "Warning [%s]: Failed to format tid %d\n", thread_type, tid);
        }
        close(fd);
    } else {
         fprintf(stderr, "Warning [%s]: Failed open %s (errno %d: %s)\n",
                 thread_type, path_buf, errno, strerror(errno));
    }
}

// Poller thread: Manages a range of pollers in round-robin.
void *poller_thread(void *arg) {
    PollerThreadArgs *targs = (PollerThreadArgs *)arg;
    move_current_thread_to_cgroup(POLLER_TARGET_CGROUP, "Poller");

    int start_idx = targs->start_poller_index;
    int num_pollers_in_thread = targs->num_pollers_for_thread;
    if (num_pollers_in_thread <= 0) return NULL;

    unsigned int seed = time(NULL) ^ (unsigned int)pthread_self() ^ syscall(SYS_gettid);

    uint64_t initial_ts = __rdtsc();
    for (int i = 0; i < num_pollers_in_thread; ++i) {
        int poller_global_idx = start_idx + i;
        PollerCtx *ctx = &pollers[poller_global_idx];
        ctx->last_ts = initial_ts;
        atomic_init(&ctx->seen, 0);
    }

    int current_poller_offset = 0;

    while (!atomic_load_explicit(&stop_flag, memory_order_relaxed)) {
        int current_poller_idx = start_idx + current_poller_offset;
        PollerCtx *ctx = &pollers[current_poller_idx];

        uint64_t current_start_ts = __rdtsc();
        uint64_t delta = current_start_ts - ctx->last_ts;
        size_t count = atomic_fetch_add_explicit(&ctx->seen, 1, memory_order_relaxed);

        if (count < RESERVOIR_K) {
            ctx->reservoir[count] = delta;
        } else {
            ctx->reservoir[rand_r(&seed) % RESERVOIR_K] = delta;
        }
        ctx->last_ts = current_start_ts;

        for (int tick = 0; tick < POLLER_TICKS_PER_BURST; ++tick) {
            volatile uint64_t dummy_read __attribute__((unused)) = __rdtsc();
        }
        if (atomic_load_explicit(&stop_flag, memory_order_relaxed)) break;

        current_poller_offset = (current_poller_offset + 1) % num_pollers_in_thread;
        if (current_poller_offset == 0) {
             sched_yield();
        }
    }
    return NULL;
}


// Main function: Parses args, sets up threads, waits, calculates, reports, cleans up.
int main(int argc, char **argv) {
    if (argc != 6) {
        fprintf(stderr, "Usage: %s <total_cores> <secs> <active_cores> <bw_lbl> <rapl_lbl>\n", argv[0]);
        // ... usage details ...
        return EXIT_FAILURE;
    }

    // Parse arguments
    int total_cores = atoi(argv[1]);
    int active_cores = atoi(argv[3]);
    int seconds = atoi(argv[2]);
    // int ignored_cores_lbl = atoi(argv[4]);
    int bw_lbl = atoi(argv[4]);
    int rapl_lbl = atoi(argv[5]);


    // Validate arguments
    if (total_cores <= 0 || active_cores <= 0 || active_cores > total_cores || seconds < 0) {
        fprintf(stderr, "Error: Invalid arguments. Requires total_cores > 0, 0 < active_cores <= total_cores, secs >= 0\n");
        return EXIT_FAILURE;
    }

    // Calculate thread/poller counts
    n_pollers = total_cores * POLLERS_PER_THREAD_CONFIG;
    active_poller_threads = active_cores;

    // --- Resource Allocation ---
    pthread_t *poller_tids = NULL;
    PollerThreadArgs *poller_args = NULL;
    int exit_code = EXIT_SUCCESS;
    RaplInfo rapl_info;
    uint64_t start_energy_uj = 0;
    uint64_t final_energy_uj = 0;
    bool start_energy_ok = false;
    bool final_energy_ok = false;
    double cycles_per_usec = 0;
    uint64_t *all_latency_samples = NULL;
    size_t max_latency_samples = 0;

    pollers = calloc(n_pollers, sizeof(PollerCtx));
    poller_tids = calloc(active_poller_threads, sizeof(pthread_t));
    poller_args = malloc(active_poller_threads * sizeof(PollerThreadArgs));

    max_latency_samples = (size_t)n_pollers * REPORTER_SAMPLE_SIZE_PER_POLLER;
    if (n_pollers > 0 && max_latency_samples / n_pollers != REPORTER_SAMPLE_SIZE_PER_POLLER) {
         fprintf(stderr, "FATAL: Potential overflow calculating size for latency sample buffer.\n");
         exit_code = EXIT_FAILURE; goto cleanup_main;
    }
    all_latency_samples = malloc(max_latency_samples * sizeof(uint64_t));


    if (!pollers || !poller_tids || !poller_args || !all_latency_samples) {
        fprintf(stderr, "FATAL: Memory allocation failed.\n");
        exit_code = EXIT_FAILURE; goto cleanup_main;
    }

    // --- Initialization ---
    cycles_per_usec = calibrate_tsc();
    atomic_init(&stop_flag, 0);

    // Setup signal handling
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    if (sigaction(SIGINT, &sa, NULL) == -1 || sigaction(SIGALRM, &sa, NULL) == -1) {
         perror("FATAL: sigaction failed");
         exit_code = EXIT_FAILURE; goto cleanup_main;
    }

    // Initialize RAPL info and read start energy
    if (init_rapl_info(&rapl_info, RAPL_SOCKET_INDEX)) {
        start_energy_ok = read_uint64_from_file(rapl_info.energy_path, &start_energy_uj);
        if (!start_energy_ok) {
            fprintf(stderr, "Warning: Failed to read initial energy from %s\n", rapl_info.energy_path);
        }
    } else {
        fprintf(stderr, "Warning: RAPL interface not available/readable. Power reporting disabled.\n");
    }

    // --- Launch Poller Threads ---
    int base_pollers_per_thread = n_pollers / active_poller_threads;
    int extra_pollers = n_pollers % active_poller_threads;
    int current_poller_start_idx = 0;
    bool poller_launch_failed = false;

    for (int i = 0; i < active_poller_threads; i++) {
        int pollers_for_this_thread = base_pollers_per_thread + (i < extra_pollers ? 1 : 0);
        poller_args[i].start_poller_index = current_poller_start_idx;
        poller_args[i].num_pollers_for_thread = pollers_for_this_thread;

        if (pthread_create(&poller_tids[i], NULL, poller_thread, &poller_args[i]) != 0) {
             fprintf(stderr, "FATAL: Failed to create poller thread %d (errno %d: %s)\n", i, errno, strerror(errno));
             atomic_store_explicit(&stop_flag, 1, memory_order_relaxed);
             exit_code = EXIT_FAILURE;
             poller_tids[i] = 0;
             poller_launch_failed = true;
        }
        current_poller_start_idx += pollers_for_this_thread;
    }

    // --- Wait for Pollers to Run ---
    if (!poller_launch_failed && exit_code == EXIT_SUCCESS) {
        if (seconds > 0) {
            alarm(seconds);
        }
        while (!atomic_load_explicit(&stop_flag, memory_order_relaxed)) {
            pause();
        }
    } else {
        atomic_store_explicit(&stop_flag, 1, memory_order_relaxed);
    }

    // --- Post-Polling Phase ---

    // Read final energy value *immediately*
    if (rapl_info.available) {
        final_energy_ok = read_uint64_from_file(rapl_info.energy_path, &final_energy_uj);
        if (!final_energy_ok) {
            fprintf(stderr, "Warning: Failed to read final energy value from %s\n", rapl_info.energy_path);
        }
    }

    // Join poller threads
    for (int i = 0; i < active_poller_threads; i++) {
        if (poller_tids[i] != 0) {
            pthread_join(poller_tids[i], NULL);
        }
    }
    int ret = system("./rapl_lift.sh");

    // --- Calculate Power ---
    double avg_socket_power_watts = NAN;
    if (start_energy_ok && final_energy_ok) {
        double total_elapsed_sec = (double)seconds;
        if (total_elapsed_sec > 0.001) {
            uint64_t delta_energy_uj = (final_energy_uj >= start_energy_uj) ?
                (final_energy_uj - start_energy_uj) :
                (rapl_info.max_energy_uj - start_energy_uj + final_energy_uj);
            avg_socket_power_watts = (delta_energy_uj / UJ_PER_J) / total_elapsed_sec;
        } else {
             fprintf(stderr, "Warning: Duration %d seconds too short for power calculation.\n", seconds);
        }
    }

    // --- Calculate Latency (using all pollers) ---
    double p50_us = NAN, p99_us = NAN;
    calculate_latency_stats_all(pollers, n_pollers, cycles_per_usec,
                                all_latency_samples, max_latency_samples, &p50_us, &p99_us);


    // --- Final Reporting ---
    printf("%d,%d,%d,%.2f,%.2f,%.2f\n",
           active_cores, // Use active_cores directly
           bw_lbl,
           rapl_lbl,
           isnan(avg_socket_power_watts) ? 0.0 : avg_socket_power_watts,
           isnan(p50_us) ? 0.0 : p50_us,
           isnan(p99_us) ? 0.0 : p99_us);
    fflush(stdout);


cleanup_main:
    // --- Resource Cleanup ---
    free(poller_args);
    free(poller_tids);
    free(pollers);
    free(all_latency_samples); // Free latency sample buffer

    return exit_code;
}
