// Port of tree-sitter crates/loader/src/loader.rs: the serde types of
// `config.json` (`Config`) and `tree-sitter.json` (`TreeSitterJSON`,
// `Grammar`, `Metadata`, `Author`, `Links`, `Bindings`, `PathsJSON`), with
// their (de)serialization written out as serde derives them.

///|
/// A serde deserialization error (`serde_json::Error` display text).
pub(all) suberror JsonError {
  JsonError(String)
}

///|
pub impl Show for JsonError with fn output(self, logger) {
  let JsonError(message) = self
  logger.write_string(message)
}

///|
/// `Config`: the loader's part of `config.json`.
pub(all) struct LoaderConfig {
  parser_directories : Array[String]
}

///|
/// `Config::get::<Config>()`: `#[derive(Deserialize)]` of `Config`, whose
/// `parser-directories` (`#[serde(default)]`) are read by
/// `deserialize_parser_directories`.
pub fn LoaderConfig::from_json(
  config : @support.Value,
) -> LoaderConfig raise JsonError {
  @support.from_value(config, LoaderConfig::deserialize) catch {
    e => raise JsonError(e.to_string())
  }
}

///|
fn LoaderConfig::deserialize(
  de : @support.Deserializer,
) -> LoaderConfig raise @support.SerdeJsonError {
  de.deserialize_struct(
    "struct Config",
    seq => {
      let parser_directories = seq
        .next_element(deserialize_parser_directories)
        .unwrap_or([])
      { parser_directories, }
    },
    map => {
      let parser_directories : @support.StructField[Array[String]] = @support.StructField::new(
        "parser-directories",
      )
      while map.next_key() is Some(key) {
        match key {
          "parser-directories" =>
            parser_directories.next_value(map, deserialize_parser_directories)
          _ => map.next_value_ignored()
        }
      }
      { parser_directories: parser_directories.or_default([]), }
    },
  )
}

///|
/// Replace `~` or `$HOME` with home path string. (While paths like
/// "~/.tree-sitter/config.json" can be deserialized, they're not valid path
/// for I/O modules.)
fn deserialize_parser_directories(
  de : @support.Deserializer,
) -> Array[String] raise @support.SerdeJsonError {
  let paths = @support.deserialize_vec(de, @support.deserialize_path_buf)
  guard @support.home_dir() is Some(home) else { return paths }
  paths.map(path => standardize_path(path, home))
}

///|
/// Replace `~` or `$HOME` with the home path.
fn standardize_path(path : String, home : String) -> String {
  if @support.strip_path_prefix(path, "~") is Some(p) {
    return @support.path_join(home, p)
  }
  if @support.strip_path_prefix(path, "$HOME") is Some(p) {
    return @support.path_join(home, p)
  }
  path
}

///|
/// `Config::initial`.
pub fn LoaderConfig::initial() -> LoaderConfig {
  let home = @support.home_dir().unwrap_or("")
  {
    parser_directories: [
      @support.path_join(home, "github"),
      @support.path_join(home, "src"),
      @support.path_join(home, "source"),
      @support.path_join(home, "projects"),
      @support.path_join(home, "dev"),
      @support.path_join(home, "git"),
    ],
  }
}

///|
pub fn LoaderConfig::to_json(self : LoaderConfig) -> Json {
  {
    "parser-directories": Json::array(self.parser_directories.map(Json::string)),
  }
}

///|
/// `PathsJSON`: absent, one path, or several paths.
pub(all) enum PathsJSON {
  Empty
  Single(String)
  Multiple(Array[String])
} derive(Eq, Debug)

///|
pub fn PathsJSON::into_vec(self : PathsJSON) -> Array[String]? {
  match self {
    Empty => None
    Single(s) => Some([s])
    Multiple(s) => Some(s)
  }
}

///|
pub fn PathsJSON::is_empty(self : PathsJSON) -> Bool {
  self is Empty
}

///|
/// Represent this set of paths as a string that can be included in
/// templates.
pub fn PathsJSON::to_variable_value(
  self : PathsJSON,
  default : String,
) -> String {
  match self {
    Empty => default
    Single(p) => p
    Multiple(paths) => paths.get(0).unwrap_or("")
  }
}

