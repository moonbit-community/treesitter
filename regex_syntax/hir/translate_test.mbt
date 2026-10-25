// Port of a representative subset of the tests of regex-syntax 0.8.11
// src/hir/translate.rs.

///|
fn parse(pattern : String) -> @ast.Ast {
  try! @ast.ParserBuilder::new().octal(true).build().parse(pattern)
}

///|
fn t(pattern : String) -> @hir.Hir {
  try! @hir.TranslatorBuilder::new()
  .utf8(true)
  .build()
  .translate(pattern, parse(pattern))
}

///|
fn t_err(pattern : String) -> (@hir.ErrorKind, Int32, Int32) {
  try
    @hir.TranslatorBuilder::new()
    .utf8(true)
    .build()
    .translate(pattern, parse(pattern))
    |> ignore
  catch {
    e => (e.kind(), e.span().start.offset, e.span().end.offset)
  } noraise {
    _ => abort("expected an error for \{pattern}")
  }
}

///|
fn t_bytes(pattern : String) -> @hir.Hir {
  try! @hir.TranslatorBuilder::new()
  .utf8(false)
  .build()
  .translate(pattern, parse(pattern))
}

///|
fn hir_lit(s : String) -> @hir.Hir {
  @hir.Hir::literal(Bytes::from_array(@hir.utf8_encode(s)))
}

///|
fn hir_blit(s : Array[Byte]) -> @hir.Hir {
  @hir.Hir::literal(Bytes::from_array(s))
}

///|
fn hir_capture(index : UInt32, expr : @hir.Hir) -> @hir.Hir {
  @hir.Hir::capture({ index, name: None, sub: expr, })
}

///|
fn hir_capture_name(index : UInt32, name : String, expr : @hir.Hir) -> @hir.Hir {
  @hir.Hir::capture({ index, name: Some(name), sub: expr, })
}

///|
fn hir_range(
  greedy : Bool,
  min : UInt32,
  max : UInt32?,
  expr : @hir.Hir,
) -> @hir.Hir {
  @hir.Hir::repetition({ min, max, greedy, sub: expr, })
}

///|
fn hir_quest(greedy : Bool, expr : @hir.Hir) -> @hir.Hir {
  hir_range(greedy, 0, Some(1), expr)
}

///|
fn hir_star(greedy : Bool, expr : @hir.Hir) -> @hir.Hir {
  hir_range(greedy, 0, None, expr)
}

///|
fn hir_plus(greedy : Bool, expr : @hir.Hir) -> @hir.Hir {
  hir_range(greedy, 1, None, expr)
}

///|
fn hir_alt(alts : Array[@hir.Hir]) -> @hir.Hir {
  @hir.Hir::alternation(alts)
}

///|
fn hir_cat(exprs : Array[@hir.Hir]) -> @hir.Hir {
  @hir.Hir::concat(exprs)
}

///|
fn uclass(ranges : Array[(Char, Char)]) -> @hir.Class {
  Unicode(
    @hir.ClassUnicode::new(
      ranges.map(r => @hir.ClassUnicodeRange::new(r.0.to_int(), r.1.to_int())),
    ),
  )
}

///|
fn bclass(ranges : Array[(Byte, Byte)]) -> @hir.Class {
  Bytes(
    @hir.ClassBytes::new(ranges.map(r => @hir.ClassBytesRange::new(r.0, r.1))),
  )
}

///|
fn hir_uclass(ranges : Array[(Char, Char)]) -> @hir.Hir {
  @hir.Hir::class(uclass(ranges))
}

///|
fn hir_bclass(ranges : Array[(Byte, Byte)]) -> @hir.Hir {
  @hir.Hir::class(bclass(ranges))
}

///|
fn hir_case_fold(expr : @hir.Hir) -> @hir.Hir {
  match expr.into_kind() {
    Class(cls) => {
      cls.case_fold_simple()
      @hir.Hir::class(cls)
    }
    _ => abort("cannot case fold non-class Hir expr")
  }
}

