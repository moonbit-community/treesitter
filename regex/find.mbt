// Leftmost-first searching (`find`, `find_iter`), as done by the `regex`
// crate's `Regex::find_at`/`find_iter` (regex 1.13, regex-automata 0.4).
//
// `is_match` only needs to know whether some thread reaches the match state,
// so its NFA (compile.mbt) ignores the priority of alternatives and
// repetitions. Finding the leftmost-first match needs that priority, so this
// file compiles a second NFA the way regex-automata's Thompson compiler
// (`nfa/thompson/compiler.rs`) does, in particular:
//
// - every consuming state consumes exactly one byte (Unicode classes are
//   expanded into their UTF-8 byte sequences), so that a classic Pike VM
//   can keep its thread lists in priority order;
// - unions list their alternatives in priority order, and repetitions use
//   the same shapes as `c_repetition` (`x+` loops back into a single copy,
//   `x*` of an `x` that can match the empty string is `(x+)?`, ...), which
//   matters for the preference order of empty-matching sub-expressions.
//
// The Pike VM tracks only the start offset of each thread.

///|
priv enum FState {
  /// Matches one byte in `[lo, hi]`, then continues at the target.
  FByte(Int32, Int32, Int32)
  /// Epsilon transitions, in priority order.
  FSplit(Array[Int32])
  /// An epsilon transition taken only when the assertion holds.
  FLook(@hir.Look, Int32)
  FMatch
  FFail
}

///|
priv struct FindProgram {
  states : Array[FState]
  start : Int32
  /// Whether every match must start at the start of the search.
  anchored : Bool
  /// Whether the NFA can match the empty string (regex-automata's
  /// `NFA::has_empty`), which is when UTF-8 mode must skip empty matches
  /// that split a code point.
  has_empty : Bool
}

///|
priv enum BKind {
  BByte(Int32, Int32)
  BUnion
  BUnionReverse
  BEmpty
  BLook(@hir.Look)
  BMatch
  BFail
}

///|
/// A state under construction; `next` and `alts` are patched later.
priv struct BNode {
  kind : BKind
  mut next : Int32
  alts : Array[Int32]
}

///|
/// regex-automata's `ThompsonRef`: the entry and exit of a compiled
/// sub-expression.
priv struct TRef {
  start : Int32
  end : Int32
}

///|
priv struct FindCompiler {
  nodes : Array[BNode]
}

///|
fn FindCompiler::add(self : FindCompiler, kind : BKind) -> Int32 {
  self.nodes.push({ kind, next: -1, alts: [], })
  self.nodes.length() - 1
}

///|
fn FindCompiler::add_union(self : FindCompiler, greedy : Bool) -> Int32 {
  self.add(if greedy { BUnion } else { BUnionReverse })
}

///|
/// Add a transition from `from` to `to` (a new alternative for unions).
fn FindCompiler::patch(self : FindCompiler, from : Int32, to : Int32) -> Unit {
  let node = self.nodes[from]
  match node.kind {
    BUnion | BUnionReverse => node.alts.push(to)
    BMatch | BFail => ()
    _ => node.next = to
  }
}

