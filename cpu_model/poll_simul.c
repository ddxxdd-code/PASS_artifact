#define _GNU_SOURCE // For pthread_setaffinity_np, CPU_* macros, DT_DIR, syscall

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <signal.h>
#include <unistd.h>
#include <pthread.h>
#include <x86intrin.h>      // for __rdtsc()
#include <sched.h>          // for cpu_set_t, CPU_SET, CPU_ZERO
#include <inttypes.h>       // for PRIu64, SCNu64 (standard integer types)
#include <time.h>           // for clock_gettime, timespec, nanosleep
#include <math.h>           // for ceil, isnan, NAN
#include <string.h>         // for memcpy, strerror, strncmp, memset
#include <stdatomic.h>      // for _Atomic types
#include <sys/time.h>       // for gettimeofday
#include <errno.h>          // for errno
#include <stdbool.h>        // for bool type
#include <dirent.h>         // for directory scanning (opendir, readdir, closedir)
#include <limits.h>         // for PATH_MAX (maximum path length)
#include <sys/types.h>      // For mode_t, pid_t potentially needed by dirent.h/unistd.h
#include <sys/stat.h>       // For stat()
#include <sys/syscall.h>    // For SYS_gettid
#include <fcntl.h>          // For open(), O_WRONLY

// --- Configuration Constants ---
#define RESERVOIR_K 100000              // Size of latency sample reservoir per poller
#define REPORTER_SAMPLE_SIZE_PER_POLLER 5000 // Max samples reporter processes per poller <<< NEW
#define RAPL_BASE_PATH "/sys/class/powercap/" // Base path for RAPL powercap interface
#define TARGET_CGROUP "poller_test"           // Name of the target cgroup

// --- Utility Macros ---
#define MIN(a, b)  (((a) < (b)) ? (a) : (b)) // Minimum of two values
#define MAX(a, b)  (((a) > (b)) ? (a) : (b)) // Maximum of two values
#define NSEC_PER_SEC 1000000000L // Nanoseconds per second
#define USEC_PER_SEC 1000000.0  // Microseconds per second (double)
#define UJ_PER_J     1000000.0  // Microjoules per Joule (double)

// --- Global Variables ---

// Structure to hold context for each poller instance
typedef struct {
    uint64_t  last_ts;                // Last timestamp read by this poller (TSC cycles)
    uint64_t  reservoir[RESERVOIR_K]; // Reservoir for storing latency samples (TSC cycles)
    _Atomic size_t seen;              // Atomic counter for number of samples seen (for reservoir logic)
} PollerCtx;

static PollerCtx *pollers = NULL;           // Array of poller contexts
static volatile sig_atomic_t stop_flag = 0; // Flag to signal threads to stop (set by signal handler)
static int n_pollers = 0;                   // Total number of pollers to run
static int n_cores = 0;                     // Number of CPU cores used for launching pollers

// Structure to hold information about each detected RAPL package/domain
typedef struct {
    char energy_path[PATH_MAX];         // Path to the energy_uj file for this package/domain
    char max_energy_path[PATH_MAX];     // Path to the max_energy_range_uj file
    uint64_t max_energy_uj;             // Max energy value before counter wraps (microjoules)
    uint64_t last_energy_uj;            // Last energy reading for this package/domain (microjoules)
    bool available;                     // Flag indicating if this package/domain is readable
} RaplPackageInfo;

// Structure to pass arguments to each poller thread
struct thread_arg {
    int core_id;        // Target CPU core ID for affinity
    int start_idx;      // Starting index in the global 'pollers' array for this thread
    int count;          // Number of pollers managed by this thread
};

// Structure to pass arguments to the reporter thread
typedef struct {
    int active_cores;       // User-provided active core count (for logging)
    int bandwidth;          // User-provided bandwidth value (for logging)
    int rapl_limit;         // User-provided RAPL limit value (for logging)
    double cycles_per_usec; // Calibrated TSC frequency
} ReporterArgs;


// --- Function Prototypes ---
int cmp_uint64(const void *a, const void *b); // Comparison function for qsort
void signal_handler(int signo);                // Handles SIGINT and SIGALRM
double calibrate_tsc(void);                    // Estimates TSC frequency (returns value)
void *poller_thread(void *arg);                // Poller thread function logic
void *reporter_thread(void *arg);              // Reporter thread function logic
static bool read_uint64_from_file(const char *path, uint64_t *value); // Helper to read RAPL files

