// Minimal headless Flutter embedder to run `lib/main.dart` without a device.
// Builds against the Flutter engine embedder library (flutter_embedder.h).
// Expect a bundle layout produced by `flutter build bundle` or a desktop build:
// <bundle>/
//   data/flutter_assets/
//   data/icudtl.dat
//   lib/libapp.so               (release/profile AOT)
//
// Run with:
//   ./embeddedFlutterApp /absolute/path/to/bundle
// or set FOO_BUNDLE_PATH to the same directory. The process stays alive until
// SIGINT/SIGTERM (or Ctrl+C on Windows).

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <dlfcn.h>
#include <pthread.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#endif

#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "embedder.h"

#define NSEC_PER_MSEC 1000000ULL
#define NSEC_PER_SEC 1000000000ULL

typedef struct {
  FlutterTask task;
  uint64_t target_time_nanos;
} ScheduledTask;

static ScheduledTask *g_tasks = NULL;
static size_t g_tasks_count = 0;
static size_t g_tasks_capacity = 0;
static FlutterEngine g_engine = NULL;
static FlutterEngineAOTData g_aot_data = NULL;
#ifdef _WIN32
static DWORD g_main_thread_id;
static HANDLE g_shutdown_event = NULL;
#elif defined(__APPLE__)
static void *g_aot_dylib = NULL; // dlopen handle for macOS
static pthread_t g_main_thread;
#else
static pthread_t g_main_thread;
#endif
static volatile sig_atomic_t g_running = 1;

static uint64_t monotonic_time_now_ns(void) {
#ifdef _WIN32
  static LARGE_INTEGER frequency = {0};
  if (frequency.QuadPart == 0) {
    QueryPerformanceFrequency(&frequency);
  }
  LARGE_INTEGER counter;
  QueryPerformanceCounter(&counter);
  return (uint64_t)((counter.QuadPart * NSEC_PER_SEC) / frequency.QuadPart);
#else
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * NSEC_PER_SEC + (uint64_t)ts.tv_nsec;
#endif
}

static bool ensure_capacity(size_t needed) {
  if (needed <= g_tasks_capacity)
    return true;
  size_t new_capacity = g_tasks_capacity == 0 ? 16 : g_tasks_capacity * 2;
  while (new_capacity < needed)
    new_capacity *= 2;
  ScheduledTask *updated =
      (ScheduledTask *)realloc(g_tasks, new_capacity * sizeof(ScheduledTask));
  if (!updated)
    return false;
  g_tasks = updated;
  g_tasks_capacity = new_capacity;
  return true;
}

static void push_task(const FlutterTask *task, uint64_t target_time_nanos) {
  if (!ensure_capacity(g_tasks_count + 1)) {
    fprintf(stderr, "Failed to grow task queue\n");
    return;
  }
  size_t i = g_tasks_count;
  // Insert keeping queue sorted by target time (smallest first).
  while (i > 0 && g_tasks[i - 1].target_time_nanos > target_time_nanos) {
    g_tasks[i] = g_tasks[i - 1];
    --i;
  }
  g_tasks[i].task = *task;
  g_tasks[i].target_time_nanos = target_time_nanos;
  g_tasks_count++;
}

static bool pop_task(ScheduledTask *out) {
  if (g_tasks_count == 0)
    return false;
  *out = g_tasks[0];
  memmove(&g_tasks[0], &g_tasks[1],
          (g_tasks_count - 1) * sizeof(ScheduledTask));
  g_tasks_count--;
  return true;
}

static void sleep_until(uint64_t target_time_nanos) {
  uint64_t now = monotonic_time_now_ns();
  if (target_time_nanos <= now)
    return;
  uint64_t delta = target_time_nanos - now;
#ifdef _WIN32
  DWORD ms = (DWORD)(delta / NSEC_PER_MSEC);
  if (ms > 0) {
    if (g_shutdown_event) {
      WaitForSingleObject(g_shutdown_event, ms);
    } else {
      Sleep(ms);
    }
  }
#else
  struct timespec ts;
  ts.tv_sec = delta / NSEC_PER_SEC;
  ts.tv_nsec = delta % NSEC_PER_SEC;
  nanosleep(&ts, NULL);
#endif
}

static void handle_signal(int signo) {
  (void)signo;
  g_running = 0;
#ifdef _WIN32
  if (g_shutdown_event) {
    SetEvent(g_shutdown_event);
  }
#endif
}

