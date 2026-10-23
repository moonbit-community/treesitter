// An estimate of the NFA size limit check of `regex`.
//
// `regex::bytes::Regex::new` builds its NFAs with a 10 MiB size limit
// (`nfa_size_limit`), and reports patterns that exceed it as invalid. The
// meta engine compiles both a forward NFA and a reverse NFA; the reverse NFA
// compiles each non-ASCII Unicode class as a union of reversed UTF-8
// sequences sharing common suffixes, which makes it the larger of the two.
// The estimate below follows that construction (32 bytes per builder state,
// 4 bytes per union alternate, 8 bytes per sparse transition), assuming a
// perfect suffix cache. It is exact enough to reject the pathological
// patterns `regex` rejects (`\w{500}`, `a{1000}{1000}`) and accept the ones it
// accepts, but it is not a port of regex-automata's compiler.

///|
let nfa_size_limit : Int32 = 10 * (1 << 20)

///|
let state_bytes : Int32 = 32

///|
/// The estimated reverse NFA size of `hir` in bytes, saturating at
/// `Int::max_value / 2`.
fn estimate_size(hir : @hir.Hir) -> Int32 {
  let cap = 0x3FFFFFFF
  fn sat(x : Int64) -> Int32 {
    if x > cap.to_int64() {
      cap
    } else {
      x.to_int()
    }
  }

  match hir.kind() {
    Empty => state_bytes
    Literal(Literal(bytes)) => state_bytes * bytes.length()
    Class(Bytes(cls)) => 2 * state_bytes + 8 * cls.ranges().length()
    Class(Unicode(cls)) =>
      if cls.is_ascii() {
        2 * state_bytes + 8 * cls.ranges().length()
      } else {
        unicode_class_size(cls)
      }
    Look(_) => state_bytes
    Capture(capture) => 2 * state_bytes + estimate_size(capture.sub)
    Concat(subs) => {
      let mut total = 0L
      for sub in subs {
        total += estimate_size(sub).to_int64()
      }
      sat(total)
    }
    Alternation(subs) => {
      let mut total = (2 * state_bytes + 4 * subs.length()).to_int64()
      for sub in subs {
        total += estimate_size(sub).to_int64()
      }
      sat(total)
    }
    Repetition(rep) => {
      // `x{n}` is n concatenated copies; every optional copy (`x{n,m}`) or
      // the loop of `x{n,}` adds a union state with two alternates.
      let sub = estimate_size(rep.sub).to_int64()
      let min = rep.min.to_int64()
      let optional = match rep.max {
        None => 1L
        Some(max) => max.to_int64() - min
      }
      let overhead = (state_bytes + 8).to_int64()
      let extra = if optional > 0L { state_bytes.to_int64() } else { 0L }
      sat(min * sub + optional * (sub + overhead) + extra)
    }
  }
}

///|
/// The reverse compilation of a non-ASCII Unicode class: a union over all
/// UTF-8 sequences, each compiled as a chain of byte ranges ending at a
/// shared end state, sharing identical suffixes.
fn unicode_class_size(cls : @hir.ClassUnicode) -> Int32 {
  let states : Map[(Int32, Int32, Int32), Int32] = Map([])
  let mut alternates = 0
  for r in cls.ranges() {
    for seq in utf8_sequences(r.start(), r.end()) {
      let mut end = -1
      for brng in seq {
        let key = (end, brng.0, brng.1)
        match states.get(key) {
          Some(id) => end = id
          None => {
            let id = states.length()
            states[key] = id
            end = id
          }
        }
      }
      alternates += 1
    }
  }
  (states.length() + 2) * state_bytes + 4 * alternates
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
