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
pub impl Show for JsonError with output(self, logger) {
  let JsonError(message) = self
  logger.write_string(message)
}

///|
/// `Config`: the loader's part of `config.json`.
pub(all) struct LoaderConfig {
  parser_directories : Array[String]
}

///|
/// `Config::get::<Config>()`: `parser-directories` with `~` and `$HOME`
/// expanded (`deserialize_parser_directories`).
pub fn LoaderConfig::from_json(json : Json) -> LoaderConfig raise JsonError {
  let dirs = []
  match json {
    { "parser-directories": value, .. } =>
      match value {
        Array(items) =>
          for item in items {
            guard item is String(path) else {
              raise JsonError(
                "invalid type: \{json_type_name(item)}, expected a path",
              )
            }
            dirs.push(path)
          }
        _ =>
          raise JsonError(
            "invalid type: \{json_type_name(value)}, expected a sequence",
          )
      }
    Object(_) => ()
    _ =>
      raise JsonError(
        "invalid type: \{json_type_name(json)}, expected struct Config",
      )
  }
  match @support.home_dir() {
    Some(home) => { parser_directories: dirs.map(p => standardize_path(p, home)) }
    None => { parser_directories: dirs }
  }
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
  { "parser-directories": Json::array(self.parser_directories.map(Json::string)) }
}

