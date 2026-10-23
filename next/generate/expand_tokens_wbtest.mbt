// Port of the tests of tree-sitter
// crates/generate/src/prepare_grammar/expand_tokens.rs.

///|
fn simulate_nfa(grammar : LexicalGrammar, s : String) -> (Int32, String)? {
  let start_states = grammar.variables.map(v => v.start_state)
  let cursor = NfaCursor::new(grammar.nfa, start_states)
  let chars : Array[Char] = s.iter().collect()
  let slice = (start : Int32, end : Int32) => {
    String::from_array(chars[start:end])
  }
  let mut result : (Int32, String)? = None
  let mut result_precedence = -2147483648
  let mut start_char = 0
  let mut end_char = 0
  for c in chars {
    for completion in cursor.completions() {
      let (id, precedence) = completion
      if result is None || result_precedence <= precedence {
        result = Some((id, slice(start_char, end_char)))
        result_precedence = precedence
      }
    }
    let transition = cursor
      .transitions()
      .iter()
      .find_first(t => {
        t.characters.contains(c.to_int()) && t.precedence >= result_precedence
      })
    match transition {
      Some({ states, is_separator, .. }) => {
        cursor.reset(states)
        end_char += 1
        if is_separator {
          start_char = end_char
        }
      }
      None => break
    }
  }
  for completion in cursor.completions() {
    let (id, precedence) = completion
    if result is None || result_precedence <= precedence {
      result = Some((id, slice(start_char, end_char)))
      result_precedence = precedence
    }
  }
  result
}

///|
/// `build` returns (token roots, separator roots).
fn check(
  build : (RulePool) -> (Array[RuleId], Array[RuleId]),
  examples : Array[(String, (Int32, String)?)],
) -> Unit raise {
  let pool = RulePool::new()
  let (roots, separators) = build(pool)
  let vars = roots.mapi((i, root) => LexicalToken::{
    name: pool.intern("tok\{i}"),
    kind: Anonymous,
    root,
  })
  let grammar = expand_tokens(pool, vars, separators)
  for example in examples {
    let (input, expected) = example
    let actual = simulate_nfa(grammar, input)
    if actual != expected {
      fail("input \{input}: expected \{Repr(expected)}, got \{Repr(actual)}")
    }
  }
}

///|
fn et_pat(p : RulePool, value : String, flags : String) -> RuleId {
  let (v, f) = (p.intern(value), p.intern(flags))
  p.pattern(v, f)
}

///|
fn et_str(p : RulePool, value : String) -> RuleId {
  let s = p.intern(value)
  p.string(s)
}

///|
fn one(
  value : String,
  flags : String,
) -> (RulePool) -> (Array[RuleId], Array[RuleId]) {
  p => ([et_pat(p, value, flags)], [])
}

