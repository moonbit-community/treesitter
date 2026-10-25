// Port of tree-sitter crates/generate/src/build_tables/token_conflicts.rs.

// Per-(i,j) token conflict status bits (upstream's `TokenConflictStatus`).

///|
const MATCHES_PREFIX : Int32 = 0x01

///|
const DOES_MATCH_CONTINUATION : Int32 = 0x02

///|
const DOES_MATCH_VALID_CONT : Int32 = 0x04

///|
const DOES_MATCH_SEPARATORS : Int32 = 0x08

///|
const MATCHES_SAME_STRING : Int32 = 0x10

///|
const MATCHES_DIFFERENT_STRING : Int32 = 0x20

///|
/// (`following_tokens` and `following_chars_by_index` are debugging aids
/// upstream; `starting_chars_by_index` is read by tests.)
#warnings("-unused_field")
priv struct TokenConflictMap {
  n : Int32
  status_matrix : FixedArray[Int32]
  following_tokens : Array[TokenSet]
  starting_chars_by_index : Array[CharacterSet]
  following_chars_by_index : Array[CharacterSet]
  /// Per-row bitsets for fast batch conflict checks.
  /// Row `i` spans `[i * row_words .. (i+1) * row_words]`.
  /// Bit `j` is set iff `does_conflict(i, j)` || `does_match_prefix(i, j)`.
  conflict_or_prefix_bits : FixedArray[UInt64]
  /// Bit `j` is set iff `does_overlap(i, j)` || `does_overlap(j, i)`.
  overlap_either_bits : FixedArray[UInt64]
  row_words : Int32
}

///|
/// Create a token conflict map based on a lexical grammar, which describes the structure
/// of each token, and a `following_token` map, which indicates which tokens may appear
/// immediately after each other token.
///
/// This analyzes the possible kinds of overlap between each pair of tokens and stores
/// them in a matrix.
fn TokenConflictMap::new(
  grammar : LexicalGrammar,
  following_tokens : Array[TokenSet],
) -> TokenConflictMap {
  let cursor = NfaCursor::new(grammar.nfa, [])
  let starting_chars = get_starting_chars(cursor, grammar)
  let following_chars = get_following_chars(starting_chars, following_tokens)

  // Pre-compute O(1) lookup: NFA state ID->owning variable index.
  // Replaces repeated O(log n) binary searches in compute_conflict_status.
  let nfa_state_to_var = FixedArray::makei(grammar.nfa.states.length(), id => {
    grammar.variable_index_for_nfa_state(id)
  })
  let n = grammar.variables.length()
  let status_matrix = FixedArray::make(n * n, 0)
  for i in 0..<n {
    for j in 0..<i {
      let status = compute_conflict_status(
        cursor, grammar, following_chars, nfa_state_to_var, i, j,
      )
      status_matrix[matrix_index(n, i, j)] = status.0
      status_matrix[matrix_index(n, j, i)] = status.1
    }
  }

  // Precompute per-row bitsets for vectorized check_token_conflicts.
  let row_words = (n + 63) / 64
  let conflict_mask = DOES_MATCH_VALID_CONT |
    DOES_MATCH_SEPARATORS |
    MATCHES_SAME_STRING |
    MATCHES_PREFIX
  let overlap_mask = DOES_MATCH_SEPARATORS |
    MATCHES_PREFIX |
    MATCHES_SAME_STRING |
    DOES_MATCH_CONTINUATION
  let conflict_or_prefix_bits : FixedArray[UInt64] = FixedArray::make(
    n * row_words,
    0,
  )
  let overlap_either_bits : FixedArray[UInt64] = FixedArray::make(
    n * row_words,
    0,
  )
  for i in 0..<n {
    let row_base = i * row_words
    for j in 0..<n {
      let entry_ij = status_matrix[matrix_index(n, i, j)]
      if (entry_ij & conflict_mask) != 0 {
        conflict_or_prefix_bits[row_base + j / 64] = conflict_or_prefix_bits[row_base +
          j / 64] |
          (1UL << (j % 64))
      }
      let entry_ji = status_matrix[matrix_index(n, j, i)]
      if (entry_ij & overlap_mask) != 0 || (entry_ji & overlap_mask) != 0 {
        overlap_either_bits[row_base + j / 64] = overlap_either_bits[row_base +
          j / 64] |
          (1UL << (j % 64))
      }
    }
  }
  {
    n,
    status_matrix,
    following_tokens,
    starting_chars_by_index: starting_chars,
    following_chars_by_index: following_chars,
    conflict_or_prefix_bits,
    overlap_either_bits,
    row_words,
  }
}

