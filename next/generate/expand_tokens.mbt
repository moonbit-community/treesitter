// Port of tree-sitter crates/generate/src/prepare_grammar/expand_tokens.rs.

///|
priv struct NfaBuilder {
  nfa : Nfa
  mut is_sep : Bool
  precedence_stack : Array[Int32]
}

///|
pub(all) suberror ExpandTokensError {
  EmptyString(String)
  Processing(ExpandTokensProcessingError)
  ExpandRule(ExpandRuleError)
} derive(Eq, Debug)

///|
pub impl Show for ExpandTokensError with fn output(self, f) {
  match self {
    EmptyString(rule) =>
      f.write_string(
        (
          $|The rule `\{rule}` matches the empty string.
          $|Tree-sitter does not support syntactic rules that match the empty string
          $|unless they are used only as the grammar's start rule.
          $|
        ),
      )
    Processing(e) => Show::output(e, f)
    ExpandRule(e) => Show::output(e, f)
  }
}

///|
pub(all) struct ExpandTokensProcessingError {
  rule : String
  error : ExpandRuleError
} derive(Eq, Debug)

///|
pub impl Show for ExpandTokensProcessingError with fn output(self, f) {
  f.write_string("Error processing rule \{self.rule}: \{self.error}\n")
}

///|
fn get_implicit_precedence(pool : RulePool, root : RuleId) -> Int32 {
  let mut id = root
  let mut boost = 0
  while true {
    match pool.node(id) {
      String(_) => return 2 + boost
      Metadata(params~, rule~) => {
        if pool.params(params).is_main_token {
          boost += 1
        }
        id = rule
      }
      _ => return boost
    }
  }
  boost
}

///|
fn get_completion_precedence(pool : RulePool, id : RuleId) -> Int32 {
  if pool.node(id) is Metadata(params~, ..) &&
    pool.params(params).precedence is Integer(p) {
    return p
  }
  0
}

///|
/// `prepare_grammar::expand_tokens`.
pub fn expand_tokens(
  pool : RulePool,
  lexical_variables : ArrayView[LexicalToken],
  separator_roots : ArrayView[RuleId],
) -> LexicalGrammar raise {
  let builder : NfaBuilder = {
    nfa: Nfa::new(),
    is_sep: true,
    precedence_stack: [0],
  }
  let separator_root = build_separator(pool, separator_roots)
  let variables = []
  for i, variable in lexical_variables {
    if pool.subtree_matches_empty_str(variable.root) {
      raise EmptyString(pool.resolve(variable.name))
    }
    let is_immediate_token = match pool.node(variable.root) {
      Metadata(params~, ..) => pool.params(params).is_main_token
      _ => false
    }
    builder.is_sep = false
    builder.nfa.states.push(
      Accept(
        variable_index=i,
        precedence=get_completion_precedence(pool, variable.root),
      ),
    )
    let last_state_id = builder.nfa.last_state_id()
    ignore(
      builder.expand_rule(pool, variable.root, last_state_id) catch {
        e => raise Processing({ rule: pool.resolve(variable.name), error: e, })
      },
    )
    if !is_immediate_token {
      builder.is_sep = true
      let last_state_id = builder.nfa.last_state_id()
      ignore(
        builder.expand_rule(pool, separator_root, last_state_id) catch {
          e => raise ExpandRule(e)
        },
      )
    }
    variables.push({
      name: variable.name,
      kind: variable.kind,
      implicit_precedence: get_implicit_precedence(pool, variable.root),
      start_state: builder.nfa.last_state_id(),
    })
  }
  { nfa: builder.nfa, variables, }
}

///|
fn build_separator(
  pool : RulePool,
  separator_roots : ArrayView[RuleId],
) -> RuleId {
  let blank = pool.push_node(Blank)
  if separator_roots.is_empty() {
    return blank
  }
  let elements : Array[RuleId] = []
  let stack = [blank]
  for i = separator_roots.length() - 1; i >= 0; i = i - 1 {
    stack.push(separator_roots[i])
  }
  while stack.pop() is Some(id) {
    if pool.node(id) is Choice(range) {
      let base = stack.length()
      for child in pool.child_slice(range) {
        stack.push(child)
      }
      // `stack[base..].reverse()`
      let mut lo = base
      let mut hi = stack.length() - 1
      while lo < hi {
        stack.swap(lo, hi)
        lo += 1
        hi -= 1
      }
    } else if !elements.iter().any(e => pool.subtree_eq(e, id)) {
      elements.push(id)
    }
  }
  let range = pool.push_children(elements)
  let choice = pool.push_node(Choice(range))
  pool.push_node(Repeat(choice))
}