///|
fn hir_negate(expr : @hir.Hir) -> @hir.Hir {
  match expr.into_kind() {
    Class(cls) => {
      cls.negate()
      @hir.Hir::class(cls)
    }
    _ => abort("cannot negate non-class Hir expr")
  }
}

///|
fn hir_look(look : @hir.Look) -> @hir.Hir {
  @hir.Hir::look(look)
}

///|
test "empty" {
  assert_eq(t(""), @hir.Hir::empty())
  assert_eq(t("(?i)"), @hir.Hir::empty())
  assert_eq(t("()"), hir_capture(1, @hir.Hir::empty()))
  assert_eq(t("(?:)"), @hir.Hir::empty())
  assert_eq(t("(?P<wat>)"), hir_capture_name(1, "wat", @hir.Hir::empty()))
  assert_eq(t("|"), hir_alt([@hir.Hir::empty(), @hir.Hir::empty()]))
  assert_eq(
    t("()|()"),
    hir_alt([
      hir_capture(1, @hir.Hir::empty()),
      hir_capture(2, @hir.Hir::empty()),
    ]),
  )
  assert_eq(
    t("(|b)"),
    hir_capture(1, hir_alt([@hir.Hir::empty(), hir_lit("b")])),
  )
  assert_eq(
    t("(a|)"),
    hir_capture(1, hir_alt([hir_lit("a"), @hir.Hir::empty()])),
  )
  assert_eq(
    t("(a||c)"),
    hir_capture(1, hir_alt([hir_lit("a"), @hir.Hir::empty(), hir_lit("c")])),
  )
  assert_eq(
    t("(||)"),
    hir_capture(
      1,
      hir_alt([@hir.Hir::empty(), @hir.Hir::empty(), @hir.Hir::empty()]),
    ),
  )
}

///|
test "literal" {
  assert_eq(t("a"), hir_lit("a"))
  assert_eq(t("(?-u)a"), hir_lit("a"))
  assert_eq(t("☃"), hir_lit("☃"))
  assert_eq(t("abcd"), hir_lit("abcd"))
  assert_eq(t_bytes("(?-u)a"), hir_lit("a"))
  assert_eq(t_bytes("(?-u)\u{61}"), hir_lit("a"))
  assert_eq(t_bytes("(?-u)\\x61"), hir_lit("a"))
  assert_eq(t_bytes("(?-u)\\xFF"), hir_blit([b'\xFF']))
  assert_eq(t("(?-u)☃"), hir_lit("☃"))
  assert_eq(t_err("(?-u)\\xFF"), (InvalidUtf8, 5, 9))
}

///|
test "literal case insensitive" {
  assert_eq(t("(?i)a"), hir_uclass([('A', 'A'), ('a', 'a')]))
  assert_eq(t("(?i:a)"), hir_uclass([('A', 'A'), ('a', 'a')]))
  assert_eq(
    t("a(?i)a(?-i)a"),
    hir_cat([hir_lit("a"), hir_uclass([('A', 'A'), ('a', 'a')]), hir_lit("a")]),
  )
  assert_eq(
    t("(?i)ab@c"),
    hir_cat([
      hir_uclass([('A', 'A'), ('a', 'a')]),
      hir_uclass([('B', 'B'), ('b', 'b')]),
      hir_lit("@"),
      hir_uclass([('C', 'C'), ('c', 'c')]),
    ]),
  )
  assert_eq(t("(?i)β"), hir_uclass([('Β', 'Β'), ('β', 'β'), ('ϐ', 'ϐ')]))
  assert_eq(t("(?i-u)a"), hir_bclass([(b'A', b'A'), (b'a', b'a')]))
  assert_eq(
    t("(?-u)a(?i)a(?-i)a"),
    hir_cat([
      hir_lit("a"),
      hir_bclass([(b'A', b'A'), (b'a', b'a')]),
      hir_lit("a"),
    ]),
  )
  assert_eq(
    t("(?i-u)ab@c"),
    hir_cat([
      hir_bclass([(b'A', b'A'), (b'a', b'a')]),
      hir_bclass([(b'B', b'B'), (b'b', b'b')]),
      hir_lit("@"),
      hir_bclass([(b'C', b'C'), (b'c', b'c')]),
    ]),
  )
  assert_eq(t_bytes("(?i-u)a"), hir_bclass([(b'A', b'A'), (b'a', b'a')]))
  assert_eq(t_bytes("(?i-u)\\x61"), hir_bclass([(b'A', b'A'), (b'a', b'a')]))
  assert_eq(t_bytes("(?i-u)\\xFF"), hir_blit([b'\xFF']))
  assert_eq(t("(?i-u)β"), hir_lit("β"))
}

