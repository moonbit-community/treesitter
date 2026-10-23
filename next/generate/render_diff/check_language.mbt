// Sanity checks of `render_language`: arrays read back from upstream's
// `parser.c` text must equal the corresponding `Language` arrays.

///|
/// The text between the `{` that ends the line declaring `name` and the
/// matching `};` line.
fn c_array_body(c : String, name : String) -> String? {
  guard c.find(" " + name + "[") is Some(start) else { return None }
  guard c[start:].find("{\n") is Some(open) else { return None }
  let body_start = start + open + 2
  guard c[body_start:].find("\n};") is Some(close) else { return None }
  Some(c[body_start:body_start + close].to_owned())
}

///|
/// The C identifiers of `enum ts_symbol_identifiers`.
fn symbol_enum(c : String) -> Map[String, Int32] {
  let result : Map[String, Int32] = { "ts_builtin_sym_end": 0 }
  guard c.find("enum ts_symbol_identifiers {\n") is Some(start) else {
    return result
  }
  let rest = c[start:].to_owned()
  for line in rest.split("\n") {
    let line = line.trim()
    if line == "};" {
      break
    }
    if line.find(" = ") is Some(eq) {
      let ident = line[:eq].to_owned()
      let value = line[eq + 3:line.length() - 1].to_owned()
      result[ident] = @string.parse_int(value) catch { _ => continue }
    }
  }
  result
}

///|
/// Resolve one initializer value: a number, `STATE(n)`, `ACTIONS(n)` or a
/// symbol identifier.
fn c_value(enum_values : Map[String, Int32], token : String) -> Int32? {
  let token = token.trim().to_owned()
  for prefix in ["STATE(", "ACTIONS("] {
    if token.has_prefix(prefix) && token.has_suffix(")") {
      return c_value(
        enum_values,
        token[prefix.length():token.length() - 1].to_owned(),
      )
    }
  }
  try @string.parse_int(token) catch {
    _ => enum_values.get(token)
  } noraise {
    value => Some(value)
  }
}

///|
/// The values of a flat initializer, skipping `[index] =` designators.
fn flat_values(
  enum_values : Map[String, Int32],
  body : String,
) -> Array[Int32?] {
  let cleaned = StringBuilder()
  let mut depth = 0
  let mut skip_eq = false
  for ch in body {
    if ch == '[' {
      depth += 1
    } else if ch == ']' {
      depth -= 1
      skip_eq = true
    } else if depth == 0 {
      if skip_eq && ch == '=' {
        skip_eq = false
      } else if ch == '\n' {
        cleaned.write_char(' ')
      } else {
        cleaned.write_char(ch)
      }
    }
  }
  let result = []
  for token in cleaned.to_string().split(",") {
    let token = token.trim().to_owned()
    if token != "" {
      result.push(c_value(enum_values, token))
    }
  }
  result
}

///|
/// `[key] = value,` lines of a designated initializer.
fn designated(body : String) -> Array[(String, String)] {
  let result = []
  for line in body.split("\n") {
    let line = line.trim().to_owned()
    guard line.has_prefix("[") && line.find("] = ") is Some(close) else {
      continue
    }
    let key = line[1:close].to_owned()
    let value = line[close + 4:].to_owned()
    let value = if value.has_suffix(",") {
      value[:value.length() - 1].to_owned()
    } else {
      value
    }
    result.push((key, value))
  }
  result
}

///|
fn strip_call(s : String, prefix : String) -> String? {
  if s.has_prefix(prefix) && s.has_suffix(")") {
    Some(s[prefix.length():s.length() - 1].to_owned())
  } else {
    None
  }
}

