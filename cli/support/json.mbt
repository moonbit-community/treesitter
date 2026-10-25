// serde_json's serializers (`to_string`, `to_string_pretty`) over MoonBit's
// `Json`, with serde_json's escaping and `PrettyFormatter` layout. Object
// keys keep their insertion order (`preserve_order`). A number with a
// `repr` is written as that text (see `Value::to_json`).

///|
fn write_json_string(sb : StringBuilder, s : String) -> Unit {
  sb.write_char('"')
  for c in s {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      '\b' => sb.write_string("\\b")
      '\u{0C}' => sb.write_string("\\f")
      _ =>
        if c.to_int() < 0x20 {
          let hex = "0123456789abcdef"
          sb.write_string("\\u00")
          sb.write_char(hex.get_char(c.to_int() >> 4).unwrap())
          sb.write_char(hex.get_char(c.to_int() & 15).unwrap())
        } else {
          sb.write_char(c)
        }
    }
  }
  sb.write_char('"')
}

///|
/// A number as serde_json prints it: integers without a fraction, other
/// values in their shortest round-trip form.
fn write_json_number(sb : StringBuilder, n : Double, repr : String?) -> Unit {
  match repr {
    Some(r) => sb.write_string(r)
    None =>
      if n == n.floor() && n.abs() < 9007199254740992.0 {
        sb.write_string(n.to_int64().to_string())
      } else {
        sb.write_string(n.to_string())
      }
  }
}

///|
fn write_json(
  sb : StringBuilder,
  value : Json,
  pretty : Bool,
  indent : Int32,
) -> Unit {
  match value {
    Null => sb.write_string("null")
    True => sb.write_string("true")
    False => sb.write_string("false")
    Number(n, repr~) => write_json_number(sb, n, repr)
    String(s) => write_json_string(sb, s)
    Array(items) => {
      if items.is_empty() {
        sb.write_string("[]")
        return
      }
      sb.write_char('[')
      for i, item in items {
        if i > 0 {
          sb.write_char(',')
        }
        if pretty {
          sb.write_char('\n')
          sb.write_string("  ".repeat(indent + 1))
        }
        write_json(sb, item, pretty, indent + 1)
      }
      if pretty {
        sb.write_char('\n')
        sb.write_string("  ".repeat(indent))
      }
      sb.write_char(']')
    }
    Object(map) => {
      if map.is_empty() {
        sb.write_string("{}")
        return
      }
      sb.write_char('{')
      let mut first = true
      for key, item in map {
        if !first {
          sb.write_char(',')
        }
        first = false
        if pretty {
          sb.write_char('\n')
          sb.write_string("  ".repeat(indent + 1))
        }
        write_json_string(sb, key)
        sb.write_string(if pretty { ": " } else { ":" })
        write_json(sb, item, pretty, indent + 1)
      }
      if pretty {
        sb.write_char('\n')
        sb.write_string("  ".repeat(indent))
      }
      sb.write_char('}')
    }
  }
}

///|
/// `serde_json::to_string_pretty`.
pub fn to_string_pretty(value : Json) -> String {
  let sb = StringBuilder()
  write_json(sb, value, true, 0)
  sb.to_string()
}

///|
/// `serde_json::to_string`.
pub fn to_string(value : Json) -> String {
  let sb = StringBuilder()
  write_json(sb, value, false, 0)
  sb.to_string()
}

///|
/// `serde_json::from_str::<Value>` as a core `Json` whose numbers carry
/// serde_json's text as their `repr` (see `Value::to_json`), so that
/// re-serializing it gives serde_json's output.
pub fn parse_json(text : String) -> Json raise SerdeJsonError {
  from_str(text).to_json()
}
