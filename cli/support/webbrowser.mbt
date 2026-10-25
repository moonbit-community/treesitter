// Port of webbrowser 1.2.4 (`webbrowser::open`, src/lib.rs, src/macos.rs,
// src/unix.rs and src/common.rs) as the CLI uses it: the default browser
// with the default `BrowserOptions` (output suppressed, no dry run).
//
// - macOS opens the target with the application that handles `https://`
//   URLs (falling back to Safari) through Launch Services, the API that
//   `NSWorkspace` wraps (see `ts_cli_macos_open` in stub.c);
// - other Unix systems try `$BROWSER`, the XDG default browser, the
//   desktop environment's opener and `x-www-browser`, as upstream does.
//   Opening `file://` URLs from WSL through the Windows browser (upstream's
//   PowerShell query of the default browser) is not ported: those attempts
//   fail and the search continues with `x-www-browser`.
//
// Errors are `std::io::Error`s (`IoError` or OS errors).

///|
#borrow(url)
extern "C" fn ts_cli_macos_open(url : Bytes) -> Int32 = "ts_cli_macos_open"

///|
extern "C" fn ts_cli_macos_open_status() -> Int32 = "ts_cli_macos_open_status"

///|
extern "C" fn ts_cli_macos_open_message() -> Bytes = "ts_cli_macos_open_message"

///|
/// `webbrowser::open`: open `url` (a URL, or a path to a local file) in the
/// default browser.
pub async fn webbrowser_open(url : String) -> Unit {
  let target = target_type_try_from(url)
  if current_os == "macos" {
    macos_open_browser_internal(target)
  } else if current_os == "windows" {
    raise Custom(kind="NotFound", error="unsupported platform")
  } else {
    unix_open_browser_default(target)
  }
}

///|
/// `TargetType::try_from`: a URL is used as it is, anything else is a file
/// path converted to a `file://` URL.
fn target_type_try_from(value : String) -> String raise {
  if has_url_scheme(value) {
    value
  } else {
    target_type_from_file_path(value)
  }
}

///|
/// Whether `url::Url::parse` accepts `value` as an absolute URL: it starts
/// with a scheme (`ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )`) and `:`.
fn has_url_scheme(value : String) -> Bool {
  for i, c in value {
    match c {
      'a'..<='z' | 'A'..<='Z' => continue
      '0'..<='9' | '+' | '-' | '.' if i > 0 => continue
      ':' => return i > 0
      _ => return false
    }
  }
  false
}

///|
/// `TargetType::from_file_path`: `url::Url::from_file_path` of the path
/// made absolute with the current directory.
fn target_type_from_file_path(value : String) -> String raise {
  let path = if is_absolute(value) {
    value
  } else {
    let current_dir = current_dir()
    path_join(current_dir, value)
  }
  let url = StringBuilder()
  url.write_string("file://")
  let comps = components(path)
  if comps.is_empty() {
    url.write_char('/')
  }
  for component in comps {
    url.write_char('/')
    for byte in @utf8.encode(component) {
      if url_special_path_segment_encodes(byte) {
        url.write_char('%')
        url.write_string(hex_upper(byte))
      } else {
        url.write_char(byte.to_char())
      }
    }
  }
  url.to_string()
}

///|
fn hex_upper(byte : Byte) -> String {
  let digits = "0123456789ABCDEF"
  let b = byte.to_int()
  let sb = StringBuilder()
  sb.write_char(digits.get_char(b >> 4).unwrap())
  sb.write_char(digits.get_char(b & 15).unwrap())
  sb.to_string()
}

///|
/// Whether `percent_encode` with url's `SPECIAL_PATH_SEGMENT` set encodes a
/// byte: C0 controls, DEL, non-ASCII, space, `"`, `<`, `>`, `` ` ``, `#`,
/// `?`, `{`, `}`, `/`, `%` and `\`.
fn url_special_path_segment_encodes(byte : Byte) -> Bool {
  byte < 0x20 ||
  byte >= 0x7f ||
  byte
  is (b' '
  | b'"'
  | b'<'
  | b'>'
  | b'`'
  | b'#'
  | b'?'
  | b'{'
  | b'}'
  | b'/'
  | b'%'
  | b'\\')
}

///|
/// `macos::open_browser_internal` for `Browser::Default`.
fn macos_open_browser_internal(target : String) -> Unit raise {
  let result = ts_cli_macos_open(c_string(target))
  if (result & 16) != 0 {
    log_error("failed to get default browser, falling back to Safari")
  }
  match result & 15 {
    0 => ()
    1 => raise Custom(kind="NotFound", error="browser not found")
    2 => raise Custom(kind="Other", error="failed to create target NSURL")
    3 => {
      // map_launch_error
      let kind = match ts_cli_macos_open_status() {
        -43 | -10814 => "NotFound"
        -10826 => "PermissionDenied"
        _ => "Other"
      }
      raise Custom(kind~, error=@utf8.decode_lossy(ts_cli_macos_open_message()))
    }
    _ => raise Custom(kind="NotFound", error="unsupported platform")
  }
}