///|
/// `ts_parse_actions`, read back as `ParseActionEntry` values.
fn c_parse_actions(
  enum_values : Map[String, Int32],
  body : String,
) -> Array[@language.ParseActionEntry]? {
  let result : Array[@language.ParseActionEntry] = []
  for line in body.split("\n") {
    let line = line.trim().to_owned()
    if line == "" {
      continue
    }
    guard line.find(".count = ") is Some(count_at) &&
      line.find(", .reusable = ") is Some(reusable_at) &&
      line.find("}},") is Some(header_end) else {
      return None
    }
    let count = @string.parse_int(line[count_at + 9:reusable_at]) catch {
      _ => return None
    }
    let reusable = line[reusable_at + 14:header_end].to_owned()
    result.push(Entry(count~, reusable=reusable == "true"))
    let actions = line[header_end + 3:].to_owned()
    // Split on the `,` that ends each action (actions contain commas inside
    // `REDUCE(...)`).
    let mut depth = 0
    let current = StringBuilder()
    for ch in actions {
      if ch == '(' {
        depth += 1
      } else if ch == ')' {
        depth -= 1
      }
      if ch == ',' && depth == 0 {
        let action = current.to_string().trim().to_owned()
        current.reset()
        let entry : @language.ParseActionEntry = if action == "ACCEPT_INPUT()" {
          Accept
        } else if action == "RECOVER()" {
          Recover
        } else if action == "SHIFT_EXTRA()" {
          Shift(state=0, extra=true, repetition=false)
        } else if strip_call(action, "SHIFT_REPEAT(") is Some(state) {
          Shift(
            state=@string.parse_int(state) catch { _ => return None },
            extra=false,
            repetition=true,
          )
        } else if strip_call(action, "SHIFT(") is Some(state) {
          Shift(
            state=@string.parse_int(state) catch { _ => return None },
            extra=false,
            repetition=false,
          )
        } else if strip_call(action, "REDUCE(") is Some(args) {
          let args = args.split(",").map(a => a.trim().to_owned()).collect()
          Reduce(
            symbol=enum_values.get(args[0]).unwrap_or(-1),
            child_count=@string.parse_int(args[1]) catch { _ => return None },
            dynamic_precedence=@string.parse_int(args[2]) catch {
              _ => return None
            },
            production_id=@string.parse_int(args[3]) catch { _ => return None },
          )
        } else {
          return None
        }
        result.push(entry)
      } else {
        current.write_char(ch)
      }
    }
  }
  Some(result)
}

