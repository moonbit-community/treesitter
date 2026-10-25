///|
test "webbrowser: targets" {
  inspect(has_url_scheme("https://github.com"), content="true")
  inspect(has_url_scheme("file:///x"), content="true")
  inspect(has_url_scheme("log.html"), content="false")
  inspect(has_url_scheme("1x:y"), content="false")
  inspect(has_url_scheme(":x"), content="false")
  inspect(
    target_type_from_file_path("/tmp/a b/#x%?{é}.html"),
    content="file:///tmp/a%20b/%23x%25%3F%7B%C3%A9%7D.html",
  )
  inspect(
    target_type_from_file_path("/tmp/./x/../log.html"),
    content="file:///tmp/x/../log.html",
  )
  inspect(target_type_from_file_path("/"), content="file:///")
}

///|
test "webbrowser: BROWSER commands" {
  debug_inspect(
    browser_env_cmd_arr("firefox --new-tab", "file:///x"),
    content=(
      #|["firefox", "--new-tab", "file:///x"]
    ),
  )
  debug_inspect(
    browser_env_cmd_arr("  open  -a %s%c%%%z% ", "u"),
    content=(
      #|["open", "-a", "u:%%z%"]
    ),
  )
  debug_inspect(
    split_ascii_whitespace(" a\tb\n c "),
    content=(
      #|["a", "b", "c"]
    ),
  )
  inspect(is_text_browser("/usr/bin/lynx"), content="true")
  inspect(is_text_browser("/usr/bin/lynx-ng"), content="false")
}

///|
test "webbrowser: desktop entry lines" {
  debug_inspect(
    rust_lines(b"[Desktop Entry]\r\nExec=x %u\n\xff\nlast"),
    content=(
      #|[Some("[Desktop Entry]"), Some("Exec=x %u"), None, Some("last")]
    ),
  )
}

///|
test "webbrowser: desktop file lines" {
  // `BufRead::lines` removes a `\r` only before a `\n`: `Hidden=true\r` on
  // the last line is not `Hidden=true`.
  debug_inspect(
    rust_lines(b"a\r\nHidden=true\r"),
    content=(
      #|[Some("a"), Some("Hidden=true\r")]
    ),
  )
}
