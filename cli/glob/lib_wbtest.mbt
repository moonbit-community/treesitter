// The assertion of glob 0.3.4's `test_recursive_wildcards` on the private
// `is_recursive` field.

///|
test "test_recursive_wildcards: is_recursive" {
  // a single ** should be valid, for globs
  let pat = Pattern::new("**")
  assert_true(pat.is_recursive)
}
