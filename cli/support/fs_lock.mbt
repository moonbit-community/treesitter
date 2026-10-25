// Host helpers for the loader's lock files and atomically published cache
// files (`LockFile` and `temp_path` in tree-sitter crates/loader/src/loader.rs)
// and its removal of the legacy macOS cache directory (`fs::remove_dir_all`).

///|
extern "C" fn ts_cli_process_id() -> Int32 = "ts_cli_process_id"

///|
/// `std::process::id()`.
pub fn process_id() -> Int32 {
  ts_cli_process_id()
}

///|
extern "C" fn ts_cli_target_os() -> Int32 = "ts_cli_target_os"

///|
/// `std::env::consts::OS` of the platform the program was compiled for, as
/// the C compiler sees it (`#cfg(platform=...)` conditions are not set by
/// every build of moon).
pub fn target_os() -> String {
  match ts_cli_target_os() {
    1 => "macos"
    2 => "linux"
    3 => "windows"
    _ => "unknown"
  }
}

///|
/// `e.kind() == std::io::ErrorKind::AlreadyExists`.
pub fn is_already_exists(err : Error) -> Bool {
  match err {
    @os_error.OSError(_) as e => e.is_EEXIST()
    _ => false
  }
}

///|
/// `fs::OpenOptions::new().create_new(true).write(true).open(path)`, closing
/// the file again: `true` if the file was created, `false` if it already
/// existed; other errors are raised.
pub async fn create_new_file(path : String) -> Bool {
  let file = @fs.open(path, mode=WriteOnly, create_mode=CreateNew) catch {
    e => if is_already_exists(e) { return false } else { raise e }
  }
  file.close()
  true
}

///|
/// `Path::is_dir` (following symbolic links; errors count as `false`).
pub async fn is_dir(path : String) -> Bool {
  let kind = @fs.kind(path, follow_symlink=true) catch { _ => return false }
  kind is Directory
}

///|
/// `fs::remove_dir_all`: remove a directory and everything in it. A symbolic
/// link is removed itself, never followed.
pub async fn remove_dir_all(path : String) -> Unit {
  let kind = @fs.kind(path, follow_symlink=false)
  if kind is Directory {
    @fs.rmdir(path, recursive=true)
  } else {
    @fs.remove(path)
  }
}