///|
/// `#[serde(untagged)]` deserialization of `PathsJSON`: the value is
/// buffered (`Content`) and tried as `Empty` (a unit), `Single(PathBuf)` and
/// `Multiple(Vec<PathBuf>)` in turn.
fn PathsJSON::deserialize(
  de : @support.Deserializer,
) -> PathsJSON raise @support.SerdeJsonError {
  let content = de.deserialize_value()
  match content {
    Null => return Empty
    String(s) => return Single(s)
    Array(items) => {
      let paths = []
      for item in items {
        guard item is String(path) else { break }
        paths.push(path)
      } nobreak {
        return Multiple(paths)
      }
    }
    _ => ()
  }
  raise @support.SerdeJsonError::custom(
    "data did not match any variant of untagged enum PathsJSON",
  )
}

///|
fn PathsJSON::to_json(self : PathsJSON) -> Json {
  match self {
    Empty => Json::null()
    Single(s) => Json::string(s)
    Multiple(s) => Json::array(s.map(Json::string))
  }
}

///|
pub(all) struct Author {
  name : String
  email : String?
  url : String?
} derive(Debug)

///|
pub(all) struct Links {
  repository : String
  funding : String?
} derive(Debug)

///|
pub(all) struct Metadata {
  version : SemverVersion
  license : String?
  description : String?
  authors : Array[Author]?
  links : Links?
  namespace : String?
} derive(Debug)

///|
pub(all) struct Bindings {
  c : Bool
  go : Bool
  java : Bool
  kotlin : Bool
  node : Bool
  python : Bool
  rust : Bool
  swift : Bool
  zig : Bool
} derive(Debug)

///|
pub fn Bindings::default() -> Bindings {
  {
    c: true,
    go: true,
    java: false,
    kotlin: false,
    node: true,
    python: true,
    rust: true,
    swift: true,
    zig: false,
  }
}

///|
/// The available languages and their default enabled state.
pub fn Bindings::languages(_self : Bindings) -> Array[(String, Bool)] {
  [
    ("c", true),
    ("go", true),
    ("java", false),
    ("node", true),
    ("python", true),
    ("rust", true),
    ("swift", true),
    ("zig", false),
  ]
}

///|
/// `Bindings::with_enabled_languages`: `Err` names an unsupported language.
pub fn Bindings::with_enabled_languages(
  languages : Array[String],
) -> Result[Bindings, String] {
  let mut out : Bindings = {
    c: false,
    go: false,
    java: false,
    kotlin: false,
    node: false,
    python: false,
    rust: false,
    swift: false,
    zig: false,
  }
  for v in languages {
    match v {
      "c" => out = { ..out, c: true, }
      "go" => out = { ..out, go: true, }
      "java" => out = { ..out, java: true, }
      "node" => out = { ..out, node: true, }
      "python" => out = { ..out, python: true, }
      "rust" => out = { ..out, rust: true, }
      "swift" => out = { ..out, swift: true, }
      "zig" => out = { ..out, zig: true, }
      unsupported => return Err(unsupported)
    }
  }
  Ok(out)
}

///|
pub(all) struct Grammar {
  name : String
  camelcase : String?
  title : String?
  scope : String
  path : String?
  external_files : PathsJSON
  file_types : Array[String]?
  highlights : PathsJSON
  injections : PathsJSON
  locals : PathsJSON
  tags : PathsJSON
  injection_regex : String?
  first_line_regex : String?
  content_regex : String?
  class_name : String?
} derive(Debug)

///|
pub(all) struct TreeSitterJSON {
  schema : String?
  grammars : Array[Grammar]
  metadata : Metadata
  bindings : Bindings
} derive(Debug)

///|
/// `Option::<String>::deserialize`.
fn deserialize_opt_string(
  de : @support.Deserializer,
) -> String? raise @support.SerdeJsonError {
  de.deserialize_option(@support.deserialize_string)
}

///|
/// `Option::<PathBuf>::deserialize`.
fn deserialize_opt_path(
  de : @support.Deserializer,
) -> String? raise @support.SerdeJsonError {
  de.deserialize_option(@support.deserialize_path_buf)
}

