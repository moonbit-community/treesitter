///|
/// Expected outputs come from semver 1.0.28 (`Version::parse`, `Display`).
test "semver parse matches semver 1.0.28" {
  let cases : Array[(String, String)] = [
    ("1.2.3-01", "err invalid leading zero in pre-release identifier"),
    ("1.2.3+01", "ok 1.2.3+01"),
    ("1.2.3-0", "ok 1.2.3-0"),
    ("1.2.3-0a", "ok 1.2.3-0a"),
    ("1.2.3-01a", "ok 1.2.3-01a"),
    ("1.2.3-a.01", "err invalid leading zero in pre-release identifier"),
    ("1.2.3-00.a", "err invalid leading zero in pre-release identifier"),
    ("1.2.3-", "err empty identifier segment in pre-release identifier"),
    ("1.2.3+", "err empty identifier segment in build metadata"),
    ("1.2.3-é", "err empty identifier segment in pre-release identifier"),
    ("1.2.3-a..b", "err empty identifier segment in pre-release identifier"),
    ("1.2.3-a.", "err empty identifier segment in pre-release identifier"),
    ("1.2.3-.a", "err empty identifier segment in pre-release identifier"),
    ("1.2.3-\u{301}", "err empty identifier segment in pre-release identifier"),
    ("1.2.3\n", "err unexpected character '\\n' after patch version number"),
    (
      "1.2.3\u{85}", "err unexpected character '\\u{85}' after patch version number",
    ),
    ("1.2.3'", "err unexpected character '\\'' after patch version number"),
    ("1.2.3\u{0}", "err unexpected character '\\0' after patch version number"),
    ("1.x", "err unexpected character 'x' while parsing minor version number"),
    ("1.2", "err unexpected end of input while parsing minor version number"),
    ("1.", "err unexpected end of input while parsing minor version number"),
    ("", "err empty string, expected a semver version"),
    ("01.2.3", "err invalid leading zero in major version number"),
    ("1.2.3-alpha.1+build.01", "ok 1.2.3-alpha.1+build.01"),
    (
      "18446744073709551616.0.0", "err value of major version number exceeds u64::MAX",
    ),
    ("18446744073709551615.0.0", "ok 18446744073709551615.0.0"),
    ("1.2.3 ", "err unexpected character ' ' after patch version number"),
    ("1.2.3-a+", "err empty identifier segment in build metadata"),
    ("1.2.3+a-b.c", "ok 1.2.3+a-b.c"),
    ("1.2.3+a_b", "err unexpected character '_' after build metadata"),
    ("1.2.3-a_b", "err unexpected character '_' after pre-release identifier"),
  ]
  for case in cases {
    let (input, expected) = case
    let actual = try @loader.SemverVersion::parse(input) catch {
      e => "err \{e}"
    } noraise {
      v => "ok \{v}"
    }
    assert_eq(actual, expected, msg=input)
  }
}