// --- Function Implementations ---

int cmp_uint64(const void *a, const void *b) {
    uint64_t arg1 = *(const uint64_t *)a;
    uint64_t arg2 = *(const uint64_t *)b;
    return (arg1 > arg2) - (arg1 < arg2);
}

void signal_handler(int signo) {
    if (signo == SIGINT || signo == SIGALRM) {
        stop_flag = 1;
    }
}

double calibrate_tsc(void) {
    struct timespec start_ts, end_ts;
    uint64_t start_cycles, end_cycles;
    long long elapsed_ns;
    double elapsed_us;
    double local_cycles_per_usec = 0.0;

    if (clock_gettime(CLOCK_MONOTONIC_RAW, &start_ts) == -1) {
         fprintf(stderr, "FATAL: clock_gettime failed in calibrate_tsc\n");
         exit(EXIT_FAILURE);
    }
    start_cycles = __rdtsc();
    struct timespec sleep_duration = {0, 200 * 1000 * 1000}; // 200 ms
    nanosleep(&sleep_duration, NULL);
    end_cycles = __rdtsc();
     if (clock_gettime(CLOCK_MONOTONIC_RAW, &end_ts) == -1) {
         fprintf(stderr, "FATAL: clock_gettime failed in calibrate_tsc\n");
         exit(EXIT_FAILURE);
     }
    elapsed_ns = (end_ts.tv_sec - start_ts.tv_sec) * NSEC_PER_SEC + (end_ts.tv_nsec - start_ts.tv_nsec);
    if (elapsed_ns <= 0) {
        local_cycles_per_usec = 2500.0;
    } else {
        elapsed_us = (double)elapsed_ns / 1000.0;
        uint64_t elapsed_cycles = end_cycles - start_cycles;
        if (elapsed_us > 1.0) {
            local_cycles_per_usec = (double)elapsed_cycles / elapsed_us;
        } else {
            local_cycles_per_usec = 2500.0;
        }
    }
     if (local_cycles_per_usec <= 100.0) {
        fprintf(stderr, "FATAL: TSC calibration resulted in unrealistically low frequency (%.2f MHz).\n", local_cycles_per_usec);
        exit(EXIT_FAILURE);
    }
    return local_cycles_per_usec;
}

void *poller_thread(void *arg) {
    struct thread_arg *t = (struct thread_arg *)arg;
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(t->core_id % sysconf(_SC_NPROCESSORS_CONF), &cpuset);
    pthread_setaffinity_np(pthread_self(), sizeof(cpuset), &cpuset); // Ignore errors for now

    pid_t tid = syscall(SYS_gettid);
    if (tid != -1) {
        char cgroup_procs_path[PATH_MAX];
        snprintf(cgroup_procs_path, sizeof(cgroup_procs_path), "/sys/fs/cgroup/%s/cgroup.procs", TARGET_CGROUP);
        cgroup_procs_path[sizeof(cgroup_procs_path) - 1] = '\0';
        int fd = open(cgroup_procs_path, O_WRONLY);
        if (fd != -1) {
            char tid_str[32];
            int len = snprintf(tid_str, sizeof(tid_str), "%d", tid);
            if (len > 0) write(fd, tid_str, len); // Ignore errors
            close(fd);
        }
    }

    unsigned int seed = time(NULL) ^ (unsigned int)pthread_self();
    for (int i = 0; i < t->count; i++) {
        int poller_index = t->start_idx + i;
        pollers[poller_index].last_ts = __rdtsc();
        atomic_init(&pollers[poller_index].seen, 0);
    }

    int current_poller_offset = 0;
    while (!stop_flag) {
        if (t->count <= 0) break;
        int poller_index = t->start_idx + current_poller_offset;
        uint64_t now   = __rdtsc();
        uint64_t delta = now - pollers[poller_index].last_ts;

        size_t count = atomic_fetch_add_explicit(&pollers[poller_index].seen, 1, memory_order_relaxed);
        if (count < RESERVOIR_K) {
            pollers[poller_index].reservoir[count] = delta;
        } else {
             if (RESERVOIR_K > 0) {
                size_t replace_idx = rand_r(&seed) % RESERVOIR_K;
                pollers[poller_index].reservoir[replace_idx] = delta;
             }
        }
        pollers[poller_index].last_ts = now;
        current_poller_offset = (current_poller_offset + 1) % t->count;
    }
    return NULL;
}