///|
fn json_type_name(json : Json) -> String {
  match json {
    Null => "null"
    True => "boolean `true`"
    False => "boolean `false`"
    Number(n, ..) =>
      if n == n.floor() {
        "integer `\{n.to_int64()}`"
      } else {
        "floating point `\{n}`"
      }
    String(s) => "string \"\{s}\""
    Array(_) => "sequence"
    Object(_) => "map"
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
pub fn PathsJSON::to_variable_value(self : PathsJSON, default : String) -> String {
  match self {
    Empty => default
    Single(p) => p
    Multiple(paths) => paths.get(0).unwrap_or("")
  }
}

///|
fn PathsJSON::from_json(json : Json?) -> PathsJSON raise JsonError {
  match json {
    None | Some(Null) => Empty
    Some(String(s)) => Single(s)
    Some(Array(items)) =>
      Multiple(
        items.map(item => match item {
          String(s) => s
          _ =>
            raise JsonError(
              "data did not match any variant of untagged enum PathsJSON",
            )
        }),
      )
    Some(_) =>
      raise JsonError("data did not match any variant of untagged enum PathsJSON")
  }
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
      "c" => out = { ..out, c: true }
      "go" => out = { ..out, go: true }
      "java" => out = { ..out, java: true }
      "node" => out = { ..out, node: true }
      "python" => out = { ..out, python: true }
      "rust" => out = { ..out, rust: true }
      "swift" => out = { ..out, swift: true }
      "zig" => out = { ..out, zig: true }
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
fn opt_string(obj : Map[String, Json], key : String) -> String? raise JsonError {
  match obj.get(key) {
    None | Some(Null) => None
    Some(String(s)) => Some(s)
    Some(other) =>
      raise JsonError(
        "invalid type: \{json_type_name(other)}, expected a string",
      )
  }
}

///|
fn req_string(obj : Map[String, Json], key : String) -> String raise JsonError {
  match obj.get(key) {
    Some(String(s)) => s
    None => raise JsonError("missing field `\{key}`")
    Some(other) =>
      raise JsonError(
        "invalid type: \{json_type_name(other)}, expected a string",
      )
  }
}

///|
fn opt_bool(obj : Map[String, Json], key : String, default : Bool) -> Bool raise JsonError {
  match obj.get(key) {
    None => default
    Some(True) => true
    Some(False) => false
    Some(other) =>
      raise JsonError(
        "invalid type: \{json_type_name(other)}, expected a boolean",
      )
  }
}

///|
fn as_object(json : Json, what : String) -> Map[String, Json] raise JsonError {
  match json {
    Object(obj) => obj
    other =>
      raise JsonError("invalid type: \{json_type_name(other)}, expected \{what}")
  }
}

///|
fn Grammar::from_json(json : Json) -> Grammar raise JsonError {
  let obj = as_object(json, "struct Grammar")
  let file_types = match obj.get("file-types") {
    None | Some(Null) => None
    Some(Array(items)) =>
      Some(
        items.map(i => match i {
          String(s) => s
          other =>
            raise JsonError(
              "invalid type: \{json_type_name(other)}, expected a string",
            )
        }),
      )
    Some(other) =>
      raise JsonError(
        "invalid type: \{json_type_name(other)}, expected a sequence",
      )
  }
  {
    name: req_string(obj, "name"),
    camelcase: opt_string(obj, "camelcase"),
    title: opt_string(obj, "title"),
    scope: req_string(obj, "scope"),
    path: opt_string(obj, "path"),
    external_files: PathsJSON::from_json(obj.get("external-files")),
    file_types,
    highlights: PathsJSON::from_json(obj.get("highlights")),
    injections: PathsJSON::from_json(obj.get("injections")),
    locals: PathsJSON::from_json(obj.get("locals")),
    tags: PathsJSON::from_json(obj.get("tags")),
    injection_regex: opt_string(obj, "injection-regex"),
    first_line_regex: opt_string(obj, "first-line-regex"),
    content_regex: opt_string(obj, "content-regex"),
    class_name: opt_string(obj, "class-name"),
  }
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
fn Metadata::from_json(json : Json) -> Metadata raise JsonError {
  let obj = as_object(json, "struct Metadata")
  let version_text = req_string(obj, "version")
  let version = SemverVersion::parse(version_text) catch {
    SemverError(e) => raise JsonError(e)
  }
  let authors = match obj.get("authors") {
    None | Some(Null) => None
    Some(Array(items)) =>
      Some(
        items.map(item => {
          let a = as_object(item, "struct Author")
          Author::{
            name: req_string(a, "name"),
            email: opt_string(a, "email"),
            url: opt_string(a, "url"),
          }
        }),
      )
    Some(other) =>
      raise JsonError(
        "invalid type: \{json_type_name(other)}, expected a sequence",
      )
  }
  let links = match obj.get("links") {
    None | Some(Null) => None
    Some(l) => {
      let l = as_object(l, "struct Links")
      Some(Links::{
        repository: req_string(l, "repository"),
        funding: opt_string(l, "funding"),
      })
    }
  }
  {
    version,
    license: opt_string(obj, "license"),
    description: opt_string(obj, "description"),
    authors,
    links,
    namespace: None,
  }
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
fn Bindings::from_json(json : Json?) -> Bindings raise JsonError {
  let d = Bindings::default()
  match json {
    None => d
    Some(json) => {
      let obj = as_object(json, "struct Bindings")
      {
        c: opt_bool(obj, "c", d.c),
        go: opt_bool(obj, "go", d.go),
        java: opt_bool(obj, "java", d.java),
        kotlin: d.kotlin,
        node: opt_bool(obj, "node", d.node),
        python: opt_bool(obj, "python", d.python),
        rust: opt_bool(obj, "rust", d.rust),
        swift: opt_bool(obj, "swift", d.swift),
        zig: opt_bool(obj, "zig", d.zig),
      }
    }
  }
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
/// Deserialize `tree-sitter.json` text.
pub fn TreeSitterJSON::parse(text : String) -> TreeSitterJSON raise JsonError {
  let json = @support.parse_json(text) catch {
    e => raise JsonError(@config.json_error_message(e))
  }
  let obj = as_object(json, "struct TreeSitterJSON")
  let grammars = match obj.get("grammars") {
    Some(Array(items)) => items.map(Grammar::from_json)
    None => raise JsonError("missing field `grammars`")
    Some(other) =>
      raise JsonError(
        "invalid type: \{json_type_name(other)}, expected a sequence",
      )
  }
  let metadata = match obj.get("metadata") {
    Some(m) => Metadata::from_json(m)
    None => raise JsonError("missing field `metadata`")
  }
  {
    schema: opt_string(obj, "$schema"),
    grammars,
    metadata,
    bindings: Bindings::from_json(obj.get("bindings")),
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
  let text = @fs.read_file(path).text() catch {
    e => raise LoaderError::IO(@support.io_error_with_path(e, Some(path)))
  }
  TreeSitterJSON::parse(text) catch {
    JsonError(e) => raise LoaderError::Serialization(e)
  }
}

///|
pub fn TreeSitterJSON::has_multiple_language_configs(
  self : TreeSitterJSON,
) -> Bool {
  self.grammars.length() > 1
}
