// Differential probe (development only): reads a JSON-lines corpus of
// `{"p": pattern, "f": flags}` and prints, per case, a canonical dump of
// regex-syntax's HIR (`RS`) and of tree-sitter's `pattern::parse` (`TS`).
// The Rust counterpart prints the same format.

///|
fn hex(n : Int32) -> String {
  let digits = "0123456789abcdef"
  if n == 0 {
    return "0"
  }
  let buf = []
  let mut n = n
  while n > 0 {
    buf.push(digits[n % 16].to_int().unsafe_to_char())
    n = n / 16
  }
  buf.rev_in_place()
  String::from_array(buf)
}

///|
fn hex2(n : Int32) -> String {
  let h = hex(n)
  if h.length() < 2 {
    "0" + h
  } else {
    h
  }
}

///|
fn esc(s : String) -> String {
  s
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="\n", new="\\n")
  .replace_all(old="\r", new="\\r")
}

///|
fn look_name(l : @hir.Look) -> String {
  match l {
    Start => "Start"
    End => "End"
    StartLF => "StartLF"
    EndLF => "EndLF"
    StartCRLF => "StartCRLF"
    EndCRLF => "EndCRLF"
    WordAscii => "WordAscii"
    WordAsciiNegate => "WordAsciiNegate"
    WordUnicode => "WordUnicode"
    WordUnicodeNegate => "WordUnicodeNegate"
    WordStartAscii => "WordStartAscii"
    WordEndAscii => "WordEndAscii"
    WordStartUnicode => "WordStartUnicode"
    WordEndUnicode => "WordEndUnicode"
    WordStartHalfAscii => "WordStartHalfAscii"
    WordEndHalfAscii => "WordEndHalfAscii"
    WordStartHalfUnicode => "WordStartHalfUnicode"
    WordEndHalfUnicode => "WordEndHalfUnicode"
  }
}

///|
fn dump(h : @hir.Hir, out : StringBuilder) -> Unit {
  match h.kind() {
    Empty => out.write_char('E')
    Literal(Literal(bytes)) => {
      out.write_string("L(")
      out.write_string(
        bytes.iter().map(b => hex2(b.to_int())).collect().join(" "),
      )
      out.write_char(')')
    }
    Class(Unicode(c)) => {
      out.write_string("U[")
      out.write_string(
        c
        .ranges()
        .iter()
        .map(r => "\{hex(r.start())}-\{hex(r.end())}")
        .collect()
        .join(","),
      )
      out.write_char(']')
    }
    Class(Bytes(c)) => {
      out.write_string("B[")
      out.write_string(
        c
        .ranges()
        .iter()
        .map(r => "\{hex(r.start().to_int())}-\{hex(r.end().to_int())}")
        .collect()
        .join(","),
      )
      out.write_char(']')
    }
    Look(l) => out.write_string("K(\{look_name(l)})")
    Repetition(r) => {
      let max = match r.max {
        Some(m) => m.to_string()
        None => "_"
      }
      out.write_string(
        "R{\{r.min},\{max},\{if r.greedy { "g" } else { "ng" }}}(",
      )
      dump(r.sub, out)
      out.write_char(')')
    }
    Capture(c) => {
      out.write_string("C{\{c.index},\{c.name.unwrap_or("_")}}(")
      dump(c.sub, out)
      out.write_char(')')
    }
    Concat(xs) => {
      out.write_string("S(")
      for i, x in xs {
        if i > 0 {
          out.write_char(';')
        }
        dump(x, out)
      }
      out.write_char(')')
    }
    Alternation(xs) => {
      out.write_string("A(")
      for i, x in xs {
        if i > 0 {
          out.write_char('|')
        }
        dump(x, out)
      }
      out.write_char(')')
    }
  }
}

///|
fn span(s : @ast.Span) -> String {
  "\{s.start.offset}:\{s.start.line}:\{s.start.column}..\{s.end.offset}:\{s.end.line}:\{s.end.column}"
}

///|
fn rs(p : String, ci : Bool) -> String {
  let ast = @ast.ParserBuilder::new().build().parse(p) catch {
      e => {
        let aux = match e.auxiliary_span() {
          Some(s) => span(s)
          None => "_"
        }
        return "AERR(\{e.kind()})@\{span(e.span())}+\{aux}"
      }
    }
  let h = @hir.TranslatorBuilder::new()
    .utf8(false)
    .case_insensitive(ci)
    .build()
    .translate(p, ast) catch {
      e => return "HERR(\{e.kind()})@\{span(e.span())}"
    }
  let out = StringBuilder()
  dump(h, out)
  out.to_string()
}

///|
fn ts(p : String, f : String) -> String {
  let s = p
    .replace_all(old="\\w", new="[0-9A-Za-z_]")
    .replace_all(old="\\s", new="[\\t-\\r ]")
    .replace_all(old="\\d", new="[0-9]")
    .replace_all(old="\\W", new="[^0-9A-Za-z_]")
    .replace_all(old="\\S", new="[^\\t-\\r ]")
    .replace_all(old="\\D", new="[^0-9]")
  let h = @generate.pattern_parse(s, f.contains("i")) catch {
    e => return "TSERR(\{esc(e.to_string())})"
  }
  let out = StringBuilder()
  dump(h, out)
  out.to_string()
}

///|
async fn main {
  let args = @env.args()
  if args[1] == "nfa" {
    for path in args[2:] {
      println("GRAMMAR \{path}")
      let dump = nfa_run(@fs.read_file(path).text())
      if dump.length() > 0 {
        println(dump.view(end_offset=dump.length() - 1))
      }
    }
    return
  }
  let text = @fs.read_file(args[1]).text()
  for line in text.split("\n") {
    if line.is_empty() {
      continue
    }
    guard @json.parse(line.to_owned()) is { "p": String(p), "f": String(f), .. } else {
      abort("bad corpus line")
    }
    println("RS\t\{rs(p, f.contains("i"))}")
    println("TS\t\{ts(p, f)}")
  }
}