///|
pub(all) suberror ExpandRuleError {
  UnexpectedSymbol(Symbol)
  UnexpectedReserved(String)
  UnexpectedEof
  Parse(RegexError)
  ExpandRegex(ExpandRegexError)
} derive(Eq, Debug)

///|
pub impl Show for ExpandRuleError with fn output(self, f) {
  match self {
    UnexpectedSymbol(symbol) =>
      f.write_string(
        "unexpected symbol Symbol { kind: \{symbol_type_debug(symbol.kind)}, index: \{symbol.index} }",
      )
    UnexpectedReserved(ctx) =>
      f.write_string("unexpected reserved-word context \{ctx}")
    UnexpectedEof =>
      f.write_string(
        "`eof()` cannot be used inside a token. A lexical rule cannot check for end of input, so use `eof()` only at the end of a syntactic rule.",
      )
    Parse(e) => Show::output(e, f)
    ExpandRegex(e) => Show::output(e, f)
  }
}

///|
/// Rust's derived `Debug` for `SymbolType`.
fn symbol_type_debug(kind : SymbolType) -> String {
  match kind {
    External => "External"
    End => "End"
    EndOfNonTerminalExtra => "EndOfNonTerminalExtra"
    Terminal => "Terminal"
    NonTerminal => "NonTerminal"
  }
}

///|
pub(all) suberror ExpandRegexError {
  Utf8(String)
  Assertion
  NonAsciiByteClass(NonAsciiByteClassError)
} derive(Eq, Debug)

///|
pub impl Show for ExpandRegexError with fn output(self, f) {
  match self {
    Utf8(message) => f.write_string(message)
    Assertion => f.write_string("Regex error: Assertions are not supported")
    NonAsciiByteClass(e) => Show::output(e, f)
  }
}

///|
pub(all) struct NonAsciiByteClassError {
  start : Byte
  end : Byte
} derive(Eq, Debug)

///|
fn hex2(b : Byte) -> String {
  let digits = "0123456789abcdef"
  let n = b.to_int()
  String::from_array([
    digits[n / 16].to_int().unsafe_to_char(),
    digits[n % 16].to_int().unsafe_to_char(),
  ])
}

///|
pub impl Show for NonAsciiByteClassError with fn output(self, f) {
  let { start, end, } = self
  f.write_string("The non-ASCII byte class ")
  if start == end {
    f.write_string("\\x\{hex2(start)}")
  } else {
    f.write_string("\\x\{hex2(start)}-\\x\{hex2(end)}")
  }
  f.write_string(" via (?-u:...) is not supported. Remove the `-u` flag.")
}