///|
test "rule expansion: regexes" {
  // regex with sequences and alternatives
  check(one("(a|b|c)d(e|f|g)h?", ""), [
    ("ade1", Some((0, "ade"))),
    ("bdf1", Some((0, "bdf"))),
    ("bdfh1", Some((0, "bdfh"))),
    ("ad1", None),
  ])
  // regex with repeats
  check(one("a*", ""), [("aaa1", Some((0, "aaa"))), ("b", Some((0, "")))])
  // regex with repeats in sequences
  check(one("a((bc)+|(de)*)f", ""), [
    ("af1", Some((0, "af"))),
    ("adedef1", Some((0, "adedef"))),
    ("abcbcbcf1", Some((0, "abcbcbcf"))),
    ("a", None),
  ])
  // regex with character ranges
  check(one("[a-fA-F0-9]+", ""), [("A1ff0.", Some((0, "A1ff0")))])
  // regex with perl character classes
  check(one("\\w\\d\\s", ""), [("_0  ", Some((0, "_0 ")))])
  // string
  check(p => ([et_str(p, "abc")], []), [("abcd", Some((0, "abc"))), ("ab", None)])
  // complex rule containing strings and regexes
  check(
    p => {
      let reg = p.intern("[a-f]+")
      let empty = p.intern("")
      let (lb, pat, rb) = (p.intern("{"), p.pattern(reg, empty), p.intern("}"))
      let (left, right) = (p.string(lb), p.string(rb))
      let seq = p.seq([left, pat, right])
      ([p.repeat(seq)], [])
    },
    [("{a}{", Some((0, "{a}"))), ("{a}{d", Some((0, "{a}"))), ("ab", None)],
  )
  // longest match rule
  check(p => ([et_pat(p, "a|bc", ""), et_pat(p, "aa", ""), et_pat(p, "bcd", "")], []), [
    ("a.", Some((0, "a"))),
    ("bc.", Some((0, "bc"))),
    ("aa.", Some((1, "aa"))),
    ("bcd?", Some((2, "bcd"))),
    ("b.", None),
    ("c.", None),
  ])
  // regex with an alternative including the empty string
  check(one("a(b|)+c", ""), [
    ("ac.", Some((0, "ac"))),
    ("abc.", Some((0, "abc"))),
    ("abbc.", Some((0, "abbc"))),
  ])
  // separators
  check(
    p => {
      let token = et_pat(p, "[a-f]+", "")
      let escaped_newline = et_str(p, "\\\n")
      let whitespace = et_pat(p, "\\s", "")
      ([token], [escaped_newline, whitespace])
    },
    [
      ("  a", Some((0, "a"))),
      ("  \nb", Some((0, "b"))),
      ("  \\a", None),
      ("  \\\na", Some((0, "a"))),
    ],
  )
  // shorter tokens with higher precedence
  check(
    p => {
      let (pat1, pat2, pat3) = (
        et_pat(p, "abc", ""),
        et_pat(p, "ab[cd]e", ""),
        et_pat(p, "[a-e]+", ""),
      )
      ([p.prec(Integer(2), pat1), p.prec(Integer(1), pat2), pat3], [])
    },
    [
      ("abceef", Some((0, "abc"))),
      ("abdeef", Some((1, "abde"))),
      ("aeeeef", Some((2, "aeeee"))),
    ],
  )
  // immediate tokens with higher precedence
  check(
    p => {
      let (pat1, pat2) = (et_pat(p, "[^a]+", ""), et_pat(p, "[^ab]+", ""))
      let r1 = p.prec(Integer(1), pat1)
      let r2 = {
        let imm = p.prec(Integer(2), pat2)
        p.immediate_token(imm)
      }
      let sep = et_pat(p, "\\s", "")
      ([r1, r2], [sep])
    },
    [("cccb", Some((1, "ccc")))],
  )
  check(
    p => {
      let r1 = et_str(p, "a")
      let r2 = {
        let (inner_1, inner_2) = (et_str(p, "b"), et_str(p, "c"))
        p.choice([inner_1, inner_2])
      }
      let r3 = et_str(p, "d")
      ([p.seq([r1, r2, r3])], [])
    },
    [
      ("abd", Some((0, "abd"))),
      ("acd", Some((0, "acd"))),
      ("abc", None),
      ("ad", None),
      ("d", None),
      ("a", None),
    ],
  )
  // nested choices within sequences
  check(
    p => {
      let r1 = et_pat(p, "[0-9]+", "")
      let r2 = {
        let blank = p.blank()
        let inner_ch = {
          let ch1 = {
            let (e1, e2) = (et_str(p, "e"), et_str(p, "E"))
            p.choice([e1, e2])
          }
          let ch2 = {
            let blank = p.blank()
            let (plus, minus) = (et_str(p, "+"), et_str(p, "-"))
            let inner_ch = p.choice([plus, minus])
            p.choice([blank, inner_ch])
          }
          let pat = et_pat(p, "[0-9]+", "")
          let sq = p.seq([ch1, ch2, pat])
          p.choice([sq])
        }
        p.choice([blank, inner_ch])
      }
      let seq = p.seq([r1, r2])
      ([seq], [])
    },
    [
      ("12", Some((0, "12"))),
      ("12e", Some((0, "12"))),
      ("12g", Some((0, "12"))),
      ("12e3", Some((0, "12e3"))),
      ("12e+", Some((0, "12"))),
      ("12E+34 +", Some((0, "12E+34"))),
      ("12e34", Some((0, "12e34"))),
    ],
  )
  // nested groups
  check(
    p => {
      let pat = et_pat(p, "([^x\\\\]|\\\\(.|\n))+", "")
      let sq = p.seq([pat])
      ([sq], [])
    },
    [("abcx", Some((0, "abc"))), ("abc\\0x", Some((0, "abc\\0")))],
  )
  // allowing unrecognized escape sequences
  check(
    p => {
      // Escaped forward slash (used in JS because '/' is the regex delimiter)
      let v1 = et_pat(p, "\\/", "")
      // Escaped quotes
      let v2 = et_pat(p, "\\\"\\'", "")
      // Quote preceded by a literal backslash
      let v3 = et_pat(p, "[\\\\']+", "")
      ([v1, v2, v3], [])
    },
    [
      ("/", Some((0, "/"))),
      ("\"'", Some((1, "\"'"))),
      ("'\\'a", Some((2, "'\\'"))),
    ],
  )
}