///|
/// Does token `i` match any strings that token `j` also matches, such that token `i`
/// is preferred over token `j`?
fn TokenConflictMap::has_same_conflict_status(
  self : TokenConflictMap,
  a : Int32,
  b : Int32,
  other : Int32,
) -> Bool {
  let left = self.status_matrix[matrix_index(self.n, a, other)]
  let right = self.status_matrix[matrix_index(self.n, b, other)]
  left == right
}

///|
/// Does token `i` match any strings that token `j` does *not* match?
fn TokenConflictMap::does_match_different_string(
  self : TokenConflictMap,
  i : Int32,
  j : Int32,
) -> Bool {
  (self.status_matrix[matrix_index(self.n, i, j)] & MATCHES_DIFFERENT_STRING) !=
  0
}

///|
/// Does token `i` match any strings that token `j` also matches, where
/// token `i` is preferred over token `j`?
fn TokenConflictMap::does_match_same_string(
  self : TokenConflictMap,
  i : Int32,
  j : Int32,
) -> Bool {
  (self.status_matrix[matrix_index(self.n, i, j)] & MATCHES_SAME_STRING) != 0
}

///|
fn TokenConflictMap::does_conflict(
  self : TokenConflictMap,
  i : Int32,
  j : Int32,
) -> Bool {
  let entry = self.status_matrix[matrix_index(self.n, i, j)]
  (
    entry &
    (DOES_MATCH_VALID_CONT | DOES_MATCH_SEPARATORS | MATCHES_SAME_STRING)
  ) !=
  0
}

///|
/// Does token `i` match any strings that are *prefixes* of strings matched by `j`?
#warnings("-unused_value")
fn TokenConflictMap::does_match_prefix(
  self : TokenConflictMap,
  i : Int32,
  j : Int32,
) -> Bool {
  (self.status_matrix[matrix_index(self.n, i, j)] & MATCHES_PREFIX) != 0
}

///|
fn TokenConflictMap::does_match_shorter_or_longer(
  self : TokenConflictMap,
  i : Int32,
  j : Int32,
) -> Bool {
  let entry = self.status_matrix[matrix_index(self.n, i, j)]
  let reverse_entry = self.status_matrix[matrix_index(self.n, j, i)]
  (entry & (DOES_MATCH_VALID_CONT | DOES_MATCH_SEPARATORS)) != 0 &&
  (reverse_entry & DOES_MATCH_SEPARATORS) == 0
}

///|
fn TokenConflictMap::does_overlap(
  self : TokenConflictMap,
  i : Int32,
  j : Int32,
) -> Bool {
  (
    self.status_matrix[matrix_index(self.n, i, j)] &
    (
      DOES_MATCH_SEPARATORS |
      MATCHES_PREFIX |
      MATCHES_SAME_STRING |
      DOES_MATCH_CONTINUATION
    )
  ) !=
  0
}

///|
fn TokenConflictMap::prefer_token(
  grammar : LexicalGrammar,
  left : (Int32, Int32),
  right : (Int32, Int32),
) -> Bool {
  let c = left.0.compare(right.0)
  if c < 0 {
    false
  } else if c > 0 {
    true
  } else {
    let c = grammar.variables[left.1].implicit_precedence.compare(
      grammar.variables[right.1].implicit_precedence,
    )
    if c < 0 {
      false
    } else if c > 0 {
      true
    } else {
      left.1 < right.1
    }
  }
}

///|
fn TokenConflictMap::prefer_transition(
  grammar : LexicalGrammar,
  t : NfaTransition,
  completed_id : Int32,
  completed_precedence : Int32,
  has_separator_transitions : Bool,
) -> Bool {
  if t.precedence < completed_precedence {
    return false
  }
  if t.precedence == completed_precedence {
    if t.is_separator {
      return false
    }
    if has_separator_transitions &&
      !grammar
      .variable_indices_for_nfa_states(t.states)
      .iter()
      .any(i => i == completed_id) {
      return false
    }
  }
  true
}

///|
fn matrix_index(variable_count : Int32, i : Int32, j : Int32) -> Int32 {
  variable_count * i + j
}

///|
fn get_starting_chars(
  cursor : NfaCursor,
  grammar : LexicalGrammar,
) -> Array[CharacterSet] {
  let result = Array(capacity=grammar.variables.length())
  for variable in grammar.variables {
    cursor.reset([variable.start_state])
    let mut all_chars = CharacterSet::empty()
    for transition in cursor.transition_chars() {
      all_chars = all_chars.add(transition.0)
    }
    result.push(all_chars)
  }
  result
}

///|
fn get_following_chars(
  starting_chars : Array[CharacterSet],
  following_tokens : Array[TokenSet],
) -> Array[CharacterSet] {
  following_tokens.map(following_tokens => {
    let mut chars = CharacterSet::empty()
    for token in following_tokens.iter() {
      if token.terminal_index() is Some(index) {
        chars = chars.add(starting_chars[index])
      }
    }
    chars
  })
}

