///|
pub impl ToJson for Dfa with fn to_json(self) {
  Json(
    self.states.map(s => (s.accepting, s.edges.map(e => (e.lo, e.hi, e.target)))),
  )
}

///|
#deprecated
pub extend Dfa with ToJson::{to_json}

///|
pub impl @json.FromJson for Dfa with fn from_json(value, path) {
  let encoded : Array[(Bool, Array[(Int32, Int32, Int32)])] = @json.from_json(
    value,
    path~,
  )
  if encoded.is_empty() {
    raise JsonDecodeError((path, "empty DFA"))
  }
  let states = []
  for (accepting, transitions) in encoded {
    let edges : Array[Transition] = []
    let mut previous_end = -1
    for (lo, hi, target) in transitions {
      if lo <= previous_end ||
        hi < lo ||
        hi > 0x10ffff ||
        (lo <= 0xdfff && hi >= 0xd800) ||
        target < 0 ||
        target >= encoded.length() {
        raise JsonDecodeError((path, "invalid DFA transition"))
      }
      edges.push({ lo, hi, target, })
      previous_end = hi
    }
    states.push({ accepting, edges, })
  }
  { states, }
}

///|
#deprecated
pub extend Dfa with @json.FromJson::{from_json}
