// Compilation of a regex-syntax `Hir` into a Thompson NFA over bytes.

///|
priv enum State {
  /// Matches any byte in `[lo, hi]`, then continues at the target.
  ByteRange(Int32, Int32, Int32)
  /// Matches one byte contained in the sorted, flattened inclusive ranges.
  ByteClass(FixedArray[Int32], Int32)
  /// Matches one well-formed UTF-8 encoded scalar value contained in the
  /// sorted, flattened inclusive code point ranges.
  CodePointClass(FixedArray[Int32], Int32)
  /// An epsilon transition to each target.
  Split(Array[Int32])
  /// An epsilon transition that is only taken when the assertion holds.
  Look(@hir.Look, Int32)
  Match
  Fail
}

///|
priv struct Program {
  states : Array[State]
  start : Int32
  /// Whether every match must start at offset 0 (`\A` prefix), in which case
  /// the search stops once no thread is alive.
  anchored : Bool
  /// Whether the regex can match the empty string (`NFA::has_empty`).
  has_empty : Bool
}

///|
priv struct Compiler {
  states : Array[State]
}

///|
fn Compiler::add(self : Compiler, state : State) -> Int32 {
  self.states.push(state)
  self.states.length() - 1
}

///|
/// Compile `hir` so that a successful traversal continues at `next`,
/// returning the entry state. Building backwards from the continuation keeps
/// the construction free of patch lists.
fn Compiler::compile(self : Compiler, hir : @hir.Hir, next : Int32) -> Int32 {
  match hir.kind() {
    Empty => next
    Literal(Literal(bytes)) => {
      let mut cur = next
      for i = bytes.length() - 1; i >= 0; i = i - 1 {
        let b = bytes[i].to_int()
        cur = self.add(ByteRange(b, b, cur))
      }
      cur
    }
    Class(Unicode(cls)) => {
      let ranges = cls.ranges()
      if ranges.length() == 0 {
        return self.add(Fail)
      }
      let flat = FixedArray::make(ranges.length() * 2, 0)
      for i, r in ranges {
        flat[2 * i] = r.start()
        flat[2 * i + 1] = r.end()
      }
      self.add(CodePointClass(flat, next))
    }
    Class(Bytes(cls)) => {
      let ranges = cls.ranges()
      if ranges.length() == 0 {
        return self.add(Fail)
      }
      if ranges.length() == 1 {
        return self.add(
          ByteRange(ranges[0].start().to_int(), ranges[0].end().to_int(), next),
        )
      }
      let flat = FixedArray::make(ranges.length() * 2, 0)
      for i, r in ranges {
        flat[2 * i] = r.start().to_int()
        flat[2 * i + 1] = r.end().to_int()
      }
      self.add(ByteClass(flat, next))
    }
    Look(look) => self.add(Look(look, next))
    Capture(capture) => self.compile(capture.sub, next)
    Concat(subs) => {
      let mut cur = next
      for i = subs.length() - 1; i >= 0; i = i - 1 {
        cur = self.compile(subs[i], cur)
      }
      cur
    }
    Alternation(subs) => {
      let targets = []
      for sub in subs {
        targets.push(self.compile(sub, next))
      }
      self.add(Split(targets))
    }
    Repetition(rep) => {
      let mut cur = next
      match rep.max {
        None => {
          // `sub*`: a loop through a split state.
          let targets = []
          let split = self.add(Split(targets))
          let body = self.compile(rep.sub, split)
          targets.push(body)
          targets.push(next)
          cur = split
        }
        Some(max) => {
          let mut i = rep.min
          while i < max {
            let body = self.compile(rep.sub, cur)
            cur = self.add(Split([body, cur]))
            i += 1
          }
        }
      }
      for _ in 0U..<rep.min {
        cur = self.compile(rep.sub, cur)
      }
      cur
    }
  }
}

///|
fn compile(hir : @hir.Hir) -> Program {
  let compiler : Compiler = { states: [], }
  let matched = compiler.add(Match)
  let start = compiler.compile(hir, matched)
  let anchored = hir.properties().look_set_prefix().contains(Start)
  let has_empty = hir.properties().minimum_len() is Some(0)
  { states: compiler.states, start, anchored, has_empty, }
}