///|
test "dot" {
  assert_eq(t("."), hir_uclass([('\u{0}', '\t'), ('\u{0B}', '\u{10FFFF}')]))
  assert_eq(
    t("(?R)."),
    hir_uclass([('\u{0}', '\t'), ('\u{0B}', '\u{0C}'), ('\u{0E}', '\u{10FFFF}')]),
  )
  assert_eq(t("(?s)."), hir_uclass([('\u{0}', '\u{10FFFF}')]))
  assert_eq(t("(?Rs)."), hir_uclass([('\u{0}', '\u{10FFFF}')]))
  assert_eq(
    t_bytes("(?-u)."),
    hir_bclass([(b'\x00', b'\t'), (b'\x0B', b'\xFF')]),
  )
  assert_eq(
    t_bytes("(?R-u)."),
    hir_bclass([(b'\x00', b'\t'), (b'\x0B', b'\x0C'), (b'\x0E', b'\xFF')]),
  )
  assert_eq(t_bytes("(?s-u)."), hir_bclass([(b'\x00', b'\xFF')]))
  assert_eq(t_bytes("(?Rs-u)."), hir_bclass([(b'\x00', b'\xFF')]))
  // If invalid UTF-8 isn't allowed, then non-Unicode `.` isn't allowed.
  assert_eq(t_err("(?-u)."), (InvalidUtf8, 5, 6))
  assert_eq(t_err("(?R-u)."), (InvalidUtf8, 6, 7))
  assert_eq(t_err("(?s-u)."), (InvalidUtf8, 6, 7))
  assert_eq(t_err("(?Rs-u)."), (InvalidUtf8, 7, 8))
}

///|
test "assertions and line anchors" {
  assert_eq(t("^"), hir_look(Start))
  assert_eq(t("$"), hir_look(End))
  assert_eq(t("\\A"), hir_look(Start))
  assert_eq(t("\\z"), hir_look(End))
  assert_eq(t("(?m)^"), hir_look(StartLF))
  assert_eq(t("(?m)$"), hir_look(EndLF))
  assert_eq(t("(?m)\\A"), hir_look(Start))
  assert_eq(t("(?m)\\z"), hir_look(End))
  assert_eq(t("\\b"), hir_look(WordUnicode))
  assert_eq(t("\\B"), hir_look(WordUnicodeNegate))
  assert_eq(t("(?-u)\\b"), hir_look(WordAscii))
  assert_eq(t("(?-u)\\B"), hir_look(WordAsciiNegate))
  assert_eq(t("(?R)^"), hir_look(Start))
  assert_eq(t("(?R)$"), hir_look(End))
  assert_eq(t("(?Rm)^"), hir_look(StartCRLF))
  assert_eq(t("(?Rm)$"), hir_look(EndCRLF))
}