///|
fn NfaBuilder::expand_rule(
  self : NfaBuilder,
  pool : RulePool,
  id : RuleId,
  next_state_id : Int32,
) -> Bool raise ExpandRuleError {
  let mut next_state_id = next_state_id
  match pool.node(id) {
    Pattern(s, f) => {
      // With unicode enabled, `\w`, `\s` and `\d` expand to character sets that are much
      // larger than intended, so we replace them with the actual
      // character sets they should represent. If the full unicode range
      // of `\w`, `\s` or `\d` are needed then `\p{L}`, `\p{Z}` and `\p{N}` should be
      // used.
      let s = pool
        .resolve(s)
        .replace_all(old="\\w", new="[0-9A-Za-z_]")
        .replace_all(old="\\s", new="[\\t-\\r ]")
        .replace_all(old="\\d", new="[0-9]")
        .replace_all(old="\\W", new="[^0-9A-Za-z_]")
        .replace_all(old="\\S", new="[^\\t-\\r ]")
        .replace_all(old="\\D", new="[^0-9]")
      // Parse WITHOUT case folding and fold ourselves (see
      // `case_fold_ascii_safe`). Letting `regex_syntax` fold would pull the
      // long s `ſ` and Kelvin sign `K` into ASCII `s`/`k`.
      let hir = pattern_parse(s, pool.resolve(f).contains("i")) catch {
        e => raise Parse(e)
      }
      self.expand_regex(hir, next_state_id) catch {
        e => raise ExpandRegex(e)
      }
    }
    String(s) => {
      let s = pool.resolve(s)
      let chars : Array[Char] = s.iter().collect()
      for i = chars.length() - 1; i >= 0; i = i - 1 {
        self.push_advance(
          CharacterSet::from_char(chars[i].to_int()),
          next_state_id,
        )
        next_state_id = self.nfa.last_state_id()
      }
      !s.is_empty()
    }
    Choice(range) => {
      let elements = pool.child_slice(range)
      let alternative_state_ids = []
      let mut did_expand = false
      for element in elements {
        if self.expand_rule(pool, element, next_state_id) {
          did_expand = true
          alternative_state_ids.push(self.nfa.last_state_id())
        } else {
          alternative_state_ids.push(next_state_id)
        }
      }
      // `sort_unstable` of plain integers: ties are indistinguishable.
      alternative_state_ids.sort()
      dedup(alternative_state_ids)
      let last_state_id = self.nfa.last_state_id()
      alternative_state_ids.retain(i => i != last_state_id)
      for alternative_state_id in alternative_state_ids {
        self.push_split(alternative_state_id)
      }
      did_expand
    }
    Seq(range) => {
      let mut result = false
      let elements = pool.child_slice(range)
      for i = elements.length() - 1; i >= 0; i = i - 1 {
        if self.expand_rule(pool, elements[i], next_state_id) {
          result = true
        }
        next_state_id = self.nfa.last_state_id()
      }
      result
    }
    Repeat(rule) => {
      self.nfa.states.push(Accept(variable_index=0, precedence=0)) // Placeholder for split
      let split_state_id = self.nfa.last_state_id()
      if self.expand_rule(pool, rule, split_state_id) {
        self.nfa.states[split_state_id] = Split(
          self.nfa.last_state_id(),
          next_state_id,
        )
        true
      } else {
        ignore(self.nfa.states.pop())
        false
      }
    }
    Metadata(params~, rule~) => {
      let has_precedence = if pool.params(params).precedence
        is Integer(precedence) {
        self.precedence_stack.push(precedence)
        true
      } else {
        false
      }
      defer (if has_precedence { ignore(self.precedence_stack.pop()) })
      self.expand_rule(pool, rule, next_state_id)
    }
    Blank => false
    Eof => raise UnexpectedEof
    Sym(symbol) => raise UnexpectedSymbol(symbol)
    Reserved(ctx~, ..) => raise UnexpectedReserved(pool.resolve(ctx))
    // `NamedSymbol` is interned to `Sym` by intern_symbols
    NamedSymbol(_) => abort("unreachable")
  }
}

