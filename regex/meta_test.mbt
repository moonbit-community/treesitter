// Behaviour of the `regex` crate's meta engine (regex 1.13, regex-automata
// 0.4.18) that depends on the strategy or engine it picks. Expected values
// are those of the Rust crate (tools/oracle/regex_harness).

///|
fn utf8_find(pattern : String, haystack : String) -> String raise {
  let regex = @regex.Regex::new(pattern, utf8=true)
  let hay = @utf8.encode(haystack)
  let found = match regex.find(hay) {
    Some((s, e)) => "\{s}-\{e}"
    None => "N"
  }
  "\{regex.is_match(hay)} \{found}"
}

///|
test "utf8 is_match skips empty matches inside a code point" {
  // `(?-u:\B)` only matches inside `☃` here.
  inspect(utf8_find("(?-u:\\B)", "a☃b"), content="false N")
  inspect(utf8_find("(?-u:\\B)", "☃"), content="true 0-0")
  // The earliest search stops at the empty matches inside `☃` (which end
  // before `x☃`), so is_match disagrees with find.
  inspect(utf8_find("x☃|(?-u:\\B)", "x☃y"), content="false 0-4")
  inspect(utf8_find("x☃|(?-u:\\B)", "x☃"), content="true 0-4")
  // Byte mode reports the empty matches.
  assert_true(@regex.Regex::new("(?-u:\\B)").is_match(@utf8.encode("a☃b")))
}

///|
test "utf8 is_match falls back to the backtracker for short haystacks" {
  // A Unicode word boundary makes the lazy DFA quit on `☃`; up to 128 bytes
  // the bounded backtracker then reports the leftmost-first match `☃`.
  let pattern = "(?:[☃é]|(?-u:\\B)+)(?:(?m:^){0,2}|\\b{start}|\\b{start}*)"
  inspect(utf8_find(pattern, "x☃y"), content="true 1-4")
  let pad = " a".repeat(61) // " a" pairs keep `(?-u:\B)` out
  inspect(utf8_find(pattern, "x☃y" + pad), content="true 1-4")
  inspect(utf8_find(pattern, "x☃y" + pad + " a"), content="false 1-4")
}

///|
test "large literal alternations" {
  // At least 3000 literals: the meta engine's Aho-Corasick strategy.
  let words = Array::makei(3000, i => "w\{i}")
  let regex = @regex.Regex::new(["abcd", "b", ..words].join("|"))
  let spans = (hay : String) => {
    regex.find_iter(@utf8.encode(hay)).map(m => "\{m.0}-\{m.1}").join(" ")
  }
  inspect(spans("abce"), content="1-2")
  inspect(spans("abcd"), content="0-4")
  inspect(spans("xxw12 w3000 abcd w29999"), content="2-4 6-8 12-16 17-19")
  assert_false(regex.is_match(@utf8.encode("xyz")))
  debug_inspect(regex.find_at(@utf8.encode("abcd"), 1), content="Some((1, 2))")
  // An earlier literal that is a prefix of a later one wins.
  let regex = @regex.Regex::new(["ab", "abc", ..words[:2998]].join("|"))
  debug_inspect(regex.find(@utf8.encode("abc")), content="Some((0, 2))")
  // A long shared prefix: linear time (the NFA search was quadratic).
  let n = 2000
  let regex = @regex.Regex::new(
    Array::makei(3000, i => "a".repeat(n) + "b\{i}").join("|"),
  )
  assert_false(regex.is_match(@utf8.encode("a".repeat(10 * n))))
  // `a…ab2`, listed before `a…ab2999`.
  debug_inspect(
    regex.find(@utf8.encode("a".repeat(n + 1) + "b2999")),
    content="Some((1, 2003))",
  )
}

///|
test "panic find_at past the end" {
  // `Input::span(3..1)`: "invalid span 3..1 for haystack of length 1".
  ignore(@regex.Regex::new("a").find_at(b"a", 3))
}

///|
test "find_at at the end" {
  let regex = @regex.Regex::new("a*")
  debug_inspect(regex.find_at(b"a", 1), content="Some((1, 1))")
  // One past the end is the termination of a search (no panic).
  debug_inspect(regex.find_at(b"a", 2), content="None")
}
