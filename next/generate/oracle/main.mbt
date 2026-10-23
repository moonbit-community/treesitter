///|
/// Usage: `oracle <dump-dir> [<ref-dir>]`.
///
/// For every `<name>.input.json` in `<dump-dir>`, run the port and compare its
/// dump with `<name>.expected.json` (variable info, supertype symbol map and
/// `node-types.json` text or error). When `<ref-dir>/<name>/src/node-types.json`
/// exists, also compare the generated text with that file byte for byte.
async fn main {
  let args = @env.args()
  guard args.length() >= 2 else { fail("usage: oracle <dump-dir> [<ref-dir>]") }
  let dir = args[1]
  let ref_dir = args.get(2)
  let mut total = 0
  let mut matched = 0
  let mut ref_total = 0
  let mut ref_matched = 0
  let mut skipped = 0
  for name in @fs.readdir(dir, sort=true) {
    guard name.strip_suffix(".expected.json") is Some(base) else { continue }
    let base = base.to_owned()
    let input_path = "\{dir}/\{base}.input.json"
    if !@fs.exists(input_path) {
      // The grammar could not be prepared upstream; nothing to compare.
      skipped += 1
      continue
    }
    total += 1
    let expected = @json.parse(@fs.read_file("\{dir}/\{name}").text())
    let actual = dump_results(
      load_prepared_inputs(@fs.read_file(input_path).text()),
    )
    let ok = expected.stringify() == actual.stringify()
    if ok {
      matched += 1
    } else {
      println("MISMATCH \{base}")
      for key in ["variable_info", "supertype_symbol_map", "node_types"] {
        if expected is Object(e) &&
          actual is Object(a) &&
          e.get(key) is Some(ev) &&
          a.get(key) is Some(av) &&
          ev.stringify() != av.stringify() {
          println("  differs: \{key}")
        }
      }
      println("  expected: \{expected.stringify().view(end_offset=600)}")
      println("  actual:   \{actual.stringify().view(end_offset=600)}")
    }
    if ref_dir is Some(ref_dir) {
      let ref_path = "\{ref_dir}/\{base}/src/node-types.json"
      if @fs.exists(ref_path) {
        ref_total += 1
        let reference = @fs.read_file(ref_path).text()
        if actual is Object(a) &&
          a.get("node_types") is Some(Object(nt)) &&
          nt.get("ok") is Some(String(text)) &&
          text == reference {
          ref_matched += 1
        } else {
          println("NODE-TYPES MISMATCH \{base}")
        }
      }
    }
  }
  println(
    "oracle dumps: \{matched}/\{total} identical (\{skipped} grammars not preparable upstream)",
  )
  if ref_dir is Some(_) {
    println("node-types.json: \{ref_matched}/\{ref_total} byte-identical")
  }
  if matched != total || ref_matched != ref_total {
    fail("differential mismatches")
  }
}
