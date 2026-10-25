///|
test "BitVec::insert_all only reads the other vector's words in use" {
  let a = TokenSet::new()
  let b = TokenSet::new()
  b.insert(Symbol::terminal(65))
  inspect(b.remove(Symbol::terminal(65)), content="true")
  inspect(b.terminal_bits.len(), content="0")
  inspect(a.insert_all(b), content="false")
  inspect(a.terminal_bits.len(), content="0")
}

///|
test "BitVec::resize works on whole words like upstream" {
  // Growing within the last word in use does not fill the new bits.
  let v = BitVec::new()
  v.resize(1, false)
  v.resize(2, true)
  debug_inspect(v.get(1), content="Some(false)")
  // Growing into new words fills them, masking the bits beyond the length.
  v.resize(70, true)
  debug_inspect(v.get(1), content="Some(false)")
  debug_inspect(v.get(64), content="Some(true)")
  debug_inspect(v.get(69), content="Some(true)")
  inspect(v.words()[1], content="63")
  // Shrinking within a word keeps the truncated bits, which reappear when
  // growing within that word again.
  v.resize(66, false)
  inspect(v.words()[1], content="63")
  v.resize(68, false)
  debug_inspect(v.get(67), content="Some(true)")
  // Shrinking by whole words clears them.
  v.resize(64, false)
  inspect(v.words()[1], content="0")
  v.resize(68, false)
  debug_inspect(v.get(67), content="Some(false)")
}

///|
test "BitVec::pop clears a word that is no longer in use" {
  let v = BitVec::new()
  v.resize(70, true)
  v.resize(65, false)
  debug_inspect(v.pop(), content="Some(true)")
  inspect(v.len(), content="64")
  inspect(v.words()[1], content="0")
  debug_inspect(v.pop(), content="Some(true)")
  debug_inspect(v.last(), content="Some(true)")
}
