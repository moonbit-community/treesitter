// Port of tree-sitter crates/cli/src/highlight.rs.

///|
pub let html_head_header : String = "\n<!doctype HTML>\n<head>\n  <title>Tree-sitter Highlighting</title>\n  <style>\n    body {\n      font-family: monospace\n    }"

///|
pub let html_line_number_style : String = "    .line-number {\n      user-select: none;\n      text-align: right;\n      color: rgba(27,31,35,.3);\n      padding: 0 10px;\n    }\n    .line {\n      white-space: pre;\n    }"

///|
pub let html_body_header : String = "\n</head>\n<body>\n"

///|
pub let html_footer : String = "\n</body>\n"

///|
pub(all) struct HlStyle {
  ansi : Style
  css : String?
} derive(Eq, Debug)

///|
pub fn HlStyle::default() -> HlStyle {
  { ansi: Style::new(), css: None, }
}

///|
pub struct Theme {
  styles : Array[HlStyle]
  highlight_names : Array[String]
}

///|
/// `Deserialize for Theme`: a map from highlight names (iterated in sorted
/// order, as a `BTreeMap`) to styles; anything else gives an empty theme.
pub fn Theme::from_json(json : Json) -> Theme {
  let styles = []
  let highlight_names = []
  if json is Object(colors) {
    let names = colors.keys().collect()
    names.sort_by((a, b) => compare_bytes(a, b))
    for name in names {
      let style = parse_style(colors[name])
      highlight_names.push(name)
      styles.push(style)
    }
  }
  { styles, highlight_names, }
}

///|
/// Rust's `Ord for str`.
pub fn compare_bytes(a : String, b : String) -> Int32 {
  let x = @support.utf8(a)
  let y = @support.utf8(b)
  let n = if x.length() < y.length() { x.length() } else { y.length() }
  for i in 0..<n {
    let c = x[i].compare(y[i])
    if c != 0 {
      return c
    }
  }
  x.length().compare(y.length())
}

///|
/// `Serialize for Theme`.
pub fn Theme::to_json(self : Theme) -> Json {
  let map : Map[String, Json] = Map([])
  for i, name in self.highlight_names {
    let style = self.styles[i].ansi
    let color = match style.fg {
      Some(Ansi(n)) =>
        Some(
          Json::string(
            match n {
              0 => "black"
              4 => "blue"
              6 => "cyan"
              2 => "green"
              5 => "purple"
              1 => "red"
              7 => "white"
              _ => "yellow"
            },
          ),
        )
      Some(Ansi256(n)) => Some(Json::number(n.to_double()))
      Some(Rgb(r, g, b)) =>
        Some(
          Json::string(
            "#\{r.to_string(radix=16)}\{g.to_string(radix=16)}\{b.to_string(radix=16)}",
          ),
        )
      None => None
    }
    if style.bold || style.italic || style.underline {
      // A `BTreeMap`: keys in sorted order.
      let style_json : Map[String, Json] = Map([])
      if style.bold {
        style_json["bold"] = Json::boolean(true)
      }
      if color is Some(color) {
        style_json["color"] = color
      }
      if style.italic {
        style_json["italic"] = Json::boolean(true)
      }
      if style.underline {
        style_json["underline"] = Json::boolean(true)
      }
      map[name] = Json::object(style_json)
    } else if color is Some(color) {
      map[name] = color
    } else {
      map[name] = Json::null()
    }
  }
  Json::object(map)
}

///|
pub fn Theme::default() -> Theme {
  let n = (v : Int32) => Json::number(v.to_double())
  Theme::from_json({
    "attribute": { "color": n(124), "italic": true },
    "comment": { "color": n(245), "italic": true },
    "constant": n(94),
    "constant.builtin": { "color": n(94), "bold": true },
    "constructor": n(136),
    "embedded": Json::null(),
    "function": n(26),
    "function.builtin": { "color": n(26), "bold": true },
    "keyword": n(56),
    "module": n(136),
    "number": { "color": n(94), "bold": true },
    "operator": { "color": n(239), "bold": true },
    "property": n(124),
    "property.builtin": { "color": n(124), "bold": true },
    "punctuation": n(239),
    "punctuation.bracket": n(239),
    "punctuation.delimiter": n(239),
    "punctuation.special": n(239),
    "string": n(28),
    "string.special": n(30),
    "tag": n(18),
    "type": n(23),
    "type.builtin": { "color": n(23), "bold": true },
    "variable": n(252),
    "variable.builtin": { "color": n(252), "bold": true },
    "variable.parameter": { "color": n(252), "underline": true },
  })
}

