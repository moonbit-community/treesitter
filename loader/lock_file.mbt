// Part of the port of tree-sitter crates/loader/src/loader.rs: `temp_path`
// and `LockFile`, which make concurrent loaders generate a language's cached
// tables once and publish them atomically.

///|
/// `temp_path`: a temporary file path for atomic writes. The temp file is a
/// hidden dotfile alongside the target, tagged with the current process and
/// thread id for debuggability (e.g. `.javascript.language.json.12345.ThreadId(1)`;
/// MoonBit programs are single-threaded, so the thread is always the main
/// thread, `ThreadId(1)`).
fn temp_path(path : String) -> String {
  let filename = @support.file_name(path).unwrap()
  let name = ".\{filename}.\{@support.process_id()}.ThreadId(1)"
  match @support.parent(path) {
    Some(parent) => @support.path_join(parent, name)
    None => name
  }
}

///|
/// RAII lock file guard. The lock file is created atomically via
/// `create_new` and removed by `drop`.
priv struct LockFile {
  path : String
}

///|
/// Attempt to atomically create the lock file.
///
/// Returns `Some` if we won the race, `None` if we lost, or the underlying
/// IO error otherwise.
async fn LockFile::create(path : String) -> LockFile? {
  let created = @support.create_new_file(path) catch {
    e => raise IO(@support.io_error_with_path(e, Some(path)))
  }
  if created {
    Some({ path, })
  } else {
    None
  }
}

///|
/// Wait for an existing lock file to be removed by whoever created it.
/// If the lock file persists beyond `timeout_ms`, raise `LockFileTimeout`.
async fn LockFile::wait_for_removal(path : String, timeout_ms : Int) -> Unit {
  let mut sleep_ms = 100
  let deadline = @support.now_ns() + timeout_ms.to_int64() * 1000000L
  while @fs.exists(path) {
    if @support.now_ns() > deadline {
      raise LockFileTimeout(path)
    }
    @async.sleep(sleep_ms)
    sleep_ms = if sleep_ms * 2 < 1000 { sleep_ms * 2 } else { 1000 }
  }
}

///|
/// `impl Drop for LockFile`.
async fn LockFile::drop(self : LockFile) -> Unit {
  @fs.remove(self.path) catch {
    e =>
      if !@support.is_not_found(e) {
        warn(
          "Failed to remove lock file '\{self.path}': \{@support.io_error_message(e)}.",
        )
      }
  }
}
