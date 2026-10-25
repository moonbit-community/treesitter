// The NFA size limit of `regex` 1.13.1: `regex::bytes::Regex::new` fails
// with `CompiledTooBig` when the Thompson NFA builder of regex-automata 0.4.18
// exceeds `nfa_size_limit` (10 MiB) while compiling the forward NFA or the
// reverse NFA that the meta engine's lazy DFA needs.
//
// The builder's accounting (nfa/thompson/builder.rs `memory_usage`) is
// `states * size_of::<State>() + memory_states`, where `memory_states` sums
// 8 bytes per sparse transition and 4 bytes per union alternate. It only
// grows, and is checked after each state is added and each union is patched,
// so the compilation fails exactly when its final value exceeds the limit.
// This file reproduces nfa/thompson/compiler.rs (with `literal_trie.rs` and
// the `Utf8BoundedMap`/`Utf8SuffixMap` caches of `map.rs`, whose hash
// collisions decide which states are shared) on a builder that only keeps
// what the accounting needs, and stops as soon as the limit is exceeded.
//
// Before compiling, the meta strategy may answer the regex with a literal
// prefilter alone, without building an NFA. Its large-alternation case (an
// alternation of at least 3000 literals) is reproduced. Its other case, an
// exact prefix literal set (at most 250 literals of at most 100 bytes), is
// not: such a regex compiles to a small NFA.

///|
let nfa_size_limit : Int32 = 10 * (1 << 20)

///|
/// `size_of::<State>()` of the builder on 64-bit targets.
let state_bytes : Int64 = 32

///|
priv suberror SizeLimitExceeded

///|
/// `ThompsonRef`.
priv struct ThompsonRef {
  start : Int32
  end : Int32
}

///|
/// An entry of the `Utf8BoundedMap`: a sorted sequence of transitions
/// (`(start, end, next)`) and the sparse state compiled for it.
priv struct Utf8BoundedEntry {
  mut version : Int32
  mut key : Array[(Int32, Int32, Int32)]
  mut val : Int32
}

///|
/// An entry of the `Utf8SuffixMap`.
priv struct Utf8SuffixEntry {
  mut version : Int32
  mut key : (Int32, Int32, Int32)
  mut val : Int32
}

///|
/// `Utf8Node`.
priv struct Utf8Node {
  trans : Array[(Int32, Int32, Int32)]
  mut last : (Int32, Int32)?
}

///|
/// The parts of `thompson::Compiler` and its `Builder` the size accounting
/// needs.
priv struct SizeCompiler {
  reverse : Bool
  /// `WhichCaptures::All` (forward) or `WhichCaptures::None` (reverse).
  captures : Bool
  limit : Int64
  /// Per state: whether it is a `Union` or `UnionReverse` state.
  unions : Array[Bool]
  mut memory_states : Int64
  // `Utf8State` (capacity 10_000).
  mut utf8_map : Array[Utf8BoundedEntry]
  mut utf8_version : Int32
  utf8_uncompiled : Array[Utf8Node]
  // `Utf8SuffixMap` (capacity 1000).
  mut suffix_map : Array[Utf8SuffixEntry]
  mut suffix_version : Int32
}

///|
fn SizeCompiler::new(reverse : Bool, limit : Int64) -> SizeCompiler {
  {
    reverse,
    captures: !reverse,
    limit,
    unions: [],
    memory_states: 0,
    utf8_map: [],
    utf8_version: 0,
    utf8_uncompiled: [],
    suffix_map: [],
    suffix_version: 0,
  }
}

///|
fn SizeCompiler::check_size_limit(
  self : SizeCompiler,
) -> Unit raise SizeLimitExceeded {
  if self.unions.length().to_int64() * state_bytes + self.memory_states >
    self.limit {
    raise SizeLimitExceeded
  }
}

///|
/// `Builder::add`: a state whose own heap memory is `memory`.
fn SizeCompiler::add(
  self : SizeCompiler,
  is_union : Bool,
  memory : Int64,
) -> Int32 raise SizeLimitExceeded {
  let id = self.unions.length()
  self.memory_states += memory
  self.unions.push(is_union)
  self.check_size_limit()
  id
}

///|
fn SizeCompiler::add_empty(
  self : SizeCompiler,
) -> Int32 raise SizeLimitExceeded {
  self.add(false, 0)
}

