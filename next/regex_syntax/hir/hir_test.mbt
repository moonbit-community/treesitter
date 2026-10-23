// Port of a representative subset of the tests of regex-syntax 0.8.11
// src/hir/mod.rs (class canonicalization, case folding and set operations)
// and src/unicode.rs.

///|
fn uc(ranges : Array[(Char, Char)]) -> @hir.ClassUnicode {
  @hir.ClassUnicode::new(
    ranges.map(r => @hir.ClassUnicodeRange::new(r.0.to_int(), r.1.to_int())),
  )
}

///|
fn bc(ranges : Array[(Byte, Byte)]) -> @hir.ClassBytes {
  @hir.ClassBytes::new(ranges.map(r => @hir.ClassBytesRange::new(r.0, r.1)))
}

///|
fn uranges(cls : @hir.ClassUnicode) -> Array[(Int32, Int32)] {
  cls.ranges().iter().map(r => (r.start(), r.end())).collect()
}

///|
fn ucasefold(cls : @hir.ClassUnicode) -> @hir.ClassUnicode {
  let c = cls.copy()
  c.case_fold_simple()
  c
}

///|
fn unegate(cls : @hir.ClassUnicode) -> @hir.ClassUnicode {
  let c = cls.copy()
  c.negate()
  c
}

///|
fn udifference(
  cls1 : @hir.ClassUnicode,
  cls2 : @hir.ClassUnicode,
) -> @hir.ClassUnicode {
  let c = cls1.copy()
  c.difference(cls2)
  c
}

///|
fn uintersect(
  cls1 : @hir.ClassUnicode,
  cls2 : @hir.ClassUnicode,
) -> @hir.ClassUnicode {
  let c = cls1.copy()
  c.intersect(cls2)
  c
}

///|
fn usymdifference(
  cls1 : @hir.ClassUnicode,
  cls2 : @hir.ClassUnicode,
) -> @hir.ClassUnicode {
  let c = cls1.copy()
  c.symmetric_difference(cls2)
  c
}

///|
test "class canonicalize unicode" {
  assert_eq(uranges(uc([('a', 'c'), ('x', 'z')])), [(0x61, 0x63), (0x78, 0x7a)])
  assert_eq(uranges(uc([('x', 'z'), ('a', 'c')])), [(0x61, 0x63), (0x78, 0x7a)])
  assert_eq(uranges(uc([('x', 'z'), ('w', 'y')])), [(0x77, 0x7a)])
  assert_eq(
    uranges(
      uc([
        ('c', 'f'),
        ('a', 'g'),
        ('d', 'j'),
        ('a', 'c'),
        ('m', 'p'),
        ('l', 's'),
      ]),
    ),
    [(0x61, 0x6a), (0x6c, 0x73)],
  )
  assert_eq(uranges(uc([('x', 'z'), ('u', 'w')])), [(0x75, 0x7a)])
  assert_eq(uranges(uc([('\u{0}', '\u{10FFFF}'), ('\u{0}', '\u{10FFFF}')])), [
    (0, 0x10FFFF),
  ])
  assert_eq(uranges(uc([('a', 'a'), ('b', 'b')])), [(0x61, 0x62)])
}

///|
test "class canonicalize bytes" {
  assert_eq(bc([(b'x', b'z'), (b'a', b'c')]), bc([(b'a', b'c'), (b'x', b'z')]))
  assert_eq(
    bc([
      (b'c', b'f'),
      (b'a', b'g'),
      (b'd', b'j'),
      (b'a', b'c'),
      (b'm', b'p'),
      (b'l', b's'),
    ])
    .ranges()
    .to_owned(),
    [
      @hir.ClassBytesRange::new(b'a', b'j'),
      @hir.ClassBytesRange::new(b'l', b's'),
    ],
  )
  assert_eq(bc([(b'a', b'a'), (b'b', b'b')]), bc([(b'a', b'b')]))
}

///|
test "class case fold unicode" {
  let cls = uc([
    ('C', 'F'),
    ('A', 'G'),
    ('D', 'J'),
    ('A', 'C'),
    ('M', 'P'),
    ('L', 'S'),
    ('c', 'f'),
  ])
  assert_eq(
    ucasefold(cls),
    uc([('A', 'J'), ('L', 'S'), ('a', 'j'), ('l', 's'), ('\u{17F}', '\u{17F}')]),
  )
  let expected = uc([
    ('A', 'Z'),
    ('a', 'z'),
    ('\u{17F}', '\u{17F}'),
    ('\u{212A}', '\u{212A}'),
  ])
  assert_eq(ucasefold(uc([('A', 'Z')])), expected)
  assert_eq(ucasefold(uc([('a', 'z')])), expected)
  assert_eq(
    ucasefold(uc([('A', 'A'), ('_', '_')])),
    uc([('A', 'A'), ('_', '_'), ('a', 'a')]),
  )
  assert_eq(
    ucasefold(uc([('A', 'A'), ('=', '=')])),
    uc([('=', '='), ('A', 'A'), ('a', 'a')]),
  )
  assert_eq(ucasefold(uc([('\u{0}', '\u{10}')])), uc([('\u{0}', '\u{10}')]))
  assert_eq(
    ucasefold(uc([('k', 'k')])),
    uc([('K', 'K'), ('k', 'k'), ('\u{212A}', '\u{212A}')]),
  )
  assert_eq(ucasefold(uc([('@', '@')])), uc([('@', '@')]))
}

