// Port of the `#[cfg(test)]` tests of glob 0.3.4 src/lib.rs (the assertion
// on the private `is_recursive` field is in lib_wbtest.mbt), followed by
// traversal tests on a temporary directory tree.

///|
fn pattern(s : String) -> @glob.Pattern {
  @glob.Pattern::new(s) catch {
    e => abort("Pattern::new(\{s}) failed: \{e}")
  }
}

///|
fn pattern_err_pos(s : String) -> Int32 {
  try @glob.Pattern::new(s) catch {
    @glob.PatternError(pos~, ..) => pos
  } noraise {
    _ => abort("Pattern::new(\{s}) succeeded")
  }
}

///|
async fn glob_err_pos(s : String) -> Int32 {
  try @glob.glob(s) catch {
    @glob.PatternError(pos~, ..) => pos
    e => raise e
  } noraise {
    _ => abort("glob(\{s}) succeeded")
  }
}

///|
fn options(
  case_sensitive~ : Bool,
  require_literal_separator~ : Bool,
  require_literal_leading_dot~ : Bool,
) -> @glob.MatchOptions {
  { case_sensitive, require_literal_separator, require_literal_leading_dot, }
}

///|
test "test_pattern_from_str" {
  assert_true(pattern("a*b").matches("a_b"))
  assert_eq(pattern_err_pos("a/**b"), 4)
}

///|
test "test_wildcard_errors" {
  assert_eq(pattern_err_pos("a/**b"), 4)
  assert_eq(pattern_err_pos("a/bc**"), 3)
  assert_eq(pattern_err_pos("a/*****"), 4)
  assert_eq(pattern_err_pos("a/b**c**d"), 2)
  assert_eq(pattern_err_pos("a**b"), 0)
}

///|
test "test_unclosed_bracket_errors" {
  assert_eq(pattern_err_pos("abc[def"), 3)
  assert_eq(pattern_err_pos("abc[!def"), 3)
  assert_eq(pattern_err_pos("abc["), 3)
  assert_eq(pattern_err_pos("abc[!"), 3)
  assert_eq(pattern_err_pos("abc[d"), 3)
  assert_eq(pattern_err_pos("abc[!d"), 3)
  assert_eq(pattern_err_pos("abc[]"), 3)
  assert_eq(pattern_err_pos("abc[!]"), 3)
}

///|
async test "test_glob_errors" {
  assert_eq(glob_err_pos("a/**b"), 4)
  assert_eq(glob_err_pos("abc[def"), 3)
}

///|
/// Upstream (`#[cfg(all(unix, not(target_os = "macos")))]`) globs
/// `/root/*` as a non-root user; here an unreadable temporary directory
/// plays the part of `/root`.
async test "test_iteration_errors" {
  let dir = @fs.tmpdir(prefix="glob-test-")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let root = dir + "/root"
  @fs.mkdir(root)
  @fs.chmod(root, 0)
  defer (@fs.chmod(root, 0o755) catch { _ => () })
  if @fs.can_read(root) {
    // running as root: nothing to test
    return
  }
  let iter = @glob.glob(root + "/*")

  // GlobErrors shouldn't halt iteration
  let next = iter.next()
  assert_true(next is Some(_))
  let err = next.unwrap()
  guard err is Err(err) else { fail("expected an error") }
  assert_true(@support.path_eq(err.path(), root))
  inspect(
    @support.io_error_message(err.error()),
    content="Permission denied (os error 13)",
  )
  inspect(
    err.to_string().replace(old=dir, new="<tmp>"),
    content="attempting to read `<tmp>/root` resulted in an error: Permission denied (os error 13)",
  )
}

///|
async test "test_absolute_pattern" {
  assert_true(@glob.glob("/").next() is Some(_))
  assert_true(@glob.glob("//").next() is Some(_))

  // assume that the filesystem is not empty!
  assert_true(@glob.glob("/*").next() is Some(_))
}