#ifdef _WIN32
static BOOL WINAPI console_handler(DWORD ctrl_type) {
  switch (ctrl_type) {
  case CTRL_C_EVENT:
  case CTRL_BREAK_EVENT:
  case CTRL_CLOSE_EVENT:
  case CTRL_LOGOFF_EVENT:
  case CTRL_SHUTDOWN_EVENT:
    g_running = 0;
    if (g_shutdown_event) {
      SetEvent(g_shutdown_event);
    }
    return TRUE;
  default:
    return FALSE;
  }
}

static void install_signal_handlers(void) {
  if (GetConsoleWindow() == NULL) {
    AttachConsole(ATTACH_PARENT_PROCESS);
  }
  g_shutdown_event = CreateEvent(NULL, TRUE, FALSE, NULL);
  SetConsoleCtrlHandler(console_handler, TRUE);
  HANDLE stdin_handle = GetStdHandle(STD_INPUT_HANDLE);
  if (stdin_handle != INVALID_HANDLE_VALUE) {
    DWORD mode = 0;
    if (GetConsoleMode(stdin_handle, &mode)) {
      SetConsoleMode(stdin_handle, mode | ENABLE_PROCESSED_INPUT);
    }
  }
  signal(SIGINT, handle_signal);
  signal(SIGTERM, handle_signal);
}
#else
static void install_signal_handlers(void) {
  struct sigaction sa;
  memset(&sa, 0, sizeof(sa));
  sa.sa_handler = handle_signal;
  sigaction(SIGINT, &sa, NULL);
  sigaction(SIGTERM, &sa, NULL);
}
#endif

static void log_callback(const char *tag, const char *message,
                         void *user_data) {
  (void)user_data;
  fprintf(stdout, "[%s] %s\n", tag ? tag : "flutter", message ? message : "");
}

// Headless embedder: frames are rendered into a software buffer that we simply
// acknowledge without displaying.
static bool surface_present_callback(void *user_data, const void *allocation,
                                     size_t row_bytes, size_t height) {
  (void)user_data;
  (void)allocation;
  (void)row_bytes;
  (void)height;
  return true;
}

static bool runs_task_on_current_thread(void *user_data) {
  (void)user_data;
#ifdef _WIN32
  return GetCurrentThreadId() == g_main_thread_id;
#else
  return pthread_equal(pthread_self(), g_main_thread);
#endif
}

static void post_flutter_task(FlutterTask task, uint64_t target_time_nanos,
                              void *user_data) {
  (void)user_data;
  push_task(&task, target_time_nanos);
}

static bool file_exists(const char *path) {
  if (!path)
    return false;
#ifdef _WIN32
  DWORD attrib = GetFileAttributesA(path);
  return (attrib != INVALID_FILE_ATTRIBUTES &&
          !(attrib & FILE_ATTRIBUTE_DIRECTORY));
#else
  struct stat st;
  return stat(path, &st) == 0 && !S_ISDIR(st.st_mode);
#endif
}

static bool dir_exists(const char *path) {
  if (!path)
    return false;
#ifdef _WIN32
  DWORD attrib = GetFileAttributesA(path);
  return (attrib != INVALID_FILE_ATTRIBUTES &&
          (attrib & FILE_ATTRIBUTE_DIRECTORY));
#else
  struct stat st;
  return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
#endif
}

static char *join_path(const char *base, const char *suffix) {
  size_t len = strlen(base) + strlen(suffix) + 2;
  char *result = (char *)malloc(len);
  if (!result)
    return NULL;
  snprintf(result, len, "%s/%s", base, suffix);
  return result;
}

static const char *bundle_path_from_args(int argc, char **argv) {
  const char *env_path = getenv("FOO_BUNDLE_PATH");
  if (env_path && env_path[0] != '\0')
    return env_path;
  if (argc > 1)
    return argv[1];
  
  // Return current working directory
  static char cwd[4096];
#ifdef _WIN32
  GetCurrentDirectoryA(sizeof(cwd), cwd);
#else
  getcwd(cwd, sizeof(cwd));
#endif
  return cwd;
}

// Cleanup function to ensure all resources are freed
static void cleanup(char *assets_path, char *icu_path, char *aot_lib_path) {
  // Shutdown Flutter engine if running
  if (g_engine) {
    fprintf(stdout, "Shutting down Flutter engine...\n");
    FlutterEngineShutdown(g_engine);
    g_engine = NULL;
  }

#if defined(__APPLE__)
  if (g_aot_dylib) {
    dlclose(g_aot_dylib);
    g_aot_dylib = NULL;
  }
#else
  // Windows and Linux use ELF-based AOT data
  if (g_aot_data) {
    FlutterEngineCollectAOTData(g_aot_data);
    g_aot_data = NULL;
  }
#endif

  // Free allocated paths
  free(assets_path);
  free(icu_path);
  free(aot_lib_path);
  free(g_tasks);
  g_tasks = NULL;
  g_tasks_count = 0;
  g_tasks_capacity = 0;

#ifdef _WIN32
  if (g_shutdown_event) {
    CloseHandle(g_shutdown_event);
    g_shutdown_event = NULL;
  }
#endif
}

