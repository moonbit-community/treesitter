// Port of tree-sitter crates/config/src/tree_sitter_config.rs.

///|
/// `ConfigError`.
pub(all) suberror ConfigError {
  ConfigRead(String, String)
  HomeDir
  IO(String)
  Serialization(String)
}

///|
pub impl Show for ConfigError with fn output(self, logger) {
  match self {
    ConfigRead(path, err) =>
      logger.write_string("Bad JSON config \{path} -- \{err}")
    HomeDir => logger.write_string("could not find home directory")
    IO(message) | Serialization(message) => logger.write_string(message)
  }
}

///|
/// Holds the contents of tree-sitter's configuration file.
///
/// The file typically lives at `~/.config/tree-sitter/config.json`, but see
/// `Config::load` for the full details on where it might be located.
///
/// This type holds the generic JSON content of the configuration file.
/// Individual tree-sitter components use `Config::get` to extract the
/// configuration fields that are specific to that component.
pub struct Config {
  location : String
  config : @support.Value
}

///|
/// `log::warn!` hook, set by the CLI to its logger.
pub let warn_hook : Ref[(String) -> Unit] = Ref(@support.log_warn)

///|
async fn is_file(path : String) -> Bool {
  (@fs.kind(path) catch { _ => @fs.FileKind::Unknown }) is Regular
}

///|
pub async fn Config::find_config_file() -> String? {
  if @env.get_env_var("TREE_SITTER_DIR") is Some(dir) {
    let path = @support.path_join(dir, "config.json")
    if !@fs.exists(path) {
      return None
    }
    if is_file(path) {
      return Some(path)
    }
  }
  let xdg_path = Config::xdg_config_file()
  if is_file(xdg_path) {
    return Some(xdg_path)
  }
  if @support.current_os == "macos" {
    guard @support.home_dir() is Some(home) else { raise HomeDir }
    // `etcetera::base_strategy::Apple::data_dir`.
    let legacy_apple_path = @support.path_join(
      home, "Library/Application Support/tree-sitter/config.json",
    )
    if is_file(legacy_apple_path) {
      let xdg_dir = @support.parent(xdg_path).unwrap()
      @support.create_dir_all(xdg_dir) catch {
        e => raise IO(@support.io_error_with_path(e, Some(xdg_dir)))
      }
      @fs.rename(legacy_apple_path, xdg_path) catch {
        e => raise IO(@support.io_error_with_path(e, Some(legacy_apple_path)))
      }
      (warn_hook.val)(
        "Your config.json file has been automatically migrated from \"\{legacy_apple_path}\" to \"\{xdg_path}\"",
      )
      return Some(xdg_path)
    }
  }
  guard @support.home_dir() is Some(home) else { raise HomeDir }
  let legacy_path = @support.path_join(home, ".tree-sitter/config.json")
  if is_file(legacy_path) {
    return Some(legacy_path)
  }
  None
}

///|
fn Config::xdg_config_file() -> String raise ConfigError {
  guard @support.config_dir() is Some(dir) else { raise HomeDir }
  @support.path_join(dir, "tree-sitter/config.json")
}

///|
/// Locates and loads in the user's configuration file. We search for the
/// configuration file in the following locations, in order:
///
///   - Location specified by the path parameter if provided
///   - `$TREE_SITTER_DIR/config.json`, if the `TREE_SITTER_DIR` environment
///     variable is set
///   - `tree-sitter/config.json` in your default user configuration directory
///   - `$HOME/.tree-sitter/config.json` as a fallback from where tree-sitter
///     _used_ to store its configuration
pub async fn Config::load(path : String?) -> Config {
  let location = match path {
    Some(path) => path
    None =>
      match Config::find_config_file() {
        Some(path) => path
        None => return Config::initial()
      }
  }
  let content = @support.read_to_string(location) catch {
    e => raise IO(@support.io_error_with_path(e, Some(location)))
  }
  let config = @support.from_str(content) catch {
    e => raise ConfigRead(location, e.to_string())
  }
  { location, config, }
}

///|
/// The display text of a `serde_json::Error` (other errors are shown as
/// they are).
pub fn json_error_message(err : Error) -> String {
  err.to_string()
}

///|
/// Creates an empty initial configuration file. You can then use
/// `Config::add` to add the component-specific configuration types for any
/// components that want to add content to the default file, and then use
/// `Config::save` to write the configuration to disk.
///
/// (Note that this is typically only done by the `tree-sitter init-config`
/// command.)
pub fn Config::initial() -> Config raise ConfigError {
  let location = match @env.get_env_var("TREE_SITTER_DIR") {
    Some(dir) => @support.path_join(dir, "config.json")
    None => Config::xdg_config_file()
  }
  { location, config: Object(Map([])), }
}

///|
/// Saves this configuration to the file that it was originally loaded from.
pub async fn Config::save(self : Config) -> Unit {
  let json = self.config.to_string_pretty()
  let config_dir = @support.parent(self.location).unwrap()
  @support.create_dir_all(config_dir) catch {
    e => raise IO(@support.io_error_with_path(e, Some(config_dir)))
  }
  // `fs::write` creates the file with mode 0o666 (less the umask).
  @fs.write_file(
    self.location,
    json,
    create_mode=CreateOrTruncate,
    permission=0o666,
  ) catch {
    e => raise IO(@support.io_error_with_path(e, Some(self.location)))
  }
}

///|
/// The configuration JSON, which a component deserializes into its own
/// configuration type (`Config::get` is `serde_json::from_value` of a
/// clone; the deserializers do not modify the value).
pub fn Config::get(self : Config) -> @support.Value {
  self.config
}

///|
/// Adds a component-specific configuration (the output of its `Serialize`,
/// a JSON object) to the configuration file (`Config::add`).
pub fn Config::add(self : Config, config : Json) -> Unit {
  guard self.config is Object(target) else { return }
  guard @support.Value::from_json(config) is Object(source) else { return }
  for k, v in source {
    target[k] = v
  }
}
