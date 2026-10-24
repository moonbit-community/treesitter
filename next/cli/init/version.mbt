// Port of tree-sitter crates/cli/src/version.rs.

///|
pub(all) enum BumpLevel {
  Patch
  Minor
  Major
} derive(Eq, Debug)

///|
pub fn BumpLevel::default() -> BumpLevel {
  Patch
}

///|
pub struct Version {
  mut version : @loader.SemverVersion?
  current_dir : String
  bump : BumpLevel?
}

///|
/// `UpdateError`.
pub(all) enum UpdateError {
  Io(String, String)
  Command(String, String)
} derive(Debug)

///|
pub impl Show for UpdateError with output(self, logger) {
  match self {
    // "Failed to update {1}:\n{0}"
    Io(error, path) => logger.write_string("Failed to update \{path}:\n\{error}")
    // "Failed to run `{0}`:\n{1}"
    Command(command, stderr) =>
      logger.write_string("Failed to run `\{command}`:\n\{stderr}")
  }
}

///|
/// `VersionError`. `Json` and `Io` carry the display text of the
/// `serde_json::Error` and `std::io::Error` they wrap (`#[error(transparent)]`).
pub(all) suberror VersionError {
  Json(String)
  Io(String)
  Update(Array[UpdateError])
} derive(Debug)

///|
pub impl Show for VersionError with output(self, logger) {
  match self {
    Json(message) | Io(message) => logger.write_string(message)
    // "Failed to update one or more files:\n\n{0}", where `UpdateErrors`
    // writes each error followed by a blank line.
    Update(errors) => {
      logger.write_string("Failed to update one or more files:\n\n")
      for error in errors {
        logger.write_string("\{error}\n\n")
      }
    }
  }
}

///|
pub fn Version::new(
  version : @loader.SemverVersion?,
  current_dir : String,
  bump : BumpLevel?,
) -> Version {
  { version, current_dir, bump }
}

///|
pub async fn Version::run(self : Version) -> Unit {
  let tree_sitter_json = @support.path_join(self.current_dir, "tree-sitter.json")
  let text = read_to_string(tree_sitter_json) catch {
    IoError(e) => raise VersionError::Io(e)
  }
  let tree_sitter_json = @loader.TreeSitterJSON::parse(text) catch {
    @loader.JsonError(e) => raise VersionError::Json(e)
  }
  let current_version = tree_sitter_json.metadata.version
  self.version = match (self.version is Some(_), self.bump) {
    (false, None) => {
      @support.log_info("Current version: \{current_version}")
      return
    }
    (true, None) => self.version
    (false, Some(bump)) => {
      let v = current_version
      Some(
        match bump {
          Patch => { ..v, patch: v.patch + 1 }
          Minor => { ..v, minor: v.minor + 1, patch: 0 }
          Major => { ..v, major: v.major + 1, minor: 0, patch: 0 }
        },
      )
    }
    (true, Some(_)) => abort("internal error: entered unreachable code")
  }
  let new_version = self.version.unwrap()
  let ord = semver_cmp(new_version, current_version)
  if ord < 0 {
    @support.log_warn("New version is lower than current!")
    @support.log_warn("Reverting version \{current_version} to \{new_version}")
  } else if ord > 0 {
    @support.log_info("Bumping version \{current_version} to \{new_version}")
  } else {
    @support.log_info("Keeping version \{current_version}")
  }
  let is_multigrammar = tree_sitter_json.grammars.length() > 1
  let errors = []

  // Helper to push errors into the errors vector, returns true if an error
  // was pushed
  fn push_err(result : Result[Unit, UpdateError]) -> Bool {
    if result is Err(e) {
      errors.push(e)
      return true
    }
    false
  }
  ignore(push_err(self.update_treesitter_json()))

  // Only update Cargo.lock if Cargo.toml was updated
  // (`bool::then`: the lock file is regenerated only when pushing the
  // Cargo.toml result reported an error, exactly as upstream does.)
  if push_err(self.update_cargo_toml()) {
    ignore(push_err(self.update_cargo_lock()))
  }

  // Only update package-lock.json if package.json was updated
  if push_err(self.update_package_json()) {
    ignore(push_err(self.update_package_lock_json()))
  }
  ignore(push_err(self.update_makefile(is_multigrammar)))
  ignore(push_err(self.update_cmakelists_txt()))
  ignore(push_err(self.update_pyproject_toml()))
  ignore(push_err(self.update_zig_zon()))
  if !errors.is_empty() {
    raise VersionError::Update(errors)
  }
}