///|
/// Compare `language` against `c`; returns the names of mismatching arrays.
fn check_language(language : @language.Language, c : String) -> Array[String] {
  let problems = []
  let enum_values = symbol_enum(c)
  let check = (name : String, ok : Bool) => if !ok { problems.push(name) }
  let defined = (name : String) => {
    guard c.find("#define \{name} ") is Some(at) else { return -1 }
    let rest = c[at + name.length() + 9:].to_owned()
    guard rest.find("\n") is Some(end) else { return -1 }
    @string.parse_int(rest[:end]) catch {
      _ => -1
    }
  }
  check("STATE_COUNT", defined("STATE_COUNT") == language.state_count)
  check(
    "LARGE_STATE_COUNT",
    defined("LARGE_STATE_COUNT") == language.large_state_count,
  )
  check("SYMBOL_COUNT", defined("SYMBOL_COUNT") == language.symbol_count)
  check("ALIAS_COUNT", defined("ALIAS_COUNT") == language.alias_count)
  check("TOKEN_COUNT", defined("TOKEN_COUNT") == language.token_count)
  check("FIELD_COUNT", defined("FIELD_COUNT") == language.field_count)
  check(
    "PRODUCTION_ID_COUNT",
    defined("PRODUCTION_ID_COUNT") == language.production_id_count,
  )
  check(
    "symbol enum",
    enum_values.length() == language.symbol_count + language.alias_count,
  )
  // ts_symbol_names (strings without escapes only)
  match c_array_body(c, "ts_symbol_names") {
    Some(body) => {
      let entries = designated(body)
      check(
        "ts_symbol_names",
        entries.length() == language.symbol_names.length(),
      )
      for entry in entries {
        let (key, value) = entry
        if !value.contains("\\") {
          check(
            "ts_symbol_names",
            enum_values
            .get(key)
            .map(v => "\"" + language.symbol_names[v] + "\"") ==
            Some(value),
          )
        }
      }
    }
    None => check("ts_symbol_names", false)
  }
  // ts_symbol_map
  match c_array_body(c, "ts_symbol_map") {
    Some(body) =>
      for entry in designated(body) {
        let (key, value) = entry
        check(
          "ts_symbol_map",
          enum_values.get(key).map(k => language.public_symbol_map[k]) ==
          enum_values.get(value),
        )
      }
    None => check("ts_symbol_map", false)
  }
  // ts_primary_state_ids
  match c_array_body(c, "ts_primary_state_ids") {
    Some(body) =>
      check(
        "ts_primary_state_ids",
        flat_values(enum_values, body) ==
        language.primary_state_ids.map(v => Some(v)),
      )
    None => check("ts_primary_state_ids", false)
  }
  // ts_non_terminal_alias_map
  match c_array_body(c, "ts_non_terminal_alias_map") {
    Some(body) =>
      check(
        "ts_non_terminal_alias_map",
        flat_values(enum_values, body) == language.alias_map.map(v => Some(v)),
      )
    None => check("ts_non_terminal_alias_map", false)
  }
  // ts_parse_table
  match c_array_body(c, "ts_parse_table") {
    Some(body) => {
      let table = Array::make(language.parse_table.length(), 0)
      let mut row = -1
      for line in body.split("\n") {
        let line = line.trim().to_owned()
        if strip_call(line, "[STATE(") is Some(_) || line.has_prefix("[STATE(") {
          row += 1
          continue
        }
        for entry in designated(line) {
          let (key, value) = entry
          match (enum_values.get(key), c_value(enum_values, value)) {
            (Some(k), Some(v)) => table[row * language.symbol_count + k] = v
            _ => check("ts_parse_table", false)
          }
        }
      }
      check("ts_parse_table", table == language.parse_table)
    }
    None => check("ts_parse_table", false)
  }
  // ts_small_parse_table / ts_small_parse_table_map
  match c_array_body(c, "ts_small_parse_table") {
    Some(body) =>
      check(
        "ts_small_parse_table",
        flat_values(enum_values, body) ==
        language.small_parse_table.map(v => Some(v)),
      )
    None => check("ts_small_parse_table", language.small_parse_table.is_empty())
  }
  match c_array_body(c, "ts_small_parse_table_map") {
    Some(body) =>
      check(
        "ts_small_parse_table_map",
        flat_values(enum_values, body) ==
        language.small_parse_table_map.map(v => Some(v)),
      )
    None =>
      check(
        "ts_small_parse_table_map",
        language.small_parse_table_map.is_empty(),
      )
  }
  // ts_parse_actions
  match c_array_body(c, "ts_parse_actions") {
    Some(body) =>
      check(
        "ts_parse_actions",
        c_parse_actions(enum_values, body) == Some(language.parse_actions),
      )
    None => check("ts_parse_actions", false)
  }
  // ts_lex_modes
  match c_array_body(c, "ts_lex_modes") {
    Some(body) => {
      let modes = []
      for entry in designated(body) {
        let value = entry.1
        if value == "{(TSStateId)(-1),}" {
          modes.push(@language.LexMode::{
            lex_state: 65535,
            external_lex_state: 0,
            reserved_word_set_id: 0,
          })
          continue
        }
        let mut lex_state = 0
        let mut external_lex_state = 0
        let mut reserved_word_set_id = 0
        for part in value[1:value.length() - 1].split(",") {
          let part = part.trim().to_owned()
          guard part.find(" = ") is Some(eq) else { continue }
          let number = @string.parse_int(part[eq + 3:]) catch { _ => -1 }
          if part.has_prefix(".lex_state") {
            lex_state = number
          } else if part.has_prefix(".external_lex_state") {
            external_lex_state = number
          } else if part.has_prefix(".reserved_word_set_id") {
            reserved_word_set_id = number
          }
        }
        modes.push({ lex_state, external_lex_state, reserved_word_set_id, })
      }
      check("ts_lex_modes", modes == language.lex_modes)
    }
    None => check("ts_lex_modes", false)
  }
  // ts_field_map_entries
  match c_array_body(c, "ts_field_map_entries") {
    Some(body) => {
      let count = body.split("\n").filter(l => l.trim().has_prefix("{")).count()
      check(
        "ts_field_map_entries",
        count == language.field_map_entries.length(),
      )
    }
    None => check("ts_field_map_entries", language.field_map_entries.is_empty())
  }
  // ts_external_scanner_symbol_map
  match c_array_body(c, "ts_external_scanner_symbol_map") {
    Some(body) =>
      check(
        "ts_external_scanner_symbol_map",
        designated(body).map(e => enum_values.get(e.1)) ==
        language.external_scanner.symbol_map.map(v => Some(v)),
      )
    None =>
      check(
        "ts_external_scanner_symbol_map",
        language.external_scanner.symbol_map.is_empty(),
      )
  }
  // ts_supertype_map_entries
  match c_array_body(c, "ts_supertype_map_entries") {
    Some(body) =>
      check(
        "ts_supertype_map_entries",
        flat_values(enum_values, body) ==
        language.supertype_map_entries.map(v => Some(v)),
      )
    None =>
      check(
        "ts_supertype_map_entries",
        language.supertype_map_entries.is_empty(),
      )
  }
  // ts_reserved_words: rows of identifiers, zero padded in the Language.
  match c_array_body(c, "ts_reserved_words") {
    Some(body) => {
      let values = flat_values(
        enum_values,
        body.replace_all(old="{", new="").replace_all(old="}", new=""),
      )
      let expected = language.reserved_words
        .filter(v => v != 0)
        .map(v => Some(v))
      check("ts_reserved_words", values == expected)
    }
    None => check("ts_reserved_words", language.reserved_words.is_empty())
  }
  dedup_names(problems)
}

///|
fn dedup_names(names : Array[String]) -> Array[String] {
  let seen : Set[String] = Set([])
  names.filter(name => {
    if seen.contains(name) {
      false
    } else {
      seen.add(name)
      true
    }
  })
}