///|
pub fn Theme::default_style(_self : Theme) -> HlStyle {
  HlStyle::default()
}

///|
/// `Config::get::<ThemeConfig>()`.
pub fn theme_config_from_json(config : Json) -> Theme {
  match config {
    { "theme": theme, .. } => Theme::from_json(theme)
    _ => Theme::default()
  }
}

///|
fn parse_style(json : Json) -> HlStyle {
  let mut ansi = Style::new()
  let mut css = None
  match json {
    Object(entries) => {
      for property_name, value in entries {
        match property_name {
          "bold" if value is True => ansi = { ..ansi, bold: true, }
          "italic" if value is True => ansi = { ..ansi, italic: true, }
          "underline" if value is True => ansi = { ..ansi, underline: true, }
          "color" =>
            if parse_color(value) is Some(color) {
              ansi = ansi.fg_color(Some(color))
            }
          _ => ()
        }
      }
      css = Some(style_to_css(ansi))
    }
    _ =>
      match parse_color(json) {
        Some(color) => {
          ansi = ansi.fg_color(Some(color))
          css = Some(style_to_css(ansi))
        }
        None => css = None
      }
  }
  if ansi.fg is Some(Rgb(r, g, b)) && !terminal_supports_truecolor() {
    ansi = ansi.fg_color(Some(Ansi256(ansi256_from_rgb(r, g, b))))
  }
  { ansi, css, }
}

///|
fn parse_color(json : Json) -> Color? {
  match json {
    Number(n, ..) =>
      if n >= 0.0 && n == n.floor() {
        Some(Ansi256(n.to_int() & 0xFF))
      } else {
        None
      }
    String(s) =>
      match s.to_lower() {
        "black" => Some(black)
        "blue" => Some(blue)
        "cyan" => Some(cyan)
        "green" => Some(green)
        "purple" => Some(magenta)
        "red" => Some(red)
        "white" => Some(white)
        "yellow" => Some(yellow)
        s =>
          match hex_string_to_rgb(s) {
            Some((r, g, b)) => Some(Rgb(r, g, b))
            None => None
          }
      }
    _ => None
  }
}

///|
fn hex_string_to_rgb(s : String) -> (Int32, Int32, Int32)? {
  if s.has_prefix("#") && @support.utf8_len(s) >= 7 {
    let hex = (start : Int32) => {
      @string.parse_int(
        s.view(start_offset=start, end_offset=start + 2),
        base=16,
      ) catch {
        _ => -1
      }
    }
    let (r, g, b) = (hex(1), hex(3), hex(5))
    if r >= 0 && g >= 0 && b >= 0 {
      Some((r, g, b))
    } else {
      None
    }
  } else {
    None
  }
}

///|
fn hex2(n : Int32) -> String {
  let s = n.to_string(radix=16)
  if s.length() < 2 {
    "0" + s
  } else {
    s
  }
}

///|
fn style_to_css(style : Style) -> String {
  let result = StringBuilder()
  if style.underline {
    result.write_string("text-decoration: underline;")
  }
  if style.bold {
    result.write_string("font-weight: bold;")
  }
  if style.italic {
    result.write_string("font-style: italic;")
  }
  if style.fg is Some(color) {
    match color {
      Ansi(n) =>
        result.write_string(
          match n {
            0 => "color: black"
            1 => "color: red"
            2 => "color: green"
            3 => "color: yellow"
            4 => "color: blue"
            5 => "color: purple"
            6 => "color: cyan"
            _ => "color: white"
          },
        )
      Ansi256(n) => {
        let rgb = ansi_colours[n]
        result.write_string(
          "color: #\{hex2((rgb >> 16) & 0xFF)}\{hex2((rgb >> 8) & 0xFF)}\{hex2(rgb & 0xFF)}",
        )
      }
      Rgb(r, g, b) =>
        result.write_string("color: #\{hex2(r)}\{hex2(g)}\{hex2(b)}")
    }
  }
  result.to_string()
}

