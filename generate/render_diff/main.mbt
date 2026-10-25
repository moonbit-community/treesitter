// Differential test of `render_c_code` / `render_language` against upstream.
//
// Usage: moon run --target native generate/render_diff -- [dir] [names...]
// where `dir` defaults to `_build/render_dump` (see tools/next/render_dump.sh).
// For every `<name>/input<variant>.json`, renders C from the dumped inputs and
// compares it byte for byte with `<name>/parser<variant>.c`, then checks the
// `Language` arrays against that C text.

///|
/// The first differing line, for diagnostics.
fn first_difference(expected : String, actual : String) -> String {
  let expected_lines = expected.split("\n").collect()
  let actual_lines = actual.split("\n").collect()
  let n = if expected_lines.length() < actual_lines.length() {
    expected_lines.length()
  } else {
    actual_lines.length()
  }
  for i in 0..<n {
    if expected_lines[i] != actual_lines[i] {
      return "line \{i + 1}:\n  expected: \{expected_lines[i]}\n  actual:   \{actual_lines[i]}"
    }
  }
  "line \{n + 1}: length differs (\{expected_lines.length()} vs \{actual_lines.length()} lines)"
}

///|
async fn main {
  let args = @env.args()
  let dir = if args.length() > 1 { args[1] } else { "_build/render_dump" }
  let only = if args.length() > 2 { args[2:].to_owned() } else { [] }
  let names = @fs.readdir(dir, sort=true)
  let mut total = 0
  let mut c_matches = 0
  let mut language_matches = 0
  for name in names {
    if !only.is_empty() && !only.contains(name) {
      continue
    }
    for variant in ["", "_abi14", "_semver"] {
      let input_path = "\{dir}/\{name}/input\{variant}.json"
      let parser_path = "\{dir}/\{name}/parser\{variant}.c"
      if !@fs.exists(input_path) || !@fs.exists(parser_path) {
        continue
      }
      total += 1
      let label = "\{name}\{variant}"
      let expected = @fs.read_file(parser_path).text()
      let input = load_render_input(@fs.read_file(input_path).text()) catch {
        e => {
          println("\{label}: LOAD ERROR \{e}")
          continue
        }
      }
      let actual = @generate.render_c_code(
        input.name,
        input.tables,
        input.syntax_grammar,
        input.lexical_grammar,
        input.default_aliases,
        input.str_pool,
        input.abi_version,
        input.semantic_version,
        input.supertype_symbol_map,
      ) catch {
        e => {
          println("\{label}: RENDER ERROR \{e}")
          continue
        }
      }
      let c_ok = actual == expected
      if c_ok {
        c_matches += 1
      } else {
        println("\{label}: C MISMATCH at \{first_difference(expected, actual)}")
      }
      let language = @generate.render_language(
        input.name,
        input.tables,
        input.syntax_grammar,
        input.lexical_grammar,
        input.default_aliases,
        input.str_pool,
        input.abi_version,
        input.semantic_version,
        input.supertype_symbol_map,
      ) catch {
        e => {
          println("\{label}: LANGUAGE ERROR \{e}")
          continue
        }
      }
      let problems = check_language(language, expected)
      if problems.is_empty() {
        language_matches += 1
      } else {
        println("\{label}: LANGUAGE MISMATCH in \{problems.join(", ")}")
      }
      // The JSON form must round-trip.
      let round_trip : @language.Language = @json.from_json(
        @json.parse(language.to_json().stringify()),
      ) catch {
        e => {
          println("\{label}: JSON ERROR \{e}")
          continue
        }
      }
      if round_trip != language {
        println("\{label}: JSON ROUND TRIP MISMATCH")
      }
    }
  }
  println(
    "parser.c identical: \{c_matches}/\{total}; Language checks passed: \{language_matches}/\{total}",
  )
}