// unix.rs

///|
/// `open_browser_default`.
async fn unix_open_browser_default(target : String) -> Unit {
  let url = target
  let attempts : Array[async () -> Bool] = [
    () => try_with_browser_env(url),
    () => try_xdg(url),
    () => {
      match guess_desktop_env() {
        "kde" =>
          try_browser("kde-open", [url]) ||
          try_browser("kde-open5", [url]) ||
          try_browser("kfmclient", ["newTab", url])
        "gnome" =>
          try_browser("gio", ["open", url]) ||
          try_browser("gvfs-open", [url]) ||
          try_browser("gnome-open", [url])
        "mate" =>
          try_browser("gio", ["open", url]) ||
          try_browser("gvfs-open", [url]) ||
          try_browser("mate-open", [url])
        "xfce" =>
          try_browser("exo-open", [url]) ||
          try_browser("gio", ["open", url]) ||
          try_browser("gvfs-open", [url])
        "wsl" => try_wsl(target)
        "flatpak" =>
          // try_flatpak
          if url.has_prefix("http:") || url.has_prefix("https:") {
            try_browser("xdg-open", [url])
          } else {
            false
          }
        _ => false
      }
    },
    () => try_browser("x-www-browser", [url]),
  ]
  for attempt in attempts {
    if attempt() {
      return
    }
  }
  raise Custom(
    kind="NotFound",
    error="No valid browsers detected. You can specify one in BROWSER environment variable",
  )
}

///|
/// `try_browser!`: run `name` (found as `for_matching_path` does) with
/// `args`; whether that succeeded.
async fn try_browser(name : String, args : Array[String]) -> Bool {
  guard for_matching_path(name) is Some(pb) else { return false }
  run_command(pb, args, !is_text_browser(pb))
}

///|
/// `try_with_browser_env`.
async fn try_with_browser_env(url : String) -> Bool {
  let browser = @env.get_env_var("BROWSER").unwrap_or("")
  for browser_env in browser.split(":") {
    let browser_env = browser_env.to_owned()
    if !browser_env.is_empty() {
      let cmdarr = browser_env_cmd_arr(browser_env, url)
      if cmdarr.is_empty() {
        continue
      }
      guard for_matching_path(cmdarr[0]) is Some(pb) else { continue }
      if run_command(pb, cmdarr[1:].to_owned(), !is_text_browser(pb)) {
        return true
      }
    }
  }
  false
}

///|
/// `browser_env_cmd_arr`.
fn browser_env_cmd_arr(browser_env : String, url : String) -> Array[String] {
  let mut url_set = false
  let arr = []
  for opt in split_ascii_whitespace(browser_env) {
    let (val, has_url) = expand_field_codes(opt, url)
    url_set = url_set || has_url
    arr.push(val)
  }
  if !url_set {
    arr.push(url)
  }
  arr
}

///|
/// `expand_field_codes`: `%s` is the URL, `%c` a colon and `%%` a percent
/// sign.
fn expand_field_codes(opt : String, url : String) -> (String, Bool) {
  let val = StringBuilder()
  let mut url_set = false
  let chars = opt.iter()
  while chars.next() is Some(ch) {
    if ch != '%' {
      val.write_char(ch)
      continue
    }
    match chars.next() {
      Some('s') => {
        val.write_string(url)
        url_set = true
      }
      Some('c') => val.write_char(':')
      Some('%') => val.write_char('%')
      Some(other) => {
        val.write_char('%')
        val.write_char(other)
      }
      None => val.write_char('%')
    }
  }
  (val.to_string(), url_set)
}

///|
/// `str::split_ascii_whitespace`.
fn split_ascii_whitespace(s : String) -> Array[String] {
  let result = []
  let current = StringBuilder()
  for c in s {
    if c is (' ' | '\t' | '\n' | '\u{0c}' | '\r') {
      if !current.is_empty() {
        result.push(current.to_string())
        current.reset()
      }
    } else {
      current.write_char(c)
    }
  }
  if !current.is_empty() {
    result.push(current.to_string())
  }
  result
}

///|
/// `is_wsl`.
fn is_wsl() -> Bool {
  if current_os != "linux" {
    return false
  }
  read_to_string("/proc/sys/fs/binfmt_misc/WSLInterop").contains("enabled") catch {
    _ => false
  }
}