///|
/// `#[derive(Deserialize)]` of `Grammar` (`rename_all = "kebab-case"`).
fn Grammar::deserialize(
  de : @support.Deserializer,
) -> Grammar raise @support.SerdeJsonError {
  let expecting = "struct Grammar with 15 elements"
  de.deserialize_struct(
    "struct Grammar",
    seq => {
      let name = seq.next_field(@support.deserialize_string, 0, expecting)
      let camelcase = seq.next_field(deserialize_opt_string, 1, expecting)
      let title = seq.next_field(deserialize_opt_string, 2, expecting)
      let scope = seq.next_field(@support.deserialize_string, 3, expecting)
      let path = seq.next_field(deserialize_opt_path, 4, expecting)
      let external_files = seq
        .next_element(PathsJSON::deserialize)
        .unwrap_or(Empty)
      let file_types = seq.next_field(
        de => {
          de.deserialize_option(de => {
            @support.deserialize_vec(de, @support.deserialize_string)
          })
        },
        6,
        expecting,
      )
      let highlights = seq.next_element(PathsJSON::deserialize).unwrap_or(Empty)
      let injections = seq.next_element(PathsJSON::deserialize).unwrap_or(Empty)
      let locals = seq.next_element(PathsJSON::deserialize).unwrap_or(Empty)
      let tags = seq.next_element(PathsJSON::deserialize).unwrap_or(Empty)
      let injection_regex = seq.next_field(
        deserialize_opt_string, 11, expecting,
      )
      let first_line_regex = seq.next_field(
        deserialize_opt_string, 12, expecting,
      )
      let content_regex = seq.next_field(deserialize_opt_string, 13, expecting)
      let class_name = seq.next_field(deserialize_opt_string, 14, expecting)
      {
        name,
        camelcase,
        title,
        scope,
        path,
        external_files,
        file_types,
        highlights,
        injections,
        locals,
        tags,
        injection_regex,
        first_line_regex,
        content_regex,
        class_name,
      }
    },
    map => {
      let name : @support.StructField[String] = @support.StructField::new(
        "name",
      )
      let camelcase : @support.StructField[String?] = @support.StructField::new(
        "camelcase",
      )
      let title : @support.StructField[String?] = @support.StructField::new(
        "title",
      )
      let scope : @support.StructField[String] = @support.StructField::new(
        "scope",
      )
      let path : @support.StructField[String?] = @support.StructField::new(
        "path",
      )
      let external_files : @support.StructField[PathsJSON] = @support.StructField::new(
        "external-files",
      )
      let file_types : @support.StructField[Array[String]?] = @support.StructField::new(
        "file-types",
      )
      let highlights : @support.StructField[PathsJSON] = @support.StructField::new(
        "highlights",
      )
      let injections : @support.StructField[PathsJSON] = @support.StructField::new(
        "injections",
      )
      let locals : @support.StructField[PathsJSON] = @support.StructField::new(
        "locals",
      )
      let tags : @support.StructField[PathsJSON] = @support.StructField::new(
        "tags",
      )
      let injection_regex : @support.StructField[String?] = @support.StructField::new(
        "injection-regex",
      )
      let first_line_regex : @support.StructField[String?] = @support.StructField::new(
        "first-line-regex",
      )
      let content_regex : @support.StructField[String?] = @support.StructField::new(
        "content-regex",
      )
      let class_name : @support.StructField[String?] = @support.StructField::new(
        "class-name",
      )
      while map.next_key() is Some(key) {
        match key {
          "name" => name.next_value(map, @support.deserialize_string)
          "camelcase" => camelcase.next_value(map, deserialize_opt_string)
          "title" => title.next_value(map, deserialize_opt_string)
          "scope" => scope.next_value(map, @support.deserialize_string)
          "path" => path.next_value(map, deserialize_opt_path)
          "external-files" =>
            external_files.next_value(map, PathsJSON::deserialize)
          "file-types" =>
            file_types.next_value(map, de => {
              de.deserialize_option(de => {
                @support.deserialize_vec(de, @support.deserialize_string)
              })
            })
          "highlights" => highlights.next_value(map, PathsJSON::deserialize)
          "injections" => injections.next_value(map, PathsJSON::deserialize)
          "locals" => locals.next_value(map, PathsJSON::deserialize)
          "tags" => tags.next_value(map, PathsJSON::deserialize)
          "injection-regex" =>
            injection_regex.next_value(map, deserialize_opt_string)
          "first-line-regex" =>
            first_line_regex.next_value(map, deserialize_opt_string)
          "content-regex" =>
            content_regex.next_value(map, deserialize_opt_string)
          "class-name" => class_name.next_value(map, deserialize_opt_string)
          _ => map.next_value_ignored()
        }
      }
      let name = name.required()
      let camelcase = camelcase.optional()
      let title = title.optional()
      let scope = scope.required()
      let path = path.optional()
      let external_files = external_files.or_default(Empty)
      let file_types = file_types.optional()
      let highlights = highlights.or_default(Empty)
      let injections = injections.or_default(Empty)
      let locals = locals.or_default(Empty)
      let tags = tags.or_default(Empty)
      let injection_regex = injection_regex.optional()
      let first_line_regex = first_line_regex.optional()
      let content_regex = content_regex.optional()
      let class_name = class_name.optional()
      {
        name,
        camelcase,
        title,
        scope,
        path,
        external_files,
        file_types,
        highlights,
        injections,
        locals,
        tags,
        injection_regex,
        first_line_regex,
        content_regex,
        class_name,
      }
    },
  )
}