///|
/// `Ord for semver::Version`: major, minor, patch, then the pre-release
/// (a version without one is greater) and the build metadata.
fn semver_cmp(a : @loader.SemverVersion, b : @loader.SemverVersion) -> Int {
  let c = a.major.compare(b.major)
  if c != 0 {
    return c
  }
  let c = a.minor.compare(b.minor)
  if c != 0 {
    return c
  }
  let c = a.patch.compare(b.patch)
  if c != 0 {
    return c
  }
  let c = match (a.pre.is_empty(), b.pre.is_empty()) {
    (true, true) => 0
    (true, false) => 1
    (false, true) => -1
    (false, false) => identifiers_cmp(a.pre, b.pre, true)
  }
  if c != 0 {
    return c
  }
  identifiers_cmp(a.build, b.build, false)
}

///|
/// `Ord for str` (byte-wise; the identifiers are ASCII).
fn lexical_cmp(a : StringView, b : StringView) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let c = a[i].compare(b[i])
    if c != 0 {
      return c
    }
  }
  a.length().compare(b.length())
}

///|
fn is_numeric_identifier(s : StringView) -> Bool {
  if s.is_empty() {
    return false
  }
  for c in s {
    if !c.is_ascii_digit() {
      return false
    }
  }
  true
}

///|
/// `Ord for Prerelease` (`prerelease = true`) and `Ord for BuildMetadata`:
/// dot-separated identifiers compared pairwise; numeric identifiers compare
/// numerically and sort before alphanumeric ones; more identifiers win.
fn identifiers_cmp(a : String, b : String, prerelease : Bool) -> Int {
  if a.is_empty() || b.is_empty() {
    return a.length().compare(b.length())
  }
  let xs = a.split(".").collect()
  let ys = b.split(".").collect()
  for i in 0..<xs.length() {
    if i >= ys.length() {
      return 1
    }
    let x = xs[i]
    let y = ys[i]
    let c = match (is_numeric_identifier(x), is_numeric_identifier(y)) {
      (true, true) =>
        if prerelease {
          // Respect numeric ordering, for example 99 < 100.
          let c = x.length().compare(y.length())
          if c != 0 {
            c
          } else {
            lexical_cmp(x, y)
          }
        } else {
          // 0 < 00 < 1 < 01 < 001 < 2 < 02 < 002 < 10
          let xt = x.trim_start(chars="0")
          let yt = y.trim_start(chars="0")
          let c = xt.length().compare(yt.length())
          let c = if c != 0 { c } else { lexical_cmp(xt, yt) }
          if c != 0 {
            c
          } else {
            x.length().compare(y.length())
          }
        }
      (true, false) => -1
      (false, true) => 1
      (false, false) => lexical_cmp(x, y)
    }
    if c != 0 {
      return c
    }
  }
  if xs.length() < ys.length() {
    -1
  } else {
    0
  }
}

///|
async fn update_file_with(
  path : String,
  update_fn : (String) -> String,
) -> Result[Unit, UpdateError] {
  let content = read_to_string(path) catch {
    IoError(e) => return Err(UpdateError::Io(e, path))
  }
  let updated_content = update_fn(content)
  fs_write(path, updated_content) catch {
    IoError(e) => return Err(UpdateError::Io(e, path))
  }
  Ok(())
}

