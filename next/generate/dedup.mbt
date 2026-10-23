// Port of tree-sitter crates/generate/src/dedup.rs.

///|
/// Decides which states of a group `split_state_id_groups` separates.
///
/// Besides `should_split`, a criterion can sort a group's states into classes of
/// equivalent states: states that never need to be split from each other, and
/// that need to be split from exactly the same states. Only the first state of
/// each class is then compared, and the rest of the class follows it.
pub(all) struct SplitCriterion[S] {
  /// Whether `left` and `right`, from the same group, must be in different
  /// groups. This must be symmetric.
  should_split : (S, S, Array[Int]) -> Bool
  /// A hash of what `equivalent` compares, if this criterion sorts states
  /// into classes.
  signature : (S, Array[Int]) -> Int?
  /// Whether two states with the same signature are equivalent.
  equivalent : (S, S, Array[Int]) -> Bool
  /// Called before a group's states are compared.
  start_group : () -> Unit
  /// Whether `state` can stay in its group with all of `kept`. `false` is
  /// always correct.
  compatible_with_all : (S, ArrayView[Int], Array[Int]) -> Bool
}

///|
pub fn[S] SplitCriterion::simple(
  should_split : (S, S, Array[Int]) -> Bool,
) -> SplitCriterion[S] {
  {
    should_split,
    signature: (_, _) => None,
    equivalent: (_, _, _) => false,
    start_group: () => (),
    compatible_with_all: (_, _, _) => false,
  }
}

///|
/// Splits every group from `start_group_id` on, including the groups split off
/// from them, so that no group has two states that `criterion` separates.
/// Returns whether any group split.
///
/// A group's states are scanned in order: each state stays unless it must be
/// split from a state that stayed before it, and the states that don't stay
/// form a new group, ordered by the state they were split from, then by
/// position.
pub fn[S] split_state_id_groups(
  states : Array[S],
  state_ids_by_group_id : Array[Array[Int]],
  group_ids_by_state_id : Array[Int],
  start_group_id : Int,
  criterion : SplitCriterion[S],
) -> Bool {
  let mut result = false
  let classes = GroupClasses::new()
  let kept : Array[Int] = []
  let split_from : Array[Int?] = []
  let moved : Array[(Int, Int)] = []
  let mut group_id = start_group_id
  while group_id < state_ids_by_group_id.length() {
    let state_ids = state_ids_by_group_id[group_id]
    // A single state has nothing to be split from.
    if state_ids.length() < 2 {
      group_id += 1
      continue
    }
    classes.classify(states, state_ids, group_ids_by_state_id, criterion)
    // A class follows its first state, so compare only those.
    (criterion.start_group)()
    kept.clear()
    split_from.clear()
    for state_id in classes.first_states {
      let state = states[state_id]
      let splitter = if kept.is_empty() {
        None
      } else {
        let first = kept[0]
        if (criterion.should_split)(states[first], state, group_ids_by_state_id) {
          Some(0)
        } else if kept.length() == 1 ||
          (criterion.compatible_with_all)(state, kept[:], group_ids_by_state_id) {
          None
        } else {
          let mut found = None
          for position in 1..<kept.length() {
            if (criterion.should_split)(
                states[kept[position]],
                state,
                group_ids_by_state_id,
              ) {
              found = Some(position)
              break
            }
          }
          found
        }
      }
      if splitter is None {
        kept.push(state_id)
      }
      split_from.push(splitter)
    }
    moved.clear()
    for i, state_id in state_ids {
      if split_from[classes.class_ids[i]] is Some(splitter) {
        moved.push((splitter, state_id))
      }
    }
    if !moved.is_empty() {
      result = true
      // The sort is stable, so states split from the same state stay in
      // position order.
      stable_sort_by(moved, (a, b) => a.0.compare(b.0))
      let retained = []
      for i, state_id in state_ids {
        if split_from[classes.class_ids[i]] is None {
          retained.push(state_id)
        }
      }
      state_ids_by_group_id[group_id] = retained
      let new_group_id = state_ids_by_group_id.length()
      let new_group = moved.map(m => {
        group_ids_by_state_id[m.1] = new_group_id
        m.1
      })
      state_ids_by_group_id.push(new_group)
    }
    group_id += 1
  }
  result
}

///|
/// The states of a group, sorted into classes of equivalent states.
priv struct GroupClasses {
  /// The class of each of the group's states, by position.
  class_ids : Array[Int]
  /// The first state of each class, in order.
  first_states : Array[Int]
  /// The first class found with each signature.
  class_ids_by_signature : Map[Int, Int]
}

///|
fn GroupClasses::new() -> GroupClasses {
  { class_ids: [], first_states: [], class_ids_by_signature: Map([]) }
}

///|
fn[S] GroupClasses::classify(
  self : GroupClasses,
  states : Array[S],
  state_ids : Array[Int],
  group_ids_by_state_id : Array[Int],
  criterion : SplitCriterion[S],
) -> Unit {
  self.class_ids.clear()
  self.first_states.clear()
  self.class_ids_by_signature.clear()
  // With fewer than three states, classes can't save a comparison. Without a
  // signature, the criterion has no classes.
  let first_signature = if state_ids.length() >= 3 {
    (criterion.signature)(states[state_ids[0]], group_ids_by_state_id)
  } else {
    None
  }
  guard first_signature is Some(first_signature) else {
    for i, state_id in state_ids {
      self.first_states.push(state_id)
      self.class_ids.push(i)
    }
  }
  self.class_ids_by_signature[first_signature] = 0
  self.first_states.push(state_ids[0])
  self.class_ids.push(0)
  for i in 1..<state_ids.length() {
    let state_id = state_ids[i]
    let state = states[state_id]
    let new_class_id = self.first_states.length()
    let signature = (criterion.signature)(state, group_ids_by_state_id)
    let class_id = match signature {
      Some(s) =>
        match self.class_ids_by_signature.get(s) {
          Some(existing) =>
            if (criterion.equivalent)(
                states[self.first_states[existing]],
                state,
                group_ids_by_state_id,
              ) {
              existing
            } else {
              new_class_id
            }
          None => {
            self.class_ids_by_signature[s] = new_class_id
            new_class_id
          }
        }
      None => new_class_id
    }
    if class_id == new_class_id {
      self.first_states.push(state_id)
    }
    self.class_ids.push(class_id)
  }
}
