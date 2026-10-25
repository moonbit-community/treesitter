///|
test "LookaheadSetPool::insert memo distinguishes symbols with equal codes" {
  let pool = LookaheadSetPool::new()
  let terminal = Symbol::terminal(0)
  // Same `Symbol::code` as `terminal`: (2 << 28) | 0x10000000 == 3 << 28.
  let extra = { kind: EndOfNonTerminalExtra, index: 0x10000000, }
  inspect(terminal.code() == extra.code(), content="true")
  let a = pool.singleton(terminal)
  let b = pool.singleton(extra)
  inspect(a == b, content="false")
  inspect(pool.get(b).end_of_nonterminal_extra, content="true")
  inspect(pool.get(b).contains(terminal), content="false")
}