///|
/// Replace the quoted value following `prefix` on `line` with `version`
/// (panics like upstream's `unwrap`s when the quotes are missing).
fn replace_quoted_after(line : String, prefix : String, version : String) -> String {
  let prefix_index = line.find(prefix).unwrap() + prefix.length()
  let start_quote = line.view(start_offset=prefix_index).find("\"").unwrap() +
    prefix_index +
    1
  let end_quote = line.view(start_offset=start_quote + 1).find("\"").unwrap() +
    start_quote +
    1
  line.view(end_offset=start_quote).to_owned() +
  version +
  line.view(start_offset=end_quote).to_owned()
}

///|
/// `content.lines().map(f).collect::<Vec<_>>().join("\n") + "\n"`.
fn map_lines(content : String, f : (String) -> String) -> String {
  rust_lines(content).map(f).join("\n") + "\n"
}

///|
async fn Version::update_treesitter_json(
  self : Version,
) -> Result[Unit, UpdateError] {
  let json_path = @support.path_join(self.current_dir, "tree-sitter.json")
  let version = self.version.unwrap().to_string()
  update_file_with(json_path, content => map_lines(content, line => if line.contains(
      "\"version\":",
    ) {
    replace_quoted_after(line, "\"version\":", version)
  } else {
    line
  }))
}

///|
async fn Version::update_cargo_toml(self : Version) -> Result[Unit, UpdateError] {
  let cargo_toml_path = @support.path_join(self.current_dir, "Cargo.toml")
  if !path_exists(cargo_toml_path) {
    return Ok(())
  }
  let version = self.version.unwrap().to_string()
  update_file_with(cargo_toml_path, content => map_lines(content, line => if line.has_prefix(
      "version =",
    ) {
    "version = \"\{version}\""
  } else {
    line
  }))
}

///|
async fn Version::update_cargo_lock(self : Version) -> Result[Unit, UpdateError] {
  if path_exists(@support.path_join(self.current_dir, "Cargo.lock")) {
    let (code, _, stderr) = @process.collect_output(
      "cargo",
      ["generate-lockfile", "--offline"],
      cwd=self.current_dir,
    ) catch {
      _ => return Ok(()) // cargo is not `executable`, ignore
    }
    if code != 0 {
      let stderr = @support.utf8_lossy(stderr.binary())
      return Err(UpdateError::Command("cargo generate-lockfile", stderr))
    }
  }
  Ok(())
}

///|
async fn Version::update_package_json(
  self : Version,
) -> Result[Unit, UpdateError] {
  let package_json_path = @support.path_join(self.current_dir, "package.json")
  if !path_exists(package_json_path) {
    return Ok(())
  }
  let version = self.version.unwrap().to_string()
  update_file_with(package_json_path, content => map_lines(content, line => if line.contains(
      "\"version\":",
    ) {
    replace_quoted_after(line, "\"version\":", version)
  } else {
    line
  }))
}

///|
async fn Version::update_package_lock_json(
  self : Version,
) -> Result[Unit, UpdateError] {
  if path_exists(@support.path_join(self.current_dir, "package-lock.json")) {
    let (code, _, stderr) = @process.collect_output(
      "npm",
      ["install", "--package-lock-only"],
      cwd=self.current_dir,
    ) catch {
      _ => return Ok(()) // npm is not `executable`, ignore
    }
    if code != 0 {
      let stderr = @support.utf8_lossy(stderr.binary())
      return Err(UpdateError::Command("npm install", stderr))
    }
  }
  Ok(())
}