///|
/// `is_flatpak`.
fn is_flatpak() -> Bool {
  match @env.get_env_var("container") {
    Some(x) => x.to_lower() == "flatpak"
    None => false
  }
}

///|
/// `guess_desktop_env`.
fn guess_desktop_env() -> String {
  let unknown = "unknown"
  let xcd = @env.get_env_var("XDG_CURRENT_DESKTOP")
    .unwrap_or(unknown)
    .to_lower()
  let dsession = @env.get_env_var("DESKTOP_SESSION")
    .unwrap_or(unknown)
    .to_lower()
  if is_flatpak() {
    "flatpak"
  } else if xcd.contains("gnome") ||
    xcd.contains("cinnamon") ||
    dsession.contains("gnome") {
    "gnome"
  } else if xcd.contains("kde") ||
    @env.get_env_var("KDE_FULL_SESSION") is Some(_) ||
    @env.get_env_var("KDE_SESSION_VERSION") is Some(_) {
    "kde"
  } else if xcd.contains("mate") || dsession.contains("mate") {
    "mate"
  } else if xcd.contains("xfce") || dsession.contains("xfce") {
    "xfce"
  } else if is_wsl() {
    "wsl"
  } else {
    unknown
  }
}

///|
/// `try_wsl`: http(s) URLs through the Windows shell; local files (which
/// upstream opens with the browser that PowerShell reports) are not
/// supported.
async fn try_wsl(target : String) -> Bool {
  if target.has_prefix("http:") || target.has_prefix("https:") {
    let url = target
    try_browser("cmd.exe", [
      "/c",
      "start",
      url.replace_all(old="^", new="^^").replace_all(old="&", new="^&"),
    ]) ||
    try_browser("powershell.exe", [
      "Start",
      url.replace_all(old="&", new="\"&\""),
    ]) ||
    try_browser("wsl-open", [url])
  } else {
    false
  }
}

///|
/// `try_xdg`: the browser of `xdg-settings get default-web-browser`.
async fn try_xdg(url : String) -> Bool {
  guard for_matching_path("xdg-settings") is Some(pb) else { return false }
  let (_, browser_name_os, _) = command_output(
    pb,
    ["get", "default-web-browser"],
    null_stderr=true,
  ) catch {
    _ => return false
  }
  guard utf8_strict(browser_name_os) is Some(browser_name) else { return false }
  let browser_name = browser_name.trim().to_owned()
  if browser_name.is_empty() {
    return false
  }
  let mut config_found = false
  let app_suffix = "applications"
  for xdg_dir in get_xdg_dirs() {
    let mut config_path = path_join(
      path_join(xdg_dir, app_suffix),
      browser_name,
    )
    let mut exists = path_exists(config_path)
    if !exists && browser_name.contains("-") {
      let child_path = browser_name.replace_all(old="-", new="/")
      config_path = path_join(path_join(xdg_dir, app_suffix), child_path)
      exists = path_exists(config_path)
    }
    if exists {
      config_found = true
      match open_using_xdg_config(config_path, url) {
        XdgOpened => return true
        XdgNotFound => ()
        // Errors other than `NotFound` end the search.
        XdgFailed => return false
      }
    }
  }
  ignore(config_found)
  false
}

///|
async fn path_exists(path : String) -> Bool {
  try {
    ignore(@fs.kind(path, follow_symlink=true))
    true
  } catch {
    _ => false
  }
}

///|
priv enum XdgResult {
  XdgOpened
  XdgNotFound
  XdgFailed
}