///|
test "test_wildcards" {
  assert_true(pattern("a*b").matches("a_b"))
  assert_true(pattern("a*b*c").matches("abc"))
  assert_true(!pattern("a*b*c").matches("abcd"))
  assert_true(pattern("a*b*c").matches("a_b_c"))
  assert_true(pattern("a*b*c").matches("a___b___c"))
  assert_true(pattern("abc*abc*abc").matches("abcabcabcabcabcabcabc"))
  assert_true(!pattern("abc*abc*abc").matches("abcabcabcabcabcabcabca"))
  assert_true(
    pattern("a*a*a*a*a*a*a*a*a").matches("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
  )
  assert_true(pattern("a*b[xyz]c*d").matches("abxcdbxcddd"))
}

///|
test "test_recursive_wildcards" {
  let pat = pattern("some/**/needle.txt")
  assert_true(pat.matches("some/needle.txt"))
  assert_true(pat.matches("some/one/needle.txt"))
  assert_true(pat.matches("some/one/two/needle.txt"))
  assert_true(pat.matches("some/other/needle.txt"))
  assert_true(!pat.matches("some/other/notthis.txt"))

  // a single ** should be valid, for globs
  // Should accept anything
  let pat = pattern("**")
  assert_true(pat.matches("abcde"))
  assert_true(pat.matches(""))
  assert_true(pat.matches(".asdf"))
  assert_true(pat.matches("/x/.asdf"))

  // collapse consecutive wildcards
  let pat = pattern("some/**/**/needle.txt")
  assert_true(pat.matches("some/needle.txt"))
  assert_true(pat.matches("some/one/needle.txt"))
  assert_true(pat.matches("some/one/two/needle.txt"))
  assert_true(pat.matches("some/other/needle.txt"))
  assert_true(!pat.matches("some/other/notthis.txt"))

  // ** can begin the pattern
  let pat = pattern("**/test")
  assert_true(pat.matches("one/two/test"))
  assert_true(pat.matches("one/test"))
  assert_true(pat.matches("test"))

  // /** can begin the pattern
  let pat = pattern("/**/test")
  assert_true(pat.matches("/one/two/test"))
  assert_true(pat.matches("/one/test"))
  assert_true(pat.matches("/test"))
  assert_true(!pat.matches("/one/notthis"))
  assert_true(!pat.matches("/notthis"))

  // Only start sub-patterns on start of path segment.
  let pat = pattern("**/.*")
  assert_true(pat.matches(".abc"))
  assert_true(pat.matches("abc/.abc"))
  assert_true(!pat.matches("ab.c"))
  assert_true(!pat.matches("abc/ab.c"))
}

///|
async test "test_lots_of_files" {
  // this is a good test because it touches lots of differently named files
  let paths = @glob.glob("/*/*/*/*")
  for _ in 0..<10000 {
    if paths.next() is None {
      break
    }
  }
  paths.next() |> ignore
}

///|
test "test_range_pattern" {
  let pat = pattern("a[0-9]b")
  for i in 0..<10 {
    assert_true(pat.matches("a\{i}b"))
  }
  assert_true(!pat.matches("a_b"))
  let pat = pattern("a[!0-9]b")
  for i in 0..<10 {
    assert_true(!pat.matches("a\{i}b"))
  }
  assert_true(pat.matches("a_b"))
  let pats = ["[a-z123]", "[1a-z23]", "[123a-z]"]
  for p in pats {
    let pat = pattern(p)
    for c in "abcdefghijklmnopqrstuvwxyz" {
      assert_true(pat.matches(c.to_string()))
    }
    for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
      let options = { ..@glob.MatchOptions::new(), case_sensitive: false, }
      assert_true(pat.matches_with(c.to_string(), options))
    }
    assert_true(pat.matches("1"))
    assert_true(pat.matches("2"))
    assert_true(pat.matches("3"))
  }
  let pats = ["[abc-]", "[-abc]", "[a-c-]"]
  for p in pats {
    let pat = pattern(p)
    assert_true(pat.matches("a"))
    assert_true(pat.matches("b"))
    assert_true(pat.matches("c"))
    assert_true(pat.matches("-"))
    assert_true(!pat.matches("d"))
  }
  let pat = pattern("[2-1]")
  assert_true(!pat.matches("1"))
  assert_true(!pat.matches("2"))
  assert_true(pattern("[-]").matches("-"))
  assert_true(!pattern("[!-]").matches("-"))
}

