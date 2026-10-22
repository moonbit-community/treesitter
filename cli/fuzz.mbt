///|
priv struct FuzzOptions {
  seed : Int32
  iterations : Int32
  edits : Int32
  include_pattern : @lex.Regex?
  exclude : @lex.Regex?
}

///|
fn fuzz_options(args : ArrayView[String]) -> FuzzOptions raise {
  let mut seed = 0
  let mut iterations = 100
  let mut edits = 3
  let mut include_pattern = None
  let mut exclude = None
  let mut i = 0
  while i < args.length() {
    let flag = args[i]
    guard args.get(i + 1) is Some(value) else {
      raise Usage("missing value for \{flag}")
    }
    if flag == "--include" {
      include_pattern = Some(@lex.Regex::new(value))
    } else if flag == "--exclude" {
      exclude = Some(@lex.Regex::new(value))
    } else if flag is ("--seed" | "--iterations" | "--edits") {
      let number = @string.parse_int(value) catch {
        _ => raise Usage("\{flag} requires a non-negative integer")
      }
      if number < 0 ||
        (flag != "--seed" && number == 0) ||
        (flag == "--edits" && number > 1073741823) {
        raise Usage("\{flag} is out of range")
      }
      match flag {
        "--seed" => seed = number
        "--iterations" => iterations = number
        _ => edits = number
      }
    } else {
      raise Usage("unknown fuzz option \{flag}")
    }
    i += 2
  }
  { seed, iterations, edits, include_pattern, exclude, }
}

///|
// Use the reference fuzzer's edit categories, with a fixed ChaCha8 stream.
// This seed format is local to the MoonBit CLI, not Rust's StdRng format.
fn fuzz_edit(random : @random.Rand, input : Bytes) -> (Int32, Int32, Bytes) {
  fn unsigned(maximum) {
    random.int(limit=maximum + 1)
  }
  fn words(maximum) {
    let count = unsigned(maximum)
    let result : Array[Byte] = []
    let operators = b"+-<>()*/&|!,.%"
    let letters = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    for i in 0..<count {
      if i > 0 {
        result.push(if unsigned(5) == 0 { b'\n' } else { b' ' })
      }
      if unsigned(3) == 0 {
        result.push(operators[unsigned(operators.length() - 1)])
      } else {
        for _ in 0..<unsigned(8) {
          result.push(letters[unsigned(letters.length() - 1)])
        }
      }
    }
    Bytes::from_array(result)
  }
  let choice = unsigned(10)
  if choice < 2 {
    (input.length(), 0, words(3))
  } else if choice < 5 {
    let count = Int32::min(unsigned(30), input.length())
    (input.length() - count, count, b"")
  } else {
    let start = unsigned(input.length())
    let removed = if choice < 8 { 0 } else { unsigned(input.length() - start) }
    (start, removed, words(1 + unsigned(3)))
  }
}

///|
fn fuzz_splice(
  source : Bytes,
  start : Int32,
  removed : Int32,
  inserted : Bytes,
) -> Bytes {
  Bytes::from_array(
    source[:start].to_array() +
    inserted.to_array() +
    source[start + removed:].to_array(),
  )
}

///|
fn fuzz_case(
  language : @language.Language,
  case : @corpus.Case,
  options : FuzzOptions,
  scanner : @ts.ExternalScanner?,
) -> Int32 raise {
  let seed = options.seed
  let random = @random.Rand::chacha8(
    seed=Bytes::makei(32, i => (seed >> (i % 4 * 8)).to_byte()),
  )
  let parser = @ts.Parser::new(language, scanner?)
  let original = @utf8.encode(case.input)
  let original_tree = parser.parse(original)
  if fuzz_check_tree(original_tree) is Some(message) {
    raise Usage("fuzz original '\{case.name}': \{message}")
  }
  let mut checked = 0
  for iteration in 0..<options.iterations {
    let mut source = original
    let mut tree = parser.parse(original)
    let history : Array[Json] = []
    let undo : Array[(Int32, Int32, Bytes)] = []
    let count = 1 + random.int(limit=options.edits)
    // Each iteration starts from the corpus input. Then apply every inverse
    // edit in reverse order and check that the original tree is recovered.
    for step in 0..<(count * 2) {
      let (start, removed, inserted) = if step < count {
        let edit = fuzz_edit(random, source)
        undo.push(
          (edit.0, edit.2.length(), source[edit.0:edit.0 + edit.1].to_owned()),
        )
        edit
      } else {
        undo.pop().unwrap()
      }
      history.push(
        Json::object({
          "start": Json(start),
          "removed": Json(removed),
          "inserted_bytes": Json(inserted.to_array().map(b => b.to_int())),
        }),
      )
      let after = fuzz_splice(source, start, removed, inserted)
      let old_points = fuzz_points(source)
      let new_points = fuzz_points(after)
      try {
        tree.edit({
          start_byte: start,
          old_end_byte: start + removed,
          new_end_byte: start + inserted.length(),
          start_point: old_points[start],
          old_end_point: old_points[start + removed],
          new_end_point: new_points[start + inserted.length()],
        })
        let next = parser.parse(after, old_tree=tree)
        let fresh = parser.parse(after)
        if fuzz_check_tree(next) is Some(message) {
          raise Usage(message)
        }
        if fuzz_check_tree(fresh) is Some(message) {
          raise Usage(message)
        }
        if fuzz_compare(next, fresh) is Some(message) {
          raise Usage(message)
        }
        tree = next
        source = after
        checked += 1
      } catch {
        error =>
          raise Usage(
            "fuzz failure: " +
            Json::object({
              "case": Json(case.name),
              "seed": Json(seed),
              "iteration": Json(iteration),
              "step": Json(step),
              "message": Json(describe(error)),
              "edits": Json(history),
              "original_bytes": Json(original.to_array().map(b => b.to_int())),
            }).stringify(),
          )
      }
    }
    if source != original || fuzz_compare(tree, original_tree) is Some(_) {
      raise Usage(
        "fuzz undo did not restore '\{case.name}' seed=\{seed} iteration=\{iteration}",
      )
    }
  }
  checked
}

///|
fn run_fuzz(
  language : @language.Language,
  cases : Array[@corpus.Case],
  options : FuzzOptions,
  scanner : @ts.ExternalScanner?,
) -> Unit raise {
  let mut selected = 0
  let mut checked = 0
  for case in cases {
    let name = @utf8.encode(case.name)
    if case.skip ||
      (options.include_pattern is Some(regex) && regex.find(name) is None) ||
      (options.exclude is Some(regex) && regex.find(name) is Some(_)) {
      continue
    }
    let count = fuzz_case(language, case, options, scanner)
    selected += 1
    checked += count
    println("PASS \{case.name}: \{count} edit checks")
  }
  if selected == 0 {
    raise Usage("no corpus cases selected for fuzzing")
  }
  println(
    "Fuzzed \{selected} cases, \{checked} edits including undo, seed=\{options.seed}",
  )
}
