///|
fn unicode_property(name : String) -> CharSet? {
  let normalized = StringBuilder()
  for c in name {
    if c != '_' && c != '-' && c != ' ' {
      normalized.write_char(
        if c >= 'A' && c <= 'Z' {
          (c.to_int() + 32).unsafe_to_char()
        } else {
          c
        },
      )
    }
  }
  let name = normalized.to_string()
  let pieces = name.split("=").to_array()
  if pieces.length() == 2 {
    let value = pieces[1].to_owned()
    return match pieces[0].to_owned() {
      "gc" | "generalcategory" => unicode_general_category(value)
      "sc" | "script" => unicode_script(value)
      "scx" | "scriptextensions" => unicode_script_extension(value)
      _ => None
    }
  }
  if name == "any" {
    return Some(CharSet::new([(0, 0x10ffff)]))
  }
  if name == "ascii" {
    return Some(CharSet::new([(0, 127)]))
  }
  if unicode_general_category(name) is Some(set) {
    return Some(set)
  }
  if unicode_script(name) is Some(set) {
    return Some(set)
  }
  unicode_property_bool(name)
}
