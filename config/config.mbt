///|
pub suberror ConfigError {
  InvalidConfig(String)
}

///|
pub(all) struct Grammar {
  name : String
  scope : String
  path : String
  file_types : Array[String]
  highlights : Array[String]
  injections : Array[String]
  locals : Array[String]
  tags : Array[String]
  content_regex : String?
  first_line_regex : String?
  injection_regex : String?
}

///|
pub struct Config {
  grammars : Array[Grammar]
  metadata : Json
}

///|
fn text(
  object : Map[String, Json],
  key : String,
  default? : String,
) -> String raise ConfigError {
  match object.get(key) {
    Some(String(value)) => value
    None | Some(Null) =>
      match default {
        Some(value) => value
        None => raise InvalidConfig("missing '\{key}'")
      }
    _ => raise InvalidConfig("'\{key}' must be a string")
  }
}

///|
fn optional_text(
  object : Map[String, Json],
  key : String,
) -> String? raise ConfigError {
  match object.get(key) {
    None | Some(Null) => None
    _ => Some(text(object, key))
  }
}

///|
fn paths(
  object : Map[String, Json],
  key : String,
) -> Array[String] raise ConfigError {
  match object.get(key) {
    None | Some(Null) => []
    Some(String(value)) => [value]
    Some(Array(items)) =>
      items.map(item => {
        match item {
          String(value) => value
          _ => raise InvalidConfig("'\{key}' must contain strings")
        }
      })
    _ => raise InvalidConfig("'\{key}' must be a string or array")
  }
}

///|
/// Read upstream tree-sitter.json language metadata. Native binding build
/// settings remain opaque because portable MoonBit languages need no C ABI.
pub fn Config::parse(source : String) -> Config raise ConfigError {
  let json = @json.parse(source) catch {
    _ => raise InvalidConfig("invalid JSON")
  }
  guard json is Object(object) else { raise InvalidConfig("expected object") }
  guard object.get("grammars") is Some(Array(items)) else {
    raise InvalidConfig("missing grammars array")
  }
  let seen : Map[String, Bool] = Map([])
  let grammars = items.map(item => {
    guard item is Object(grammar) else {
      raise InvalidConfig("expected grammar object")
    }
    let name = text(grammar, "name")
    if name.is_empty() || seen.contains(name) {
      raise InvalidConfig("empty or duplicate grammar name")
    }
    seen[name] = true
    let result : Grammar = {
      name,
      scope: text(grammar, "scope"),
      path: text(grammar, "path", default="."),
      file_types: paths(grammar, "file-types"),
      highlights: paths(grammar, "highlights"),
      injections: paths(grammar, "injections"),
      locals: paths(grammar, "locals"),
      tags: paths(grammar, "tags"),
      content_regex: optional_text(grammar, "content-regex"),
      first_line_regex: optional_text(grammar, "first-line-regex"),
      injection_regex: optional_text(grammar, "injection-regex"),
    }
    for
      regex in [
        result.content_regex,
        result.first_line_regex,
        result.injection_regex,
      ] {
      if regex is Some(pattern) {
        ignore(score(pattern, ""))
      }
    }
    result
  })
  { grammars, metadata: object.get("metadata").unwrap_or(Json::null()), }
}

///|
fn score(pattern : String, text : String) -> Int32 raise ConfigError {
  let anchored_start = pattern.has_prefix("^")
  let anchored_end = pattern.has_suffix("$") && !pattern.has_suffix("\\$")
  let first = if anchored_start { 1 } else { 0 }
  let last = pattern.length() - (if anchored_end { 1 } else { 0 })
  let regex = @lex.compile(@lex.parse(pattern[first:last].to_owned())) catch {
    _ => raise InvalidConfig("invalid selection regex '\{pattern}'")
  }
  let bytes = @utf8.encode(text)
  let mut offset = 0
  let mut best = -1
  for ;; {
    if regex.match_prefix(bytes, start=offset) is Some(end) &&
      (!anchored_end || end == bytes.length()) {
      best = Int32::max(best, end - offset)
    }
    if anchored_start || offset == bytes.length() {
      break
    }
    offset += @lex.decode(bytes, offset).1
  }
  best
}

///|
/// Select by explicit scope, filename/extension, then shebang/first-line regex.
/// Content regexes disambiguate languages sharing a file type.
pub fn select(
  grammars : Array[Grammar],
  filename : String,
  source : String,
  scope? : String,
) -> Grammar? raise ConfigError {
  if scope is Some(scope) {
    return grammars.filter(g => g.scope == scope).get(0)
  }
  let filename = filename.split("/").last().unwrap().to_owned()
  let extension = filename.split(".").last().unwrap().to_owned()
  let candidates = grammars.filter(g => {
    g.file_types.contains(filename) || g.file_types.contains(extension)
  })
  if !candidates.is_empty() {
    let mut best = candidates[0]
    let mut best_score = -1
    for grammar in candidates {
      let score = match grammar.content_regex {
        Some(regex) => score(regex, source)
        None => 0
      }
      if score > best_score {
        best = grammar
        best_score = score
      }
    }
    return Some(best)
  }
  let first_line = source.split("\n").next().unwrap_or("").to_owned()
  for grammar in grammars {
    if grammar.first_line_regex is Some(regex) && score(regex, first_line) >= 0 {
      return Some(grammar)
    }
  }
  None
}

///|
pub fn select_injection(
  grammars : Array[Grammar],
  name : String,
) -> Grammar? raise ConfigError {
  let mut best = None
  let mut best_score = -1
  for grammar in grammars {
    if grammar.injection_regex is Some(regex) {
      let score = score(regex, name)
      if score > best_score {
        best_score = score
        best = Some(grammar)
      }
    }
  }
  best
}
