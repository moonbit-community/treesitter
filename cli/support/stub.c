// Native helpers for the tree-sitter CLI port: raw (unbuffered, binary)
// writes to file descriptors with Rust's `std::io` error reporting, process
// exit, a monotonic clock, terminal detection, sequential file reads
// (`std::fs::read`), the account-database home directory
// (`std::env::home_dir`), the OS thread id shown in panic messages and the
// macOS default-browser launch of `webbrowser`.

#include <moonbit.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#include <string.h>
#include <errno.h>
#ifdef _WIN32
#include <io.h>
#include <windows.h>
#define isatty _isatty
#else
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <pthread.h>
#include <sys/stat.h>
#include <sys/wait.h>
#ifdef __linux__
#include <sys/syscall.h>
#endif
#endif
#ifdef __APPLE__
#include <dlfcn.h>
#endif

// Write all of `data[offset..offset+len]` to `fd` (`write_all` over a raw
// file descriptor). Returns 0 on success, the `errno` of the failing write,
// or -1 when a write wrote nothing (`ErrorKind::WriteZero`). As Rust's
// `StdoutRaw`/`StderrRaw` do, a closed standard stream (`EBADF`) swallows
// the output. C stdio output of the same stream (MoonBit's `println`) is
// flushed first so that both kinds of output stay in order.
MOONBIT_FFI_EXPORT
int32_t ts_cli_write(int32_t fd, moonbit_bytes_t data, int32_t offset, int32_t len) {
  if (fd == 1) {
    fflush(stdout);
  } else if (fd == 2) {
    fflush(stderr);
  }
  const char *p = (const char *)data + offset;
  size_t remaining = (size_t)len;
  while (remaining > 0) {
#ifdef _WIN32
    int n = _write(fd, p, (unsigned int)remaining);
#else
    ssize_t n = write(fd, p, remaining);
#endif
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      if (errno == EBADF && (fd == 1 || fd == 2)) {
        return 0;
      }
      return errno;
    }
    if (n == 0) {
      return -1;
    }
    p += n;
    remaining -= (size_t)n;
  }
  return 0;
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

static moonbit_bytes_t ts_cli_bytes_of(const char *s, size_t n) {
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  memcpy(b, s, n);
  return b;
}

// The name of the `std::io::ErrorKind` of an OS error code
// (`std::sys::pal::unix::decode_error_kind`).
MOONBIT_FFI_EXPORT
moonbit_bytes_t ts_cli_errno_kind(int32_t err) {
  const char *kind = "Uncategorized";
  switch (err) {
#ifdef E2BIG
  case E2BIG: kind = "ArgumentListTooLong"; break;
#endif
#ifdef EADDRINUSE
  case EADDRINUSE: kind = "AddrInUse"; break;
#endif
#ifdef EADDRNOTAVAIL
  case EADDRNOTAVAIL: kind = "AddrNotAvailable"; break;
#endif
#ifdef EBUSY
  case EBUSY: kind = "ResourceBusy"; break;
#endif
#ifdef ECONNABORTED
  case ECONNABORTED: kind = "ConnectionAborted"; break;
#endif
#ifdef ECONNREFUSED
  case ECONNREFUSED: kind = "ConnectionRefused"; break;
#endif
#ifdef ECONNRESET
  case ECONNRESET: kind = "ConnectionReset"; break;
#endif
#ifdef EDEADLK
  case EDEADLK: kind = "Deadlock"; break;
#endif
#ifdef EDQUOT
  case EDQUOT: kind = "QuotaExceeded"; break;
#endif
#ifdef EEXIST
  case EEXIST: kind = "AlreadyExists"; break;
#endif
#ifdef EFBIG
  case EFBIG: kind = "FileTooLarge"; break;
#endif
#ifdef EHOSTUNREACH
  case EHOSTUNREACH: kind = "HostUnreachable"; break;
#endif
#ifdef EINTR
  case EINTR: kind = "Interrupted"; break;
#endif
#ifdef EINVAL
  case EINVAL: kind = "InvalidInput"; break;
#endif
#ifdef EISDIR
  case EISDIR: kind = "IsADirectory"; break;
#endif
#ifdef ELOOP
  case ELOOP: kind = "FilesystemLoop"; break;
#endif
#ifdef ENOENT
  case ENOENT: kind = "NotFound"; break;
#endif
#ifdef ENOMEM
  case ENOMEM: kind = "OutOfMemory"; break;
#endif
#ifdef ENOSPC
  case ENOSPC: kind = "StorageFull"; break;
#endif
#ifdef ENOSYS
  case ENOSYS: kind = "Unsupported"; break;
#endif
#ifdef EMLINK
  case EMLINK: kind = "TooManyLinks"; break;
#endif
#ifdef ENAMETOOLONG
  case ENAMETOOLONG: kind = "InvalidFilename"; break;
#endif
#ifdef ENETDOWN
  case ENETDOWN: kind = "NetworkDown"; break;
#endif
#ifdef ENETUNREACH
  case ENETUNREACH: kind = "NetworkUnreachable"; break;
#endif
#ifdef ENOTCONN
  case ENOTCONN: kind = "NotConnected"; break;
#endif
#ifdef ENOTDIR
  case ENOTDIR: kind = "NotADirectory"; break;
#endif
#ifdef ENOTEMPTY
  case ENOTEMPTY: kind = "DirectoryNotEmpty"; break;
#endif
#ifdef EPIPE
  case EPIPE: kind = "BrokenPipe"; break;
#endif
#ifdef EROFS
  case EROFS: kind = "ReadOnlyFilesystem"; break;
#endif
#ifdef ESPIPE
  case ESPIPE: kind = "NotSeekable"; break;
#endif
#ifdef ESTALE
  case ESTALE: kind = "StaleNetworkFileHandle"; break;
#endif
#ifdef ETIMEDOUT
  case ETIMEDOUT: kind = "TimedOut"; break;
#endif
#ifdef ETXTBSY
  case ETXTBSY: kind = "ExecutableFileBusy"; break;
#endif
#ifdef EXDEV
  case EXDEV: kind = "CrossesDevices"; break;
#endif
#ifdef EINPROGRESS
  case EINPROGRESS: kind = "InProgress"; break;
#endif
#ifdef EACCES
  case EACCES: kind = "PermissionDenied"; break;
#endif
#ifdef EPERM
  case EPERM: kind = "PermissionDenied"; break;
#endif
  default:
#if defined(EAGAIN)
    if (err == EAGAIN) {
      kind = "WouldBlock";
    }
#endif
#if defined(EWOULDBLOCK)
    if (err == EWOULDBLOCK) {
      kind = "WouldBlock";
    }
#endif
    break;
  }
  return ts_cli_bytes_of(kind, strlen(kind));
}

