// Port of the case conversions of the `heck` crate (0.5.0) that init.rs and
// main.rs use: `to_kebab_case`, `to_snake_case`, `to_shouty_snake_case` and
// `to_upper_camel_case`, all built on heck's `transform` word splitter.
//
// Character classes and case mappings are exact for ASCII. Non-ASCII
// characters are treated as alphanumeric and uncased (Rust would consult the
// Unicode tables); grammar names are C identifiers, so this does not arise
// for names that `tree-sitter generate` accepts.

///|
fn heck_is_alphanumeric(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c.is_ascii_digit() || !c.is_ascii()
}

///|
fn heck_is_lowercase(c : Char) -> Bool {
  c.is_ascii_lowercase()
}

///|
fn heck_is_uppercase(c : Char) -> Bool {
  c.is_ascii_uppercase()
}

///|
/// Tracks the current 'mode' of the transformation algorithm as it scans the
/// input string.
priv enum WordMode {
  /// There have been no lowercase or uppercase characters in the current
  /// word.
  Boundary
  /// The previous cased character in the current word is lowercase.
  Lowercase
  /// The previous cased character in the current word is uppercase.
  Uppercase
} derive(Eq)

///|
/// `heck::transform`: split `s` into words, calling `with_word` for each word
/// and `boundary` between words.
fn transform(
  s : String,
  with_word : (String) -> Unit,
  boundary : () -> Unit,
) -> Unit {
  let mut first_word = true
  // `s.split(|c: char| !c.is_alphanumeric())`
  let words : Array[Array[Char]] = [[]]
  for c in s {
    if heck_is_alphanumeric(c) {
      words[words.length() - 1].push(c)
    } else {
      words.push([])
    }
  }
  for word in words {
    let mut init = 0
    let mut mode = Boundary
    for i in 0..<word.length() {
      let c = word[i]
      if i + 1 < word.length() {
        let next_i = i + 1
        let next = word[next_i]
        // The mode including the current character, assuming the current
        // character does not result in a word boundary.
        let next_mode = if heck_is_lowercase(c) {
          Lowercase
        } else if heck_is_uppercase(c) {
          Uppercase
        } else {
          mode
        }
        // Word boundary after if current is not uppercase and next is
        // uppercase
        if next_mode == Lowercase && heck_is_uppercase(next) {
          if !first_word {
            boundary()
          }
          with_word(String::from_array(word[init:next_i]))
          first_word = false
          init = next_i
          mode = Boundary
          // Otherwise if current and previous are uppercase and next is
          // lowercase, word boundary before
        } else if mode == Uppercase &&
          heck_is_uppercase(c) &&
          heck_is_lowercase(next) {
          if !first_word {
            boundary()
          } else {
            first_word = false
          }
          with_word(String::from_array(word[init:i]))
          init = i
          mode = Boundary
          // Otherwise no word boundary, just update the mode
        } else {
          mode = next_mode
        }
      } else {
        // Collect trailing characters as a word
        if !first_word {
          boundary()
        } else {
          first_word = false
        }
        with_word(String::from_array(word[init:]))
        break
      }
    }
  }
}

///|
fn heck_lowercase(s : String, out : StringBuilder) -> Unit {
  for c in s {
    out.write_char(c.to_ascii_lowercase())
  }
}

///|
fn heck_uppercase(s : String, out : StringBuilder) -> Unit {
  for c in s {
    out.write_char(c.to_ascii_uppercase())
  }
}

///|
fn heck_capitalize(s : String, out : StringBuilder) -> Unit {
  let mut first = true
  for c in s {
    if first {
      out.write_char(c.to_ascii_uppercase())
      first = false
    } else {
      out.write_char(c.to_ascii_lowercase())
    }
  }
}

///|
/// `ToKebabCase::to_kebab_case`.
fn to_kebab_case(s : String) -> String {
  let out = StringBuilder()
  transform(s, w => heck_lowercase(w, out), () => out.write_char('-'))
  out.to_string()
}

///|
/// `ToSnakeCase::to_snake_case`.
fn to_snake_case(s : String) -> String {
  let out = StringBuilder()
  transform(s, w => heck_lowercase(w, out), () => out.write_char('_'))
  out.to_string()
}

///|
/// `ToShoutySnakeCase::to_shouty_snake_case`.
fn to_shouty_snake_case(s : String) -> String {
  let out = StringBuilder()
  transform(s, w => heck_uppercase(w, out), () => out.write_char('_'))
  out.to_string()
}

///|
/// `ToUpperCamelCase::to_upper_camel_case`.
fn to_upper_camel_case(s : String) -> String {
  let out = StringBuilder()
  transform(s, w => heck_capitalize(w, out), () => ())
  out.to_string()
}