///|
fn FindCompiler::c(self : FindCompiler, hir : @hir.Hir) -> TRef {
  match hir.kind() {
    Empty => self.c_empty()
    Literal(Literal(bytes)) => {
      if bytes.length() == 0 {
        return self.c_empty()
      }
      let start = self.add(BByte(bytes[0].to_int(), bytes[0].to_int()))
      let mut end = start
      for i in 1..<bytes.length() {
        let b = bytes[i].to_int()
        let id = self.add(BByte(b, b))
        self.patch(end, id)
        end = id
      }
      { start, end, }
    }
    Class(Unicode(cls)) => {
      let seqs = []
      for r in cls.ranges() {
        for seq in utf8_sequences(r.start(), r.end()) {
          seqs.push(seq)
        }
      }
      self.c_byte_sequences(seqs)
    }
    Class(Bytes(cls)) =>
      self.c_byte_sequences(
        cls.ranges().map(r => [(r.start().to_int(), r.end().to_int())]),
      )
    Look(look) => {
      let id = self.add(BLook(look))
      { start: id, end: id, }
    }
    Capture(capture) => self.c(capture.sub)
    Concat(subs) => {
      if subs.length() == 0 {
        return self.c_empty()
      }
      let first = self.c(subs[0])
      let mut end = first.end
      for i in 1..<subs.length() {
        let compiled = self.c(subs[i])
        self.patch(end, compiled.start)
        end = compiled.end
      }
      { start: first.start, end, }
    }
    Alternation(subs) => {
      if subs.length() == 1 {
        return self.c(subs[0])
      }
      let union = self.add(BUnion)
      let end = self.add(BEmpty)
      for sub in subs {
        let compiled = self.c(sub)
        self.patch(union, compiled.start)
        self.patch(compiled.end, end)
      }
      { start: union, end, }
    }
    Repetition(rep) =>
      match (rep.min, rep.max) {
        (0, Some(1)) => self.c_zero_or_one(rep.sub, rep.greedy)
        (min, None) => self.c_at_least(rep.sub, rep.greedy, min)
        (min, Some(max)) if min == max => self.c_exactly(rep.sub, min)
        (min, Some(max)) => self.c_bounded(rep.sub, rep.greedy, min, max)
      }
  }
}

///|
fn FindCompiler::c_empty(self : FindCompiler) -> TRef {
  let id = self.add(BEmpty)
  { start: id, end: id, }
}

///|
/// A union of disjoint byte sequences (a class); identical suffixes share
/// their states.
fn FindCompiler::c_byte_sequences(
  self : FindCompiler,
  seqs : Array[Array[(Int32, Int32)]],
) -> TRef {
  if seqs.length() == 0 {
    let id = self.add(BFail)
    return { start: id, end: id, }
  }
  let end = self.add(BEmpty)
  let cache : Map[(Int32, Int32, Int32), Int32] = Map([])
  let starts = []
  for seq in seqs {
    let mut cur = end
    for i = seq.length() - 1; i >= 0; i = i - 1 {
      let (lo, hi) = seq[i]
      cur = match cache.get((lo, hi, cur)) {
        Some(id) => id
        None => {
          let id = self.add(BByte(lo, hi))
          self.patch(id, cur)
          cache[(lo, hi, cur)] = id
          id
        }
      }
    }
    starts.push(cur)
  }
  if starts.length() == 1 {
    return { start: starts[0], end, }
  }
  let union = self.add(BUnion)
  for s in starts {
    self.patch(union, s)
  }
  { start: union, end, }
}

///|
fn FindCompiler::c_exactly(
  self : FindCompiler,
  expr : @hir.Hir,
  n : UInt32,
) -> TRef {
  if n == 0 {
    return self.c_empty()
  }
  let first = self.c(expr)
  let mut end = first.end
  for _ in 1U..<n {
    let compiled = self.c(expr)
    self.patch(end, compiled.start)
    end = compiled.end
  }
  { start: first.start, end, }
}

///|
fn FindCompiler::c_bounded(
  self : FindCompiler,
  expr : @hir.Hir,
  greedy : Bool,
  min : UInt32,
  max : UInt32,
) -> TRef {
  let prefix = self.c_exactly(expr, min)
  if min == max {
    return prefix
  }
  let empty = self.add(BEmpty)
  let mut prev_end = prefix.end
  for _ in min..<max {
    let union = self.add_union(greedy)
    let compiled = self.c(expr)
    self.patch(prev_end, union)
    self.patch(union, compiled.start)
    self.patch(union, empty)
    prev_end = compiled.end
  }
  self.patch(prev_end, empty)
  { start: prefix.start, end: empty, }
}