static bool read_uint64_from_file(const char *path, uint64_t *value) {
    FILE *f = fopen(path, "r");
    if (!f) return false;
    if (fscanf(f, "%" SCNu64, value) != 1) { fclose(f); return false; }
    fclose(f);
    return true;
}

/**
 * @brief Reporter thread function. Samples a smaller number of latencies
 * from each poller to calculate statistics faster.
 */
void *reporter_thread(void *arg) {
    ReporterArgs *rargs = (ReporterArgs *)arg;
    double cycles_per_usec_local = rargs->cycles_per_usec;

    // <<< MODIFICATION: Allocate temp buffer for smaller sample size >>>
    uint64_t *temp_reservoir = NULL;
    // Ensure sample size is valid and positive
    #if REPORTER_SAMPLE_SIZE_PER_POLLER <= 0
    #error "REPORTER_SAMPLE_SIZE_PER_POLLER must be positive."
    #endif

    temp_reservoir = malloc(REPORTER_SAMPLE_SIZE_PER_POLLER * sizeof(uint64_t));
    if (!temp_reservoir) {
        fprintf(stderr, "FATAL [Reporter]: Failed to allocate temporary sample buffer (%zu bytes).\n",
                REPORTER_SAMPLE_SIZE_PER_POLLER * sizeof(uint64_t));
        stop_flag = 1; return NULL;
    }

    struct timespec sleep_time = {1, 0};

    // --- RAPL Initialization (Simplified - assumes it works) ---
    RaplPackageInfo *rapl_packages = NULL;
    int num_rapl_packages = 0;
    int rapl_packages_capacity = 0;
    bool any_rapl_available = false;
    struct timespec last_report_time;
    bool first_reading = true;

    DIR *dp = opendir(RAPL_BASE_PATH);
    if (dp) {
        struct dirent *ep;
        while ((ep = readdir(dp))) {
            if (strncmp(ep->d_name, "intel-rapl:", 11) == 0) {
                char full_path[PATH_MAX]; snprintf(full_path, PATH_MAX, "%s%s", RAPL_BASE_PATH, ep->d_name); full_path[PATH_MAX - 1] = '\0';
                struct stat st; if (stat(full_path, &st) != 0 || !S_ISDIR(st.st_mode)) continue;
                if (num_rapl_packages >= rapl_packages_capacity) {
                    rapl_packages_capacity = (rapl_packages_capacity == 0) ? 2 : rapl_packages_capacity * 2;
                    RaplPackageInfo *new_ptr = realloc(rapl_packages, rapl_packages_capacity * sizeof(RaplPackageInfo));
                    if (!new_ptr) { fprintf(stderr, "FATAL [Reporter]: Failed realloc RAPL info.\n"); free(rapl_packages); stop_flag=1; closedir(dp); free(temp_reservoir); return NULL; }
                    rapl_packages = new_ptr;
                }
                int idx = num_rapl_packages; rapl_packages[idx].available = false;
                snprintf(rapl_packages[idx].energy_path, PATH_MAX, "%s%s/energy_uj", RAPL_BASE_PATH, ep->d_name);
                snprintf(rapl_packages[idx].max_energy_path, PATH_MAX, "%s%s/max_energy_range_uj", RAPL_BASE_PATH, ep->d_name);
                rapl_packages[idx].energy_path[PATH_MAX - 1] = '\0'; rapl_packages[idx].max_energy_path[PATH_MAX - 1] = '\0';
                if (read_uint64_from_file(rapl_packages[idx].max_energy_path, &rapl_packages[idx].max_energy_uj) &&
                    read_uint64_from_file(rapl_packages[idx].energy_path, &rapl_packages[idx].last_energy_uj)) {
                    rapl_packages[idx].available = true; any_rapl_available = true; num_rapl_packages++;
                }
            }
        }
        closedir(dp);
        if (any_rapl_available) clock_gettime(CLOCK_MONOTONIC_RAW, &last_report_time); // Ignore error
    }
    // --- End RAPL Init ---

    // --- Main Reporting Loop ---
    while (!stop_flag) {
        nanosleep(&sleep_time, NULL);
        if (stop_flag) break;

        // --- RAPL Power Calculation ---
        struct timespec current_report_time;
        double delta_time_sec = 0.0;
        double total_power_watts = NAN;
        if (any_rapl_available) {
            if(clock_gettime(CLOCK_MONOTONIC_RAW, &current_report_time) == 0) {
                uint64_t total_delta_energy_uj = 0;
                for (int i = 0; i < num_rapl_packages; ++i) {
                    if (!rapl_packages[i].available) continue;
                    uint64_t current_energy_uj;
                    if (!read_uint64_from_file(rapl_packages[i].energy_path, &current_energy_uj)) continue;
                    uint64_t delta_energy_uj = 0;
                    if (current_energy_uj < rapl_packages[i].last_energy_uj) {
                        if (rapl_packages[i].max_energy_uj > 0) delta_energy_uj = (rapl_packages[i].max_energy_uj - rapl_packages[i].last_energy_uj) + current_energy_uj;
                        else delta_energy_uj = current_energy_uj;
                    } else {
                        delta_energy_uj = current_energy_uj - rapl_packages[i].last_energy_uj;
                    }
                    total_delta_energy_uj += delta_energy_uj;
                    rapl_packages[i].last_energy_uj = current_energy_uj;
                }
                if (!first_reading) {
                    delta_time_sec = (current_report_time.tv_sec - last_report_time.tv_sec) + (current_report_time.tv_nsec - last_report_time.tv_nsec) / (double)NSEC_PER_SEC;
                    if (delta_time_sec > 0.001) total_power_watts = (total_delta_energy_uj / UJ_PER_J) / delta_time_sec;
                    else total_power_watts = NAN;
                }
                last_report_time = current_report_time;
            }
        }
        // --- End RAPL ---

        // --- Latency Calculation (Using Sampling) ---
        size_t overall_total_samples = 0;       // Total samples processed this interval
        uint64_t overall_sum_latency_cycles = 0;// Sum based on processed samples
        uint64_t max_p99_latency_cycles = 0;    // Max P99 from processed samples

        if(temp_reservoir != NULL && n_pollers > 0) {
            for (int i = 0; i < n_pollers; ++i) {
                size_t current_seen = atomic_load_explicit(&pollers[i].seen, memory_order_relaxed);
                // Determine how many samples are actually available in the reservoir
                size_t available_samples = MIN(current_seen, RESERVOIR_K);
                // Determine how many samples to actually process (up to the sample size limit)
                size_t count_to_process = MIN(available_samples, REPORTER_SAMPLE_SIZE_PER_POLLER); // <<< USE SAMPLE SIZE

                if (count_to_process > 0) {
                    // Copy only the samples we intend to process into the temporary buffer
                    // We take the first 'count_to_process' samples from the reservoir.
                    // This is simpler than random sampling within the reporter.
                    memcpy(temp_reservoir, pollers[i].reservoir, count_to_process * sizeof(uint64_t)); // <<< Copy smaller amount

                    // Accumulate sum using only the processed samples
                    for (size_t j = 0; j < count_to_process; ++j) {
                        overall_sum_latency_cycles += temp_reservoir[j];
                    }
                    overall_total_samples += count_to_process;

                    // Sort the smaller temporary buffer
                    qsort(temp_reservoir, count_to_process, sizeof(uint64_t), cmp_uint64);

                    // Calculate P99 index based on the number of *processed* samples
                    size_t p99_index = (size_t)ceil(0.99 * count_to_process) - 1;
                    if ((ssize_t)p99_index < 0) p99_index = 0;
                    if (p99_index >= count_to_process) p99_index = count_to_process > 0 ? count_to_process - 1 : 0;

                    if (count_to_process > 0) {
                        uint64_t poller_p99_cycles = temp_reservoir[p99_index];
                        max_p99_latency_cycles = MAX(max_p99_latency_cycles, poller_p99_cycles);
                    }
                }
            } // End loop through pollers
        }

        double avg_latency_us = NAN;
        double p99_latency_us = NAN;

        // Calculate final metrics based on the sampled data
        if (overall_total_samples > 0 && cycles_per_usec_local > 0) {
            avg_latency_us = ((double)overall_sum_latency_cycles / overall_total_samples) / cycles_per_usec_local;
            p99_latency_us = ((double)max_p99_latency_cycles) / cycles_per_usec_local;
        }
        // --- End Latency ---

        // --- Report Results ---
        if (!first_reading) {
            printf("%d %d %d %.2f %.2f %.2f\n",
                   rargs->active_cores,
                   rargs->bandwidth,
                   rargs->rapl_limit,
                   isnan(total_power_watts) ? 0.0 : total_power_watts,
                   isnan(avg_latency_us) ? 0.0 : avg_latency_us, // Avg based on samples
                   isnan(p99_latency_us) ? 0.0 : p99_latency_us); // P99 based on samples
            fflush(stdout);
        }
        first_reading = false;

    } // End while(!stop_flag) reporting loop

    // --- Cleanup within Reporter Thread ---
    free(temp_reservoir);
    free(rapl_packages);
    return NULL;
}


