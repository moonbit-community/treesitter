///|
test "mbtx split preserves comments aliases and body line numbers" {
  let input = "// grammar\nimport {\n  \"moonbit-community/treesitter/grammar\" @g, // }\n}\nfn main {}\n"
  let (imports, body) = @mbtx.prepare(input)
  assert_true(imports.contains("@g"))
  assert_eq(body.split("\n").count(), input.split("\n").count())
  assert_true(body.has_suffix("fn main {}\n"))
}