///|
fn SizeCompiler::add_union(
  self : SizeCompiler,
) -> Int32 raise SizeLimitExceeded {
  self.add(true, 0)
}

///|
fn SizeCompiler::add_sparse(
  self : SizeCompiler,
  transitions : Int32,
) -> Int32 raise SizeLimitExceeded {
  self.add(false, transitions.to_int64() * 8)
}

///|
/// `Builder::patch`: adding an alternate to a union costs 4 bytes.
fn SizeCompiler::patch(
  self : SizeCompiler,
  from : Int32,
) -> Unit raise SizeLimitExceeded {
  if self.unions[from] {
    self.memory_states += 4
    self.check_size_limit()
  }
}

///|
/// `Compiler::compile` of a single pattern.
fn SizeCompiler::compile(
  self : SizeCompiler,
  expr : @hir.Hir,
) -> Unit raise SizeLimitExceeded {
  self.check_size_limit()
  let props = expr.properties()
  let all_anchored = if self.reverse {
    props.look_set_suffix().contains(End)
  } else {
    props.look_set_prefix().contains(Start)
  }
  let unanchored_prefix = if all_anchored {
    self.c_empty()
  } else {
    self.c_at_least(@hir.Hir::dot(AnyByte), false, 0)
  }
  let one = self.c_cap(expr)
  let match_state_id = self.add(false, 0)
  self.patch(one.end)
  ignore(match_state_id)
  self.patch(unanchored_prefix.end)
}

///|
fn SizeCompiler::c(
  self : SizeCompiler,
  expr : @hir.Hir,
) -> ThompsonRef raise SizeLimitExceeded {
  match expr.kind() {
    Empty => self.c_empty()
    Literal(Literal(bytes)) => self.c_literal(bytes)
    Class(Bytes(c)) => self.c_sparse_class(c.ranges().length())
    Class(Unicode(c)) => self.c_unicode_class(c)
    Look(_) => {
      let id = self.add(false, 0)
      { start: id, end: id, }
    }
    Repetition(rep) => self.c_repetition(rep)
    Capture(c) => self.c_cap(c.sub)
    Concat(es) => self.c_concat(es.length(), i => self.c(es[i]))
    Alternation(es) => self.c_alt_slice(es)
  }
}

///|
/// `c_concat`: `n` expressions compiled by `f`, in order (from the last one
/// when compiling in reverse).
fn SizeCompiler::c_concat(
  self : SizeCompiler,
  n : Int32,
  f : (Int32) -> ThompsonRef raise SizeLimitExceeded,
) -> ThompsonRef raise SizeLimitExceeded {
  if n == 0 {
    return self.c_empty()
  }
  let index = (k : Int32) => if self.reverse { n - 1 - k } else { k }
  let first = f(index(0))
  let mut end = first.end
  for k in 1..<n {
    let compiled = f(index(k))
    self.patch(end)
    end = compiled.end
  }
  { start: first.start, end, }
}

///|
fn SizeCompiler::c_alt_slice(
  self : SizeCompiler,
  exprs : ArrayView[@hir.Hir],
) -> ThompsonRef raise SizeLimitExceeded {
  let mut literal_count = 0
  for e in exprs {
    if e.kind() is Literal(_) {
      literal_count += 1
    }
  }
  if literal_count <= 1 || literal_count < exprs.length() {
    return self.c_alt_iter(exprs.length(), i => self.c(exprs[i]))
  }
  let trie = LiteralTrie::new(self.reverse)
  for e in exprs {
    guard e.kind() is Literal(Literal(bytes)) else {
      abort("expected a literal")
    }
    trie.add(bytes)
  }
  trie.compile(self)
}

///|
fn SizeCompiler::c_alt_iter(
  self : SizeCompiler,
  n : Int32,
  f : (Int32) -> ThompsonRef raise SizeLimitExceeded,
) -> ThompsonRef raise SizeLimitExceeded {
  if n == 0 {
    return self.c_fail()
  }
  let first = f(0)
  if n == 1 {
    return first
  }
  let second = f(1)
  let union = self.add_union()
  let end = self.add_empty()
  self.patch(union)
  self.patch(first.end)
  self.patch(union)
  self.patch(second.end)
  for i in 2..<n {
    let compiled = f(i)
    self.patch(union)
    self.patch(compiled.end)
  }
  ignore(end)
  { start: union, end, }
}