///|
test "rule expansion: unicode" {
  // unicode property escapes
  check(
    p => {
      let v1 = et_pat(p, "\\p{L}+\\P{L}+", "")
      let v2 = et_pat(
        p, "\\p{White_Space}+\\P{White_Space}+[\\p{White_Space}]*", "",
      )
      ([v1, v2], [])
    },
    [
      ("  123   abc", Some((1, "  123   "))),
      ("ბΨƁ___ƀƔ", Some((0, "ბΨƁ___"))),
    ],
  )
  // unicode property escapes in bracketed sets
  check(one("[\\p{L}\\p{Nd}]+", ""), [
    ("abΨ12٣٣, ok", Some((0, "abΨ12٣٣"))),
  ])
  // unicode character escapes
  check(
    p => {
      let v1 = et_pat(p, "\\u{00dc}", "")
      let v2 = et_pat(p, "\\U{000000dd}", "")
      let v3 = et_pat(p, "\\u00de", "")
      let v4 = et_pat(p, "\\U000000df", "")
      ([v1, v2, v3, v4], [])
    },
    [
      ("\u{00dc}", Some((0, "\u{00dc}"))),
      ("\u{00dd}", Some((1, "\u{00dd}"))),
      ("\u{00de}", Some((2, "\u{00de}"))),
      ("\u{00df}", Some((3, "\u{00df}"))),
    ],
  )
  check(
    p => {
      let v1 = et_pat(p, "u\\{[0-9a-fA-F]+\\}", "")
      // Already-escaped curly braces
      let v2 = et_pat(p, "\\{[ab]{3}\\}", "")
      // Unicode codepoints
      let v3 = et_pat(p, "\\u{1000A}", "")
      // Unicode codepoints (lowercase)
      let v4 = et_pat(p, "\\u{1000b}", "")
      ([v1, v2, v3, v4], [])
    },
    [
      ("u{1234} ok", Some((0, "u{1234}"))),
      ("{aba}}", Some((1, "{aba}"))),
      ("\u{1000A}", Some((2, "\u{1000A}"))),
      ("\u{1000b}", Some((3, "\u{1000b}"))),
    ],
  )
  // Emojis
  check(one("\\p{Emoji}+", ""), [
    ("🐎", Some((0, "🐎"))),
    ("🐴🐴", Some((0, "🐴🐴"))),
    ("#0", Some((0, "#0"))), // These chars are technically emojis!
    ("⻢", None),
    ("♞", None),
    ("horse", None),
  ])
}

