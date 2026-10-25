// Port of tree-sitter crates/generate/src/build_tables/coincident_tokens.rs.

///|
priv struct CoincidentTokenIndex {
  /// Flat bitset for fast `contains()` checks. Indexed as `a * n + b`
  /// (both `(a,b)` and `(b,a)` bits are set, so no min/max normalization needed).
  contains_bits : FixedArray[UInt64]
  /// Flat biset for fast `Self::all_coincident_states_have_word` checks.
  /// Bit `(a, b)` is set iff tokens `a` and `b` are coincident in some parse state
  /// where the grammar's word token is _not_ a valid lookahead. Allows for fast
  /// answers to "do all states containing this pair also contain the word token?".
  without_word_bits : FixedArray[UInt64]
  /// Word-aligned per-row bitsets for vectorized intersection checks.
  /// Row `a` spans `[a * row_words .. (a+1) * row_words]`.
  /// Bit `b` is set iff tokens `a` and `b` are coincident in some parse state.
  row_bits : FixedArray[UInt64]
  n : Int32
}

///|
fn set_bit(bits : FixedArray[UInt64], index : Int32) -> Unit {
  bits[index / 64] = bits[index / 64] | (1UL << (index % 64))
}

///|
fn CoincidentTokenIndex::new(
  table : ParseTable,
  lexical_grammar : LexicalGrammar,
  word_token : Symbol?,
) -> CoincidentTokenIndex {
  let n = lexical_grammar.variables.length()
  let row_words = (n + 63) / 64
  let result = {
    n,
    contains_bits: FixedArray::make((n * n + 63) / 64, 0UL),
    without_word_bits: FixedArray::make((n * n + 63) / 64, 0UL),
    row_bits: FixedArray::make(n * row_words, 0UL),
  }
  // Pre-collect terminal indices up front rather than continuously recomputing within the
  // loop below.
  let terminal_indices : Array[Int32] = []
  // The index only records which terminals share some state, so a state adds nothing if a
  // state with the same terminals was already recorded, with/without the word token.
  let recorded_with_word : Map[Array[Int32], Unit] = Map([])
  let recorded_without_word : Map[Array[Int32], Unit] = Map([])
  for state in table.states {
    terminal_indices.clear()
    for s in state.terminal_entries.keys() {
      if s.terminal_index() is Some(index) {
        terminal_indices.push(index)
      }
    }
    terminal_indices.sort()
    let has_word = match word_token {
      Some(w) => state.terminal_entries.contains_key(w)
      None => false
    }
    let recorded = if has_word {
      recorded_with_word
    } else {
      recorded_without_word
    }
    if recorded.contains(terminal_indices) {
      continue
    }
    recorded[terminal_indices.copy()] = ()
    for i, a in terminal_indices {
      for k in i..<terminal_indices.length() {
        let b = terminal_indices[k]
        // Set both (a,b) and (b,a) bits so `contains()` needs
        // no min/max normalization.
        let ab = a * n + b
        let ba = b * n + a
        set_bit(result.contains_bits, ab)
        set_bit(result.contains_bits, ba)
        if !has_word {
          set_bit(result.without_word_bits, ab)
          set_bit(result.without_word_bits, ba)
        }
        // Also populate the word-aligned row bitsets.
        set_bit(result.row_bits, a * row_words * 64 + b)
        set_bit(result.row_bits, b * row_words * 64 + a)
      }
    }
  }
  result
}

///|
fn CoincidentTokenIndex::all_coincident_states_have_word(
  self : CoincidentTokenIndex,
  a : Int32,
  b : Int32,
) -> Bool {
  let bit_index = a * self.n + b
  (self.without_word_bits[bit_index / 64] & (1UL << (bit_index % 64))) == 0
}

///|
fn CoincidentTokenIndex::contains(
  self : CoincidentTokenIndex,
  a : Int32,
  b : Int32,
) -> Bool {
  let bit_index = a * self.n + b
  (self.contains_bits[bit_index / 64] & (1UL << (bit_index % 64))) != 0
}
