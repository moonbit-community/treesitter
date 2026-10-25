// Differential probe (development only): reads the JSON-lines corpus of
// tools/next/regex_corpus.py and prints, per pattern, `ERR` when
// `Regex::new` fails, or one `0`/`1` per haystack giving `is_match`.
// tools/next/regex_harness prints the same format for the Rust `regex` crate.

///|
fn unhex(s : String) -> Bytes {
  let digit = (c : UInt16) => {
    let c = c.to_int()
    if c >= '0' && c <= '9' {
      c - '0'
    } else {
      c - 'a' + 10
    }
  }
  Bytes::makei(s.length() / 2, i => {
    (digit(s[2 * i]) * 16 + digit(s[2 * i + 1])).to_byte()
  })
}

///|
async fn main {
  let args = @env.args()
  let text = @fs.read_file(args[1]).text()
  for line in text.split("\n") {
    if line.is_empty() {
      continue
    }
    guard @json.parse(line.to_owned())
      is { "p": String(pattern), "t": Array(texts), .. } else {
      abort("bad corpus line")
    }
    let regex = @regex.Regex::new(pattern) catch {
      _ => {
        println("ERR")
        continue
      }
    }
    let sb = StringBuilder()
    for t in texts {
      guard t is String(hex) else { abort("bad haystack") }
      sb.write_char(if regex.is_match(unhex(hex)) { '1' } else { '0' })
    }
    println(sb.to_string())
  }
}
