///|
pub struct GrammarLocation {
  root : String
  grammar : @config.Grammar
}

///|
/// Discover tree-sitter.json packages in configured directories and their
/// immediate tree-sitter-* children. Results are deterministic and deduplicated.
pub async fn discover(directories : Array[String]) -> Array[GrammarLocation] {
  let results = []
  let seen : Map[String, Bool] = Map([])
  for directory in directories {
    if !@fs.exists(directory) {
      continue
    }
    let candidates = [directory]
    let entries = @fs.readdir(directory, sort=true)
    for name in entries {
      if name.has_prefix("tree-sitter-") &&
        @fs.kind("\{directory}/\{name}") == Directory {
        candidates.push("\{directory}/\{name}")
      }
    }
    for candidate in candidates {
      let path = "\{candidate}/tree-sitter.json"
      if !@fs.exists(path) {
        continue
      }
      let root = @fs.realpath(candidate)
      if seen.contains(root) {
        continue
      }
      seen[root] = true
      let config = @config.Config::parse(@fs.read_file(path).text())
      for grammar in config.grammars {
        results.push({ root, grammar, })
      }
    }
  }
  results
}

///|
/// Read parser-directories from an explicit or standard user configuration.
pub async fn parser_directories(path? : String) -> Array[String] {
  let home = @env.get_env_var("HOME").unwrap_or(".")
  let candidates = match path {
    Some(path) => [path]
    None => {
      let paths = []
      if @env.get_env_var("TREE_SITTER_DIR") is Some(dir) {
        paths.push("\{dir}/config.json")
      }
      let config_home = @env.get_env_var("XDG_CONFIG_HOME").unwrap_or(
        "\{home}/.config",
      )
      paths.append([
        "\{config_home}/tree-sitter/config.json",
        "\{home}/.tree-sitter/config.json",
      ])
      paths
    }
  }
  for candidate in candidates {
    if !@fs.exists(candidate) {
      continue
    }
    let json = @json.parse(@fs.read_file(candidate).text())
    guard json is Object(obj) &&
      obj.get("parser-directories") is Some(Array(dirs)) else {
      raise LoadFailure("config must contain parser-directories")
    }
    return dirs.map(dir => {
      match dir {
        String(path) =>
          if path.has_prefix("~/") {
            home + path[1:].to_owned()
          } else {
            path
          }
        _ => raise LoadFailure("parser-directories must contain strings")
      }
    })
  }
  if path is Some(path) {
    raise LoadFailure("configuration does not exist: \{path}")
  }
  []
}

///|
pub async fn GrammarLocation::language(
  self : GrammarLocation,
  module_root : String,
) -> @language.Language {
  let directory = "\{self.root}/\{self.grammar.path}"
  for filename in ["language.json", "src/language.json"] {
    let path = "\{directory}/\{filename}"
    if @fs.exists(path) {
      return load_language(path)
    }
  }
  for filename in ["grammar.mbtx", "src/grammar.json"] {
    let path = "\{directory}/\{filename}"
    if @fs.exists(path) {
      return @generate.generate(load_grammar(path, module_root))
    }
  }
  raise LoadFailure("no MoonBit language tables or grammar in \{directory}")
}

///|
pub async fn GrammarLocation::queries(
  self : GrammarLocation,
  kind : String,
) -> String {
  let paths = match kind {
    "highlights" => self.grammar.highlights
    "injections" => self.grammar.injections
    "locals" => self.grammar.locals
    "tags" => self.grammar.tags
    _ => raise LoadFailure("unknown query kind '\{kind}'")
  }
  let required = !paths.is_empty()
  let paths = if paths.is_empty() {
    ["\{self.grammar.path}/queries/\{kind}.scm"]
  } else {
    paths
  }
  let parts = []
  for path in paths {
    let path = "\{self.root}/\{path}"
    if @fs.exists(path) {
      parts.push(@fs.read_file(path).text())
    } else if required {
      raise LoadFailure("query file does not exist: \{path}")
    }
  }
  parts.join("\n")
}