///|
fn Grammar::to_json(self : Grammar) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["name"] = Json::string(self.name)
  if self.camelcase is Some(v) {
    obj["camelcase"] = Json::string(v)
  }
  if self.title is Some(v) {
    obj["title"] = Json::string(v)
  }
  obj["scope"] = Json::string(self.scope)
  if self.path is Some(v) {
    obj["path"] = Json::string(v)
  }
  if !self.external_files.is_empty() {
    obj["external-files"] = self.external_files.to_json()
  }
  obj["file-types"] = match self.file_types {
    Some(v) => Json::array(v.map(Json::string))
    None => Json::null()
  }
  if !self.highlights.is_empty() {
    obj["highlights"] = self.highlights.to_json()
  }
  if !self.injections.is_empty() {
    obj["injections"] = self.injections.to_json()
  }
  if !self.locals.is_empty() {
    obj["locals"] = self.locals.to_json()
  }
  if !self.tags.is_empty() {
    obj["tags"] = self.tags.to_json()
  }
  if self.injection_regex is Some(v) {
    obj["injection-regex"] = Json::string(v)
  }
  if self.first_line_regex is Some(v) {
    obj["first-line-regex"] = Json::string(v)
  }
  if self.content_regex is Some(v) {
    obj["content-regex"] = Json::string(v)
  }
  if self.class_name is Some(v) {
    obj["class-name"] = Json::string(v)
  }
  Json::object(obj)
}

///|
/// `Deserialize for Version` (semver's `serde` feature).
fn deserialize_version(
  de : @support.Deserializer,
) -> SemverVersion raise @support.SerdeJsonError {
  de.deserialize_str("semver version", string => {
    SemverVersion::parse(string) catch {
      e => raise @support.SerdeJsonError::custom(e.to_string())
    }
  })
}

///|
/// `#[derive(Deserialize)]` of `Author`.
fn Author::deserialize(
  de : @support.Deserializer,
) -> Author raise @support.SerdeJsonError {
  let expecting = "struct Author with 3 elements"
  de.deserialize_struct(
    "struct Author",
    seq => {
      let name = seq.next_field(@support.deserialize_string, 0, expecting)
      let email = seq.next_field(deserialize_opt_string, 1, expecting)
      let url = seq.next_field(deserialize_opt_string, 2, expecting)
      { name, email, url, }
    },
    map => {
      let name : @support.StructField[String] = @support.StructField::new(
        "name",
      )
      let email : @support.StructField[String?] = @support.StructField::new(
        "email",
      )
      let url : @support.StructField[String?] = @support.StructField::new("url")
      while map.next_key() is Some(key) {
        match key {
          "name" => name.next_value(map, @support.deserialize_string)
          "email" => email.next_value(map, deserialize_opt_string)
          "url" => url.next_value(map, deserialize_opt_string)
          _ => map.next_value_ignored()
        }
      }
      let name = name.required()
      let email = email.optional()
      let url = url.optional()
      { name, email, url, }
    },
  )
}

