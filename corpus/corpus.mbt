///|
pub(all) struct Case {
  name : String
  input : String
  expected : String
  skip : Bool
  error : Bool
  cst : Bool
}

///|
pub(all) struct Result {
  name : String
  passed : Bool
  skipped : Bool
  expected : String
  actual : String
}

///|
pub suberror CorpusError {
  InvalidCorpus(String)
}

///|
fn delimiter(line : String, c : Char) -> Bool {
  line.length() >= 3 && line.iter().all(ch => ch == c || ch == '\r')
}

///|
/// Parse standard Tree-sitter s-expression corpus entries. Unsupported header
/// modes are diagnosed instead of silently treating them as ordinary tests.
pub fn parse(source : String) -> Array[Case] raise CorpusError {
  let lines = source.split("\n").map(s => s.to_owned()).to_array()
  let cases = []
  let mut i = 0
  while i < lines.length() {
    if !delimiter(lines[i], '=') {
      i += 1
      continue
    }
    i += 1
    let names = []
    let mut skip = false
    let mut error = false
    let mut cst = false
    while i < lines.length() && !delimiter(lines[i], '=') {
      let line = lines[i].trim().to_owned()
      if line == ":skip" {
        skip = true
      } else if line == ":error" {
        error = true
      } else if line == ":cst" {
        cst = true
      } else if line.has_prefix(":") {
        raise InvalidCorpus("unsupported corpus mode: \{line}")
      } else if line != "" {
        names.push(line)
      }
      i += 1
    }
    if i == lines.length() {
      raise InvalidCorpus("unterminated test header")
    }
    i += 1
    let start = i
    while i < lines.length() && !delimiter(lines[i], '-') {
      i += 1
    }
    if i == lines.length() {
      raise InvalidCorpus("missing test separator")
    }
    let input = lines[start:i].join("\n")
    i += 1
    let expected_start = i
    while i < lines.length() && !delimiter(lines[i], '=') {
      i += 1
    }
    let expected = lines[expected_start:i].join("\n").trim().to_owned()
    cases.push({ name: names.join(" "), input, expected, skip, error, cst, })
  }
  cases
}

///|
/// Normalize insignificant s-expression whitespace while preserving quoted text.
pub fn normalize_sexp(source : String) -> String {
  let out = StringBuilder()
  let mut quoted = false
  let mut escaped = false
  let mut space = false
  let mut last = '('
  let mut comment = false
  for c in source {
    if comment {
      if c == '\n' {
        comment = false
        space = true
      }
      continue
    }
    if !quoted && c == ';' {
      comment = true
      continue
    }
    if quoted {
      out.write_char(c)
      if escaped {
        escaped = false
      } else if c == '\\' {
        escaped = true
      } else if c == '"' {
        quoted = false
      }
      last = c
    } else if c is (' ' | '\n' | '\r' | '\t') {
      space = true
    } else {
      if space && last != '(' && c != ')' {
        out.write_char(' ')
      }
      space = false
      out.write_char(c)
      if c == '"' {
        quoted = true
      }
      last = c
    }
  }
  out.to_string()
}

///|
pub fn run(
  language : @language.Language,
  cases : Array[Case],
  scanner? : @ts.ExternalScanner,
) -> Array[Result] raise {
  let parser = @ts.Parser::new(language, scanner?)
  cases.map(case => {
    if case.skip {
      return {
        name: case.name,
        passed: true,
        skipped: true,
        expected: case.expected,
        actual: "",
      }
    }
    let root = parser.parse_string(case.input).root_node() catch {
        error => {
          parser.reset()
          return {
            name: case.name,
            passed: false,
            skipped: false,
            expected: case.expected,
            actual: "parse failed: \{error.to_repr()}",
          }
        }
      }
    let actual = if case.cst {
      render_cst(root, case.input)
    } else {
      root.to_sexp(fields=has_fields(case.expected))
    }
    {
      name: case.name,
      skipped: false,
      expected: case.expected,
      actual,
      passed: if case.error {
        root.has_error()
      } else if case.cst {
        actual.trim().to_owned() == case.expected.trim().to_owned()
      } else {
        normalize_sexp(actual) == normalize_sexp(case.expected)
      },
    }
  })
}

///|
fn has_fields(source : String) -> Bool {
  let mut quote : Char? = None
  let mut escaped = false
  for char in source {
    if quote is Some(delimiter) {
      if escaped {
        escaped = false
      } else if char == '\\' {
        escaped = true
      } else if char == delimiter {
        quote = None
      }
    } else if char == '"' || char == '\'' {
      quote = Some(char)
    } else if char == ':' {
      return true
    }
  }
  false
}