///|
/// `c_cap`: capture states for every group in the forward NFA, none in the
/// reverse one.
fn SizeCompiler::c_cap(
  self : SizeCompiler,
  expr : @hir.Hir,
) -> ThompsonRef raise SizeLimitExceeded {
  if !self.captures {
    return self.c(expr)
  }
  let start = self.add(false, 0)
  let inner = self.c(expr)
  let end = self.add(false, 0)
  self.patch(start)
  self.patch(inner.end)
  { start, end, }
}

///|
fn SizeCompiler::c_repetition(
  self : SizeCompiler,
  rep : @hir.Repetition,
) -> ThompsonRef raise SizeLimitExceeded {
  match (rep.min, rep.max) {
    (0, Some(1)) => self.c_zero_or_one(rep.sub, rep.greedy)
    (min, None) => self.c_at_least(rep.sub, rep.greedy, min)
    (min, Some(max)) if min == max => self.c_exactly(rep.sub, min)
    (min, Some(max)) => self.c_bounded(rep.sub, rep.greedy, min, max)
  }
}

///|
fn SizeCompiler::c_bounded(
  self : SizeCompiler,
  expr : @hir.Hir,
  greedy : Bool,
  min : UInt32,
  max : UInt32,
) -> ThompsonRef raise SizeLimitExceeded {
  let prefix = self.c_exactly(expr, min)
  if min == max {
    return prefix
  }
  let empty = self.add_empty()
  let mut prev_end = prefix.end
  for _ in min..<max {
    let union = self.add_union()
    let compiled = self.c(expr)
    self.patch(prev_end)
    self.patch(union)
    self.patch(union)
    prev_end = compiled.end
  }
  self.patch(prev_end)
  ignore(greedy)
  { start: prefix.start, end: empty, }
}

///|
fn SizeCompiler::c_at_least(
  self : SizeCompiler,
  expr : @hir.Hir,
  greedy : Bool,
  n : UInt32,
) -> ThompsonRef raise SizeLimitExceeded {
  ignore(greedy)
  if n == 0 {
    // When the expression cannot match the empty string, then we can do
    // better with a single union.
    if expr.properties().minimum_len() is Some(len) && len > 0 {
      let union = self.add_union()
      let compiled = self.c(expr)
      self.patch(union)
      self.patch(compiled.end)
      return { start: union, end: union, }
    }
    let compiled = self.c(expr)
    let plus = self.add_union()
    self.patch(compiled.end)
    self.patch(plus)
    let question = self.add_union()
    let empty = self.add_empty()
    self.patch(question)
    self.patch(question)
    self.patch(plus)
    { start: question, end: empty, }
  } else if n == 1 {
    let compiled = self.c(expr)
    let union = self.add_union()
    self.patch(compiled.end)
    self.patch(union)
    { start: compiled.start, end: union, }
  } else {
    let prefix = self.c_exactly(expr, n - 1)
    let last = self.c(expr)
    let union = self.add_union()
    self.patch(prefix.end)
    self.patch(last.end)
    self.patch(union)
    { start: prefix.start, end: union, }
  }
}

///|
fn SizeCompiler::c_zero_or_one(
  self : SizeCompiler,
  expr : @hir.Hir,
  greedy : Bool,
) -> ThompsonRef raise SizeLimitExceeded {
  ignore(greedy)
  let union = self.add_union()
  let compiled = self.c(expr)
  let empty = self.add_empty()
  self.patch(union)
  self.patch(union)
  self.patch(compiled.end)
  { start: union, end: empty, }
}

///|
fn SizeCompiler::c_exactly(
  self : SizeCompiler,
  expr : @hir.Hir,
  n : UInt32,
) -> ThompsonRef raise SizeLimitExceeded {
  // A count beyond `Int` exceeds the limit long before it is reached.
  let n = if n > 0x7FFFFFFFU { 0x7FFFFFFF } else { n.reinterpret_as_int() }
  self.c_concat(n, _ => self.c(expr))
}