///|
test "rule expansion: case insensitivity" {
  // Case-insensitive patterns must not fold in the two non-ASCII code
  // points that Unicode simple case folding maps onto ASCII letters:
  // `ſ` (U+017F) onto `s`, and the Kelvin sign `K` (U+212A) onto `k`.
  check(one("[sk]+", "i"), [
    ("sSkK.", Some((0, "sSkK"))),
    ("\u{017f}", None), // long s, not matched by `s`
    ("\u{212a}", None), // Kelvin sign, not matched by `k`
    ("sk\u{212a}", Some((0, "sk"))), // folded code point ends the token
  ])
  // A broad class carrying `/i` (a negated class, `\p{L}`, ...) keeps
  // `ſ`/`K`: folding never *introduces* them here (the class already
  // contains them), so there is nothing to drop.
  check(one("[^\"]", "i"), [
    ("\u{017f}", Some((0, "\u{017f}"))), // long s kept under /i
    ("\u{212a}", Some((0, "\u{212a}"))), // Kelvin sign kept under /i
    ("s", Some((0, "s"))),
  ])
  // An intentionally-written `ſ`/`K` is preserved: the stripping above
  // only fires when the ASCII pair it folds with is also present.
  check(one("[\u{017f}\u{212a}]+", ""), [
    ("\u{017f}\u{212a}.", Some((0, "\u{017f}\u{212a}"))),
  ])
  // Without the `i` flag nothing is folded, so a broad class such as
  // `[^"]` must keep `ſ`/`K` instead of stripping them as fold artifacts.
  check(one("[^\"]", ""), [
    ("a", Some((0, "a"))),
    ("\u{017f}", Some((0, "\u{017f}"))), // long s
    ("\u{212a}", Some((0, "\u{212a}"))), // Kelvin sign
    ("\"", None), // the one excluded character
  ])
  // `ſ`/`K` fold with nothing, so an explicit one pulls in no ASCII letter.
  check(one("[\u{017f}\u{212a}]+", "i"), [
    ("\u{017f}\u{212a}.", Some((0, "\u{017f}\u{212a}"))),
    ("s", None),
    ("k", None),
  ])
  // `\p{L}` already contains `ſ`/`K`, so folding adds nothing to strip.
  check(one("\\p{L}+", "i"), [
    ("\u{017f}", Some((0, "\u{017f}"))),
    ("\u{212a}", Some((0, "\u{212a}"))),
    ("aA", Some((0, "aA"))),
    ("1", None),
  ])
  // Folding happens at the leaves, before negation: `[^a-z]` under `/i`
  // must exclude `A-Z`, not re-admit it.
  check(one("[^a-z]", "i"), [
    ("!", Some((0, "!"))),
    ("a", None),
    ("A", None),
    ("\u{017f}", Some((0, "\u{017f}"))),
    ("\u{212a}", Some((0, "\u{212a}"))),
  ])
  // The same ordering through a nested class and through class-set algebra.
  check(one("[^[a-c]]", "i"), [
    ("d", Some((0, "d"))),
    ("a", None),
    ("A", None),
    ("C", None),
  ])
  check(one("[[a-z]--[b-d]]", "i"), [
    ("a", Some((0, "a"))),
    ("A", Some((0, "A"))),
    ("b", None),
    ("B", None),
  ])
  check(one("[[a-z]&&[b-d]]", "i"), [
    ("b", Some((0, "b"))),
    ("B", Some((0, "B"))),
    ("e", None),
    ("E", None),
  ])
  // Scoped flags apply only where they are in effect.
  check(one("(?i)a(?-i)b", ""), [
    ("ab", Some((0, "ab"))),
    ("Ab", Some((0, "Ab"))),
    ("aB", None),
  ])
  // Case-insensitivity does not leak from one token to the next.
  check(p => ([et_pat(p, "ab", "i"), et_pat(p, "cd", ""), et_str(p, "ef")], []), [
    ("AB", Some((0, "AB"))),
    ("cd", Some((1, "cd"))),
    ("CD", None),
    ("ef", Some((2, "ef"))),
    ("EF", None),
  ])
  check(one("\\$\\{[a-z0-9_\\.]*[^a-z0-9_\\.\\}]", "i"), [
    ("${a}", None),
    ("${A}", None),
    ("${a!", Some((0, "${a!"))),
    ("${!", Some((0, "${!"))),
  ])
  // `(?-u:...)` matches bytes. A byte below `0x80` is its own code point,
  // so an ASCII byte class converts exactly.
  check(one("(?-u:[a-z])+", ""), [("abc.", Some((0, "abc"))), ("ABC", None)])
  // Byte folding is ASCII only, so it cannot pull in `K`.
  check(one("(?-u:(?i)k)+", ""), [("kK.", Some((0, "kK"))), ("\u{212a}", None)])
}