MOONBIT_FFI_EXPORT
int32_t ts_cli_epipe(void) {
#ifdef EPIPE
  return EPIPE;
#else
  return 32;
#endif
}

// Rust ignores `SIGPIPE` before `main` runs, so that writes to a closed
// pipe fail with `EPIPE` instead of killing the process.
MOONBIT_FFI_EXPORT
void ts_cli_ignore_sigpipe(void) {
#ifndef _WIN32
  signal(SIGPIPE, SIG_IGN);
#endif
}

// The OS id of the calling thread, as Rust prints it in panic messages
// (`thread 'main' (<id>) panicked at ...`).
MOONBIT_FFI_EXPORT
uint64_t ts_cli_thread_id(void) {
#if defined(__APPLE__)
  uint64_t tid = 0;
  pthread_threadid_np(NULL, &tid);
  return tid;
#elif defined(__linux__)
  return (uint64_t)syscall(SYS_gettid);
#elif defined(_WIN32)
  return (uint64_t)GetCurrentThreadId();
#else
  return 0;
#endif
}

static int32_t ts_cli_read_errno = 0;

// `std::fs::read`: open the file and read it sequentially until end of
// file, so that pipes and character devices (`/dev/null`) work like regular
// files. On failure the result is empty and `ts_cli_read_error` returns the
// `errno`.
MOONBIT_FFI_EXPORT
moonbit_bytes_t ts_cli_read_file(moonbit_bytes_t path) {
  ts_cli_read_errno = 0;
#ifdef _WIN32
  int fd = _open((const char *)path, _O_RDONLY | _O_BINARY);
#else
  int fd;
  do {
    fd = open((const char *)path, O_RDONLY | O_CLOEXEC);
  } while (fd < 0 && errno == EINTR);
#endif
  if (fd < 0) {
    ts_cli_read_errno = errno;
    return moonbit_make_bytes(0, 0);
  }
  size_t cap = 8192;
#ifndef _WIN32
  struct stat st;
  if (fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 0) {
    cap = (size_t)st.st_size + 1;
  }
#endif
  char *buf = malloc(cap);
  size_t len = 0;
  for (;;) {
    if (len == cap) {
      cap *= 2;
      char *grown = realloc(buf, cap);
      if (!grown) {
        free(buf);
        close(fd);
        ts_cli_read_errno = ENOMEM;
        return moonbit_make_bytes(0, 0);
      }
      buf = grown;
    }
#ifdef _WIN32
    int n = _read(fd, buf + len, (unsigned int)(cap - len));
#else
    ssize_t n = read(fd, buf + len, cap - len);
#endif
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      ts_cli_read_errno = errno;
      free(buf);
      close(fd);
      return moonbit_make_bytes(0, 0);
    }
    if (n == 0) {
      break;
    }
    len += (size_t)n;
  }
  close(fd);
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)len, 0);
  memcpy(result, buf, len);
  free(buf);
  return result;
}

