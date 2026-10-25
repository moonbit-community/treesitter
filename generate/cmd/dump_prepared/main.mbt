// Development tool for the differential harness: prints the canonical dump of
// `parse_grammar` + `prepare_grammar` for each `grammar.json` argument.

///|
async fn main {
  let args = @env.args()
  for i in 1..<args.length() {
    let json = @fs.read_file(args[i]).text()
    @stdio.stdout.write(@generate.dump_grammar_json(json))
  }
}