int main(int argc, char **argv) {
  int exit_code = 0;
  char *assets_path = NULL;
  char *icu_path = NULL;
  char *aot_lib_path = NULL;

#ifdef _WIN32
  g_main_thread_id = GetCurrentThreadId();
#else
  g_main_thread = pthread_self();
#endif

  install_signal_handlers();

  const char *bundle_root = bundle_path_from_args(argc, argv);
  assets_path = join_path(bundle_root, "flutter_assets");
  icu_path = join_path(bundle_root, "icudtl.dat");

  // Platform-specific AOT library paths
#ifdef _WIN32
  aot_lib_path = join_path(bundle_root, "app.so");
  if (!file_exists(aot_lib_path)) {
    free(aot_lib_path);
    aot_lib_path = join_path(bundle_root, "libapp.dll");
  }
#elif defined(__APPLE__)
  // Try App.framework first (flutter build output), then libapp.dylib
  aot_lib_path = join_path(bundle_root, "App.framework/Versions/A/App");
  if (!file_exists(aot_lib_path)) {
    free(aot_lib_path);
    aot_lib_path = join_path(bundle_root, "libapp.dylib");
  }
#else
  aot_lib_path = join_path(bundle_root, "libapp.so");
#endif

  if (!dir_exists(assets_path)) {
    fprintf(stderr, "Missing flutter assets at %s\n", assets_path);
    exit_code = 1;
    goto cleanup_and_exit;
  }
  if (!file_exists(icu_path)) {
    fprintf(stderr, "Missing ICU data at %s\n", icu_path);
    exit_code = 1;
    goto cleanup_and_exit;
  }

  bool use_aot = file_exists(aot_lib_path);

  if (!use_aot) {
    fprintf(stderr, "Missing AOT library at %s\n", aot_lib_path);
#ifdef _WIN32
    fprintf(stderr, "Build with: flutter assemble \
      --output=clib/build/windows-x64 \
      -dTargetPlatform=windows-x64 \
      -dBuildMode=release \
      -dTreeShakeIcons=true \
      release_bundle_windows-x64_assets\n");
#elif defined(__APPLE__)
    fprintf(stderr, "Build with: flutter assemble \
      --output=clib/build/macos-arm64 \
      -dTargetPlatform=darwin \
      -dDarwinArchs=arm64 \
      -dBuildMode=release \
      -dTreeShakeIcons=true \
      release_macos_bundle_flutter_assets\n");
#else
    fprintf(stderr, "Build with: flutter assemble \
      --output=clib/build/linux-x64 \
      -dTargetPlatform=linux \
      -dLinuxArchs=x64 \
      -dBuildMode=release \
      -dTreeShakeIcons=true \
      release_linux_bundle_flutter_assets\n");
#endif
    exit_code = 1;
    goto cleanup_and_exit;
  }

  // Snapshot pointers (only needed for macOS which uses dlopen)
#ifdef __APPLE__
  const uint8_t *vm_snapshot_data = NULL;
  const uint8_t *vm_snapshot_instr = NULL;
  const uint8_t *isolate_snapshot_data = NULL;
  const uint8_t *isolate_snapshot_instr = NULL;
#endif

#if defined(_WIN32) || defined(__linux__)
  // Windows and Linux: Use ELF loader
  FlutterEngineAOTDataSource aot_source = {0};
  aot_source.type = kFlutterEngineAOTDataSourceTypeElfPath;
  aot_source.elf_path = aot_lib_path;

  FlutterEngineResult aot_result =
      FlutterEngineCreateAOTData(&aot_source, &g_aot_data);
  if (aot_result != kSuccess) {
    fprintf(stderr, "Failed to create AOT data from %s: %d\n", aot_lib_path,
            aot_result);
    exit_code = 1;
    goto cleanup_and_exit;
  }
  fprintf(stdout, "Loaded AOT library (ELF): %s\n", aot_lib_path);
#elif defined(__APPLE__)
  // macOS: Use dlopen/dlsym to load Mach-O symbols
  g_aot_dylib = dlopen(aot_lib_path, RTLD_NOW | RTLD_LOCAL);
  if (!g_aot_dylib) {
    fprintf(stderr, "Failed to dlopen %s: %s\n", aot_lib_path, dlerror());
    exit_code = 1;
    goto cleanup_and_exit;
  }

  vm_snapshot_data = (const uint8_t *)dlsym(g_aot_dylib, "kDartVmSnapshotData");
  vm_snapshot_instr =
      (const uint8_t *)dlsym(g_aot_dylib, "kDartVmSnapshotInstructions");
  isolate_snapshot_data =
      (const uint8_t *)dlsym(g_aot_dylib, "kDartIsolateSnapshotData");
  isolate_snapshot_instr =
      (const uint8_t *)dlsym(g_aot_dylib, "kDartIsolateSnapshotInstructions");

  if (!vm_snapshot_data || !vm_snapshot_instr || !isolate_snapshot_data ||
      !isolate_snapshot_instr) {
    fprintf(stderr, "Failed to find AOT symbols in %s\n", aot_lib_path);
    fprintf(stderr, "  vm_snapshot_data: %p\n", (void *)vm_snapshot_data);
    fprintf(stderr, "  vm_snapshot_instr: %p\n", (void *)vm_snapshot_instr);
    fprintf(stderr, "  isolate_snapshot_data: %p\n",
            (void *)isolate_snapshot_data);
    fprintf(stderr, "  isolate_snapshot_instr: %p\n",
            (void *)isolate_snapshot_instr);
    exit_code = 1;
    goto cleanup_and_exit;
  }
  fprintf(stdout, "Loaded AOT library (dlopen): %s\n", aot_lib_path);
#endif

  FlutterRendererConfig config = {0};
  config.type = kSoftware;
  config.software.struct_size = sizeof(FlutterSoftwareRendererConfig);
  config.software.surface_present_callback = surface_present_callback;

  FlutterProjectArgs args = {0};
  args.struct_size = sizeof(FlutterProjectArgs);
  args.assets_path = assets_path;
  args.icu_data_path = icu_path;
  args.shutdown_dart_vm_when_done = true;
  args.log_message_callback = log_callback;

#if defined(__APPLE__)
  args.vm_snapshot_data = vm_snapshot_data;
  args.vm_snapshot_instructions = vm_snapshot_instr;
  args.isolate_snapshot_data = isolate_snapshot_data;
  args.isolate_snapshot_instructions = isolate_snapshot_instr;
#else
  // Windows and Linux use ELF-based AOT data
  args.aot_data = g_aot_data;
#endif

  FlutterTaskRunnerDescription platform_task_runner = {0};
  platform_task_runner.struct_size = sizeof(FlutterTaskRunnerDescription);
  platform_task_runner.user_data = NULL;
  platform_task_runner.identifier = 1;
  platform_task_runner.runs_task_on_current_thread_callback =
      runs_task_on_current_thread;
  platform_task_runner.post_task_callback = post_flutter_task;

  FlutterCustomTaskRunners task_runners = {0};
  task_runners.struct_size = sizeof(FlutterCustomTaskRunners);
  task_runners.platform_task_runner = &platform_task_runner;
  args.custom_task_runners = &task_runners;

  FlutterEngineResult result =
      FlutterEngineRun(FLUTTER_ENGINE_VERSION, &config, &args, NULL, &g_engine);
  if (result != kSuccess) {
    fprintf(stderr, "FlutterEngineRun failed: %d\n", result);
    exit_code = 1;
    goto cleanup_and_exit;
  }

  fprintf(stdout, "Flutter engine started. Using bundle: %s\n", bundle_root);

  while (g_running) {
    ScheduledTask task;
    if (!pop_task(&task)) {
      // Idle briefly to avoid a tight loop.
#ifdef _WIN32
      if (g_shutdown_event) {
        WaitForSingleObject(g_shutdown_event, 5);
      } else {
        Sleep(5);
      }
#else
      struct timespec ts = {.tv_sec = 0, .tv_nsec = 5 * NSEC_PER_MSEC};
      nanosleep(&ts, NULL);
#endif
      continue;
    }

    uint64_t now = monotonic_time_now_ns();
    if (task.target_time_nanos > now) {
      sleep_until(task.target_time_nanos);
    }

    FlutterEngineRunTask(g_engine, &task.task);
  }

cleanup_and_exit:
  cleanup(assets_path, icu_path, aot_lib_path);
  return exit_code;
}