///|
fn FindCompiler::c_at_least(
  self : FindCompiler,
  expr : @hir.Hir,
  greedy : Bool,
  n : UInt32,
) -> TRef {
  if n == 0 {
    if expr.properties().minimum_len() is Some(len) && len > 0 {
      let union = self.add_union(greedy)
      let compiled = self.c(expr)
      self.patch(union, compiled.start)
      self.patch(compiled.end, union)
      return { start: union, end: union, }
    }
    let compiled = self.c(expr)
    let plus = self.add_union(greedy)
    self.patch(compiled.end, plus)
    self.patch(plus, compiled.start)
    let question = self.add_union(greedy)
    let empty = self.add(BEmpty)
    self.patch(question, compiled.start)
    self.patch(question, empty)
    self.patch(plus, empty)
    { start: question, end: empty, }
  } else if n == 1 {
    let compiled = self.c(expr)
    let union = self.add_union(greedy)
    self.patch(compiled.end, union)
    self.patch(union, compiled.start)
    { start: compiled.start, end: union, }
  } else {
    let prefix = self.c_exactly(expr, n - 1)
    let last = self.c(expr)
    let union = self.add_union(greedy)
    self.patch(prefix.end, last.start)
    self.patch(last.end, union)
    self.patch(union, last.start)
    { start: prefix.start, end: union, }
  }
}

///|
fn FindCompiler::c_zero_or_one(
  self : FindCompiler,
  expr : @hir.Hir,
  greedy : Bool,
) -> TRef {
  let union = self.add_union(greedy)
  let compiled = self.c(expr)
  let empty = self.add(BEmpty)
  self.patch(union, compiled.start)
  self.patch(union, empty)
  self.patch(compiled.end, empty)
  { start: union, end: empty, }
}

///|
fn compile_find(hir : @hir.Hir) -> FindProgram {
  let compiler : FindCompiler = { nodes: [], }
  let compiled = compiler.c(hir)
  let matched = compiler.add(BMatch)
  compiler.patch(compiled.end, matched)
  let states = compiler.nodes.map(node => {
    match node.kind {
      BByte(lo, hi) => FByte(lo, hi, node.next)
      BUnion => FSplit(node.alts)
      BUnionReverse => FSplit(node.alts.rev())
      BEmpty => FSplit([node.next])
      BLook(look) => FLook(look, node.next)
      BMatch => FMatch
      BFail => FFail
    }
  })
  let anchored = hir.properties().look_set_prefix().contains(Start)
  let has_empty = match hir.properties().minimum_len() {
    Some(0) => true
    _ => false
  }
  { states, start: compiled.start, anchored, has_empty, }
}

///|
/// A Pike VM thread list: states in priority order, each with the start
/// offset of the thread that reached it.
priv struct Threads {
  states : Array[Int32]
  starts : Array[Int32]
  /// `stamps[state] == generation` iff the state is in this list.
  stamps : FixedArray[Int32]
  mut generation : Int32
}

///|
fn Threads::new(n : Int32) -> Threads {
  { states: [], starts: [], stamps: FixedArray::make(n, -1), generation: 0, }
}

///|
fn Threads::clear(self : Threads) -> Unit {
  self.states.clear()
  self.starts.clear()
  self.generation += 1
}

///|
/// Add `state` and its epsilon closure at `pos` (in priority order) for a
/// thread that started at `start`.
fn FindProgram::add_thread(
  self : FindProgram,
  list : Threads,
  stack : Array[Int32],
  hay : BytesView,
  pos : Int32,
  state : Int32,
  start : Int32,
) -> Unit {
  stack.push(state)
  while stack.pop() is Some(s) {
    if list.stamps[s] == list.generation {
      continue
    }
    list.stamps[s] = list.generation
    match self.states[s] {
      FSplit(targets) =>
        for i = targets.length() - 1; i >= 0; i = i - 1 {
          stack.push(targets[i])
        }
      FLook(look, next) => if look_matches(look, hay, pos) { stack.push(next) }
      FFail => ()
      FByte(_) | FMatch => {
        list.states.push(s)
        list.starts.push(start)
      }
    }
  }
}

