///|
test "language aliases sort in Rust string order" {
  let ids : Array[(Int32, String)] = [
    (0, "b"),
    (0, "aa"),
    (1, "é"),
    (1, "z"),
    (1, "😀"),
    (1, "\u{ffff}"),
  ]
  ids.sort_by((a, b) => {
    let c = a.0.compare(b.0)
    if c != 0 {
      c
    } else {
      rust_str_cmp(a.1, b.1)
    }
  })
  debug_inspect(
    ids.map(i => i.1),
    content=(
      #|["aa", "b", "z", "é", "￿", "😀"]
    ),
  )
}
