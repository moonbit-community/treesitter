// Differential probe (development only): reads the JSON-lines corpus of
// tools/oracle/regex_corpus.py and prints, per pattern, `ERR` when
// `Regex::new` fails, or one `0`/`1` per haystack giving `is_match`.
// tools/oracle/regex_harness prints the same format for the Rust `regex` crate.

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
fn span(m : (Int32, Int32)) -> String {
  "\{m.0}-\{m.1}"
}

///|
/// `<is_match>:<find>:<find_iter>` (the `find` modes of the harness).
fn find_results(regex : @regex.Regex, haystack : Bytes) -> String {
  let found = match regex.find(haystack) {
    Some(m) => span(m)
    None => "N"
  }
  let all = regex.find_iter(haystack).map(span).join(",")
  "\{if regex.is_match(haystack) { 1 } else { 0 }}:\{found}:\{all}"
}

///|
/// Usage: probe <corpus> [is_match|find|find-utf8], as
/// tools/oracle/regex_harness.
async fn main {
  let args = @env.args()
  let text = @fs.read_file(args[1]).text()
  let mode = if args.length() > 2 { args[2] } else { "is_match" }
  guard mode is ("is_match" | "find" | "find-utf8") else {
    abort("unknown mode \{mode}")
  }
  for line in text.split("\n") {
    if line.is_empty() {
      continue
    }
    guard @json.parse(line.to_owned())
      is { "p": String(pattern), "t": Array(texts), .. } else {
      abort("bad corpus line")
    }
    let regex = @regex.Regex::new(pattern, utf8=mode == "find-utf8") catch {
      _ => {
        println("ERR")
        continue
      }
    }
    let haystacks = texts.map(t => {
      guard t is String(hex) else { abort("bad haystack") }
      unhex(hex)
    })
    match mode {
      "is_match" => {
        let sb = StringBuilder()
        for haystack in haystacks {
          sb.write_char(if regex.is_match(haystack) { '1' } else { '0' })
        }
        println(sb.to_string())
      }
      "find" => println(haystacks.map(h => find_results(regex, h)).join(" "))
      _ =>
        println(
          haystacks
          .map(h => {
            (@utf8.decode(h) catch { _ => return "X" }) |> ignore
            find_results(regex, h)
          })
          .join(" "),
        )
    }
  }
}