MOONBIT_FFI_EXPORT
int32_t ts_cli_read_error(void) {
  return ts_cli_read_errno;
}

// `std::env::current_dir`: `getcwd` with a growing buffer. On failure the
// result is empty and `ts_cli_read_error` returns the `errno`.
MOONBIT_FFI_EXPORT
moonbit_bytes_t ts_cli_getcwd(void) {
  ts_cli_read_errno = 0;
#ifndef _WIN32
  size_t cap = 512;
  for (;;) {
    char *buf = (char *)malloc(cap);
    if (buf == NULL) {
      ts_cli_read_errno = ENOMEM;
      break;
    }
    if (getcwd(buf, cap) != NULL) {
      size_t len = strlen(buf);
      moonbit_bytes_t result = moonbit_make_bytes((int32_t)len, 0);
      memcpy(result, buf, len);
      free(buf);
      return result;
    }
    int err = errno;
    free(buf);
    if (err != ERANGE) {
      ts_cli_read_errno = err;
      break;
    }
    cap *= 2;
  }
#else
  ts_cli_read_errno = ENOSYS;
#endif
  return moonbit_make_bytes(0, 0);
}

// Write all bytes to a (possibly non-blocking) file descriptor, waiting
// until it is writable. Errors are ignored, as tree-sitter ignores errors of
// the stream its dot graphs are written to.
MOONBIT_FFI_EXPORT
void ts_cli_write_fd_blocking(int32_t fd, moonbit_bytes_t data, int32_t offset, int32_t len) {
#ifndef _WIN32
  const char *p = (const char *)data + offset;
  size_t remaining = (size_t)len;
  while (remaining > 0) {
    ssize_t n = write(fd, p, remaining);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        struct pollfd pfd = {fd, POLLOUT, 0};
        poll(&pfd, 1, -1);
        continue;
      }
      return;
    }
    p += n;
    remaining -= (size_t)n;
  }
#else
  (void)fd;
  (void)data;
  (void)offset;
  (void)len;
#endif
}

// Clear `O_NONBLOCK` on `fd` (the child's end of a pipe, which Rust's
// `Stdio::piped()` leaves blocking). Returns 0 or the `errno` of `fcntl`.
MOONBIT_FFI_EXPORT
int32_t ts_cli_set_blocking(int32_t fd) {
#ifndef _WIN32
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0 || fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) < 0) {
    return errno;
  }
#else
  (void)fd;
#endif
  return 0;
}

// The home directory of the current user in the account database
// (`getpwuid_r(getuid())`, the fallback of `std::env::home_dir`). The first
// byte of the result is 1 when the directory was found.
MOONBIT_FFI_EXPORT
moonbit_bytes_t ts_cli_passwd_home(void) {
#ifndef _WIN32
  long amt = sysconf(_SC_GETPW_R_SIZE_MAX);
  size_t size = amt < 0 ? 512 : (size_t)amt;
  char *buf = malloc(size);
  struct passwd pwd;
  struct passwd *result = NULL;
  int r = getpwuid_r(getuid(), &pwd, buf, size, &result);
  if (r == 0 && result != NULL && result->pw_dir != NULL) {
    size_t n = strlen(result->pw_dir);
    moonbit_bytes_t b = moonbit_make_bytes((int32_t)n + 1, 1);
    memcpy(b + 1, result->pw_dir, n);
    free(buf);
    return b;
  }
  free(buf);
#endif
  return moonbit_make_bytes(1, 0);
}

// Whether `path` (NUL-terminated) is a regular file with an execute bit
// (`metadata.is_file() && metadata.permissions().mode() & 0o111 != 0`).
MOONBIT_FFI_EXPORT
int32_t ts_cli_is_executable_file(moonbit_bytes_t path) {
#ifndef _WIN32
  struct stat st;
  if (stat((const char *)path, &st) != 0) {
    return 0;
  }
  return S_ISREG(st.st_mode) && (st.st_mode & 0111) != 0;
#else
  (void)path;
  return 0;
#endif
}