///|
fn NfaBuilder::expand_regex(
  self : NfaBuilder,
  hir : @hir.Hir,
  next_state_id : Int32,
) -> Bool raise ExpandRegexError {
  let mut next_state_id = next_state_id
  match hir.kind() {
    Empty => false
    Literal(Literal(bytes)) => {
      let chars = @hir.from_utf8(bytes[:]) catch {
        e => raise Utf8(e.to_string())
      }
      for i = chars.length() - 1; i >= 0; i = i - 1 {
        self.push_advance(
          CharacterSet::from_char(chars[i].to_int()),
          next_state_id,
        )
        next_state_id = self.nfa.last_state_id()
      }
      true
    }
    Class(class) =>
      match class {
        Unicode(class) => {
          let mut chars = CharacterSet::empty()
          for c in class.ranges() {
            chars = chars.add_range(c.start(), c.end())
          }
          self.push_advance(chars, next_state_id)
          true
        }
        // Byte classes only come from non-Unicode `(?-u:...)` groups, which
        // JS regex syntax can't express. A byte below `0x80` is its own
        // code point, so it converts exactly. Above that, a byte is one
        // part of a UTF-8 sequence and has no character to convert to.
        Bytes(bytes_class) => {
          let mut chars = CharacterSet::empty()
          for c in bytes_class.ranges() {
            if c.end() > 0x7F {
              raise NonAsciiByteClass({ start: c.start(), end: c.end(), })
            }
            chars = chars.add_range(c.start().to_int(), c.end().to_int())
          }
          self.push_advance(chars, next_state_id)
          true
        }
      }
    Look(_) => raise Assertion
    Repetition(repetition) =>
      match (repetition.min, repetition.max) {
        (0, Some(1)) => self.expand_zero_or_one(repetition.sub, next_state_id)
        (1, None) => self.expand_one_or_more(repetition.sub, next_state_id)
        (0, None) => self.expand_zero_or_more(repetition.sub, next_state_id)
        (min, Some(max)) if min == max =>
          self.expand_count(repetition.sub, min, next_state_id)
        (min, None) =>
          if self.expand_zero_or_more(repetition.sub, next_state_id) {
            self.expand_count(repetition.sub, min, next_state_id)
          } else {
            false
          }
        (min, Some(max)) => {
          let mut result = self.expand_count(repetition.sub, min, next_state_id)
          for _ in min..<max {
            if result {
              next_state_id = self.nfa.last_state_id()
            }
            if self.expand_zero_or_one(repetition.sub, next_state_id) {
              result = true
            }
          }
          result
        }
      }
    Capture(capture) => self.expand_regex(capture.sub, next_state_id)
    Concat(concat) => {
      let mut result = false
      for i = concat.length() - 1; i >= 0; i = i - 1 {
        if self.expand_regex(concat[i], next_state_id) {
          result = true
          next_state_id = self.nfa.last_state_id()
        }
      }
      result
    }
    Alternation(alternations) => {
      let alternative_state_ids = []
      for hir in alternations {
        if self.expand_regex(hir, next_state_id) {
          alternative_state_ids.push(self.nfa.last_state_id())
        } else {
          alternative_state_ids.push(next_state_id)
        }
      }
      // `sort_unstable` of plain integers: ties are indistinguishable.
      alternative_state_ids.sort()
      dedup(alternative_state_ids)
      let last_state_id = self.nfa.last_state_id()
      alternative_state_ids.retain(i => i != last_state_id)
      for alternative_state_id in alternative_state_ids {
        self.push_split(alternative_state_id)
      }
      true
    }
  }
}

///|
fn NfaBuilder::expand_one_or_more(
  self : NfaBuilder,
  hir : @hir.Hir,
  next_state_id : Int32,
) -> Bool raise ExpandRegexError {
  self.nfa.states.push(Accept(variable_index=0, precedence=0)) // Placeholder for split
  let split_state_id = self.nfa.last_state_id()
  if self.expand_regex(hir, split_state_id) {
    self.nfa.states[split_state_id] = Split(
      self.nfa.last_state_id(),
      next_state_id,
    )
    true
  } else {
    ignore(self.nfa.states.pop())
    false
  }
}

///|
fn NfaBuilder::expand_zero_or_one(
  self : NfaBuilder,
  hir : @hir.Hir,
  next_state_id : Int32,
) -> Bool raise ExpandRegexError {
  if self.expand_regex(hir, next_state_id) {
    self.push_split(next_state_id)
    true
  } else {
    false
  }
}

///|
fn NfaBuilder::expand_zero_or_more(
  self : NfaBuilder,
  hir : @hir.Hir,
  next_state_id : Int32,
) -> Bool raise ExpandRegexError {
  if self.expand_one_or_more(hir, next_state_id) {
    self.push_split(next_state_id)
    true
  } else {
    false
  }
}

///|
fn NfaBuilder::expand_count(
  self : NfaBuilder,
  hir : @hir.Hir,
  count : UInt32,
  next_state_id : Int32,
) -> Bool raise ExpandRegexError {
  let mut next_state_id = next_state_id
  let mut result = false
  for _ in 0U..<count {
    if self.expand_regex(hir, next_state_id) {
      result = true
      next_state_id = self.nfa.last_state_id()
    }
  }
  result
}

///|
fn NfaBuilder::push_advance(
  self : NfaBuilder,
  chars : CharacterSet,
  state_id : Int32,
) -> Unit {
  let precedence = self.precedence_stack[self.precedence_stack.length() - 1]
  self.nfa.states.push(
    Advance(chars~, state_id~, precedence~, is_sep=self.is_sep),
  )
}

///|
fn NfaBuilder::push_split(self : NfaBuilder, state_id : Int32) -> Unit {
  let last_state_id = self.nfa.last_state_id()
  self.nfa.states.push(Split(state_id, last_state_id))
}