///|
test "test_pattern_matches" {
  let txt_pat = pattern("*hello.txt")
  assert_true(txt_pat.matches("hello.txt"))
  assert_true(txt_pat.matches("gareth_says_hello.txt"))
  assert_true(txt_pat.matches("some/path/to/hello.txt"))
  assert_true(txt_pat.matches("some\\path\\to\\hello.txt"))
  assert_true(txt_pat.matches("/an/absolute/path/to/hello.txt"))
  assert_true(!txt_pat.matches("hello.txt-and-then-some"))
  assert_true(!txt_pat.matches("goodbye.txt"))
  let dir_pat = pattern("*some/path/to/hello.txt")
  assert_true(dir_pat.matches("some/path/to/hello.txt"))
  assert_true(dir_pat.matches("a/bigger/some/path/to/hello.txt"))
  assert_true(!dir_pat.matches("some/path/to/hello.txt-and-then-some"))
  assert_true(!dir_pat.matches("some/other/path/to/hello.txt"))
}

///|
test "test_pattern_escape" {
  let s = "_[_]_?_*_!_"
  assert_eq(@glob.Pattern::escape(s), "_[[]_[]]_[?]_[*]_!_")
  assert_true(pattern(@glob.Pattern::escape(s)).matches(s))
}

///|
test "test_pattern_matches_case_insensitive" {
  let pat = pattern("aBcDeFg")
  let options = options(
    case_sensitive=false,
    require_literal_separator=false,
    require_literal_leading_dot=false,
  )
  assert_true(pat.matches_with("aBcDeFg", options))
  assert_true(pat.matches_with("abcdefg", options))
  assert_true(pat.matches_with("ABCDEFG", options))
  assert_true(pat.matches_with("AbCdEfG", options))
}

///|
test "test_pattern_matches_case_insensitive_range" {
  let pat_within = pattern("[a]")
  let pat_except = pattern("[!a]")
  let options_case_insensitive = options(
    case_sensitive=false,
    require_literal_separator=false,
    require_literal_leading_dot=false,
  )
  let options_case_sensitive = options(
    case_sensitive=true,
    require_literal_separator=false,
    require_literal_leading_dot=false,
  )
  assert_true(pat_within.matches_with("a", options_case_insensitive))
  assert_true(pat_within.matches_with("A", options_case_insensitive))
  assert_true(!pat_within.matches_with("A", options_case_sensitive))
  assert_true(!pat_except.matches_with("a", options_case_insensitive))
  assert_true(!pat_except.matches_with("A", options_case_insensitive))
  assert_true(pat_except.matches_with("A", options_case_sensitive))
}

///|
test "test_pattern_matches_require_literal_separator" {
  let options_require_literal = options(
    case_sensitive=true,
    require_literal_separator=true,
    require_literal_leading_dot=false,
  )
  let options_not_require_literal = options(
    case_sensitive=true,
    require_literal_separator=false,
    require_literal_leading_dot=false,
  )
  assert_true(
    pattern("abc/def").matches_with("abc/def", options_require_literal),
  )
  assert_true(
    !pattern("abc?def").matches_with("abc/def", options_require_literal),
  )
  assert_true(
    !pattern("abc*def").matches_with("abc/def", options_require_literal),
  )
  assert_true(
    !pattern("abc[/]def").matches_with("abc/def", options_require_literal),
  )
  assert_true(
    pattern("abc/def").matches_with("abc/def", options_not_require_literal),
  )
  assert_true(
    pattern("abc?def").matches_with("abc/def", options_not_require_literal),
  )
  assert_true(
    pattern("abc*def").matches_with("abc/def", options_not_require_literal),
  )
  assert_true(
    pattern("abc[/]def").matches_with("abc/def", options_not_require_literal),
  )
}