///|
/// `c_byte_class`, and `c_unicode_class` for an ASCII class: an empty state
/// and a sparse state with one transition per range.
fn SizeCompiler::c_sparse_class(
  self : SizeCompiler,
  ranges : Int32,
) -> ThompsonRef raise SizeLimitExceeded {
  let end = self.add_empty()
  let start = self.add_sparse(ranges)
  { start, end, }
}

///|
fn SizeCompiler::c_unicode_class(
  self : SizeCompiler,
  cls : @hir.ClassUnicode,
) -> ThompsonRef raise SizeLimitExceeded {
  if cls.is_ascii() {
    self.c_sparse_class(cls.ranges().length())
  } else if self.reverse {
    // `shrink` is disabled by the meta engine.
    self.c_unicode_class_reverse_with_suffix(cls)
  } else {
    let utf8c = Utf8Compiler::new(self)
    for rng in cls.ranges() {
      for seq in utf8_sequences(rng.start(), rng.end()) {
        utf8c.add(seq)
      }
    }
    utf8c.finish()
  }
}

///|
fn SizeCompiler::c_unicode_class_reverse_with_suffix(
  self : SizeCompiler,
  cls : @hir.ClassUnicode,
) -> ThompsonRef raise SizeLimitExceeded {
  self.suffix_clear()
  let union = self.add_union()
  let alt_end = self.add_empty()
  for urng in cls.ranges() {
    for seq in utf8_sequences(urng.start(), urng.end()) {
      let mut end = alt_end
      for brng in seq {
        let key = (end, brng.0, brng.1)
        let hash = suffix_hash(key, self.suffix_map.length())
        if self.suffix_get(key, hash) is Some(id) {
          end = id
          continue
        }
        let compiled = self.c_range()
        self.patch(compiled.end)
        end = compiled.start
        self.suffix_set(key, hash, end)
      }
      self.patch(union)
    }
  }
  { start: union, end: alt_end, }
}

///|
fn SizeCompiler::c_literal(
  self : SizeCompiler,
  bytes : Bytes,
) -> ThompsonRef raise SizeLimitExceeded {
  self.c_concat(bytes.length(), _ => self.c_range())
}

///|
fn SizeCompiler::c_range(
  self : SizeCompiler,
) -> ThompsonRef raise SizeLimitExceeded {
  let id = self.add(false, 0)
  { start: id, end: id, }
}

///|
fn SizeCompiler::c_empty(
  self : SizeCompiler,
) -> ThompsonRef raise SizeLimitExceeded {
  let id = self.add_empty()
  { start: id, end: id, }
}

///|
fn SizeCompiler::c_fail(
  self : SizeCompiler,
) -> ThompsonRef raise SizeLimitExceeded {
  let id = self.add(false, 0)
  { start: id, end: id, }
}

// map.rs ------------------------------------------------------------------------

///|
const FNV_PRIME : UInt64 = 1099511628211

///|
const FNV_INIT : UInt64 = 14695981039346656037

///|
/// `Utf8BoundedMap::clear`.
fn SizeCompiler::utf8_clear(self : SizeCompiler) -> Unit {
  if self.utf8_map.is_empty() {
    self.utf8_map = Array::makei(10_000, _ => { version: 0, key: [], val: 0, })
  } else {
    self.utf8_version = (self.utf8_version + 1) & 0xFFFF
    if self.utf8_version == 0 {
      self.utf8_map = Array::makei(10_000, _ => { version: 0, key: [], val: 0, })
    }
  }
}

///|
/// `Utf8BoundedMap::hash`.
fn utf8_hash(key : Array[(Int32, Int32, Int32)], len : Int32) -> Int32 {
  let mut h = FNV_INIT
  for t in key {
    h = (h ^ t.0.to_uint64()) * FNV_PRIME
    h = (h ^ t.1.to_uint64()) * FNV_PRIME
    h = (h ^ t.2.to_uint64()) * FNV_PRIME
  }
  (h % len.to_uint64()).to_int()
}

///|
/// `Utf8SuffixMap::clear`.
fn SizeCompiler::suffix_clear(self : SizeCompiler) -> Unit {
  if self.suffix_map.is_empty() {
    self.suffix_map = Array::makei(1000, _ => {
      version: 0,
      key: (0, 0, 0),
      val: 0,
    })
  } else {
    self.suffix_version = (self.suffix_version + 1) & 0xFFFF
    if self.suffix_version == 0 {
      self.suffix_map = Array::makei(1000, _ => {
        version: 0,
        key: (0, 0, 0),
        val: 0,
      })
    }
  }
}