// `webbrowser::open` on macOS: open `url` (NUL-terminated) with the
// application that handles `https://` URLs (falling back to Safari) through
// Launch Services, which `NSWorkspace` wraps. The frameworks are loaded at
// run time so that the executable does not link against them.
//
// Results: 0 = launched; 1 = browser not found; 2 = the URL could not be
// created; 3 = the launch failed (`ts_cli_macos_open_status` is the
// `OSStatus`, `ts_cli_macos_open_message` its description); 4 = Launch
// Services is not available. 16 is added when the default browser could
// not be determined and Safari was used instead.
static int32_t ts_cli_open_status = 0;
static char *ts_cli_open_message = NULL;

MOONBIT_FFI_EXPORT
int32_t ts_cli_macos_open(moonbit_bytes_t url) {
#ifdef __APPLE__
  typedef const void *CFTypeRef;
  typedef const void *CFAllocatorRef;
  typedef const void *CFURLRef;
  typedef const void *CFArrayRef;
  typedef const void *CFStringRef;
  typedef const void *CFErrorRef;
  typedef long CFIndex;
  typedef struct {
    CFIndex version;
    const void *retain;
    const void *release;
    const void *copyDescription;
    const void *equal;
  } CFArrayCallBacks;
#pragma pack(push, 2)
  typedef struct {
    CFURLRef appURL;
    CFArrayRef itemURLs;
    const void *passThruParams;
    uint32_t launchFlags;
    void *asyncRefCon;
  } LSLaunchURLSpec;
#pragma pack(pop)
  const uint32_t kCFStringEncodingUTF8 = 0x08000100;
  const uint32_t kLSRolesAll = 0xFFFFFFFF;

  static void *cf = NULL;
  static void *cs = NULL;
  if (!cf) {
    cf = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_LAZY);
  }
  if (!cs) {
    cs = dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY);
  }
  if (!cf || !cs) {
    return 4;
  }
  CFURLRef (*CFURLCreateWithBytes)(CFAllocatorRef, const uint8_t *, CFIndex, uint32_t, CFURLRef) =
    dlsym(cf, "CFURLCreateWithBytes");
  CFArrayRef (*CFArrayCreate)(CFAllocatorRef, const void **, CFIndex, const CFArrayCallBacks *) =
    dlsym(cf, "CFArrayCreate");
  const void *(*CFArrayGetValueAtIndex)(CFArrayRef, CFIndex) = dlsym(cf, "CFArrayGetValueAtIndex");
  CFIndex (*CFArrayGetCount)(CFArrayRef) = dlsym(cf, "CFArrayGetCount");
  CFStringRef (*CFStringCreateWithCString)(CFAllocatorRef, const char *, uint32_t) =
    dlsym(cf, "CFStringCreateWithCString");
  CFTypeRef (*CFRetain)(CFTypeRef) = dlsym(cf, "CFRetain");
  void (*CFRelease)(CFTypeRef) = dlsym(cf, "CFRelease");
  CFErrorRef (*CFErrorCreate)(CFAllocatorRef, CFStringRef, CFIndex, const void *) =
    dlsym(cf, "CFErrorCreate");
  CFStringRef (*CFErrorCopyDescription)(CFErrorRef) = dlsym(cf, "CFErrorCopyDescription");
  CFIndex (*CFStringGetLength)(CFStringRef) = dlsym(cf, "CFStringGetLength");
  CFIndex (*CFStringGetMaximumSizeForEncoding)(CFIndex, uint32_t) =
    dlsym(cf, "CFStringGetMaximumSizeForEncoding");
  unsigned char (*CFStringGetCString)(CFStringRef, char *, CFIndex, uint32_t) =
    dlsym(cf, "CFStringGetCString");
  const CFArrayCallBacks *kCFTypeArrayCallBacks = dlsym(cf, "kCFTypeArrayCallBacks");
  const CFStringRef *kCFErrorDomainOSStatus = dlsym(cf, "kCFErrorDomainOSStatus");
  CFURLRef (*LSCopyDefaultApplicationURLForURL)(CFURLRef, uint32_t, CFErrorRef *) =
    dlsym(cs, "LSCopyDefaultApplicationURLForURL");
  CFArrayRef (*LSCopyApplicationURLsForBundleIdentifier)(CFStringRef, CFErrorRef *) =
    dlsym(cs, "LSCopyApplicationURLsForBundleIdentifier");
  int32_t (*LSOpenFromURLSpec)(const LSLaunchURLSpec *, CFURLRef *) = dlsym(cs, "LSOpenFromURLSpec");
  if (!CFURLCreateWithBytes || !CFArrayCreate || !CFArrayGetValueAtIndex || !CFArrayGetCount ||
      !CFStringCreateWithCString || !CFRetain || !CFRelease || !CFErrorCreate ||
      !CFErrorCopyDescription || !CFStringGetLength || !CFStringGetMaximumSizeForEncoding ||
      !CFStringGetCString || !kCFTypeArrayCallBacks || !kCFErrorDomainOSStatus ||
      !LSCopyDefaultApplicationURLForURL || !LSCopyApplicationURLsForBundleIdentifier ||
      !LSOpenFromURLSpec) {
    return 4;
  }

  int32_t flags = 0;
  // resolve_default_browser
  CFURLRef app_url = NULL;
  CFURLRef https = CFURLCreateWithBytes(NULL, (const uint8_t *)"https://", 8, kCFStringEncodingUTF8, NULL);
  if (https) {
    app_url = LSCopyDefaultApplicationURLForURL(https, kLSRolesAll, NULL);
    CFRelease(https);
  }
  if (!app_url) {
    flags = 16;
    CFStringRef safari = CFStringCreateWithCString(NULL, "com.apple.Safari", kCFStringEncodingUTF8);
    if (safari) {
      CFArrayRef apps = LSCopyApplicationURLsForBundleIdentifier(safari, NULL);
      if (apps) {
        if (CFArrayGetCount(apps) > 0) {
          app_url = CFRetain(CFArrayGetValueAtIndex(apps, 0));
        }
        CFRelease(apps);
      }
      CFRelease(safari);
    }
  }
  if (!app_url) {
    return flags | 1;
  }

  size_t url_len = strlen((const char *)url);
  CFURLRef target = CFURLCreateWithBytes(NULL, (const uint8_t *)url, (CFIndex)url_len, kCFStringEncodingUTF8, NULL);
  if (!target) {
    CFRelease(app_url);
    return flags | 2;
  }
  const void *items[1] = {target};
  CFArrayRef urls = CFArrayCreate(NULL, items, 1, kCFTypeArrayCallBacks);
  // kLSLaunchDefaults, as `NSWorkspaceLaunchOptions::Default`.
  LSLaunchURLSpec spec = {app_url, urls, NULL, 0x00000001, NULL};
  int32_t status = LSOpenFromURLSpec(&spec, NULL);
  CFRelease(urls);
  CFRelease(target);
  CFRelease(app_url);
  if (status == 0) {
    return flags;
  }
  ts_cli_open_status = status;
  free(ts_cli_open_message);
  ts_cli_open_message = NULL;
  CFErrorRef error = CFErrorCreate(NULL, *kCFErrorDomainOSStatus, status, NULL);
  if (error) {
    CFStringRef description = CFErrorCopyDescription(error);
    if (description) {
      CFIndex size = CFStringGetMaximumSizeForEncoding(CFStringGetLength(description), kCFStringEncodingUTF8) + 1;
      ts_cli_open_message = malloc((size_t)size);
      if (ts_cli_open_message && !CFStringGetCString(description, ts_cli_open_message, size, kCFStringEncodingUTF8)) {
        ts_cli_open_message[0] = 0;
      }
      CFRelease(description);
    }
    CFRelease(error);
  }
  return flags | 3;
#else
  (void)url;
  return 4;
#endif
}

MOONBIT_FFI_EXPORT
int32_t ts_cli_macos_open_status(void) {
  return ts_cli_open_status;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t ts_cli_macos_open_message(void) {
  const char *s = ts_cli_open_message ? ts_cli_open_message : "";
  return ts_cli_bytes_of(s, strlen(s));
}

// Wait for the child process `pid`: `ExitStatus::code()`, with -1 for a
// process ended by a signal (no code), or -2 with `errno` set when waiting
// fails (`ts_cli_wait_error`).
static int ts_cli_last_wait_error = 0;

MOONBIT_FFI_EXPORT
int32_t ts_cli_wait_exit_code(int32_t pid) {
#ifdef _WIN32
  (void)pid;
  ts_cli_last_wait_error = ENOSYS;
  return -2;
#else
  int status;
  for (;;) {
    pid_t ret = waitpid((pid_t)pid, &status, 0);
    if (ret == (pid_t)pid) break;
    if (ret < 0 && errno == EINTR) continue;
    ts_cli_last_wait_error = errno;
    return -2;
  }
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  return -1;
#endif
}

MOONBIT_FFI_EXPORT
int32_t ts_cli_wait_error(void) {
  return ts_cli_last_wait_error;
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