///|
fn compute_conflict_status(
  cursor : NfaCursor,
  grammar : LexicalGrammar,
  following_chars : Array[CharacterSet],
  nfa_state_to_var : FixedArray[Int32],
  i : Int32,
  j : Int32,
) -> (Int32, Int32) {
  // Upstream keeps a set of 64-bit hashes of the visited state sets, treating
  // a (vanishingly unlikely) hash collision as a visit. The state sets
  // themselves are kept here.
  let visited_state_sets : Map[Array[Int32], Unit] = Map([])
  let state_set_queue : Array[Array[Int32]] = [
    [grammar.variables[i].start_state, grammar.variables[j].start_state],
  ]
  let mut result0 = 0
  let mut result1 = 0
  while state_set_queue.pop() is Some(state_set) {
    // If only one of the two tokens could possibly match from this state, then
    // there is no reason to analyze any of its successors. Just record the fact
    // that the token matches a string that the other token does not match.
    let first_live_variable_index = nfa_state_to_var[state_set[0]]
    if state_set
      .iter()
      .all(s => nfa_state_to_var[s] == first_live_variable_index) {
      if first_live_variable_index == i {
        result0 = result0 | MATCHES_DIFFERENT_STRING
      } else {
        result1 = result1 | MATCHES_DIFFERENT_STRING
      }
      continue
    }

    // Don't pursue states where there's no potential for conflict.
    cursor.reset(state_set)

    // Compute lazily: most BFS states have no completions, so
    // `within_separator` is never needed in those iterations.
    let mut within_separator : Bool? = None

    // Examine each possible completed token in this state.
    let mut completion : (Int32, Int32)? = None
    for item in cursor.completions() {
      let (id, precedence) = item
      let sep = match within_separator {
        Some(sep) => sep
        None => {
          let sep = cursor.transition_chars().iter().any(t => t.1)
          within_separator = Some(sep)
          sep
        }
      }
      if sep {
        if id == i {
          result0 = result0 | DOES_MATCH_SEPARATORS
        } else {
          result1 = result1 | DOES_MATCH_SEPARATORS
        }
      }

      // If the other token has already completed, then this is
      // a same-string conflict.
      match completion {
        Some((prev_id, prev_precedence)) => {
          if id == prev_id {
            continue
          }

          // Determine which of the two tokens is preferred.
          let preferred_id = if TokenConflictMap::prefer_token(
              grammar,
              (prev_precedence, prev_id),
              (precedence, id),
            ) {
            prev_id
          } else {
            completion = Some((id, precedence))
            id
          }
          if preferred_id == i {
            result0 = result0 | MATCHES_SAME_STRING
          } else {
            result1 = result1 | MATCHES_SAME_STRING
          }
        }
        None => completion = Some((id, precedence))
      }
    }

    // Examine each possible transition from this state to detect substring conflicts.
    for transition in cursor.transitions() {
      let mut can_advance = true

      // If there is already a completed token in this state, then determine
      // if the next state can also match the completed token. If so, then
      // this is *not* a conflict.
      if completion is Some((completed_id, completed_precedence)) {
        let mut advanced_id = None
        let mut successor_contains_completed_id = false
        let mut prev_var = None
        for state_id in transition.states {
          let var_id = nfa_state_to_var[state_id]
          if prev_var == Some(var_id) {
            continue
          }
          prev_var = Some(var_id)
          if var_id == completed_id {
            successor_contains_completed_id = true
            break
          }
          advanced_id = Some(var_id)
        }

        // Determine which action is preferred: matching the already complete
        // token, or continuing on to try and match the other longer token.
        if advanced_id is Some(advanced_id) && !successor_contains_completed_id {
          if TokenConflictMap::prefer_transition(
              grammar,
              transition,
              completed_id,
              completed_precedence,
              within_separator.unwrap_or(false),
            ) {
            can_advance = true
            if advanced_id == i {
              result0 = result0 | DOES_MATCH_CONTINUATION
              if transition.characters.does_intersect(following_chars[j]) {
                result0 = result0 | DOES_MATCH_VALID_CONT
              }
            } else {
              result1 = result1 | DOES_MATCH_CONTINUATION
              if transition.characters.does_intersect(following_chars[i]) {
                result1 = result1 | DOES_MATCH_VALID_CONT
              }
            }
          } else if completed_id == i {
            result0 = result0 | MATCHES_PREFIX
          } else {
            result1 = result1 | MATCHES_PREFIX
          }
        }
      }
      if can_advance && !visited_state_sets.contains(transition.states) {
        visited_state_sets[transition.states] = ()
        state_set_queue.push(transition.states.copy())
      }
    }
  }
  (result0, result1)
}