///|
/// `Utf8SuffixMap::hash` of the key `(from, start, end)`.
fn suffix_hash(key : (Int32, Int32, Int32), len : Int32) -> Int32 {
  let mut h = FNV_INIT
  h = (h ^ key.0.to_uint64()) * FNV_PRIME
  h = (h ^ key.1.to_uint64()) * FNV_PRIME
  h = (h ^ key.2.to_uint64()) * FNV_PRIME
  (h % len.to_uint64()).to_int()
}

///|
fn SizeCompiler::suffix_get(
  self : SizeCompiler,
  key : (Int32, Int32, Int32),
  hash : Int32,
) -> Int32? {
  let entry = self.suffix_map[hash]
  if entry.version != self.suffix_version || entry.key != key {
    None
  } else {
    Some(entry.val)
  }
}

///|
fn SizeCompiler::suffix_set(
  self : SizeCompiler,
  key : (Int32, Int32, Int32),
  hash : Int32,
  id : Int32,
) -> Unit {
  let entry = self.suffix_map[hash]
  entry.version = self.suffix_version
  entry.key = key
  entry.val = id
}

// Utf8Compiler (compiler.rs) -------------------------------------------------------

///|
priv struct Utf8Compiler {
  c : SizeCompiler
  target : Int32
}

///|
fn Utf8Compiler::new(c : SizeCompiler) -> Utf8Compiler raise SizeLimitExceeded {
  let target = c.add_empty()
  c.utf8_clear()
  c.utf8_uncompiled.clear()
  c.utf8_uncompiled.push({ trans: [], last: None, })
  { c, target, }
}

///|
fn Utf8Compiler::finish(
  self : Utf8Compiler,
) -> ThompsonRef raise SizeLimitExceeded {
  self.compile_from(0)
  let node = self.pop_root()
  let start = self.compile(node)
  { start, end: self.target, }
}

///|
fn Utf8Compiler::add(
  self : Utf8Compiler,
  ranges : Array[(Int32, Int32)],
) -> Unit raise SizeLimitExceeded {
  let uncompiled = self.c.utf8_uncompiled
  let mut prefix_len = 0
  while prefix_len < ranges.length() &&
        prefix_len < uncompiled.length() &&
        uncompiled[prefix_len].last is Some(t) &&
        t == ranges[prefix_len] {
    prefix_len += 1
  }
  self.compile_from(prefix_len)
  self.add_suffix(ranges[prefix_len:])
}

///|
fn Utf8Compiler::compile_from(
  self : Utf8Compiler,
  from : Int32,
) -> Unit raise SizeLimitExceeded {
  let mut next = self.target
  while from + 1 < self.c.utf8_uncompiled.length() {
    let node = self.pop_freeze(next)
    next = self.compile(node)
  }
  self.top_last_freeze(next)
}

///|
fn Utf8Compiler::compile(
  self : Utf8Compiler,
  node : Array[(Int32, Int32, Int32)],
) -> Int32 raise SizeLimitExceeded {
  let c = self.c
  let hash = utf8_hash(node, c.utf8_map.length())
  let entry = c.utf8_map[hash]
  if entry.version == c.utf8_version && entry.key == node {
    return entry.val
  }
  let id = c.add_sparse(node.length())
  entry.version = c.utf8_version
  entry.key = node
  entry.val = id
  id
}

///|
fn Utf8Compiler::add_suffix(
  self : Utf8Compiler,
  ranges : ArrayView[(Int32, Int32)],
) -> Unit {
  let uncompiled = self.c.utf8_uncompiled
  uncompiled[uncompiled.length() - 1].last = Some(ranges[0])
  for r in ranges[1:] {
    uncompiled.push({ trans: [], last: Some(r), })
  }
}

///|
fn Utf8Compiler::pop_freeze(
  self : Utf8Compiler,
  next : Int32,
) -> Array[(Int32, Int32, Int32)] {
  let node = self.c.utf8_uncompiled.pop().unwrap()
  node.set_last_transition(next)
  node.trans
}