///|
test "test_pattern_matches_require_literal_leading_dot" {
  let options_require_literal_leading_dot = options(
    case_sensitive=true,
    require_literal_separator=false,
    require_literal_leading_dot=true,
  )
  let options_not_require_literal_leading_dot = options(
    case_sensitive=true,
    require_literal_separator=false,
    require_literal_leading_dot=false,
  )
  let f = options => pattern("*.txt").matches_with(".hello.txt", options)
  assert_true(f(options_not_require_literal_leading_dot))
  assert_true(!f(options_require_literal_leading_dot))
  let f = options => pattern(".*.*").matches_with(".hello.txt", options)
  assert_true(f(options_not_require_literal_leading_dot))
  assert_true(f(options_require_literal_leading_dot))
  let f = options => pattern("aaa/bbb/*").matches_with("aaa/bbb/.ccc", options)
  assert_true(f(options_not_require_literal_leading_dot))
  assert_true(!f(options_require_literal_leading_dot))
  let f = options => {
    pattern("aaa/bbb/*").matches_with("aaa/bbb/c.c.c.", options)
  }
  assert_true(f(options_not_require_literal_leading_dot))
  assert_true(f(options_require_literal_leading_dot))
  let f = options => pattern("aaa/bbb/.*").matches_with("aaa/bbb/.ccc", options)
  assert_true(f(options_not_require_literal_leading_dot))
  assert_true(f(options_require_literal_leading_dot))
  let f = options => pattern("aaa/?bbb").matches_with("aaa/.bbb", options)
  assert_true(f(options_not_require_literal_leading_dot))
  assert_true(!f(options_require_literal_leading_dot))
  let f = options => pattern("aaa/[.]bbb").matches_with("aaa/.bbb", options)
  assert_true(f(options_not_require_literal_leading_dot))
  assert_true(!f(options_require_literal_leading_dot))
  let f = options => pattern("**/*").matches_with(".bbb", options)
  assert_true(f(options_not_require_literal_leading_dot))
  assert_true(!f(options_require_literal_leading_dot))
}

///|
test "test_matches_path" {
  // on windows, (Path::new("a/b").as_str().unwrap() == "a\\b"), so this
  // tests that / and \ are considered equivalent on windows
  assert_true(pattern("a/b").matches_path("a/b"))
}

///|
test "test_path_join" {
  let pattern = @support.path_join("one", "**/*.rs")
  let ok = try {
    @glob.Pattern::new(pattern) |> ignore
    true
  } catch {
    _ => false
  }
  assert_true(ok)
}

// Traversal tests (not upstream). The expected outputs were produced by
// glob 0.3.4 through the upstream CLI on the same tree.

///|
/// The paths `pattern` (relative to `dir`) yields, relative to `dir`, with
/// errors shown as `ERR <message>`.
async fn glob_in(dir : String, pattern : String) -> String {
  let paths = @glob.glob(dir + "/" + pattern) catch {
    e => return "PatternError: \{e}"
  }
  let out = []
  while paths.next() is Some(r) {
    match r {
      Ok(p) => out.push(p.replace(old=dir + "/", new=""))
      Err(e) => out.push("ERR " + e.to_string().replace(old=dir + "/", new=""))
    }
  }
  out.join(" ")
}

///|
async fn make_tree() -> String {
  let dir = @fs.tmpdir(prefix="glob-tree-")
  for d in ["a/b/c", "a/.hid", "d", "p/locked"] {
    @fs.mkdir(dir + "/" + d, recursive=true)
  }
  for
    f in [
      "a/x.json", "a/b/y.json", "a/b/c/z.json", "a/.hid/h.json", "a/.dot.json", "top.json",
      "d/Z.json", "d/_.json", "d/a.json", "d/é.json", "d/B.json", "d/\u{1F600}.json",
      "d/\u{FF5E}.json", "p/ok.json", "p/locked/q.json",
    ] {
    @fs.write_file(dir + "/" + f, "1\n", create_mode=CreateOrTruncate)
  }
  @fs.symlink(target="a/b", dir + "/lnk")
  @fs.symlink(target="nowhere", dir + "/dangling")
  dir
}