///|
/// `#[derive(Deserialize)]` of `Links`.
fn Links::deserialize(
  de : @support.Deserializer,
) -> Links raise @support.SerdeJsonError {
  let expecting = "struct Links with 2 elements"
  de.deserialize_struct(
    "struct Links",
    seq => {
      let repository = seq.next_field(@support.deserialize_string, 0, expecting)
      let funding = seq.next_field(deserialize_opt_string, 1, expecting)
      { repository, funding, }
    },
    map => {
      let repository : @support.StructField[String] = @support.StructField::new(
        "repository",
      )
      let funding : @support.StructField[String?] = @support.StructField::new(
        "funding",
      )
      while map.next_key() is Some(key) {
        match key {
          "repository" =>
            repository.next_value(map, @support.deserialize_string)
          "funding" => funding.next_value(map, deserialize_opt_string)
          _ => map.next_value_ignored()
        }
      }
      let repository = repository.required()
      let funding = funding.optional()
      { repository, funding, }
    },
  )
}

///|
fn deserialize_opt_authors(
  de : @support.Deserializer,
) -> Array[Author]? raise @support.SerdeJsonError {
  de.deserialize_option(de => @support.deserialize_vec(de, Author::deserialize))
}

///|
fn deserialize_opt_links(
  de : @support.Deserializer,
) -> Links? raise @support.SerdeJsonError {
  de.deserialize_option(Links::deserialize)
}

///|
/// `#[derive(Deserialize)]` of `Metadata` (`namespace` is
/// `#[serde(skip)]`).
fn Metadata::deserialize(
  de : @support.Deserializer,
) -> Metadata raise @support.SerdeJsonError {
  let expecting = "struct Metadata with 5 elements"
  de.deserialize_struct(
    "struct Metadata",
    seq => {
      let version = seq.next_field(deserialize_version, 0, expecting)
      let license = seq.next_field(deserialize_opt_string, 1, expecting)
      let description = seq.next_field(deserialize_opt_string, 2, expecting)
      let authors = seq.next_field(deserialize_opt_authors, 3, expecting)
      let links = seq.next_field(deserialize_opt_links, 4, expecting)
      { version, license, description, authors, links, namespace: None, }
    },
    map => {
      let version : @support.StructField[SemverVersion] = @support.StructField::new(
        "version",
      )
      let license : @support.StructField[String?] = @support.StructField::new(
        "license",
      )
      let description : @support.StructField[String?] = @support.StructField::new(
        "description",
      )
      let authors : @support.StructField[Array[Author]?] = @support.StructField::new(
        "authors",
      )
      let links : @support.StructField[Links?] = @support.StructField::new(
        "links",
      )
      while map.next_key() is Some(key) {
        match key {
          "version" => version.next_value(map, deserialize_version)
          "license" => license.next_value(map, deserialize_opt_string)
          "description" => description.next_value(map, deserialize_opt_string)
          "authors" => authors.next_value(map, deserialize_opt_authors)
          "links" => links.next_value(map, deserialize_opt_links)
          _ => map.next_value_ignored()
        }
      }
      let version = version.required()
      let license = license.optional()
      let description = description.optional()
      let authors = authors.optional()
      let links = links.optional()
      { version, license, description, authors, links, namespace: None, }
    },
  )
}

///|
fn Metadata::to_json(self : Metadata) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["version"] = Json::string(self.version.to_string())
  if self.license is Some(v) {
    obj["license"] = Json::string(v)
  }
  if self.description is Some(v) {
    obj["description"] = Json::string(v)
  }
  if self.authors is Some(authors) {
    obj["authors"] = Json::array(
      authors.map(a => {
        let o : Map[String, Json] = Map([])
        o["name"] = Json::string(a.name)
        if a.email is Some(v) {
          o["email"] = Json::string(v)
        }
        if a.url is Some(v) {
          o["url"] = Json::string(v)
        }
        Json::object(o)
      }),
    )
  }
  if self.links is Some(links) {
    let o : Map[String, Json] = Map([])
    o["repository"] = Json::string(links.repository)
    if links.funding is Some(v) {
      o["funding"] = Json::string(v)
    }
    obj["links"] = Json::object(o)
  }
  Json::object(obj)
}

