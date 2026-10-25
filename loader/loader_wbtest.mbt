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

///|
test "standardize_path keeps the spelling of the rest of the path" {
  // `home.join(path.strip_prefix("~"))`: only the prefix is replaced.
  inspect(
    standardize_path("~/git//treesitter/./x", "/home/u"),
    content="/home/u/git//treesitter/./x",
  )
  inspect(standardize_path("$HOME/a", "/home/u"), content="/home/u/a")
  inspect(standardize_path("~", "/home/u"), content="/home/u/")
  inspect(standardize_path("~x/a", "/home/u"), content="~x/a")
}
