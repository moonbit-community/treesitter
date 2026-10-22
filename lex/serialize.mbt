///|
pub impl ToJson for Dfa with fn to_json(self) {
  Json(
    self.states.map(s => {
      (
        s.accepting,
        s.edges.map(e => {
          let values = [e.lo, e.hi, e.target]
          if e.precedence is Some(p) {
            values.push(p)
          }
          values
        }),
      )
    }),
  )
}

///|
#deprecated
pub extend Dfa with ToJson::{to_json}

///|
pub impl @json.FromJson for Dfa with fn from_json(value, path) {
  let encoded : Array[(Bool, Array[Array[Int32]])] = @json.from_json(
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
    for transition in transitions {
      guard transition.length() == 3 || transition.length() == 4 else {
        raise JsonDecodeError((path, "invalid DFA transition length"))
      }
      let lo = transition[0]
      let hi = transition[1]
      let target = transition[2]
      if lo <= previous_end ||
        hi < lo ||
        hi > 0x10ffff ||
        (lo <= 0xdfff && hi >= 0xd800) ||
        target < 0 ||
        target >= encoded.length() {
        raise JsonDecodeError((path, "invalid DFA transition"))
      }
      edges.push({ lo, hi, target, precedence: transition.get(3), })
      previous_end = hi
    }
    states.push({ accepting, edges, })
  }
  {
    weighted: states.any(s => s.edges.any(e => e.precedence is Some(_))),
    states,
  }
}

///|
#deprecated
pub extend Dfa with @json.FromJson::{from_json}
