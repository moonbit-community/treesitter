// Native helpers for the tree-sitter CLI port: raw (unterminated, binary)
// writes to the C stdio streams that `println` also uses, process exit,
// a monotonic clock and terminal detection.

#include <moonbit.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#include <string.h>
#ifdef _WIN32
#include <io.h>
#include <windows.h>
#define isatty _isatty
#else
#include <unistd.h>
#endif

MOONBIT_FFI_EXPORT
void ts_cli_write(int32_t fd, moonbit_bytes_t data, int32_t offset, int32_t len) {
  FILE *stream = fd == 2 ? stderr : stdout;
  fwrite(data + offset, 1, (size_t)len, stream);
}

MOONBIT_FFI_EXPORT
void ts_cli_flush(void) {
  fflush(stdout);
  fflush(stderr);
}

MOONBIT_FFI_EXPORT
void ts_cli_exit(int32_t code) {
  fflush(stdout);
  fflush(stderr);
  exit(code);
}

MOONBIT_FFI_EXPORT
int64_t ts_cli_now_ns(void) {
#ifdef _WIN32
  LARGE_INTEGER freq, counter;
  QueryPerformanceFrequency(&freq);
  QueryPerformanceCounter(&counter);
  return (int64_t)((double)counter.QuadPart * 1e9 / (double)freq.QuadPart);
#else
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
#endif
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t ts_cli_strerror(int32_t err) {
  const char *s = strerror(err);
  size_t n = strlen(s);
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  memcpy(b, s, n);
  return b;
}

MOONBIT_FFI_EXPORT
int32_t ts_cli_isatty(int32_t fd) {
  return isatty(fd) ? 1 : 0;
}

// ---- Loader cache publication (cli/support/fs_lock.mbt) ----
// `std::process::id()`, used to name the loader's temporary output files.

#ifdef _WIN32
#include <process.h>
#endif

MOONBIT_FFI_EXPORT
int32_t ts_cli_process_id(void) {
#ifdef _WIN32
  return (int32_t)_getpid();
#else
  return (int32_t)getpid();
#endif
}
// `std::env::consts::OS` of the platform the stub was compiled for (the
// loader's `cfg!(target_os = "macos")`).
MOONBIT_FFI_EXPORT
int32_t ts_cli_target_os(void) {
#if defined(__APPLE__)
  return 1;
#elif defined(__linux__)
  return 2;
#elif defined(_WIN32)
  return 3;
#else
  return 0;
#endif
}
// ---- end of loader cache publication block ----
