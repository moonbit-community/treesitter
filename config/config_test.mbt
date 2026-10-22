///|
test "grammar metadata selection and query paths" {
  let config = @config.Config::parse(
    (
      #|{"grammars":[
      #| {"name":"first","scope":"source.first","file-types":["x","Makefile"],"injection-regex":"x","highlights":"queries/highlights.scm"},
      #| {"name":"second","scope":"source.second","file-types":["x"],"content-regex":"special","first-line-regex":"^#!.*second","injection-regex":"xyz","tags":["a.scm","b.scm"]}
      #| ],"metadata":{"version":"1.0.0"}}
    ),
  )
  assert_eq(
    @config.select(config.grammars, "a.x", "special").unwrap().name,
    "second",
  )
  assert_eq(
    @config.select(config.grammars, "Makefile", "").unwrap().name,
    "first",
  )
  assert_eq(
    @config.select(config.grammars, "unknown", "#!/bin/second\n").unwrap().name,
    "second",
  )
  assert_eq(
    @config.select(config.grammars, "a.x", "special", scope="source.first").unwrap().name,
    "first",
  )
  assert_eq(
    @config.select_injection(config.grammars, "xyz").unwrap().name,
    "second",
  )
  assert_eq(config.grammars[0].highlights, ["queries/highlights.scm"])
  assert_eq(config.grammars[1].tags, ["a.scm", "b.scm"])
}

///|
test "filename matching tries exact name then longest compound extension" {
  let config = @config.Config::parse(
    "{\"grammars\":[{\"name\":\"ts\",\"scope\":\"source.ts\",\"file-types\":[\"ts\"]},{\"name\":\"dts\",\"scope\":\"source.dts\",\"file-types\":[\"d.ts\"]}]}",
  )
  assert_eq(
    @config.select(config.grammars, "file.d.ts", "").unwrap().name,
    "dts",
  )
  assert_eq(
    @config.select(config.grammars, "file.other.ts", "").unwrap().name,
    "ts",
  )
}
