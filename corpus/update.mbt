///|
/// Replace failed expectations with the generated trees, preserving headers,
/// input text and unchanged expectations verbatim. Skipped and successful
/// :error cases are unchanged. A failed case with ERROR/MISSING nodes, a failed
/// :error assertion, or a parser failure raises instead of returning an update.
pub fn update(
  language : @language.Language,
  source : String,
  scanner? : @ts.ExternalScanner,
) -> String raise {
  let entries = parse_entries(source)
  let parser = @ts.Parser::new(language, scanner?)
  let output = StringBuilder()
  let mut copied = 0
  for entry in entries {
    let (result, has_error) = run_case(parser, entry.case)
    if result.passed {
      continue
    }
    if has_error || entry.case.error {
      raise InvalidCorpus(
        "cannot update '\{entry.case.name}': unexpected parse error or failed :error assertion",
      )
    }
    let old = source[entry.output_start:entry.output_end].to_owned()
    let prefix = old.length() - old.trim_start().length()
    let end = Int32::max(prefix, old.trim_end().length())
    output.write_string(source[copied:entry.output_start + prefix].to_owned())
    let replacement = if entry.case.cst {
      result.actual.trim().to_owned()
    } else {
      format_sexp(result.actual)
    }
    let replacement = if source.contains("\r\n") {
      replacement.replace_all(old="\n", new="\r\n")
    } else {
      replacement
    }
    output.write_string(replacement)
    // Even an empty final expectation needs separation from the next header.
    if end == old.length() && entry.output_end < source.length() {
      output.write_string(if source.contains("\r\n") { "\r\n" } else { "\n" })
    }
    copied = entry.output_start + end
  }
  output.write_string(source[copied:].to_owned())
  output.to_string()
}

///|
/// Indent an s-expression syntax tree, retaining field labels and quoted tokens.
pub fn format_sexp(source : String) -> String {
  let chars = source.iter().to_array()
  let tokens : Array[String] = []
  let mut i = 0
  while i < chars.length() {
    let char = chars[i]
    if char is (' ' | '\n' | '\r' | '\t') {
      i += 1
      continue
    }
    if char == '(' || char == ')' {
      tokens.push(char.to_string())
      i += 1
      continue
    }
    let token = StringBuilder()
    if char == '"' || char == '\'' {
      token.write_char(char)
      i += 1
      let mut escaped = false
      while i < chars.length() {
        let next = chars[i]
        token.write_char(next)
        i += 1
        if escaped {
          escaped = false
        } else if next == '\\' {
          escaped = true
        } else if next == char {
          break
        }
      }
    } else {
      while i < chars.length() &&
            !(chars[i] is (' ' | '\n' | '\r' | '\t' | '(' | ')')) {
        token.write_char(chars[i])
        i += 1
      }
    }
    tokens.push(token.to_string())
  }
  let output = StringBuilder()
  let mut depth = 0
  let mut previous = ""
  for token in tokens {
    if token == "(" {
      if previous.has_suffix(":") {
        output.write_char(' ')
      } else if previous != "" {
        output.write_char('\n')
        output.write_string(spaces(depth * 2))
      }
      output.write_char('(')
      depth += 1
    } else if token == ")" {
      depth = Int32::max(0, depth - 1)
      output.write_char(')')
    } else if token.has_suffix(":") {
      output.write_char('\n')
      output.write_string(spaces(depth * 2))
      output.write_string(token)
    } else {
      if previous != "(" && previous != "" {
        output.write_char(' ')
      }
      output.write_string(token)
    }
    previous = token
  }
  output.to_string()
}
