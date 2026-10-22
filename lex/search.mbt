///|
pub suberror SearchError {
  SearchLimit
  SearchCancelled
}

///|
priv enum Instruction {
  Consume(CharSet, Int32)
  Split(Array[Int32])
  Check(Assertion, Int32)
  Match
}

///|
/// Ordered Thompson VM for text predicates. Unlike lexical DFAs, assertions
/// retain their position, alternation is left-biased, and quantifiers retain
/// greediness. No backtracking or backreferences are used.
pub struct Regex {
  priv code : Array[Instruction]
  priv start : Int32
  priv word : CharSet
}

///|
pub fn Regex::new(pattern : String) -> Regex raise RegexError {
  let code = [Instruction::Match]
  let start = compile_search(parse(pattern, assertions=true), 0, code)
  { code, start, word: unicode_word(), }
}

///|
fn emit_search(
  code : Array[Instruction],
  instruction : Instruction,
) -> Int32 raise RegexError {
  if code.length() >= 100000 {
    raise InvalidRegex(0, "regex instruction limit exceeded")
  }
  let id = code.length()
  code.push(instruction)
  id
}

///|
fn compile_search(
  expr : Expr,
  next : Int32,
  code : Array[Instruction],
) -> Int32 raise RegexError {
  match expr {
    Empty => next
    Chars(chars) => emit_search(code, Consume(chars, next))
    Assert(assertion) => emit_search(code, Check(assertion, next))
    Precedence(_, child) => compile_search(child, next, code)
    Concat(parts) => {
      let mut next = next
      for i = parts.length() - 1; i >= 0; i = i - 1 {
        next = compile_search(parts[i], next, code)
      }
      next
    }
    Alt(parts) =>
      emit_search(code, Split(parts.map(p => compile_search(p, next, code))))
    Many(child) => compile_search(Repeat(child, 0, None, true), next, code)
    Repeat(child, min, max, greedy) => {
      let mut next = next
      match max {
        None => {
          let split = emit_search(code, Split([]))
          let start = compile_search(child, split, code)
          code[split] = Split(
            if greedy {
              [start, next]
            } else {
              [next, start]
            },
          )
          next = split
        }
        Some(max) =>
          for _ in min..<max {
            let start = compile_search(child, next, code)
            next = emit_search(
              code,
              Split(if greedy { [start, next] } else { [next, start] }),
            )
          }
      }
      for _ in 0..<min {
        next = compile_search(child, next, code)
      }
      next
    }
  }
}

///|
priv struct SearchBudget {
  mut steps : Int32
  limit : Int32
  tick : () -> Bool
}

///|
fn SearchBudget::check(self : SearchBudget) -> Unit raise SearchError {
  self.steps += 1
  if self.steps > self.limit {
    raise SearchLimit
  }
  if !(self.tick)() {
    raise SearchCancelled
  }
}

///|
fn previous_scalar(input : Bytes, position : Int32) -> Int32 {
  if position == 0 {
    return -1
  }
  let mut start = position - 1
  while start > 0 &&
        input[start].to_int() >= 128 &&
        input[start].to_int() < 192 &&
        position - start < 4 {
    start -= 1
  }
  decode(input, start).0
}

///|
fn Regex::assertion(
  self : Regex,
  assertion : Assertion,
  input : Bytes,
  position : Int32,
) -> Bool {
  let previous = previous_scalar(input, position)
  let next = if position == input.length() {
    -1
  } else {
    decode(input, position).0
  }
  match assertion {
    StartText => position == 0
    EndText => position == input.length()
    StartLine(crlf) =>
      position == 0 || previous == 10 || (crlf && previous == 13 && next != 10)
    EndLine(crlf) =>
      position == input.length() ||
      (next == 10 && (!crlf || previous != 13)) ||
      (crlf && next == 13)
    WordBoundary(positive, unicode) => {
      let word = fn(c) {
        if unicode {
          self.word.contains(c)
        } else {
          c is (65..<=90 | 97..<=122 | 48..<=57 | 95)
        }
      }
      (word(previous) != word(next)) == positive
    }
  }
}

///|
fn Regex::closure(
  self : Regex,
  seeds : Array[Int32],
  input : Bytes,
  position : Int32,
  budget : SearchBudget,
) -> Array[Int32] raise SearchError {
  let stack = seeds.copy()
  stack.rev_in_place()
  let seen : Map[Int32, Bool] = Map([])
  let result = []
  while stack.pop() is Some(id) {
    budget.check()
    if seen.contains(id) {
      continue
    }
    seen[id] = true
    match self.code[id] {
      Consume(_, _) => result.push(id)
      Match => {
        result.push(id)
        break
      }
      Check(assertion, next) =>
        if self.assertion(assertion, input, position) {
          stack.push(next)
        }
      Split(targets) =>
        for i = targets.length() - 1; i >= 0; i = i - 1 {
          stack.push(targets[i])
        }
    }
  }
  result
}

///|
fn Regex::prefix(
  self : Regex,
  input : Bytes,
  start : Int32,
  budget : SearchBudget,
) -> Int32? raise SearchError {
  let mut position = start
  let mut states = self.closure([self.start], input, position, budget)
  let mut matched = None
  for ;; {
    if states.last() is Some(id) && self.code[id] is Match {
      matched = Some(position)
      ignore(states.pop())
    }
    if states.is_empty() || position == input.length() {
      return matched
    }
    let (scalar, size) = decode(input, position)
    let seeds = []
    for id in states {
      budget.check()
      if self.code[id] is Consume(chars, next) && chars.contains(scalar) {
        seeds.push(next)
      }
    }
    if seeds.is_empty() {
      return matched
    }
    position += size
    states = self.closure(seeds, input, position, budget)
  }
}

///|
/// Find the first match at or after a UTF-8 byte offset, preserving anchors
/// against the complete input. The optional tick callback supports cancellation
/// and lets callers charge regex work to their own shared budget.
pub fn Regex::find(
  self : Regex,
  input : Bytes,
  start~ : Int32 = 0,
  max_steps~ : Int32 = 1000000,
  tick~ : () -> Bool = () => true,
) -> (Int32, Int32)? raise SearchError {
  if start < 0 || start > input.length() {
    return None
  }
  let budget : SearchBudget = { steps: 0, limit: max_steps, tick, }
  let mut start = start
  for ;; {
    if self.prefix(input, start, budget) is Some(end) {
      return Some((start, end))
    }
    if start == input.length() {
      return None
    }
    start += decode(input, start).1
  }
}