///|
fn terminal_supports_truecolor() -> Bool {
  match @env.get_env_var("COLORTERM") {
    Some("truecolor") | Some("24bit") => true
    _ => false
  }
}

///|
/// The kind of HTML emitted when highlighting to HTML.
pub(all) enum HtmlOutput {
  Document
  NumberedDocument
  Fragment
} derive(Eq)

///|
/// How token colors are applied in HTML output.
pub(all) enum HtmlStyling {
  Classes
  Inline
  Minimal
} derive(Eq)

///|
pub struct HighlightOptions {
  theme : Theme
  check : Bool
  captures_path : String?
  html : (HtmlOutput, HtmlStyling)?
  quiet : Bool
  print_time : Bool
  encoding : InputEncoding?
}

///|
fn encoding_flag(e : InputEncoding) -> UInt32 {
  match e {
    Utf8 => @highlight.input_encoding_utf8
    Utf16LE => @highlight.input_encoding_utf16le
    Utf16BE => @highlight.input_encoding_utf16be
  }
}

///|
/// Load the languages that highlighting `source` injects.
///
/// Upstream's injection callback loads injected languages on demand, in the
/// middle of highlighting; the loader loads languages asynchronously, so
/// its callback only records the languages it is asked for
/// (`Loader::injection_callback`). Before the events are streamed, the
/// document is highlighted (discarding the events, and stopping as soon as
/// an unknown language is requested) until no language is pending, so the
/// final pass sees the same configurations as upstream's. Configurations
/// whose queries capture no `injection.content` never call the callback and
/// need no such pass.
pub async fn load_injected_languages(
  loader : @loader.Loader,
  config : @highlight.HighlightConfiguration,
  source : Bytes,
  encoding : UInt32?,
) -> Unit {
  if config.query.capture_index_for_name("injection.content") is None {
    return
  }
  for ;; {
    let highlighter = @highlight.Highlighter::new()
    let events = highlighter.highlight(
      config,
      source,
      encoding?,
      loader.injection_callback(),
    )
    while !loader.has_pending_injections() && events.next() is Some(Ok(_)) {

    }
    if !loader.has_pending_injections() {
      return
    }
    loader.resolve_pending_injections()
  }
}