///|
fn Utf8Compiler::pop_root(self : Utf8Compiler) -> Array[(Int32, Int32, Int32)] {
  self.c.utf8_uncompiled.pop().unwrap().trans
}

///|
fn Utf8Compiler::top_last_freeze(self : Utf8Compiler, next : Int32) -> Unit {
  let uncompiled = self.c.utf8_uncompiled
  uncompiled[uncompiled.length() - 1].set_last_transition(next)
}

///|
fn Utf8Node::set_last_transition(self : Utf8Node, next : Int32) -> Unit {
  if self.last is Some((start, end)) {
    self.last = None
    self.trans.push((start, end, next))
  }
}

// literal_trie.rs ------------------------------------------------------------------

///|
/// A `LiteralTrie` state: its transitions `(byte, next)` and the chunk
/// boundaries that a match ends.
priv struct TrieState {
  transitions : Array[(Int32, Int32)]
  chunks : Array[(Int32, Int32)]
}

///|
priv struct LiteralTrie {
  states : Array[TrieState]
  rev : Bool
}

///|
fn LiteralTrie::new(rev : Bool) -> LiteralTrie {
  { states: [{ transitions: [], chunks: [], }], rev, }
}

///|
fn TrieState::active_chunk_start(self : TrieState) -> Int32 {
  match self.chunks.last() {
    Some((_, end)) => end
    None => 0
  }
}

///|
fn TrieState::add_match(self : TrieState) -> Unit {
  // This is not strictly necessary, but there's no point in recording
  // another match if the active chunk is empty.
  if self.transitions.is_empty() && !self.chunks.is_empty() {
    return
  }
  let chunk_start = self.active_chunk_start()
  let chunk_end = self.transitions.length()
  self.chunks.push((chunk_start, chunk_end))
}

///|
/// `StateChunksIter`: the closed chunks, then the active one.
fn TrieState::chunk_list(self : TrieState) -> Array[(Int32, Int32)] {
  let chunks = self.chunks.copy()
  chunks.push((self.active_chunk_start(), self.transitions.length()))
  chunks
}

///|
fn LiteralTrie::add(self : LiteralTrie, bytes : Bytes) -> Unit {
  let mut prev = 0
  let n = bytes.length()
  for k in 0..<n {
    let b = bytes[if self.rev { n - 1 - k } else { k }].to_int()
    prev = self.get_or_add_state(prev, b)
  }
  self.states[prev].add_match()
}

///|
fn LiteralTrie::get_or_add_state(
  self : LiteralTrie,
  from : Int32,
  byte : Int32,
) -> Int32 {
  let state = self.states[from]
  let start = state.active_chunk_start()
  // Binary search in the active chunk, which is sorted by byte.
  let mut lo = start
  let mut hi = state.transitions.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let b = state.transitions[mid].0
    if b < byte {
      lo = mid + 1
    } else if b > byte {
      hi = mid
    } else {
      return state.transitions[mid].1
    }
  }
  let next = self.states.length()
  self.states.push({ transitions: [], chunks: [], })
  state.transitions.insert(lo, (byte, next))
  next
}

///|
/// A `Frame` of `LiteralTrie::compile`.
priv struct TrieFrame {
  chunks : Array[(Int32, Int32)]
  mut chunk : Int32
  state : Int32
  mut transition : Int32
  union : Array[Int32]
  sparse : Array[Int32]
}

///|
fn LiteralTrie::frame(self : LiteralTrie, state : Int32) -> TrieFrame {
  let chunks = self.states[state].chunk_list()
  { chunks, chunk: 0, state, transition: chunks[0].0, union: [], sparse: [], }
}

