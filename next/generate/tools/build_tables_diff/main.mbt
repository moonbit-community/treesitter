// Differential check of `build_tables` against the upstream harness output.
//
// Usage: build_tables_diff <bt_ref dir> [--repeat N] [names...]
// For each `<dir>/<name>/inputs.json`, runs `build_tables` and compares the
// canonical dump with `<dir>/<name>/tables.txt`, writing `mbt_tables.txt` next
// to it when they differ. Prints one line per grammar: name, OK/DIFF, the
// best time over the repeats (ms) and upstream's time (ms).

///|
fn run_one(inputs : BuildTablesInputs) -> String {
  let diagnostics : Array[@generate.Diagnostic] = []
  let out = StringBuilder()
  try
    @generate.build_tables(
      inputs.syntax_grammar,
      inputs.lexical_grammar,
      inputs.simple_aliases,
      inputs.variable_info,
      inputs.inlines,
      inputs.str_pool,
      None,
      @generate.default_opt_level,
      diagnostics,
    )
  catch {
    e => out.write_string("error: \{e}\n")
  } noraise {
    tables => out.write_string(dump_tables(tables, inputs.str_pool))
  }
  for d in diagnostics {
    out.write_string("diagnostic: \{d}\n")
  }
  out.to_string()
}

///|
async fn main {
  let args = @env.args()
  let root = args[1]
  let mut repeat = 1
  let names = []
  let mut i = 2
  while i < args.length() {
    if args[i] == "--repeat" {
      repeat = @string.parse_int(args[i + 1]) catch { _ => 1 }
      i += 2
      continue
    }
    names.push(args[i])
    i += 1
  }
  if names.is_empty() {
    for name in @fs.readdir(root, sort=true) {
      names.push(name)
    }
  }
  let mut matched = 0
  let mut total = 0
  for name in names {
    let dir = "\{root}/\{name}"
    let inputs_text = @fs.read_file("\{dir}/inputs.json").text() catch {
      _ => continue
    }
    let expected = @fs.read_file("\{dir}/tables.txt").text()
    let upstream_us = @fs.read_file("\{dir}/time_us").text().trim()
    let mut best = -1L
    let mut actual = ""
    for _ in 0..<repeat {
      let inputs = load_inputs(inputs_text)
      let start = @env.now()
      actual = run_one(inputs)
      let elapsed = (@env.now() - start).reinterpret_as_int64()
      if best < 0L || elapsed < best {
        best = elapsed
      }
    }
    total += 1
    let status = if actual == expected {
      matched += 1
      "OK"
    } else {
      @fs.write_file(
        "\{dir}/mbt_tables.txt",
        actual,
        create_mode=CreateOrTruncate,
      )
      "DIFF"
    }
    println("\{name} \{status} \{best}ms upstream=\{upstream_us}us")
  }
  println("matched \{matched}/\{total}")
}
