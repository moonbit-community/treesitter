///|
/// Expected values: heck 0.5.0 and `str::to_lowercase` under Rust 1.97.1.
test "heck case conversions of non-ASCII names" {
  let names = [
    "\u{C9}Foo",
    "\u{E9}Foo",
    "foo\u{C9}",
    "\u{3A3}\u{391}\u{3A3}",
    "a\u{3A3}",
    "\u{3A3}a",
    "\u{3A3}\u{3A3}",
    "stra\u{DF}e",
    "STRASSE",
    "\u{1C5}emal",
    "\u{130}stanbul",
    "\u{149}",
    "\u{FB03}",
    "foo\u{2014}bar",
    "foo\u{B7}bar",
    "a\u{661}b",
    "\u{216B}foo",
    "\u{391}\u{392}\u{393}\u{3B4}",
    "HTTPServer",
    "fooBarBaz",
    "foo_bar",
    "x\u{B2}y",
    "\u{65E5}\u{672C}\u{8A9E}",
    "\u{1F88}",
    "\u{FB00}oo",
    "a\u{3A3}_b",
    "A\u{3A3}-B",
    "\u{1C8}\u{1C8}",
    "\u{3A3}\u{3A3}a",
    "Ab\u{301}C",
    "a\u{345}B",
    "\u{24D0}\u{24B6}b",
    "\u{AB70}",
    "\u{13A0}\u{AB70}",
    "\u{1C90}\u{1C91}",
    "\u{1F0}",
    "\u{390}",
    "\u{1E9E}a",
  ]
  let rows = names.map(n => {
    "\{n}: \{to_kebab_case(n)} \{to_snake_case(n)} \{to_shouty_snake_case(n)} \{to_upper_camel_case(n)} | \{str_to_lowercase(n)}"
  })
  inspect(
    rows.join("\n"),
    content=(
      #|ÉFoo: é-foo é_foo É_FOO ÉFoo | éfoo
      #|éFoo: é-foo é_foo É_FOO ÉFoo | éfoo
      #|fooÉ: foo-é foo_é FOO_É FooÉ | fooé
      #|ΣΑΣ: σας σας ΣΑΣ Σας | σας
      #|aΣ: a-ς a_ς A_Σ AΣ | aς
      #|Σa: σa σa ΣA Σa | σa
      #|ΣΣ: σς σς ΣΣ Σς | σς
      #|straße: straße straße STRASSE Straße | straße
      #|STRASSE: strasse strasse STRASSE Strasse | strasse
      #|ǅemal: ǆemal ǆemal ǄEMAL Ǆemal | ǆemal
      #|İstanbul: i̇stanbul i̇stanbul İSTANBUL İstanbul | i̇stanbul
      #|ŉ: ŉ ŉ ʼN ʼN | ŉ
      #|ﬃ: ﬃ ﬃ FFI FFI | ﬃ
      #|foo—bar: foo-bar foo_bar FOO_BAR FooBar | foo—bar
      #|foo·bar: foo-bar foo_bar FOO_BAR FooBar | foo·bar
      #|a١b: a١b a١b A١B A١b | a١b
      #|Ⅻfoo: ⅻfoo ⅻfoo ⅫFOO Ⅻfoo | ⅻfoo
      #|ΑΒΓδ: αβ-γδ αβ_γδ ΑΒ_ΓΔ ΑβΓδ | αβγδ
      #|HTTPServer: http-server http_server HTTP_SERVER HttpServer | httpserver
      #|fooBarBaz: foo-bar-baz foo_bar_baz FOO_BAR_BAZ FooBarBaz | foobarbaz
      #|foo_bar: foo-bar foo_bar FOO_BAR FooBar | foo_bar
      #|x²y: x²y x²y X²Y X²y | x²y
      #|日本語: 日本語 日本語 日本語 日本語 | 日本語
      #|ᾈ: ᾀ ᾀ ἈΙ ἈΙ | ᾀ
      #|ﬀoo: ﬀoo ﬀoo FFOO FFoo | ﬀoo
      #|aΣ_b: a-ς-b a_ς_b A_Σ_B AΣB | aς_b
      #|AΣ-B: aς-b aς_b AΣ_B AςB | aς-b
      #|ǈǈ: ǉǉ ǉǉ ǇǇ Ǉǉ | ǉǉ
      #|ΣΣa: ς-σa ς_σa Σ_ΣA ΣΣa | σσa
      #|Ab́C: ab-c ab_c AB_C AbC | ab́c
      #|aͅB: aͅ-b aͅ_b AΙ_B AͅB | aͅb
      #|ⓐⒶb: ⓐ-ⓐb ⓐ_ⓐb Ⓐ_ⒶB ⒶⒶb | ⓐⓐb
      #|ꭰ: ꭰ ꭰ Ꭰ Ꭰ | ꭰ
      #|Ꭰꭰ: ꭰꭰ ꭰꭰ ᎠᎠ Ꭰꭰ | ꭰꭰ
      #|ᲐᲑ: აბ აბ ᲐᲑ Აბ | აბ
      #|ǰ: ǰ ǰ J̌ J̌ | ǰ
      #|ΐ: ΐ ΐ Ϊ́ Ϊ́ | ΐ
      #|ẞa: ßa ßa ẞA ẞa | ßa
    ),
  )
}

///|
test "str::to_lowercase final sigma" {
  let inputs = [
    "ΣΑΣ", "AΣ", "AΣ b", "AΣb", "Σ", "aΣ\u{301}", "a\u{301}Σ", "1Σ", "ΑΣ.Α", "ΑΣ'Α",
  ]
  inspect(
    inputs.map(str_to_lowercase).join(" "),
    content="σας aς aς b aσb σ aς\u{301} a\u{301}ς 1σ ασ.α ασ'α",
  )
}

