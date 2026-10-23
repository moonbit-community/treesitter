// Expected values are those of the Rust `regex` crate (1.13):
// `regex::Regex::new(p).unwrap().find_iter(h)`.

///|
fn find_all(pattern : String, haystack : String) -> String raise {
  @regex.Regex::new(pattern, utf8=true)
  .find_iter(@utf8.encode(haystack))
  .map(m => "\{m.0}-\{m.1}")
  .join(" ")
}

///|
test "find_iter: leftmost-first preference" {
  inspect(find_all("(foo|foobar)", "foobar foo"), content="0-3 7-10")
  inspect(find_all("(foobar|foo)", "foobar foo"), content="0-6 7-10")
  inspect(find_all("a+?b", "aaab ab"), content="0-4 5-7")
  inspect(find_all("a{2,3}?", "aaaaa"), content="0-2 2-4")
  inspect(find_all("a{2,3}", "aaaaa"), content="0-3 3-5")
  inspect(find_all("(a|ab)(c|bcd)", "abcd"), content="0-4")
}

///|
test "find_iter: empty matches" {
  inspect(find_all("a*", "baa"), content="0-0 1-3")
  inspect(find_all("(|a)+", "aa"), content="0-0 1-1 2-2")
  inspect(find_all("(a|)+", "aa"), content="0-2")
  // Empty matches never split a code point in UTF-8 mode.
  inspect(find_all("", "é"), content="0-0 2-2")
}

///|
test "find_iter: tags strip patterns" {
  inspect(
    find_all("(^['\"\\s]*)|(['\"\\s]*$)", "\"\"\"\n  Data\n  \"\"\""),
    content="0-6 10-16",
  )
  inspect(
    find_all("^[\\s\\*/]+|^[\\s\\*/]$", "/**\n * Get\n */"),
    content="0-7",
  )
  inspect(find_all("^#\\s*", "# hi # there"), content="0-2")
}

///|
test "find_at" {
  let regex = @regex.Regex::new("\\bb\\w*")
  let hay = @utf8.encode("abc bcd")
  debug_inspect(regex.find(hay), content="Some((4, 7))")
  debug_inspect(regex.find_at(hay, 5), content="None")
}