///|
/// `open_using_xdg_config`: run the `Exec` line of the `[Desktop Entry]`
/// group of a desktop file.
async fn open_using_xdg_config(config_path : String, url : String) -> XdgResult {
  let contents = read_file(config_path) catch {
    @os_error.OSError(_) as e if e.is_ENOENT() => return XdgNotFound
    _ => return XdgFailed
  }
  let mut in_desktop_entry = false
  let mut hidden = false
  let mut cmdline = None
  let mut requires_terminal = false
  // `BufReader::lines().map_while(Result::ok)` stops at the first line that
  // is not UTF-8.
  for line in rust_lines(contents) {
    guard line is Some(line) else { break }
    if line == "[Desktop Entry]" {
      in_desktop_entry = true
    } else if line.has_prefix("[") {
      in_desktop_entry = false
    } else if in_desktop_entry && !line.has_prefix("#") {
      if line.find("=") is Some(idx) {
        let key = line.unsafe_substring(start=0, end=idx)
        let value = line.unsafe_substring(start=idx + 1, end=line.length())
        match key {
          "Exec" => cmdline = Some(value)
          "Hidden" => hidden = value == "true"
          "Terminal" => requires_terminal = value == "true"
          _ => ()
        }
      }
    }
  }
  if hidden {
    return XdgNotFound
  }
  guard cmdline is Some(cmdline) else { return XdgNotFound }
  let cmdarr = split_ascii_whitespace(cmdline)
  if cmdarr.is_empty() {
    rust_panic(
      "index out of bounds: the len is 0 but the index is 0",
      crate_location("webbrowser-1.2.4/src/unix.rs:409:27"),
    )
  }
  guard for_matching_path(cmdarr[0]) is Some(pb) else { return XdgNotFound }
  let args = []
  let mut url_added = false
  for arg in cmdarr[1:] {
    match arg {
      "%u" | "%U" | "%f" | "%F" => {
        url_added = true
        args.push(url)
      }
      _ => args.push(arg)
    }
  }
  if !url_added {
    args.push(url)
  }
  if run_command(pb, args, !requires_terminal) {
    XdgOpened
  } else {
    XdgFailed
  }
}

///|
/// `BufRead::lines` of a byte buffer: lines without their `\n` (and `\r`),
/// `None` for a line that is not valid UTF-8.
fn rust_lines(contents : Bytes) -> Array[String?] {
  let result = []
  let mut start = 0
  let n = contents.length()
  while start < n {
    let mut end = start
    while end < n && contents[end] != b'\n' {
      end += 1
    }
    let mut line_end = end
    // `\r` is removed only before a `\n`.
    if end < n && line_end > start && contents[line_end - 1] == b'\r' {
      line_end -= 1
    }
    result.push(utf8_strict(contents[start:line_end]))
    start = end + 1
  }
  result
}

///|
/// `get_xdg_dirs`.
fn get_xdg_dirs() -> Array[String] {
  let xdg_dirs = []
  let data_home = match @env.get_env_var("XDG_DATA_HOME") {
    Some(path) if is_absolute(path) => Some(path)
    _ => home_dir().map(path => path_join(path, ".local/share"))
  }
  if data_home is Some(data_home) {
    xdg_dirs.push(data_home)
  }
  match @env.get_env_var("XDG_DATA_DIRS") {
    Some(data_dirs) =>
      for d in data_dirs.split(":") {
        xdg_dirs.push(d.to_owned())
      }
    None => {
      xdg_dirs.push("/usr/local/share")
      xdg_dirs.push("/usr/share")
    }
  }
  xdg_dirs
}

///|
let text_browsers : Array[String] = [
  "lynx", "links", "links2", "elinks", "w3m", "eww", "netrik", "retawq", "curl",
]

///|
/// `is_text_browser`: whether the last component of the path is a text
/// browser.
fn is_text_browser(pb : String) -> Bool {
  match file_name(pb) {
    Some(name) => text_browsers.contains(name)
    None => false
  }
}

///|
/// `for_matching_path`: an executable regular file named `name`, either a
/// path or found in `PATH`.
fn for_matching_path(name : String) -> String? {
  if name.contains("/") {
    if is_executable_file(name) {
      Some(name)
    } else {
      None
    }
  } else {
    match @env.get_env_var("PATH") {
      Some(path) =>
        for entry in path.split(":") {
          let pb = path_join(entry.to_owned(), name)
          if is_executable_file(pb) {
            return Some(pb)
          }
        }
      None => ()
    }
    None
  }
}

///|
#borrow(path)
extern "C" fn ts_cli_is_executable_file(path : Bytes) -> Int32 = "ts_cli_is_executable_file"

///|
/// `metadata.is_file() && metadata.permissions().mode() & 0o111 != 0`.
fn is_executable_file(path : String) -> Bool {
  ts_cli_is_executable_file(c_string(path)) != 0
}

///|
/// `common::run_command` with the default options: a GUI browser runs in
/// the background with its output suppressed, a text browser in the
/// foreground. Whether it could be run.
async fn run_command(
  program : String,
  args : Array[String],
  background : Bool,
) -> Bool {
  if background {
    let null_in = @process.redirect_from_file("/dev/null")
    let null_out = @process.redirect_to_file("/dev/null")
    let null_err = @process.redirect_to_file("/dev/null")
    try {
      ignore(
        @process.spawn_orphan(
          program,
          args,
          stdin=null_in,
          stdout=null_out,
          stderr=null_err,
        ),
      )
      true
    } catch {
      _ => false
    }
  } else {
    // `cmd.status()`: a process ended by a signal did not succeed.
    (command_status(program, args) catch { _ => None }) == Some(0)
  }
}