///|
test "rule expansion: class set operations" {
  // Intersection
  check(one("[[0-7]&&[4-9]]+", ""), [
    ("456", Some((0, "456"))),
    ("64", Some((0, "64"))),
    ("452", Some((0, "45"))),
    ("91", None),
    ("8", None),
    ("3", None),
  ])
  // Difference
  check(one("[[0-9]--[4-7]]+", ""), [
    ("123", Some((0, "123"))),
    ("83", Some((0, "83"))),
    ("9", Some((0, "9"))),
    ("124", Some((0, "12"))),
    ("67", None),
    ("4", None),
  ])
  // Symmetric difference
  check(one("[[0-7]~~[4-9]]+", ""), [
    ("123", Some((0, "123"))),
    ("83", Some((0, "83"))),
    ("9", Some((0, "9"))),
    ("124", Some((0, "12"))),
    ("67", None),
    ("4", None),
  ])
  // Nested set operations
  //               0 1 2 3 4 5 6 7 8 9
  // [0-5]:        y y y y y y
  // [2-4]:            y y y
  // [0-5]--[2-4]: y y       y
  // [3-9]:              y y y y y y y
  // [6-7]:                    y y
  // [3-9]--[5-7]:       y y y     y y
  // final regex:  y y   y y       y y
  check(one("[[[0-5]--[2-4]]~~[[3-9]--[6-7]]]+", ""), [
    ("01", Some((0, "01"))),
    ("432", Some((0, "43"))),
    ("8", Some((0, "8"))),
    ("9", Some((0, "9"))),
    ("2", None),
    ("567", None),
  ])
}

///|
test "non ascii byte class is rejected" {
  let pool = RulePool::new()
  let root = et_pat(pool, "(?-u:[\\xc3\\xa9])", "")
  let vars = [
    LexicalToken::{ name: pool.intern("tok"), kind: Anonymous, root, },
  ]
  try expand_tokens(pool, vars, []) |> ignore catch {
    ExpandTokensError::Processing(err) => {
      assert_eq(err, {
        rule: "tok",
        error: ExpandRegex(NonAsciiByteClass({ start: 0xa9, end: 0xa9, })),
      })
      inspect(
        err,
        content="Error processing rule tok: The non-ASCII byte class \\xa9 via (?-u:...) is not supported. Remove the `-u` flag.\n",
      )
    }
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "repeat of empty choice does not leave an accept state" {
  check(
    p => {
      let token_a = et_str(p, "a")
      let (left, right) = (p.blank(), p.blank())
      let empty_choice = p.choice([left, right])
      let repeated_empty = p.repeat(empty_choice)
      let token_b_suffix = et_str(p, "b")
      let token_b = p.seq([repeated_empty, token_b_suffix])
      ([token_a, token_b], [])
    },
    [("b", Some((1, "b")))],
  )
}

///|
test "expand_tokens error messages" {
  let cases : Array[(String, String)] = [
    ("(?-u:\\xff)", "invalid utf-8 sequence of 1 bytes from index 0"),
    ("a\\b", "Regex error: Assertions are not supported"),
    ("(?-u:[\\x80-\\xff])", "The non-ASCII byte class \\x80-\\xff"),
    ("(?-u).", "The non-ASCII byte class \\x0b-\\xff"),
  ]
  for case in cases {
    let (value, expected) = case
    let pool = RulePool::new()
    let root = et_pat(pool, value, "")
    let vars = [
      LexicalToken::{ name: pool.intern("tok"), kind: Anonymous, root, },
    ]
    let message = try expand_tokens(pool, vars, []) catch {
      e => e.to_string()
    } noraise {
      _ => "no error"
    }
    if !message.contains(expected) {
      fail("\{value}: \{message}")
    }
  }
  // An empty token.
  let pool = RulePool::new()
  let root = et_str(pool, "")
  let vars = [
    LexicalToken::{ name: pool.intern("empty"), kind: Anonymous, root, },
  ]
  let message = try expand_tokens(pool, vars, []) catch {
    e => e.to_string()
  } noraise {
    _ => "no error"
  }
  inspect(
    message,
    content=(
      #|The rule `empty` matches the empty string.
      #|Tree-sitter does not support syntactic rules that match the empty string
      #|unless they are used only as the grammar's start rule.
      #|
    ),
  )
}