///|
test "group" {
  assert_eq(t("(a)"), hir_capture(1, hir_lit("a")))
  assert_eq(
    t("(a)(b)"),
    hir_cat([hir_capture(1, hir_lit("a")), hir_capture(2, hir_lit("b"))]),
  )
  assert_eq(
    t("(a)|(b)"),
    hir_alt([hir_capture(1, hir_lit("a")), hir_capture(2, hir_lit("b"))]),
  )
  assert_eq(t("(?P<foo>)"), hir_capture_name(1, "foo", @hir.Hir::empty()))
  assert_eq(t("(?P<foo>a)"), hir_capture_name(1, "foo", hir_lit("a")))
  assert_eq(
    t("(?P<foo>a)(?P<bar>b)"),
    hir_cat([
      hir_capture_name(1, "foo", hir_lit("a")),
      hir_capture_name(2, "bar", hir_lit("b")),
    ]),
  )
  assert_eq(t("(?:a)"), hir_lit("a"))
  assert_eq(
    t("(?:a)(b)"),
    hir_cat([hir_lit("a"), hir_capture(1, hir_lit("b"))]),
  )
  assert_eq(
    t("(a)(?:b)(c)"),
    hir_cat([
      hir_capture(1, hir_lit("a")),
      hir_lit("b"),
      hir_capture(2, hir_lit("c")),
    ]),
  )
  assert_eq(t("((?i))"), hir_capture(1, @hir.Hir::empty()))
  assert_eq(t("((?x))"), hir_capture(1, @hir.Hir::empty()))
  assert_eq(t("(((?x)))"), hir_capture(1, hir_capture(2, @hir.Hir::empty())))
}

///|
test "flags" {
  assert_eq(
    t("(?i:a)a"),
    hir_cat([hir_uclass([('A', 'A'), ('a', 'a')]), hir_lit("a")]),
  )
  assert_eq(
    t("(?i-u:a)β"),
    hir_cat([hir_bclass([(b'A', b'A'), (b'a', b'a')]), hir_lit("β")]),
  )
  assert_eq(
    t("((?i-u)a)b"),
    hir_cat([
      hir_capture(1, hir_bclass([(b'A', b'A'), (b'a', b'a')])),
      hir_lit("b"),
    ]),
  )
  assert_eq(
    t("(?i)(?-i:a)a"),
    hir_cat([hir_lit("a"), hir_uclass([('A', 'A'), ('a', 'a')])]),
  )
  assert_eq(
    t("(?im)a^(?i-m)a^"),
    hir_cat([
      hir_uclass([('A', 'A'), ('a', 'a')]),
      hir_look(StartLF),
      hir_uclass([('A', 'A'), ('a', 'a')]),
      hir_look(Start),
    ]),
  )
  assert_eq(
    t("(?U)a*a*?(?-U)a*a*?"),
    hir_cat([
      hir_star(false, hir_lit("a")),
      hir_star(true, hir_lit("a")),
      hir_star(true, hir_lit("a")),
      hir_star(false, hir_lit("a")),
    ]),
  )
  assert_eq(
    t("(?i)(?:a(?-i)a)a"),
    hir_cat([
      hir_cat([hir_uclass([('A', 'A'), ('a', 'a')]), hir_lit("a")]),
      hir_uclass([('A', 'A'), ('a', 'a')]),
    ]),
  )
}

///|
test "escape and repetition" {
  assert_eq(
    t("\\\\\\.\\+\\*\\?\\(\\)\\|\\[\\]\\{\\}\\^\\$\\#"),
    hir_lit("\\.+*?()|[]{}^$#"),
  )
  assert_eq(t("a?"), hir_quest(true, hir_lit("a")))
  assert_eq(t("a*"), hir_star(true, hir_lit("a")))
  assert_eq(t("a+"), hir_plus(true, hir_lit("a")))
  assert_eq(t("a??"), hir_quest(false, hir_lit("a")))
  assert_eq(t("a*?"), hir_star(false, hir_lit("a")))
  assert_eq(t("a+?"), hir_plus(false, hir_lit("a")))
  assert_eq(t("a{1}"), hir_range(true, 1, Some(1), hir_lit("a")))
  assert_eq(t("a{1,}"), hir_range(true, 1, None, hir_lit("a")))
  assert_eq(t("a{1,2}"), hir_range(true, 1, Some(2), hir_lit("a")))
  assert_eq(t("a{1,2}?"), hir_range(false, 1, Some(2), hir_lit("a")))
  assert_eq(t("ab?"), hir_cat([hir_lit("a"), hir_quest(true, hir_lit("b"))]))
  assert_eq(t("(ab)?"), hir_quest(true, hir_capture(1, hir_lit("ab"))))
  assert_eq(t("a|b?"), hir_alt([hir_lit("a"), hir_quest(true, hir_lit("b"))]))
}