///|
/// The leftmost-first match in `hay[from:]` (looking at all of `hay` for
/// assertions), as `(start, end)`.
fn FindProgram::search(
  self : FindProgram,
  hay : BytesView,
  from : Int32,
) -> (Int32, Int32)? {
  let n = self.states.length()
  let mut clist = Threads::new(n)
  let mut nlist = Threads::new(n)
  let stack = []
  let len = hay.length()
  let mut matched : (Int32, Int32)? = None
  for pos = from; pos <= len; pos = pos + 1 {
    if matched is None && (!self.anchored || pos == from) {
      self.add_thread(clist, stack, hay, pos, self.start, pos)
    }
    if clist.states.length() == 0 {
      if matched is Some(_) || self.anchored {
        break
      }
      clist.clear()
      continue
    }
    nlist.clear()
    for i in 0..<clist.states.length() {
      let start = clist.starts[i]
      match self.states[clist.states[i]] {
        FMatch => {
          matched = Some((start, pos))
          // Lower-priority threads cannot produce a preferred match.
          break
        }
        FByte(lo, hi, next) =>
          if pos < len {
            let b = hay[pos].to_int()
            if b >= lo && b <= hi {
              self.add_thread(nlist, stack, hay, pos + 1, next, start)
            }
          }
        _ => ()
      }
    }
    let tmp = clist
    clist = nlist
    nlist = tmp
  }
  matched
}

///|
fn is_char_boundary(hay : BytesView, at : Int32) -> Bool {
  at >= hay.length() || (hay[at].to_int() & 0xC0) != 0x80
}

///|
fn Regex::find_program(self : Regex) -> FindProgram {
  match self.find_program {
    Some(program) => program
    None => {
      let program = compile_find(self.hir)
      self.find_program = Some(program)
      program
    }
  }
}

///|
/// The search of `find_at`, including UTF-8 mode's skipping of empty matches
/// that split a code point (regex-automata's `skip_splits_fwd`).
fn Regex::search_at(
  self : Regex,
  hay : BytesView,
  start : Int32,
) -> (Int32, Int32)? {
  let program = self.find_program()
  if start > hay.length() {
    return None
  }
  let mut from = start
  let mut m = program.search(hay, from)
  if self.utf8 && program.has_empty {
    while m is Some((_, end)) && !is_char_boundary(hay, end) {
      from += 1
      if from > hay.length() {
        return None
      }
      m = program.search(hay, from)
    }
  }
  m
}

///|
/// The leftmost-first match of the regex in `haystack` that starts at or
/// after `start`, as a `(start, end)` byte range. Assertions such as `^` and
/// `\b` see the whole haystack (like `Regex::find_at`).
pub fn Regex::find_at(
  self : Regex,
  haystack : BytesView,
  start : Int32,
) -> (Int32, Int32)? {
  self.search_at(haystack, start)
}

///|
/// The leftmost-first match of the regex in `haystack`, as a `(start, end)`
/// byte range.
pub fn Regex::find(self : Regex, haystack : BytesView) -> (Int32, Int32)? {
  self.search_at(haystack, 0)
}

///|
/// All successive non-overlapping leftmost-first matches in `haystack`, as
/// `(start, end)` byte ranges (`Regex::find_iter`). An empty match that ends
/// where the previous match ended is skipped by searching again one byte
/// further.
pub fn Regex::find_iter(
  self : Regex,
  haystack : BytesView,
) -> Array[(Int32, Int32)] {
  let result = []
  let mut start = 0
  let mut last_match_end : Int32? = None
  while self.search_at(haystack, start) is Some(m) {
    let mut m = m
    if m.0 == m.1 && last_match_end is Some(end) && end == m.1 {
      match self.search_at(haystack, start + 1) {
        Some(next) => m = next
        None => break
      }
    }
    result.push(m)
    start = m.1
    last_match_end = Some(m.1)
  }
  result
}
