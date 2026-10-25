// Expected values come from Rust 1.97.1 std (`Path::components`,
// `PartialEq for Path`, `Path::file_name`, `Path::strip_prefix`).

///|
fn show_components(path : String) -> String {
  @support.path_components(path).map(c => "\{Repr(c)}").join(",")
}

///|
test "path_components" {
  inspect(show_components(""), content="")
  inspect(show_components("."), content="CurDir")
  inspect(show_components("./"), content="CurDir")
  inspect(show_components("./."), content="CurDir")
  inspect(show_components("././a"), content="CurDir,Normal(\"a\")")
  inspect(show_components("a/./b"), content="Normal(\"a\"),Normal(\"b\")")
  inspect(show_components("a//b/"), content="Normal(\"a\"),Normal(\"b\")")
  inspect(show_components("/"), content="RootDir")
  inspect(show_components("//"), content="RootDir")
  inspect(show_components("//a"), content="RootDir,Normal(\"a\")")
  inspect(show_components("/./a"), content="RootDir,Normal(\"a\")")
  inspect(show_components("/."), content="RootDir")
  inspect(show_components("a/.."), content="Normal(\"a\"),ParentDir")
  inspect(show_components("../a/."), content="ParentDir,Normal(\"a\")")
  inspect(
    show_components("a/b/../c"),
    content="Normal(\"a\"),Normal(\"b\"),ParentDir,Normal(\"c\")",
  )
  inspect(show_components(".hidden"), content="Normal(\".hidden\")")
}

///|
test "path_eq" {
  assert_true(@support.path_eq("a/./b", "a/b"))
  assert_true(@support.path_eq("a//b/", "a/b"))
  assert_true(@support.path_eq("cli/./input.mbt", "cli/input.mbt"))
  assert_true(@support.path_eq("./a", "././a"))
  assert_false(@support.path_eq("./a", "a"))
  assert_false(@support.path_eq("a/..", "a"))
  assert_false(@support.path_eq("/a", "a"))
  assert_false(@support.path_eq("", "."))
}

///|
test "path_file_name" {
  debug_inspect(@support.path_file_name(""), content="None")
  debug_inspect(@support.path_file_name("./."), content="None")
  debug_inspect(@support.path_file_name("/"), content="None")
  debug_inspect(@support.path_file_name("a/.."), content="None")
  debug_inspect(@support.path_file_name("a/."), content="Some(\"a\")")
  debug_inspect(@support.path_file_name("a//b/"), content="Some(\"b\")")
}

///|
test "path_strip_prefix" {
  let strip = (p : String, b : String) => @support.path_strip_prefix(p, b)
  debug_inspect(strip("!", "!"), content="Some(\"\")")
  debug_inspect(
    strip("!/cli/input.mbt", "!"),
    content="Some(\"cli/input.mbt\")",
  )
  debug_inspect(strip("!/./a//b/./", "!"), content="Some(\"a//b\")")
  debug_inspect(strip("!//a/.", "!"), content="Some(\"a\")")
  debug_inspect(strip("!a", "!"), content="None")
  debug_inspect(strip("a/b/c", "a"), content="Some(\"b/c\")")
  debug_inspect(strip("a/b/c", ""), content="Some(\"a/b/c\")")
  debug_inspect(strip("/a/b/", "/"), content="Some(\"a/b\")")
  debug_inspect(strip("./a/./", ""), content="Some(\"./a\")")
  debug_inspect(strip("a", "a"), content="Some(\"\")")
  debug_inspect(strip("a/", "a/b"), content="None")
}