///|
test "cat alt" {
  let a = () => hir_look(Start)
  let b = () => hir_look(End)
  let c = () => hir_look(WordUnicode)
  let d = () => hir_look(WordUnicodeNegate)
  assert_eq(t("(^$)"), hir_capture(1, hir_cat([a(), b()])))
  assert_eq(t("^|$"), hir_alt([a(), b()]))
  assert_eq(t("^|$|\\b"), hir_alt([a(), b(), c()]))
  assert_eq(
    t("^$|$\\b|\\b\\B"),
    hir_alt([hir_cat([a(), b()]), hir_cat([b(), c()]), hir_cat([c(), d()])]),
  )
  assert_eq(
    t("(^$|($\\b|(\\b\\B)))"),
    hir_capture(
      1,
      hir_alt([
        hir_cat([a(), b()]),
        hir_capture(
          2,
          hir_alt([hir_cat([b(), c()]), hir_capture(3, hir_cat([c(), d()]))]),
        ),
      ]),
    ),
  )
}

///|
test "cat class flattened" {
  assert_eq(t("[a-z]|[A-Z]"), hir_uclass([('A', 'Z'), ('a', 'z')]))
  assert_eq(
    t(
      (
        #|(?x)
        #|    \p{Lowercase_Letter}
        #|    |\p{Uppercase_Letter}
        #|    |\p{Titlecase_Letter}
        #|    |\p{Modifier_Letter}
        #|    |\p{Other_Letter}
      ),
    ),
    @hir.Hir::class(Unicode(try! @hir.class(Binary("letter")))),
  )
  // Byte classes that can truly match invalid UTF-8 cannot be combined
  // with Unicode classes.
  assert_eq(
    t_bytes("[Δδ]|(?-u:[\\x90-\\xFF])|[Λλ]"),
    hir_alt([
      hir_uclass([('Δ', 'Δ'), ('δ', 'δ')]),
      hir_bclass([(b'\x90', b'\xFF')]),
      hir_uclass([('Λ', 'Λ'), ('λ', 'λ')]),
    ]),
  )
  // Byte classes on their own can be combined, even if some are ASCII
  // and others are invalid UTF-8.
  assert_eq(
    t_bytes("[a-z]|(?-u:[\\x90-\\xFF])|[A-Z]"),
    hir_bclass([(b'A', b'Z'), (b'a', b'z'), (b'\x90', b'\xFF')]),
  )
}

