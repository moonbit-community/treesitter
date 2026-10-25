// Port of tree-sitter crates/generate/src/render.rs: the decisions of
// `add_lex_function`, `add_lex_state` and `add_character_range_conditions`,
// captured as a `@language.LexProgram`. `RenderedParser::add_lex_function`
// (render_c.mbt) prints the C lex function from it.

///|
/// `CharacterSet::ranges` as `TSCharacterRange`s.
fn Generator::character_ranges(
  chars : CharacterSet,
) -> Array[@language.CharacterRange] {
  chars.ranges().map(range => { start: range.0, end: range.1, })
}

///|
/// The lex function for `lex_table`. Its `large_character_sets` are all of
/// `Tables::large_character_sets`, so a set's index is upstream's index.
fn Generator::lex_program(
  self : Generator,
  lex_table : LexTable,
) -> @language.LexProgram {
  {
    states: lex_table.states.map(state => self.lex_state_code(state)),
    large_character_sets: self.large_character_sets.map(entry => {
      Generator::character_ranges(entry.1)
    }),
  }
}

///|
/// `add_lex_state`.
fn Generator::lex_state_code(
  self : Generator,
  state : LexState,
) -> @language.LexStateCode {
  let accept_token = match state.accept_action {
    Some(accept_action) => Some(self.symbol_value(accept_action))
    None => None
  }
  let eof_advance = match state.eof_action {
    Some(eof_action) => Some(eof_action.state)
    None => None
  }
  let chars_copy = CharacterSet::empty()
  let large_set = CharacterSet::empty()
  let mut ruled_out_chars = CharacterSet::empty()

  // The transitions in a lex state are sorted with the single-character
  // transitions first. If there are many single-character transitions,
  // then implement them using an array of (lookahead character, state)
  // pairs, instead of individual if statements, in order to reduce compile
  // time.
  let mut leading_simple_transition_count = 0
  let mut leading_simple_transition_range_count = 0
  for entry in state.advance_actions {
    let (chars, action) = entry
    if action.in_main_token &&
      chars
      .ranges()
      .iter()
      .all(r => {
        let (start, end) = r
        end <= start + 1 && end <= 0xFFFF
      }) {
      leading_simple_transition_count += 1
      leading_simple_transition_range_count += chars.range_count()
    } else {
      break
    }
  }
  let advance_map : Array[(Int32, Int32)] = []
  if leading_simple_transition_range_count >= 8 {
    for entry in state.advance_actions[0:leading_simple_transition_count] {
      let (chars, action) = entry
      for range in chars.ranges() {
        let (start, end) = range
        advance_map.push((start, action.state))
        if end > start {
          advance_map.push((end, action.state))
        }
      }
      ruled_out_chars = ruled_out_chars.add(chars)
    }
  } else {
    leading_simple_transition_count = 0
  }
  let transitions : Array[@language.LexTransition] = []
  for entry in state.advance_actions[leading_simple_transition_count:] {
    let (chars, action) = entry

    // The lex state's advance actions are represented with disjoint
    // sets of characters. When translating these disjoint sets into a
    // sequence of checks, we don't need to re-check conditions that
    // have already been checked due to previous transitions.
    //
    // Note that this simplification may result in an empty character set.
    // That means that the transition is guaranteed (nothing further needs to
    // be checked), not that this transition is impossible.
    let simplified_chars = chars.simplify_ignoring(ruled_out_chars)

    // For large character sets, find the best matching character set from
    // a pre-selected list of large character sets, which are based on the
    // state transitions for individual tokens. This transition may not exactly
    // match one of the pre-selected character sets. In that case, determine
    // the additional checks that need to be performed to match this transition.
    let mut best_large_char_set : (Int32, CharacterSet, CharacterSet)? = None
    if simplified_chars.range_count() >= render_large_character_range_count {
      // Prefer the last candidate on ties. Searching backwards lets
      // us stop as soon as a match needs no additional checks.
      for ix = self.large_character_sets.length() - 1; ix >= 0; ix = ix - 1 {
        let set = self.large_character_sets[ix].1
        chars_copy.assign(simplified_chars)
        large_set.assign(set)
        let intersection = chars_copy.remove_intersection(large_set)
        if !intersection.is_empty() {
          let additions = chars_copy.simplify_ignoring(ruled_out_chars)
          let removals = large_set.simplify_ignoring(ruled_out_chars)
          let total_range_count = additions.range_count() +
            removals.range_count()
          if total_range_count >= simplified_chars.range_count() {
            continue
          }
          if best_large_char_set is Some((_, best_additions, best_removals)) {
            let best_range_count = best_additions.range_count() +
              best_removals.range_count()
            // Only a set that needs fewer checks replaces the best one, so on
            // a tie the set found first wins.
            if best_range_count <= total_range_count {
              continue
            }
          }
          best_large_char_set = Some((ix, additions, removals))
          if total_range_count == 0 {
            break
          }
        }
      }
    }

    // Add this transition's character set to the set of ruled out characters,
    // which don't need to be checked for subsequent transitions in this state.
    ruled_out_chars = ruled_out_chars.add(chars)
    let mut large_char_set_ix = None
    let mut asserted_chars = simplified_chars
    let mut negated_chars = CharacterSet::empty()
    if best_large_char_set is Some((char_set_ix, additions, removals)) {
      asserted_chars = additions
      negated_chars = removals
      large_char_set_ix = Some(char_set_ix)
    }
    let large_set_condition = match large_char_set_ix {
      // If the character set contains the null character, check that we
      // are not at the end of the file.
      Some(ix) => Some((ix, self.large_character_sets[ix].1.contains(0)))
      None => None
    }
    let asserted : @language.RangeCondition? = if !asserted_chars.is_empty() {
      // If the character set contains the max character, then it probably
      // corresponds to a negated character class in a regex, so it will be more
      // concise and readable to express it in terms of negated ranges.
      let is_included = !asserted_chars.contains(0x10FFFF)
      if !is_included {
        asserted_chars = asserted_chars.negate().add_char(0)
      }
      Some({ ranges: Generator::character_ranges(asserted_chars), is_included, })
    } else {
      None
    }
    let negated : @language.RangeCondition? = if !negated_chars.is_empty() {
      Some({
        ranges: Generator::character_ranges(negated_chars),
        is_included: false,
      })
    } else {
      None
    }
    transitions.push({
      condition: { large_set: large_set_condition, asserted, negated, },
      state: action.state,
      skip: !action.in_main_token,
    })
  }
  { accept_token, eof_advance, advance_map, transitions, }
}