///|
test "class case fold bytes" {
  let cls = bc([(b'C', b'F'), (b'A', b'G'), (b'c', b'f')])
  cls.case_fold_simple()
  assert_eq(cls, bc([(b'A', b'G'), (b'a', b'g')]))
  let cls = bc([(b'A', b'Z')])
  cls.case_fold_simple()
  assert_eq(cls, bc([(b'A', b'Z'), (b'a', b'z')]))
  let cls = bc([(b'\x00', b'\x10')])
  cls.case_fold_simple()
  assert_eq(cls, bc([(b'\x00', b'\x10')]))
}

///|
test "class negate unicode" {
  assert_eq(
    unegate(uc([('a', 'a')])),
    uc([('\u{0}', '\u{60}'), ('\u{62}', '\u{10FFFF}')]),
  )
  assert_eq(
    unegate(uc([('a', 'c'), ('x', 'z')])),
    uc([('\u{0}', '\u{60}'), ('\u{64}', '\u{77}'), ('\u{7B}', '\u{10FFFF}')]),
  )
  assert_eq(unegate(uc([('\u{0}', 'a')])), uc([('\u{62}', '\u{10FFFF}')]))
  assert_eq(unegate(uc([('a', '\u{10FFFF}')])), uc([('\u{0}', '\u{60}')]))
  assert_eq(unegate(uc([('\u{0}', '\u{10FFFF}')])), uc([]))
  assert_eq(unegate(uc([])), uc([('\u{0}', '\u{10FFFF}')]))
  assert_eq(
    unegate(uc([('\u{0}', '\u{10FFFD}'), ('\u{10FFFF}', '\u{10FFFF}')])),
    uc([('\u{10FFFE}', '\u{10FFFE}')]),
  )
  assert_eq(
    unegate(uc([('\u{0}', '\u{D7FF}')])),
    uc([('\u{E000}', '\u{10FFFF}')]),
  )
  assert_eq(
    unegate(uc([('\u{0}', '\u{D7FE}')])),
    uc([('\u{D7FF}', '\u{10FFFF}')]),
  )
  assert_eq(
    unegate(uc([('\u{E000}', '\u{10FFFF}')])),
    uc([('\u{0}', '\u{D7FF}')]),
  )
  assert_eq(
    unegate(uc([('\u{E001}', '\u{10FFFF}')])),
    uc([('\u{0}', '\u{E000}')]),
  )
}

///|
test "class negate bytes" {
  let cls = bc([(b'a', b'a')])
  cls.negate()
  assert_eq(cls, bc([(b'\x00', b'\x60'), (b'\x62', b'\xFF')]))
  let cls = bc([])
  cls.negate()
  assert_eq(cls, bc([(b'\x00', b'\xFF')]))
}

///|
test "class intersect unicode" {
  assert_eq(uintersect(uc([]), uc([('a', 'a')])), uc([]))
  assert_eq(uintersect(uc([('a', 'a')]), uc([('a', 'a')])), uc([('a', 'a')]))
  assert_eq(uintersect(uc([('a', 'a')]), uc([('b', 'b')])), uc([]))
  assert_eq(uintersect(uc([('a', 'c')]), uc([('b', 'd')])), uc([('b', 'c')]))
  assert_eq(
    uintersect(uc([('a', 'b'), ('d', 'e'), ('g', 'h')]), uc([('a', 'h')])),
    uc([('a', 'b'), ('d', 'e'), ('g', 'h')]),
  )
  assert_eq(
    uintersect(uc([('a', 'b'), ('d', 'e'), ('g', 'h')]), uc([('h', 'h')])),
    uc([('h', 'h')]),
  )
  assert_eq(
    uintersect(
      uc([('a', 'b'), ('e', 'f'), ('i', 'j')]),
      uc([('c', 'd'), ('g', 'h'), ('k', 'l')]),
    ),
    uc([]),
  )
  assert_eq(
    uintersect(
      uc([('a', 'b'), ('c', 'd'), ('e', 'f')]),
      uc([('b', 'c'), ('d', 'e'), ('f', 'g')]),
    ),
    uc([('b', 'f')]),
  )
}