///|
/// `LiteralTrie::compile`: the builder states it adds. `sparse` holds the
/// targets of the pending transitions (`-1` for the trie's own end state).
fn LiteralTrie::compile(
  self : LiteralTrie,
  builder : SizeCompiler,
) -> ThompsonRef raise SizeLimitExceeded {
  let end = builder.add_empty()
  let stack : Array[TrieFrame] = []
  let mut f = self.frame(0)
  for ;; {
    let (_, chunk_end) = f.chunks[f.chunk]
    if f.transition < chunk_end {
      let (_, next) = self.states[f.state].transitions[f.transition]
      f.transition += 1
      if self.states[next].transitions.is_empty() {
        f.sparse.push(end)
      } else {
        f.sparse.push(0)
        stack.push(f)
        f = self.frame(next)
      }
      continue
    }
    if !f.sparse.is_empty() {
      let chunk_id = if f.sparse.length() == 1 {
        builder.add(false, 0)
      } else {
        builder.add_sparse(f.sparse.length())
      }
      f.sparse.clear()
      f.union.push(chunk_id)
    }
    if f.chunk + 1 < f.chunks.length() {
      f.chunk += 1
      f.union.push(end)
      f.transition = f.chunks[f.chunk].0
      continue
    }
    let start = builder.add(true, f.union.length().to_int64() * 4)
    match stack.pop() {
      None => return { start, end, }
      Some(parent) => {
        parent.sparse[parent.sparse.length() - 1] = start
        f = parent
      }
    }
  }
}

// The meta engine ----------------------------------------------------------------

///|
/// Whether the meta engine answers `hir` with an Aho-Corasick prefilter
/// alone (`Pre::from_alternation_literals`), without building an NFA.
fn is_large_literal_alternation(hir : @hir.Hir) -> Bool {
  let props = hir.properties()
  props.look_set().is_empty() &&
  props.explicit_captures_len() == 0 &&
  props.is_alternation_literal() &&
  hir.kind() is Alternation(alts) &&
  alts.length() >= 3000
}

///|
/// Whether `regex` rejects `hir` because its forward or its reverse NFA
/// exceeds the size limit.
fn exceeds_size_limit(hir : @hir.Hir) -> Bool {
  if is_large_literal_alternation(hir) {
    return false
  }
  let limit = nfa_size_limit.to_int64()
  for reverse in [false, true] {
    SizeCompiler::new(reverse, limit).compile(hir) catch {
      SizeLimitExceeded => return true
    }
  }
  false
}

///|
/// regex-syntax's `Utf8Sequences`: the sequences of byte ranges matching
/// exactly the UTF-8 encodings of the scalar values in `[start, end]`.
fn utf8_sequences(start : Int32, end : Int32) -> Array[Array[(Int32, Int32)]] {
  let out = []
  let stack = [(start, end)]
  while stack.pop() is Some((s, e)) {
    let s = s
    let mut e = e
    let mut emitted = false
    while !emitted {
      // Split around the surrogate gap.
      if s < 0xE000 && e > 0xD7FF {
        stack.push((0xE000, e))
        e = 0xD7FF
        continue
      }
      if s > e {
        break
      }
      let mut split = false
      for i in 1..<4 {
        let max = max_scalar_value(i)
        if s <= max && max < e {
          stack.push((max + 1, e))
          e = max
          split = true
          break
        }
      }
      if split {
        continue
      }
      if e <= 0x7F {
        out.push([(s, e)])
        emitted = true
        continue
      }
      for i in 1..<4 {
        let m = (1 << (6 * i)) - 1
        if (s & m.lnot()) != (e & m.lnot()) {
          if (s & m) != 0 {
            stack.push(((s | m) + 1, e))
            e = s | m
            split = true
            break
          }
          if (e & m) != m {
            stack.push((e & m.lnot(), e))
            e = (e & m.lnot()) - 1
            split = true
            break
          }
        }
      }
      if split {
        continue
      }
      let a = encode_utf8(s)
      let b = encode_utf8(e)
      out.push(Array::makei(a.length(), i => (a[i], b[i])))
      emitted = true
    }
  }
  out
}

///|
fn max_scalar_value(nbytes : Int32) -> Int32 {
  match nbytes {
    1 => 0x7F
    2 => 0x7FF
    3 => 0xFFFF
    _ => 0x10FFFF
  }
}

///|
fn encode_utf8(cp : Int32) -> Array[Int32] {
  if cp < 0x80 {
    [cp]
  } else if cp < 0x800 {
    [0xC0 | (cp >> 6), 0x80 | (cp & 0x3F)]
  } else if cp < 0x10000 {
    [0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F)]
  } else {
    [
      0xF0 | (cp >> 18),
      0x80 | ((cp >> 12) & 0x3F),
      0x80 | ((cp >> 6) & 0x3F),
      0x80 | (cp & 0x3F),
    ]
  }
}
