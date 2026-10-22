///|
pub suberror ScriptError {
  InvalidScript(String)
}

///|
/// Split the standard mbtx import prelude from its body. Preserve line numbers
/// in the body for compiler diagnostics. String/comment contents do not close
/// the import block. Package imports retain their MoonBit aliases.
pub fn prepare(source : String) -> (String, String) raise ScriptError {
  let chars = source.iter().to_array()
  let mut i = 0
  while i < chars.length() {
    if chars[i] is (' ' | '\t' | '\r' | '\n') {
      i += 1
      continue
    }
    if chars[i] == '/' && chars.get(i + 1) == Some('/') {
      while i < chars.length() && chars[i] != '\n' {
        i += 1
      }
      continue
    }
    break
  }
  let start = i
  for c in "import" {
    if chars.get(i) != Some(c) {
      raise InvalidScript("grammar.mbtx must start with an import block")
    }
    i += 1
  }
  while chars.get(i) is Some(' ' | '\t' | '\r' | '\n') {
    i += 1
  }
  if chars.get(i) != Some('{') {
    raise InvalidScript("expected '{' after import")
  }
  i += 1
  let mut quoted = false
  let mut escaped = false
  while i < chars.length() {
    let c = chars[i]
    if quoted {
      if escaped {
        escaped = false
      } else if c == '\\' {
        escaped = true
      } else if c == '"' {
        quoted = false
      }
    } else if c == '"' {
      quoted = true
    } else if c == '/' && chars.get(i + 1) == Some('/') {
      while i < chars.length() && chars[i] != '\n' {
        i += 1
      }
      continue
    } else if c == '}' {
      let imports = String::from_array(chars[start:i + 1])
      let body = chars.copy()
      for j in start..<=i {
        if body[j] != '\n' && body[j] != '\r' {
          body[j] = ' '
        }
      }
      return (imports, String::from_array(body))
    }
    i += 1
  }
  raise InvalidScript("unterminated import block")
}