///|
test "class difference unicode" {
  assert_eq(udifference(uc([('a', 'a')]), uc([('a', 'a')])), uc([]))
  assert_eq(udifference(uc([('a', 'a')]), uc([])), uc([('a', 'a')]))
  assert_eq(udifference(uc([]), uc([('a', 'a')])), uc([]))
  assert_eq(udifference(uc([('a', 'z')]), uc([('a', 'a')])), uc([('b', 'z')]))
  assert_eq(udifference(uc([('a', 'z')]), uc([('z', 'z')])), uc([('a', 'y')]))
  assert_eq(
    udifference(uc([('a', 'z')]), uc([('m', 'm')])),
    uc([('a', 'l'), ('n', 'z')]),
  )
  let cls1 = uc([('a', 'c'), ('g', 'i'), ('r', 't')])
  assert_eq(udifference(cls1, uc([('a', 'z')])), uc([]))
  assert_eq(udifference(cls1, uc([('d', 'v')])), uc([('a', 'c')]))
  assert_eq(
    udifference(cls1, uc([('b', 'g'), ('s', 'u')])),
    uc([('a', 'a'), ('h', 'i'), ('r', 'r')]),
  )
  assert_eq(
    udifference(cls1, uc([('b', 'd'), ('e', 'g'), ('s', 'u')])),
    uc([('a', 'a'), ('h', 'i'), ('r', 'r')]),
  )
  assert_eq(
    udifference(uc([('x', 'z')]), uc([('a', 'c'), ('e', 'g'), ('s', 'u')])),
    uc([('x', 'z')]),
  )
  assert_eq(
    udifference(uc([('a', 'z')]), uc([('a', 'c'), ('e', 'g'), ('s', 'u')])),
    uc([('d', 'd'), ('h', 'r'), ('v', 'z')]),
  )
}

///|
test "class symmetric difference unicode" {
  assert_eq(
    usymdifference(uc([('a', 'm')]), uc([('g', 't')])),
    uc([('a', 'f'), ('n', 't')]),
  )
}

///|
test "unicode class queries" {
  // Canonicalization of property names and values (UAX44-LM3), `is`
  // prefixes and the `isc`/`cf`/`sc`/`lc` special cases.
  let greek = try! @hir.class(Binary("Greek"))
  assert_eq(try! @hir.class(Binary("isgreek")), greek)
  assert_eq(try! @hir.class(Binary("GREEK")), greek)
  assert_eq(
    try! @hir.class(ByValue(property_name="sc", property_value="Grek")),
    greek,
  )
  assert_eq(
    try! @hir.class(ByValue(property_name="Script", property_value="greek")),
    greek,
  )
  assert_eq(
    try! @hir.class(Binary("cf")),
    try! @hir.class(ByValue(property_name="gc", property_value="Format")),
  )
  assert_eq(
    try! @hir.class(Binary("lc")),
    try! @hir.class(ByValue(property_name="gc", property_value="Cased_Letter")),
  )
  assert_eq(try! @hir.class(OneLetter('L')), try! @hir.class(Binary("Letter")))
  assert_eq(try! @hir.class(Binary("ascii")), uc([('\u{0}', '\u{7F}')]))
  assert_eq(try! @hir.class(Binary("any")), uc([('\u{0}', '\u{10FFFF}')]))
  let assigned = try! @hir.class(Binary("assigned"))
  let unassigned = try! @hir.class(Binary("Cn"))
  unassigned.negate()
  assert_eq(assigned, unassigned)
  assert_eq(try! @hir.class(Binary("Decimal_Number")), try! @hir.perl_digit())
  assert_eq(try! @hir.class(Binary("White_Space")), try! @hir.perl_space())
  // Age values accumulate every earlier version.
  let v1 = try! @hir.class(ByValue(property_name="age", property_value="1.1"))
  let v2 = try! @hir.class(ByValue(property_name="age", property_value="2.0"))
  assert_eq(uintersect(v1, v2), v1)
  // Errors.
  let err = (q : @hir.ClassQuery) => {
    try @hir.class(q) |> ignore catch {
      PropertyNotFound => "PropertyNotFound"
      PropertyValueNotFound => "PropertyValueNotFound"
      PerlClassNotFound => "PerlClassNotFound"
    } noraise {
      _ => "ok"
    }
  }
  inspect(err(Binary("Foo")), content="PropertyNotFound")
  // `isc` normalizes to the ISO_Comment property, which has no table.
  inspect(err(Binary("isc")), content="PropertyNotFound")
  inspect(
    err(ByValue(property_name="gc", property_value="Foo")),
    content="PropertyValueNotFound",
  )
  inspect(
    err(ByValue(property_name="Foo", property_value="Bar")),
    content="PropertyNotFound",
  )
  inspect(
    err(ByValue(property_name="Bidi_Class", property_value="L")),
    content="PropertyValueNotFound",
  )
  inspect(
    err(ByValue(property_name="wb", property_value="ALetter")),
    content="ok",
  )
}