///|
/// `#[derive(Deserialize)]` of `Bindings` (`#[serde(default)]`; `kotlin` is
/// `#[serde(skip)]`).
fn Bindings::deserialize(
  de : @support.Deserializer,
) -> Bindings raise @support.SerdeJsonError {
  let default = Bindings::default()
  de.deserialize_struct(
    "struct Bindings",
    seq => {
      let bool = @support.Deserializer::deserialize_bool
      let c = seq.next_element(bool).unwrap_or(default.c)
      let go = seq.next_element(bool).unwrap_or(default.go)
      let java = seq.next_element(bool).unwrap_or(default.java)
      let node = seq.next_element(bool).unwrap_or(default.node)
      let python = seq.next_element(bool).unwrap_or(default.python)
      let rust = seq.next_element(bool).unwrap_or(default.rust)
      let swift = seq.next_element(bool).unwrap_or(default.swift)
      let zig = seq.next_element(bool).unwrap_or(default.zig)
      { c, go, java, kotlin: default.kotlin, node, python, rust, swift, zig, }
    },
    map => {
      let bool = @support.Deserializer::deserialize_bool
      let c : @support.StructField[Bool] = @support.StructField::new("c")
      let go : @support.StructField[Bool] = @support.StructField::new("go")
      let java : @support.StructField[Bool] = @support.StructField::new("java")
      let node : @support.StructField[Bool] = @support.StructField::new("node")
      let python : @support.StructField[Bool] = @support.StructField::new(
        "python",
      )
      let rust : @support.StructField[Bool] = @support.StructField::new("rust")
      let swift : @support.StructField[Bool] = @support.StructField::new(
        "swift",
      )
      let zig : @support.StructField[Bool] = @support.StructField::new("zig")
      while map.next_key() is Some(key) {
        match key {
          "c" => c.next_value(map, bool)
          "go" => go.next_value(map, bool)
          "java" => java.next_value(map, bool)
          "node" => node.next_value(map, bool)
          "python" => python.next_value(map, bool)
          "rust" => rust.next_value(map, bool)
          "swift" => swift.next_value(map, bool)
          "zig" => zig.next_value(map, bool)
          _ => map.next_value_ignored()
        }
      }
      {
        c: c.or_default(default.c),
        go: go.or_default(default.go),
        java: java.or_default(default.java),
        kotlin: default.kotlin,
        node: node.or_default(default.node),
        python: python.or_default(default.python),
        rust: rust.or_default(default.rust),
        swift: swift.or_default(default.swift),
        zig: zig.or_default(default.zig),
      }
    },
  )
}

///|
pub fn Bindings::to_json(self : Bindings) -> Json {
  {
    "c": Json::boolean(self.c),
    "go": Json::boolean(self.go),
    "java": Json::boolean(self.java),
    "node": Json::boolean(self.node),
    "python": Json::boolean(self.python),
    "rust": Json::boolean(self.rust),
    "swift": Json::boolean(self.swift),
    "zig": Json::boolean(self.zig),
  }
}

