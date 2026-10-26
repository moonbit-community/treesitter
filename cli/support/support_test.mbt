///|
test "paths" {
  inspect(@support.path_join("a/b", "c"), content="a/b/c")
  inspect(@support.path_join("a/", "/c"), content="/c")
  debug_inspect(@support.parent("grammar.js"), content="Some(\"\")")
  debug_inspect(
    @support.parent("/x/src/grammar.json"),
    content="Some(\"/x/src\")",
  )
  debug_inspect(@support.extension("a/b.tar.gz"), content="Some(\"gz\")")
  debug_inspect(@support.extension(".bashrc"), content="None")
  debug_inspect(@support.file_stem("dir/foo.js"), content="Some(\"foo\")")
  inspect(@support.with_extension("lib/foo", "json"), content="lib/foo.json")
  inspect(@support.path_starts_with("/a/b/c", "/a/b"), content="true")
  debug_inspect(
    @support.path_strip_prefix("~/x/y", "~"),
    content="Some(\"x/y\")",
  )
}

///|
test "serde_json pretty printing" {
  let json : Json = {
    "a": [1, 2.5, "x\ny\u{1}"],
    "b": {},
    "c": [],
    "d": { "e": null, "f": true },
  }
  inspect(
    @support.to_string_pretty(json),
    content=(
      #|{
      #|  "a": [
      #|    1,
      #|    2.5,
      #|    "x\ny\u0001"
      #|  ],
      #|  "b": {},
      #|  "c": [],
      #|  "d": {
      #|    "e": null,
      #|    "f": true
      #|  }
      #|}
    ),
  )
  inspect(
    @support.to_string(json),
    content="{\"a\":[1,2.5,\"x\\ny\\u0001\"],\"b\":{},\"c\":[],\"d\":{\"e\":null,\"f\":true}}",
  )
}

///|
test "utf8 helpers" {
  inspect(@support.utf8_len("aé😀"), content="7")
  inspect(@support.char_count("aé😀"), content="3")
}
