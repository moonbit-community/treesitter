///|
test "heck case conversions" {
  let names = [
    "my_lang", "fooBar", "HTTPServer", "c_sharp", "XMLHttpRequest", "foo-bar baz",
    "embedded_template", "abc123def", "__x__",
  ]
  let rows = names.map(n => {
    "\{n}: \{to_kebab_case(n)} \{to_snake_case(n)} \{to_shouty_snake_case(n)} \{to_upper_camel_case(n)}"
  })
  inspect(
    rows.join("\n"),
    content=(
      #|my_lang: my-lang my_lang MY_LANG MyLang
      #|fooBar: foo-bar foo_bar FOO_BAR FooBar
      #|HTTPServer: http-server http_server HTTP_SERVER HttpServer
      #|c_sharp: c-sharp c_sharp C_SHARP CSharp
      #|XMLHttpRequest: xml-http-request xml_http_request XML_HTTP_REQUEST XmlHttpRequest
      #|foo-bar baz: foo-bar-baz foo_bar_baz FOO_BAR_BAZ FooBarBaz
      #|embedded_template: embedded-template embedded_template EMBEDDED_TEMPLATE EmbeddedTemplate
      #|abc123def: abc123def abc123def ABC123DEF Abc123def
      #|__x__: x x X X
    ),
  )
}

///|
test "indoc" {
  inspect(
    indoc(
      (
        #|
        #|        # Zig bindings
        #|          build.zig linguist-generated
        #|
      ),
    ),
    content=(
      #|# Zig bindings
      #|  build.zig linguist-generated
      #|
    ),
  )
  inspect(indoc("same line\n    next"), content="same line\nnext")
}

///|
test "rust_lines" {
  debug_inspect(
    rust_lines("a\r\nb\n\nc\n"),
    content=(
      #|["a", "b", "", "c"]
    ),
  )
  debug_inspect(rust_lines(""), content="[]")
  debug_inspect(
    rust_lines("x"),
    content=(
      #|["x"]
    ),
  )
}

///|
test "crc32" {
  inspect(
    crc32(@support.utf8("tree_sitter_my_lang")).to_string(radix=16),
    content="e6503c5b",
  )
  inspect(crc32(b"123456789").to_string(radix=16), content="cbf43926")
}

///|
test "replace_cmake_version" {
  inspect(
    replace_cmake_version(
      "project(tree-sitter-foo\n        VERSION \"0.1.0\"\n        LANGUAGES C)\nVERSION \"1.2.3\"",
      "2.0.0",
    ),
    content=(
      #|project(tree-sitter-foo
      #|        VERSION "2.0.0"
      #|        LANGUAGES C)
      #|VERSION "1.2.3"
    ),
  )
  inspect(
    replace_cmake_version("VERSION 1.0.0", "2.0.0"),
    content="VERSION 1.0.0",
  )
  inspect(
    replace_cmake_version("  VERSION\t \"1.2.3\"x VERSION \"4.5.6\"", "2.0.0"),
    content="  VERSION\t \"2.0.0\"x VERSION \"4.5.6\"",
  )
  // Long whitespace runs without a match are scanned in linear time (the
  // search used to restart the whitespace scan at every character).
  let spaces = " ".repeat(200000)
  let content = spaces + "# comment\n" + spaces + "VERSION  \"1.2.3\""
  let replaced = replace_cmake_version(content, "2.0.0")
  inspect(replaced.has_suffix(spaces + "VERSION  \"2.0.0\""), content="true")
  inspect(replaced.length() == content.length(), content="true")
}

///|
test "semver_cmp" {
  let v = s => try! @loader.SemverVersion::parse(s)
  let pairs = [
    ("1.0.0", "1.0.0"),
    ("1.0.0-alpha", "1.0.0"),
    ("1.0.0-alpha.1", "1.0.0-alpha"),
    ("1.0.0-alpha.beta", "1.0.0-alpha.1"),
    ("1.0.0-rc.11", "1.0.0-rc.2"),
    ("1.0.0+2", "1.0.0+10"),
    ("1.0.0", "0.9.9"),
  ]
  inspect(
    pairs.map(p => semver_cmp(v(p.0), v(p.1)).to_string()).join(" "),
    content="0 -1 1 1 1 -1 1",
  )
}

///|
test "str::lines keeps the \\r of an unterminated last line" {
  debug_inspect(
    rust_lines("a\r\nb\r"),
    content=(
      #|["a", "b\r"]
    ),
  )
  debug_inspect(
    rust_lines("\n"),
    content=(
      #|[""]
    ),
  )
  debug_inspect(
    rust_lines("a\n\r"),
    content=(
      #|["a", "\r"]
    ),
  )
}