///|
/// Patterns and their results (`glob` relative to the tree of `make_tree`).
let traversal_cases : Array[(String, String)] = [
  (
    "d/*", "d/B.json d/Z.json d/_.json d/a.json d/é.json d/～.json d/😀.json",
  ),
  ("a/[.]*", "a/.dot.json a/.hid"),
  ("a/.*", "a/.. a/. a/.dot.json a/.hid"),
  ("a/.*/h.json", "a/.hid/h.json"),
  ("a/..*/a/x.json", "a/../a/x.json"),
  ("d/[^a]*", "d/a.json"),
  ("d/[!a_]*", "d/B.json d/Z.json d/é.json d/～.json d/😀.json"),
  ("d/[]Z]*", "d/Z.json"),
  ("d/[!]B]*", "d/Z.json d/_.json d/a.json d/é.json d/～.json d/😀.json"),
  ("d/[a-z]*", "d/a.json"),
  ("d/[～-😀]*", "d/～.json d/😀.json"),
  (
    "d/?.json", "d/B.json d/Z.json d/_.json d/a.json d/é.json d/～.json d/😀.json",
  ),
  (
    "**/*.json", "a/.dot.json a/.hid/h.json a/b/c/z.json a/b/y.json a/x.json d/B.json d/Z.json d/_.json d/a.json d/é.json d/～.json d/😀.json lnk/c/z.json lnk/y.json p/locked/q.json p/ok.json top.json",
  ),
  ("a/**/", "a/.hid a/b a/b/c"),
  ("a/**", "a/.hid a/b a/b/c"),
  (
    "a/**/**/*.json", "a/.dot.json a/.hid/h.json a/b/c/z.json a/b/y.json a/x.json",
  ),
  ("**/c", "a/b/c lnk/c"),
  ("a/*/", "a/.hid a/b"),
  ("a/*.json/", ""),
  ("a/x.json/", ""),
  ("dangling", "dangling"),
  ("dangling/", ""),
  ("dangling*", "dangling"),
  ("a/./x.json", "a/./x.json"),
  ("a//x.json", "a/x.json"),
  ("a/*//*.json", "a/.hid/h.json a/b/y.json"),
  ("lnk/../x.json", "lnk/../x.json"),
  ("a/.", "a/."),
  ("a/..", "a/.."),
  ("a/./*", "a/./.dot.json a/./.hid a/./b a/./x.json"),
  ("*/.", "a/. d/. lnk/. p/."),
  ("a/**/.", ""),
  ("**/..", ""),
  ("a/*/..", "a/.hid/.. a/b/.."),
  ("lnk/*", "lnk/c lnk/y.json"),
  ("lnk", "lnk"),
  ("lnk/", "lnk"),
  ("x/**/y/**", ""),
  ("[]]", ""),
]

///|
async test "glob traversal" {
  let dir = make_tree()
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  for case in traversal_cases {
    let (pattern, expected) = case
    assert_eq((pattern, glob_in(dir, pattern)), (pattern, expected))
  }
}

///|
let unreadable_cases : Array[(String, String)] = [
  ("p/*", "p/locked p/ok.json"),
  (
    "p/*/*.json", "ERR attempting to read `p/locked` resulted in an error: Permission denied (os error 13)",
  ),
  (
    "p/**/*.json", "ERR attempting to read `p/locked` resulted in an error: Permission denied (os error 13) p/ok.json",
  ),
  ("p/locked/q.json", ""),
  (
    "p/locked/*", "ERR attempting to read `p/locked` resulted in an error: Permission denied (os error 13)",
  ),
  ("p/*/", "p/locked"),
]

///|
async test "glob unreadable directory" {
  let dir = make_tree()
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  @fs.chmod(dir + "/p/locked", 0)
  defer (@fs.chmod(dir + "/p/locked", 0o755) catch { _ => () })
  if @fs.can_read(dir + "/p/locked") {
    // running as root: nothing to test
    return
  }
  for case in unreadable_cases {
    let (pattern, expected) = case
    assert_eq((pattern, glob_in(dir, pattern)), (pattern, expected))
  }
}

///|
let pattern_error_cases : Array[(String, String)] = [
  (
    "a/**b", "PatternError: Pattern syntax error near position 4: recursive wildcards must form a single path component",
  ),
  (
    "a[/]b", "PatternError: Pattern syntax error near position 1: invalid range pattern",
  ),
  (
    "[", "PatternError: Pattern syntax error near position 0: invalid range pattern",
  ),
  (
    "**a", "PatternError: Pattern syntax error near position 2: recursive wildcards must form a single path component",
  ),
  (
    "a/***", "PatternError: Pattern syntax error near position 4: wildcards are either regular `*` or recursive `**`",
  ),
  (
    "[!]", "PatternError: Pattern syntax error near position 0: invalid range pattern",
  ),
  (
    "é/[", "PatternError: Pattern syntax error near position 2: invalid range pattern",
  ),
  (
    "😀[", "PatternError: Pattern syntax error near position 1: invalid range pattern",
  ),
  (
    "/x/**b", "PatternError: Pattern syntax error near position 5: recursive wildcards must form a single path component",
  ),
  (
    "a/b**", "PatternError: Pattern syntax error near position 2: recursive wildcards must form a single path component",
  ),
]

///|
async test "glob pattern errors" {
  for case in pattern_error_cases {
    let (pattern, expected) = case
    let actual = try @glob.glob(pattern) catch {
      e => "PatternError: \{e}"
    } noraise {
      _ => ""
    }
    assert_eq((pattern, actual), (pattern, expected))
  }
}