///|
test "class bracketed intersect" {
  assert_eq(t("[abc&&b-c]"), hir_uclass([('b', 'c')]))
  assert_eq(t("[abc&&[b-c]]"), hir_uclass([('b', 'c')]))
  assert_eq(t("[[abc]&&[b-c]]"), hir_uclass([('b', 'c')]))
  assert_eq(t("[a-z&&b-y&&c-x]"), hir_uclass([('c', 'x')]))
  assert_eq(t("[c-da-b&&a-d]"), hir_uclass([('a', 'd')]))
  assert_eq(t("[a-d&&c-da-b]"), hir_uclass([('a', 'd')]))
  assert_eq(t("[^[a-z&&a-c]]"), hir_negate(hir_uclass([('a', 'c')])))
  assert_eq(t("(?-u)[abc&&b-c]"), hir_bclass([(b'b', b'c')]))
  assert_eq(t("(?-u)[a-z&&b-y&&c-x]"), hir_bclass([(b'c', b'x')]))
  assert_eq(t("(?i)[abc&&b-c]"), hir_case_fold(hir_uclass([('b', 'c')])))
  assert_eq(t("(?i)[a-z&&b-y&&c-x]"), hir_case_fold(hir_uclass([('c', 'x')])))
  assert_eq(t("(?i-u)[abc&&b-c]"), hir_case_fold(hir_bclass([(b'b', b'c')])))
  assert_eq(t("[\\^&&^]"), hir_uclass([('^', '^')]))
  assert_eq(t("[]&&\\]]"), hir_uclass([(']', ']')]))
  assert_eq(t("[-&&-]"), hir_uclass([('-', '-')]))
  assert_eq(t("[\\&&&&]"), hir_uclass([('&', '&')]))
  assert_eq(t("[\\&&&\\&]"), hir_uclass([('&', '&')]))
  // Test precedence.
  assert_eq(t("[a-w&&[^c-g]z]"), hir_uclass([('a', 'b'), ('h', 'w')]))
}

///|
test "smart constructors" {
  assert_eq(t("a{0}"), @hir.Hir::empty())
  assert_eq(t("a{1}"), hir_lit("a"))
  assert_eq(t("\\B{32111}"), hir_look(WordUnicodeNegate))
  assert_eq(t("(?:foo)(?:bar)"), hir_lit("foobar"))
  assert_eq(t("quux(?:foo)(?:bar)baz"), hir_lit("quuxfoobarbaz"))
  assert_eq(
    t("foo(?:ba(?:r^b)az)quux"),
    hir_cat([hir_lit("foobar"), hir_look(Start), hir_lit("bazquux")]),
  )
  assert_eq(t("(?:foo)|(?:bar)"), hir_alt([hir_lit("foo"), hir_lit("bar")]))
  assert_eq(
    t("quux|(?:abc|(?:def|mno)|xyz)|baz"),
    hir_alt([
      hir_lit("quux"),
      hir_lit("abc"),
      hir_lit("def"),
      hir_lit("mno"),
      hir_lit("xyz"),
      hir_lit("baz"),
    ]),
  )
  assert_eq(t("a|b|c|d|e|f|x|y|z"), hir_uclass([('a', 'f'), ('x', 'z')]))
  // Tests that we lift common prefixes out of an alternation.
  assert_eq(
    t("[A-Z]foo|[A-Z]quux"),
    hir_cat([
      hir_uclass([('A', 'Z')]),
      hir_alt([hir_lit("foo"), hir_lit("quux")]),
    ]),
  )
  assert_eq(
    t("[A-Z][A-Z]|[A-Z][A-Z]quux"),
    hir_cat([
      hir_uclass([('A', 'Z')]),
      hir_uclass([('A', 'Z')]),
      hir_alt([@hir.Hir::empty(), hir_lit("quux")]),
    ]),
  )
}

///|
test "regressions" {
  let span = @ast.Span::splat(@ast.Position::new(0, 0, 0))
  let ast = @ast.Ast::Alternation({ span, asts: [Concat({ span, asts: [], })], })
  assert_eq(@hir.Translator::new().translate("", ast), @hir.Hir::empty())
  let ast = @ast.Ast::Concat({ span, asts: [Alternation({ span, asts: [], })], })
  assert_eq(@hir.Translator::new().translate("", ast), @hir.Hir::fail())
  let ast = @ast.Ast::Concat({
    span,
    asts: [Alternation({ span, asts: [Dot(span)], })],
  })
  assert_eq(
    @hir.Translator::new().translate("", ast),
    @hir.Hir::dot(AnyCharExceptLF),
  )
  // Must not panic.
  ignore(
    t(
      "\\W\\W|\\W[^\\v--\\W\\W\\P{Script_Extensions:Pau_Cin_Hau}\\u10A1A1-\\U{3E3E3}--~~~~--~~~~~~~~------~~~~~~--~~~~~~]*",
    ),
  )
}
