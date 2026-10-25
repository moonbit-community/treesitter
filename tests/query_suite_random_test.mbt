// Port of `test_query_random` from tree-sitter
// crates/cli/src/tests/query_test.rs.

///|
async test "query_random" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let cursor = @treesitter.QueryCursor::new()
  cursor.set_match_limit(64)

  // include_str!("helpers/query_helpers.rs")
  guard read_first([
      "api/tests/testdata/query_helpers.rs", "testdata/query_helpers.rs",
    ])
    is Some(query_helpers_rs) else {
    fail("missing testdata/query_helpers.rs")
  }
  let pattern_tree = parse(parser, query_helpers_rs)
  let test_tree = parse(parser, query_helpers_rs)
  let start_seed = 0
  let end_seed = start_seed + iteration_count()
  for seed in start_seed..<(start_seed + end_seed) {
    let seed = seed.to_uint64()
    let rand = StdRng::seed_from_u64(seed)
    let (pattern_ast, _) = Pattern::random_pattern_in_tree(pattern_tree, rand)
    let pattern = Show::to_string(pattern_ast)
    let expected_matches = pattern_ast.matches_in_tree(test_tree)
    let query = @treesitter.Query::new(language, pattern) catch {
      e =>
        fail(
          "failed to build query for pattern \{pattern}. seed: \{seed}\n\{e}",
        )
    }
    let actual_matches = []
    // Upstream passes the bytes of `parser_test.rs` as the text provider;
    // random patterns have no predicates, so the text is never read.
    let match_iter = cursor.matches(
      query,
      test_tree.root_node(),
      utf8(query_helpers_rs),
    )
    while match_iter.next() is Some(mat) {
      let transformed_match : Match = {
        last_node: None,
        captures: mat
        .captures()
        .iter()
        .map(c => (query.capture_names()[c.index], c.node))
        .to_array(),
      }
      actual_matches.push(transformed_match)
    }

    // actual_matches.sort_unstable();
    let actual_matches = dedup_matches(actual_matches)
    if !cursor.did_exceed_match_limit() {
      if actual_matches != expected_matches {
        fail(
          "seed: \{seed}, pattern:\n\{pattern}\nactual: \{format_matches(actual_matches)}\nexpected: \{format_matches(expected_matches)}",
        )
      }
    }
  }
}