///|
pub async fn highlight(
  loader : @loader.Loader,
  path : String,
  name : String,
  config : @highlight.HighlightConfiguration,
  print_name : Bool,
  opts : HighlightOptions,
) -> Unit {
  if opts.check {
    let names = match opts.captures_path {
      Some(path) => {
        let file = @support.read_to_string(path)
        let capture_names = @hashset.HashSet([])
        for line in rust_lines(file) {
          let trimmed = line.trim()
          if trimmed.is_empty() || trimmed.has_prefix(";") {
            continue
          }
          let first = line.split(";").next().unwrap()
          capture_names.add(first.trim().trim(chars="\"").to_owned())
        }
        config.nonconformant_capture_names(capture_names)
      }
      None => config.nonconformant_capture_names(@hashset.HashSet([]))
    }
    if names.is_empty() {
      log_info("All highlight captures conform to standards.")
    } else {
      log_warn(
        "Non-standard highlight \{if names.length() > 1 { "captures" } else { "capture" }} detected:\n* \{names.join("\n* ")}",
      )
    }
  }
  let source = @support.read_file(path)
  let encoding = match opts.encoding {
    None if source.length() >= 2 =>
      if source[0] == 0xFF && source[1] == 0xFE {
        Some(Utf16LE)
      } else if source[0] == 0xFE && source[1] == 0xFF {
        Some(Utf16BE)
      } else {
        None
      }
    e => e
  }
  let stdout = @support.stdout_lock()
  let time = @support.now_ns()
  let highlighter = @highlight.Highlighter::new()
  let encoding = encoding.map(encoding_flag)
  load_injected_languages(loader, config, source, encoding)
  let events = highlighter.highlight(
    config,
    source,
    encoding?,
    loader.injection_callback(),
  )
  let theme = opts.theme
  // A fragment is pure code markup, so it must not be prefixed with the
  // filename.
  let html_fragment = opts.html is Some((Fragment, _))
  if !opts.quiet && print_name && !html_fragment {
    stdout.write_string("\{name}\n")
  }
  match opts.html {
    Some((layout, style)) => {
      if !opts.quiet && layout != Fragment {
        stdout.write_string("\{html_head_header}\n")
        if layout == NumberedDocument {
          stdout.write_string("\{html_line_number_style}\n")
        }
        if style == Classes {
          for i, name in theme.highlight_names {
            if theme.styles[i].css is Some(css) {
              stdout.write_string("    .\{name} { \{css}; }\n")
            }
          }
        }
        stdout.write_string("  </style>\n")
        stdout.write_string("\{html_body_header}\n")
      }
      let renderer = @highlight.HtmlRenderer::new()
      renderer.render(events.iter(), source, (highlight, output) => {
        let index = highlight.0
        if style == Inline {
          push_bytes(output, @support.utf8("style='"))
          match theme.styles[index].css {
            Some(css) => push_bytes(output, @support.utf8(css))
            None => ()
          }
        } else {
          push_bytes(output, @support.utf8("class='"))
          let parts = theme.highlight_names[index].split(".").collect()
          for i, part in parts {
            push_bytes(output, @support.utf8(part.to_owned()))
            if i + 1 < parts.length() {
              output.push(b' ')
            }
          }
        }
        output.push(b'\'')
      })
      if !opts.quiet {
        if layout == NumberedDocument {
          stdout.write_string("<table>\n")
          for i, line in renderer.lines().collect() {
            stdout.write_string(
              "<tr><td class=line-number>\{i + 1}</td><td class=line>\{line}</td></tr>\n",
            )
          }
          stdout.write_string("</table>\n")
        } else {
          let mut body = renderer.lines().collect().join("")
          if body.has_suffix("\n") {
            body = body.unsafe_substring(start=0, end=body.length() - 1)
          }
          stdout.write_string(
            "<div class=\"highlight\">\n<pre><code>\{body}</code></pre>\n</div>\n",
          )
        }
        if layout != Fragment {
          stdout.write_string("\{html_footer}\n")
        }
      }
    }
    None => {
      let style_stack = [theme.default_style().ansi]
      while events.next() is Some(event) {
        match event {
          Ok(HighlightStart(highlight)) =>
            style_stack.push(theme.styles[highlight.0].ansi)
          Ok(HighlightEnd) => ignore(style_stack.pop())
          Ok(Source(start~, end~)) => {
            let style = style_stack[style_stack.length() - 1]
            // `write!(&mut stdout, "{style}").unwrap()`
            stdout.write_string(style.render()) catch {
              e => unwrap_failed(e, "crates/cli/src/highlight.rs:507:52")
            }
            stdout.write_bytes(source[start:end])
            stdout.write_string(style.render_reset()) catch {
              e => unwrap_failed(e, "crates/cli/src/highlight.rs:509:54")
            }
          }
          Err(e) => raise e
        }
      }
    }
  }
  if opts.print_time {
    log_info("Time: \{(@support.now_ns() - time) / 1000000L}ms")
  }
}

///|
/// `ansi_colours::ansi256_from_rgb`.
fn ansi256_from_rgb(r : Int32, g : Int32, b : Int32) -> Int32 {
  let luminance = (3567664 * r + 11998547 * g + 1211005 * b + (1 << 23)) >> 24
  let grey_index = ansi256_from_grey[luminance & 0xFF]
  let grey_distance = colour_distance(r, g, b, ansi_colours[grey_index])
  let (ri, rv) = cube_thresholds(r, 38, 115, 155, 196, 235)
  let (gi, gv) = cube_thresholds(g, 36, 116, 154, 195, 235)
  let (bi, bv) = cube_thresholds(b, 35, 115, 155, 195, 235)
  let cube_index = ri * 36 + 16 + gi * 6 + bi
  let cube_rgb = (rv << 16) + (gv << 8) + bv
  if colour_distance(r, g, b, cube_rgb) < grey_distance {
    cube_index
  } else {
    grey_index
  }
}

