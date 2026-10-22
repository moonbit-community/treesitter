///|
// Find this module without mistaking the grammar author's own moon.mod for the
// runtime checkout. A missing checkout selects normal registry dependencies.
async fn find_checkout(path : String) -> String? {
  if path.is_empty() || !@fs.exists(path) {
    return None
  }
  let mut directory = @fs.realpath(path)
  if @fs.kind(directory) != Directory {
    directory = parent_directory(directory).unwrap_or(directory)
  }
  for ;; {
    let manifest = "\{directory}/moon.mod"
    if @fs.exists(manifest) &&
      module_name(@fs.read_file(manifest).text()) == Some("bobzhang/treesitter") {
      return Some(directory)
    }
    let legacy = "\{directory}/moon.mod.json"
    if @fs.exists(legacy) {
      let value = @json.parse(@fs.read_file(legacy).text()) catch {
        _ => Json::null()
      }
      if value is { "name": "bobzhang/treesitter", .. } {
        return Some(directory)
      }
    }
    guard parent_directory(directory) is Some(parent) else { return None }
    directory = parent
  }
}

///|
fn parent_directory(path : String) -> String? {
  let slash = Int32::max(
    path.rev_find("/").unwrap_or(-1),
    path.rev_find("\\").unwrap_or(-1),
  )
  if slash < 0 ||
    path == "/" ||
    path == "\\" ||
    (path.length() == 3 && path.code_unit_at(1).to_int() == ':'.to_int()) {
    None
  } else if slash == 0 {
    Some(path[:1].to_owned())
  } else if slash == 2 && path.code_unit_at(1).to_int() == ':'.to_int() {
    Some(path[:3].to_owned())
  } else {
    Some(path[:slash].to_owned())
  }
}

///|
fn module_name(source : String) -> String? {
  for line in source.split("\n") {
    let line = line.trim()
    if line.has_prefix("name") {
      let rest = line[4:].trim()
      if rest.has_prefix("=") {
        let value = @json.parse(rest[1:].trim()) catch { _ => Json::null() }
        if value is String(name) {
          return Some(name)
        }
      }
    }
  }
  None
}

///|
async fn prepare_workspace(
  temp : String,
  hint : String,
  executable~ : String = @env.args().get(0).unwrap_or(""),
) -> String? {
  let checkout = match find_checkout(hint) {
    Some(root) => Some(root)
    None => find_checkout(executable)
  }
  let members = ["script"]
  if checkout is Some(root) {
    members.push(root)
  }
  write_file("\{temp}/moon.work", "members = \{Json(members).stringify()}\n")
  checkout
}