/**
 * @brief Main function: Parses arguments, sets up resources, creates threads,
 * sets timer, waits for completion, and cleans up.
 */
int main(int argc, char **argv) {
    if (argc != 6) {
        fprintf(stderr, "Usage: %s <num_cores> <seconds> <active_cores> <bandwidth> <rapl_limit>\n", argv[0]);
        return EXIT_FAILURE;
    }
    n_cores = atoi(argv[1]);
    int seconds = atoi(argv[2]);
    int active_cores_arg = atoi(argv[3]);
    int bandwidth_arg = atoi(argv[4]);
    int rapl_limit_arg = atoi(argv[5]);

    if (n_cores <= 0 || seconds <= 0) {
        fprintf(stderr, "Error: num_cores and seconds must be positive.\n");
        return EXIT_FAILURE;
    }
    n_pollers = n_cores * 3;

    double cycles_per_usec_calibrated = calibrate_tsc();

    pollers = calloc(n_pollers, sizeof(PollerCtx));
    pthread_t *poller_threads = calloc(n_cores, sizeof(pthread_t));
    struct thread_arg *poller_args = malloc(n_cores * sizeof(struct thread_arg));
    ReporterArgs *reporter_args = malloc(sizeof(ReporterArgs));
    pthread_t reporter_tid = 0;
    if (!pollers || !poller_threads || !poller_args || !reporter_args) {
        fprintf(stderr, "FATAL [Main]: Failed memory allocation.\n");
        free(pollers); free(poller_threads); free(poller_args); free(reporter_args);
        return EXIT_FAILURE;
    }

    reporter_args->active_cores = active_cores_arg;
    reporter_args->bandwidth = bandwidth_arg;
    reporter_args->rapl_limit = rapl_limit_arg;
    reporter_args->cycles_per_usec = cycles_per_usec_calibrated;

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = signal_handler;
    if (sigaction(SIGINT, &sa, NULL) == -1 || sigaction(SIGALRM, &sa, NULL) == -1) {
         fprintf(stderr, "FATAL [Main]: Failed to set signal handlers: %s\n", strerror(errno));
         free(pollers); free(poller_threads); free(poller_args); free(reporter_args);
         return EXIT_FAILURE;
    }

    int base_pollers_per_core = n_pollers / n_cores;
    int extra_pollers = n_pollers % n_cores;
    int current_poller_idx = 0;
    for (int i = 0; i < n_cores; i++) {
        int count_for_this_core = base_pollers_per_core + (i < extra_pollers ? 1 : 0);
        if (count_for_this_core == 0) { poller_threads[i] = 0; continue; }
        poller_args[i].core_id   = i;
        poller_args[i].start_idx = current_poller_idx;
        poller_args[i].count     = count_for_this_core;
        current_poller_idx += count_for_this_core;
        int rc = pthread_create(&poller_threads[i], NULL, poller_thread, &poller_args[i]);
        if (rc != 0) {
             fprintf(stderr, "FATAL [Main]: Failed to create poller thread %d: %s\n", i, strerror(rc));
             stop_flag = 1;
             for(int j = 0; j < i; ++j) if(poller_threads[j] != 0) pthread_join(poller_threads[j], NULL);
             free(pollers); free(poller_threads); free(poller_args); free(reporter_args);
             return EXIT_FAILURE;
        }
    }

    int rc = pthread_create(&reporter_tid, NULL, reporter_thread, reporter_args);
    if (rc != 0) {
        fprintf(stderr, "FATAL [Main]: Failed to create reporter thread: %s\n", strerror(rc));
        stop_flag = 1; reporter_tid = 0;
    }

    if (seconds > 0) alarm(seconds);

    if (reporter_tid != 0) pthread_join(reporter_tid, NULL);
    else while (!stop_flag) sleep(1);
    stop_flag = 1;

    for (int i = 0; i < n_cores; i++) if (poller_threads[i] != 0) pthread_join(poller_threads[i], NULL);

    free(pollers);
    free(poller_threads);
    free(poller_args);
    free(reporter_args);
    return EXIT_SUCCESS;
}
