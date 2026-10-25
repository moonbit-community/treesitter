// Port of tree-sitter crates/cli/src/paint.rs, with the `anstyle` colors
// the CLI uses.

///|
/// An `anstyle::Color`.
pub(all) enum Color {
  Ansi(Int32)
  Ansi256(Int32)
  Rgb(Int32, Int32, Int32)
} derive(Eq, Debug)

///|
pub let black : Color = Ansi(0)

///|
pub let red : Color = Ansi(1)

///|
pub let green : Color = Ansi(2)

///|
pub let yellow : Color = Ansi(3)

///|
pub let blue : Color = Ansi(4)

///|
pub let magenta : Color = Ansi(5)

///|
pub let cyan : Color = Ansi(6)

///|
pub let white : Color = Ansi(7)

///|
pub let bright_black : Color = Ansi(8)

///|
pub let bright_red : Color = Ansi(9)

///|
pub let bright_green : Color = Ansi(10)

///|
pub let bright_yellow : Color = Ansi(11)

///|
pub let bright_blue : Color = Ansi(12)

///|
pub let bright_magenta : Color = Ansi(13)

///|
pub let bright_cyan : Color = Ansi(14)

///|
pub let bright_white : Color = Ansi(15)

///|
/// The SGR sequence that sets `color` as the foreground.
fn Color::render_fg(self : Color) -> String {
  match self {
    Ansi(n) => if n < 8 { "\u{1b}[\{30 + n}m" } else { "\u{1b}[\{90 + n - 8}m" }
    Ansi256(n) => "\u{1b}[38;5;\{n}m"
    Rgb(r, g, b) => "\u{1b}[38;2;\{r};\{g};\{b}m"
  }
}

///|
/// An `anstyle::Style` (the subset the CLI uses).
pub(all) struct Style {
  fg : Color?
  bg : Color?
  bold : Bool
  italic : Bool
  underline : Bool
  dimmed : Bool
} derive(Eq, Debug)

///|
pub fn Style::new() -> Style {
  {
    fg: None,
    bg: None,
    bold: false,
    italic: false,
    underline: false,
    dimmed: false,
  }
}

///|
pub fn Style::fg_color(self : Style, color : Color?) -> Style {
  { ..self, fg: color, }
}

///|
pub fn Style::is_plain(self : Style) -> Bool {
  self == Style::new()
}

///|
/// `Display for Style` (the start sequence).
pub fn Style::render(self : Style) -> String {
  let sb = StringBuilder()
  if self.bold {
    sb.write_string("\u{1b}[1m")
  }
  if self.dimmed {
    sb.write_string("\u{1b}[2m")
  }
  if self.italic {
    sb.write_string("\u{1b}[3m")
  }
  if self.underline {
    sb.write_string("\u{1b}[4m")
  }
  if self.fg is Some(c) {
    sb.write_string(c.render_fg())
  }
  if self.bg is Some(c) {
    sb.write_string(
      match c {
        Ansi(n) =>
          if n < 8 {
            "\u{1b}[\{40 + n}m"
          } else {
            "\u{1b}[\{100 + n - 8}m"
          }
        Ansi256(n) => "\u{1b}[48;5;\{n}m"
        Rgb(r, g, b) => "\u{1b}[48;2;\{r};\{g};\{b}m"
      },
    )
  }
  sb.to_string()
}

///|
/// `{style:#}`: the reset sequence, if the style is not plain.
pub fn Style::render_reset(self : Style) -> String {
  if self.is_plain() {
    ""
  } else {
    "\u{1b}[0m"
  }
}

///|
pub let style_red : Style = Style::new().fg_color(Some(red))

///|
pub let style_yellow : Style = Style::new().fg_color(Some(yellow))

///|
let color_enabled_cache : Ref[Bool?] = Ref(None)

///|
/// Colors are enabled unless `NO_COLOR` is set to a non-empty value.
pub fn color_enabled() -> Bool {
  match color_enabled_cache.val {
    Some(v) => v
    None => {
      let v = match @env.get_env_var("NO_COLOR") {
        None => true
        Some(v) => v.is_empty()
      }
      color_enabled_cache.val = Some(v)
      v
    }
  }
}

///|
/// `Paint(style, text)`.
pub fn paint_style(style : Style, text : String) -> String {
  if color_enabled() {
    style.render() + text + style.render_reset()
  } else {
    text
  }
}

///|
/// `paint(color, text)`.
pub fn paint(color : Color?, text : String) -> String {
  paint_style(Style::new().fg_color(color), text)
}