///|
async fn Version::update_makefile(
  self : Version,
  is_multigrammar : Bool,
) -> Result[Unit, UpdateError] {
  let makefile_path = if is_multigrammar {
    @support.path_join(
      @support.path_join(self.current_dir, "common"),
      "common.mak",
    )
  } else {
    @support.path_join(self.current_dir, "Makefile")
  }
  if !path_exists(makefile_path) {
    return Ok(())
  }
  let version = self.version.unwrap().to_string()
  update_file_with(makefile_path, content => map_lines(content, line => if line.has_prefix(
      "VERSION",
    ) {
    "VERSION := \{version}"
  } else {
    line
  }))
}

///|
async fn Version::update_cmakelists_txt(
  self : Version,
) -> Result[Unit, UpdateError] {
  let cmake_lists_path = @support.path_join(self.current_dir, "CMakeLists.txt")
  if !path_exists(cmake_lists_path) {
    return Ok(())
  }
  let version = self.version.unwrap().to_string()
  update_file_with(cmake_lists_path, content => replace_cmake_version(
    content, version,
  ))
}

///|
/// `Regex::new(r#"(\s*VERSION\s+)"[0-9]+\.[0-9]+\.[0-9]+""#).replace(content,
/// format!(r#"$1"{}""#, version))`: replace the leftmost-first match.
fn replace_cmake_version(content : String, version : String) -> String {
  let chars : Array[Char] = content.iter().collect()
  let n = chars.length()
  fn is_space(c : Char) -> Bool {
    c.is_whitespace()
  }

  fn digits(i : Int) -> Int? {
    let mut j = i
    while j < n && chars[j] >= '0' && chars[j] <= '9' {
      j += 1
    }
    if j > i {
      Some(j)
    } else {
      None
    }
  }

  // The end of group 1 and the end of the match, for a match at `start`.
  fn match_at(start : Int) -> (Int, Int)? {
    let mut i = start
    while i < n && is_space(chars[i]) {
      i += 1
    }
    let keyword = "VERSION"
    for k in 0..<keyword.length() {
      if i + k >= n || chars[i + k].to_int() != keyword[k].to_int() {
        return None
      }
    }
    i += keyword.length()
    let ws_start = i
    while i < n && is_space(chars[i]) {
      i += 1
    }
    if i == ws_start {
      return None
    }
    let group_end = i
    guard i < n && chars[i] == '"' else { return None }
    guard digits(i + 1) is Some(i) else { return None }
    guard i < n && chars[i] == '.' else { return None }
    guard digits(i + 1) is Some(i) else { return None }
    guard i < n && chars[i] == '.' else { return None }
    guard digits(i + 1) is Some(i) else { return None }
    guard i < n && chars[i] == '"' else { return None }
    Some((group_end, i + 1))
  }

  for start in 0..=n {
    if match_at(start) is Some((group_end, end)) {
      return String::from_array(chars[:group_end]) +
        "\"\{version}\"" +
        String::from_array(chars[end:])
    }
  }
  content
}

///|
async fn Version::update_pyproject_toml(
  self : Version,
) -> Result[Unit, UpdateError] {
  let pyproject_toml_path = @support.path_join(
    self.current_dir, "pyproject.toml",
  )
  if !path_exists(pyproject_toml_path) {
    return Ok(())
  }
  let version = self.version.unwrap().to_string()
  update_file_with(pyproject_toml_path, content => map_lines(content, line => if line.has_prefix(
      "version =",
    ) {
    "version = \"\{version}\""
  } else {
    line
  }))
}

///|
async fn Version::update_zig_zon(self : Version) -> Result[Unit, UpdateError] {
  let zig_zon_path = @support.path_join(self.current_dir, "build.zig.zon")
  if !path_exists(zig_zon_path) {
    return Ok(())
  }
  let version = self.version.unwrap().to_string()
  update_file_with(zig_zon_path, content => {
    let zig_version_prefix = ".version ="
    map_lines(content, line => if line
      .trim_start(chars=" \t\n\r\u{0C}")
      .has_prefix(zig_version_prefix) {
      replace_quoted_after(line, zig_version_prefix, version)
    } else {
      line
    })
  })
}