///|
/// `#[derive(Deserialize)]` of `TreeSitterJSON` (`rename_all =
/// "kebab-case"`).
fn TreeSitterJSON::deserialize(
  de : @support.Deserializer,
) -> TreeSitterJSON raise @support.SerdeJsonError {
  let expecting = "struct TreeSitterJSON with 4 elements"
  let grammars_de = (de : @support.Deserializer) => {
    @support.deserialize_vec(de, Grammar::deserialize)
  }
  de.deserialize_struct(
    "struct TreeSitterJSON",
    seq => {
      let schema = seq.next_field(deserialize_opt_string, 0, expecting)
      let grammars = seq.next_field(grammars_de, 1, expecting)
      let metadata = seq.next_field(Metadata::deserialize, 2, expecting)
      let bindings = seq
        .next_element(Bindings::deserialize)
        .unwrap_or(Bindings::default())
      { schema, grammars, metadata, bindings, }
    },
    map => {
      let schema : @support.StructField[String?] = @support.StructField::new(
        "$schema",
      )
      let grammars : @support.StructField[Array[Grammar]] = @support.StructField::new(
        "grammars",
      )
      let metadata : @support.StructField[Metadata] = @support.StructField::new(
        "metadata",
      )
      let bindings : @support.StructField[Bindings] = @support.StructField::new(
        "bindings",
      )
      while map.next_key() is Some(key) {
        match key {
          "$schema" => schema.next_value(map, deserialize_opt_string)
          "grammars" => grammars.next_value(map, grammars_de)
          "metadata" => metadata.next_value(map, Metadata::deserialize)
          "bindings" => bindings.next_value(map, Bindings::deserialize)
          _ => map.next_value_ignored()
        }
      }
      let schema = schema.optional()
      let grammars = grammars.required()
      let metadata = metadata.required()
      let bindings = bindings.or_default(Bindings::default())
      { schema, grammars, metadata, bindings, }
    },
  )
}

///|
/// `serde_json::from_str::<TreeSitterJSON>`.
pub fn TreeSitterJSON::parse(text : String) -> TreeSitterJSON raise JsonError {
  @support.from_str_with(text, TreeSitterJSON::deserialize) catch {
    e => raise JsonError(e.to_string())
  }
}

///|
pub fn TreeSitterJSON::to_json(self : TreeSitterJSON) -> Json {
  {
    "$schema": match self.schema {
      Some(s) => Json::string(s)
      None => Json::null()
    },
    "grammars": Json::array(self.grammars.map(Grammar::to_json)),
    "metadata": self.metadata.to_json(),
    "bindings": self.bindings.to_json(),
  }
}

///|
/// `TreeSitterJSON::from_file`: read `<path>/tree-sitter.json`.
pub async fn TreeSitterJSON::from_file(path : String) -> TreeSitterJSON {
  let path = @support.path_join(path, "tree-sitter.json")
  let text = @support.read_to_string(path) catch {
    e => raise LoaderError::IO(@support.io_error_with_path(e, Some(path)))
  }
  TreeSitterJSON::parse(text) catch {
    JsonError(e) => raise LoaderError::Serialization(e)
  }
}

///|
/// `serde_json::from_str::<TreeSitterJson>` of `read_grammar_version`
/// (crates/generate/src/generate.rs), whose `#[derive(Deserialize)]` types
/// are `TreeSitterJson { metadata: Metadata }` and `Metadata { version:
/// String }`: the `metadata.version` of a `tree-sitter.json`.
pub fn parse_grammar_version_json(text : String) -> String raise JsonError {
  let deserialize_metadata = (de : @support.Deserializer) => {
    de.deserialize_struct(
      "struct Metadata",
      seq => {
        seq.next_field(
          @support.deserialize_string, 0, "struct Metadata with 1 element",
        )
      },
      map => {
        let version : @support.StructField[String] = @support.StructField::new(
          "version",
        )
        while map.next_key() is Some(key) {
          match key {
            "version" => version.next_value(map, @support.deserialize_string)
            _ => map.next_value_ignored()
          }
        }
        version.required()
      },
    )
  }
  let deserialize = (de : @support.Deserializer) => {
    de.deserialize_struct(
      "struct TreeSitterJson",
      seq => {
        seq.next_field(
          deserialize_metadata, 0, "struct TreeSitterJson with 1 element",
        )
      },
      map => {
        let metadata : @support.StructField[String] = @support.StructField::new(
          "metadata",
        )
        while map.next_key() is Some(key) {
          match key {
            "metadata" => metadata.next_value(map, deserialize_metadata)
            _ => map.next_value_ignored()
          }
        }
        metadata.required()
      },
    )
  }
  @support.from_str_with(text, deserialize) catch {
    e => raise JsonError(e.to_string())
  }
}

///|
pub fn TreeSitterJSON::has_multiple_language_configs(
  self : TreeSitterJSON,
) -> Bool {
  self.grammars.length() > 1
}