///|
fn cube_thresholds(
  v : Int32,
  a : Int32,
  b : Int32,
  c : Int32,
  d : Int32,
  e : Int32,
) -> (Int32, Int32) {
  if v < a {
    (0, 0)
  } else if v < b {
    (1, 95)
  } else if v < c {
    (2, 135)
  } else if v < d {
    (3, 175)
  } else if v < e {
    (4, 215)
  } else {
    (5, 255)
  }
}

///|
fn colour_distance(xr : Int32, xg : Int32, xb : Int32, y : Int32) -> UInt32 {
  let (yr, yg, yb) = ((y >> 16) & 0xFF, (y >> 8) & 0xFF, y & 0xFF)
  let r_sum = xr + yr
  let r = xr - yr
  let g = xg - yg
  let b = xb - yb
  ((1024 + r_sum) * r * r + 2048 * g * g + (1534 - r_sum) * b * b).reinterpret_as_uint()
}

///|
let ansi_colours : Array[Int32] = [
  0x000000,
  0xcd0000,
  0x00cd00,
  0xcdcd00,
  0x0000ee,
  0xcd00cd,
  0x00cdcd,
  0xe5e5e5,
  0x7f7f7f,
  0xff0000,
  0x00ff00,
  0xffff00,
  0x5c5cff,
  0xff00ff,
  0x00ffff,
  0xffffff,
  ..ansi_cube(),
  0x080808,
  0x121212,
  0x1c1c1c,
  0x262626,
  0x303030,
  0x3a3a3a,
  0x444444,
  0x4e4e4e,
  0x585858,
  0x626262,
  0x6c6c6c,
  0x767676,
  0x808080,
  0x8a8a8a,
  0x949494,
  0x9e9e9e,
  0xa8a8a8,
  0xb2b2b2,
  0xbcbcbc,
  0xc6c6c6,
  0xd0d0d0,
  0xdadada,
  0xe4e4e4,
  0xeeeeee,
]

///|
fn ansi_cube() -> Array[Int32] {
  let levels = [0, 0x5f, 0x87, 0xaf, 0xd7, 0xff]
  let result = []
  for r in levels {
    for g in levels {
      for b in levels {
        result.push((r << 16) | (g << 8) | b)
      }
    }
  }
  result
}

///|
let ansi256_from_grey : Array[Int32] = [
  16, 16, 16, 16, 16, 232, 232, 232, 232, 232, 232, 232, 232, 232, 233, 233, 233,
  233, 233, 233, 233, 233, 233, 233, 234, 234, 234, 234, 234, 234, 234, 234, 234,
  234, 235, 235, 235, 235, 235, 235, 235, 235, 235, 235, 236, 236, 236, 236, 236,
  236, 236, 236, 236, 236, 237, 237, 237, 237, 237, 237, 237, 237, 237, 237, 238,
  238, 238, 238, 238, 238, 238, 238, 238, 238, 239, 239, 239, 239, 239, 239, 239,
  239, 239, 239, 240, 240, 240, 240, 240, 240, 240, 240, 59, 59, 59, 59, 59, 241,
  241, 241, 241, 241, 241, 241, 242, 242, 242, 242, 242, 242, 242, 242, 242, 242,
  243, 243, 243, 243, 243, 243, 243, 243, 243, 244, 244, 244, 244, 244, 244, 244,
  244, 244, 102, 102, 102, 102, 102, 245, 245, 245, 245, 245, 245, 246, 246, 246,
  246, 246, 246, 246, 246, 246, 246, 247, 247, 247, 247, 247, 247, 247, 247, 247,
  247, 248, 248, 248, 248, 248, 248, 248, 248, 248, 145, 145, 145, 145, 145, 249,
  249, 249, 249, 249, 249, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 251,
  251, 251, 251, 251, 251, 251, 251, 251, 251, 252, 252, 252, 252, 252, 252, 252,
  252, 252, 188, 188, 188, 188, 188, 253, 253, 253, 253, 253, 253, 254, 254, 254,
  254, 254, 254, 254, 254, 254, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255,
  255, 255, 255, 255, 255, 231, 231, 231, 231, 231, 231, 231, 231, 231,
]

///|
/// `Result::unwrap` of a failed write.
fn unwrap_failed(e : Error, location : String) -> Unit {
  @support.rust_panic(
    "called `Result::unwrap()` on an `Err` value: \{@support.io_error_debug(e)}",
    location,
  )
}
