// Port of tree-sitter crates/cli/src/parse.rs.

///|
/// `Stats`. The counters are `usize`s.
pub struct Stats {
  mut successful_parses : UInt64
  mut total_parses : UInt64
  mut total_bytes : UInt64
  /// Nanoseconds.
  mut total_duration : Int64
}

///|
pub fn Stats::default() -> Stats {
  { successful_parses: 0, total_parses: 0, total_bytes: 0, total_duration: 0, }
}

///|
/// `format!("{:.2}", x)`.
pub fn format_fixed2(x : Double) -> String {
  format_fixed(x, 2)
}

///|
/// `format!("{:.precision$}", x)` for an `f64`: the exact binary value
/// rounded to `precision` decimals, with ties to even (Rust's exact-mode
/// `float_to_decimal_exact`); the sign is printed for every negative value,
/// `-0.0` included.
pub fn format_fixed(x : Double, precision : Int32) -> String {
  if x.is_nan() {
    return "NaN"
  }
  let bits = x.reinterpret_as_uint64()
  let sign = if bits >> 63 != 0UL { "-" } else { "" }
  if x.is_inf() {
    return sign + "inf"
  }
  let biased_exponent = ((bits >> 52) & 0x7FFUL).to_int()
  let fraction = bits & 0xFFFFFFFFFFFFFUL
  // x = mantissa * 2^exponent
  let (mantissa, exponent) = if biased_exponent == 0 {
    (fraction, -1074)
  } else {
    (fraction | 0x10000000000000UL, biased_exponent - 1075)
  }
  let mantissa = @bigint.BigInt::from_uint64(mantissa)
  let one = @bigint.BigInt::from_int(1)
  let scale = @bigint.BigInt::from_int(10).pow(
    @bigint.BigInt::from_int(precision),
  )
  // The value times 10^precision, rounded to an integer.
  let scaled = if exponent >= 0 {
    (mantissa << exponent) * scale
  } else {
    let k = -exponent
    let product = mantissa * scale
    let q = product >> k
    let rem = product - (q << k)
    let cmp = rem.compare(one << (k - 1))
    if cmp > 0 || (cmp == 0 && !q.land(one).is_zero()) {
      q + one
    } else {
      q
    }
  }
  let digits = scaled.to_string()
  let digits = if digits.length() <= precision {
    "0".repeat(precision + 1 - digits.length()) + digits
  } else {
    digits
  }
  let point = digits.length() - precision
  let int_part = digits.unsafe_substring(start=0, end=point)
  if precision == 0 {
    sign + int_part
  } else {
    sign +
    int_part +
    "." +
    digits.unsafe_substring(start=point, end=digits.length())
  }
}

///|
/// Right-align `s` to `width` characters (`{:>width$}`).
pub fn pad_left(s : String, width : Int32) -> String {
  let n = @support.char_count(s)
  if n >= width {
    s
  } else {
    " ".repeat(width - n) + s
  }
}

///|
/// Left-align `s` to `width` characters (`{:width$}`).
pub fn pad_right(s : String, width : Int32) -> String {
  let n = @support.char_count(s)
  if n >= width {
    s
  } else {
    s + " ".repeat(width - n)
  }
}

///|
/// `Display for Stats`.
pub impl Show for Stats with fn output(self, f) {
  let duration_us = self.total_duration / 1000L
  let success_rate = if self.total_parses > 0 {
    format_fixed2(
      self.successful_parses.to_double() / self.total_parses.to_double() * 100.0,
    ) +
    "%"
  } else {
    "N/A"
  }
  let duration_str = if self.total_parses == 0 {
    "N/A"
  } else if duration_us == 0L {
    "0 bytes/ms"
  } else {
    // `((self.total_bytes as u128) * 1_000) / duration_us` is q * 1000 + r,
    // which may exceed `u64::MAX`.
    let duration_us = duration_us.reinterpret_as_uint64()
    let q = self.total_bytes / duration_us
    let r = self.total_bytes % duration_us * 1000UL / duration_us
    if q == 0 {
      "\{r} bytes/ms"
    } else {
      let r = r.to_string()
      "\{q}\{"0".repeat(3 - r.length())}\{r} bytes/ms"
    }
  }
  f.write_string(
    "Total parses: \{self.total_parses}; successful parses: \{self.successful_parses}; failed parses: \{self.total_parses - self.successful_parses}; success percentage: \{success_rate}; average speed: \{duration_str}\n",
  )
}

///|
/// A `usize` serialized by serde_json.
fn usize_json(n : UInt64) -> Json {
  Json::number(n.to_double(), repr=n.to_string())
}

///|
fn duration_json(nanos : Int64) -> Json {
  {
    "secs": Json::number((nanos / 1000000000L).to_double()),
    "nanos": Json::number((nanos % 1000000000L).to_double()),
  }
}

///|
fn Stats::to_json(self : Stats) -> Json {
  {
    "successful_parses": usize_json(self.successful_parses),
    "total_parses": usize_json(self.total_parses),
    "total_bytes": usize_json(self.total_bytes),
    "total_duration": duration_json(self.total_duration),
  }
}

///|
/// Sets the colors used in the output of `tree-sitter parse --cst`.
pub(all) struct ParseTheme {
  node_kind : Color?
  node_text : Color?
  field : Color?
  row_color : Color?
  row_color_named : Color?
  extra : Color?
  error : Color?
  missing : Color?
  line_feed : Color?
  backtick : Color?
  literal : Color?
}

///|
pub fn ParseTheme::empty() -> ParseTheme {
  {
    node_kind: None,
    node_text: None,
    field: None,
    row_color: None,
    row_color_named: None,
    extra: None,
    error: None,
    missing: None,
    line_feed: None,
    backtick: None,
    literal: None,
  }
}

///|
pub fn ParseTheme::default() -> ParseTheme {
  {
    node_kind: Some(bright_cyan),
    node_text: Some(Rgb(118, 118, 118)),
    field: Some(blue),
    row_color: Some(white),
    row_color_named: Some(bright_cyan),
    extra: Some(bright_magenta),
    error: Some(red),
    missing: Some(Rgb(255, 153, 51)),
    line_feed: Some(Rgb(166, 172, 181)),
    backtick: Some(Rgb(101, 192, 67)),
    literal: Some(Rgb(219, 219, 173)),
  }
}

///|
/// `Rgb(pub u8, pub u8, pub u8)`.
priv struct ParseRgb(Int32, Int32, Int32)

///|
/// `#[derive(Deserialize)]` of the tuple struct `Rgb`.
fn ParseRgb::deserialize(
  de : @support.Deserializer,
) -> ParseRgb raise @support.SerdeJsonError {
  let expecting = "tuple struct Rgb with 3 elements"
  de.deserialize_tuple_struct("tuple struct Rgb", seq => {
    let u8 = @support.Deserializer::deserialize_u8
    let red = seq.next_field(u8, 0, expecting)
    let green = seq.next_field(u8, 1, expecting)
    let blue = seq.next_field(u8, 2, expecting)
    ParseRgb(red.to_int(), green.to_int(), blue.to_int())
  })
}

///|
fn deserialize_opt_rgb(
  de : @support.Deserializer,
) -> ParseRgb? raise @support.SerdeJsonError {
  de.deserialize_option(ParseRgb::deserialize)
}

///|
/// The fields of `ParseThemeRaw` (`rename_all = "kebab-case"`), in order.
let parse_theme_raw_fields : FixedArray[String] = [
  "node-kind", "node-text", "field", "row-color", "row-color-named", "extra", "error",
  "missing", "line-feed", "backtick", "literal",
]

///|
/// `#[derive(Deserialize)]` of `ParseThemeRaw`: its eleven `Option<Rgb>`
/// fields, in declaration order.
fn deserialize_parse_theme_raw(
  de : @support.Deserializer,
) -> Array[ParseRgb?] raise @support.SerdeJsonError {
  let expecting = "struct ParseThemeRaw with 11 elements"
  de.deserialize_struct(
    "struct ParseThemeRaw",
    seq => {
      let values = []
      for i in 0..<parse_theme_raw_fields.length() {
        values.push(seq.next_field(deserialize_opt_rgb, i, expecting))
      }
      values
    },
    map => {
      let fields : Array[@support.StructField[ParseRgb?]] = parse_theme_raw_fields
        .iter()
        .map(name => @support.StructField::new(name))
        .collect()
      while map.next_key() is Some(key) {
        match parse_theme_raw_fields.search(key) {
          Some(i) => fields[i].next_value(map, deserialize_opt_rgb)
          None => map.next_value_ignored()
        }
      }
      fields.map(field => field.optional())
    },
  )
}

///|
/// `#[derive(Deserialize)]` of `parse::Config { parse_theme:
/// Option<ParseThemeRaw> }`.
fn deserialize_parse_config(
  de : @support.Deserializer,
) -> Array[ParseRgb?]? raise @support.SerdeJsonError {
  let deserialize_parse_theme = (de : @support.Deserializer) => {
    de.deserialize_option(deserialize_parse_theme_raw)
  }
  de.deserialize_struct(
    "struct Config",
    seq => {
      seq.next_field(deserialize_parse_theme, 0, "struct Config with 1 element")
    },
    map => {
      let parse_theme : @support.StructField[Array[ParseRgb?]?] = @support.StructField::new(
        "parse-theme",
      )
      while map.next_key() is Some(key) {
        match key {
          "parse-theme" => parse_theme.next_value(map, deserialize_parse_theme)
          _ => map.next_value_ignored()
        }
      }
      parse_theme.optional()
    },
  )
}

///|
/// `Config::get::<parse::Config>()`, `.parse_theme.unwrap_or_default()`
/// and `From<ParseThemeRaw> for ParseTheme`: the `parse-theme` of
/// `config.json` over the default theme.
pub fn ParseTheme::from_config(
  config : @support.Value,
) -> ParseTheme raise CliError {
  let raw = @support.from_value(config, deserialize_parse_config) catch {
    e => raise anyhow(e.to_string())
  }
  let raw = raw.unwrap_or(Array::make(11, None))
  let default = ParseTheme::default()
  fn val_or_default(val : ParseRgb?, default : Color?) -> Color? {
    match val {
      Some(ParseRgb(r, g, b)) => Some(Rgb(r, g, b))
      None => default
    }
  }
  {
    node_kind: val_or_default(raw[0], default.node_kind),
    node_text: val_or_default(raw[1], default.node_text),
    field: val_or_default(raw[2], default.field),
    row_color: val_or_default(raw[3], default.row_color),
    row_color_named: val_or_default(raw[4], default.row_color_named),
    extra: val_or_default(raw[5], default.extra),
    error: val_or_default(raw[6], default.error),
    missing: val_or_default(raw[7], default.missing),
    line_feed: val_or_default(raw[8], default.line_feed),
    backtick: val_or_default(raw[9], default.backtick),
    literal: val_or_default(raw[10], default.literal),
  }
}

///|
pub(all) enum ParseOutput {
  Normal
  Quiet
  Xml
  Cst
  Dot
} derive(Eq)

///|
pub struct ParseSummary {
  file : String
  successful : Bool
  start : @treesitter.Point?
  end : @treesitter.Point?
  duration : Int64?
  bytes : Int32?
}

///|
fn point_json(p : @treesitter.Point?) -> Json {
  match p {
    Some(p) =>
      {
        "row": Json::number(p.row.to_double()),
        "column": Json::number(p.column.to_double()),
      }
    None => Json::null()
  }
}

///|
fn ParseSummary::to_json(self : ParseSummary) -> Json {
  {
    "file": Json::string(self.file),
    "successful": Json::boolean(self.successful),
    "start": point_json(self.start),
    "end": point_json(self.end),
    "duration": match self.duration {
      Some(d) => duration_json(d)
      None => Json::null()
    },
    "bytes": match self.bytes {
      Some(b) => Json::number(b.to_double())
      None => Json::null()
    },
  }
}

///|
pub struct ParseStats {
  parse_summaries : Array[ParseSummary]
  cumulative_stats : Stats
  mut source_count : Int32
}

///|
pub fn ParseStats::default() -> ParseStats {
  { parse_summaries: [], cumulative_stats: Stats::default(), source_count: 1, }
}

///|
pub fn ParseStats::to_json(self : ParseStats) -> Json {
  {
    "parse_summaries": Json::array(self.parse_summaries.map(s => s.to_json())),
    "cumulative_stats": self.cumulative_stats.to_json(),
    "source_count": Json::number(self.source_count.to_double()),
  }
}

///|
pub(all) enum ParseDebugType {
  Quiet
  Normal
  Pretty
} derive(Eq)

///|
/// `TSInputEncoding`.
pub(all) enum InputEncoding {
  Utf8
  Utf16LE
  Utf16BE
} derive(Eq)

///|
pub struct ParseFileOptions {
  edits : Array[String]
  output : ParseOutput
  stats : ParseStats
  print_time : Bool
  timeout : UInt64
  debug : ParseDebugType
  debug_graph : Bool
  encoding : InputEncoding?
  open_log : Bool
  no_ranges : Bool
  parse_theme : ParseTheme
}

///|
fn utf16_units(bytes : Bytes, big_endian : Bool) -> Array[UInt16] {
  let units = []
  let mut i = 0
  while i + 1 < bytes.length() {
    let (a, b) = (bytes[i].to_int(), bytes[i + 1].to_int())
    units.push(
      (if big_endian { (a << 8) | b } else { (b << 8) | a }).to_uint16(),
    )
    i += 2
  }
  units
}

///|
let pretty_debug_colors : Array[Color] = [
  white, red, blue, green, cyan, yellow, magenta, bright_white, bright_red, bright_blue,
  bright_green, bright_cyan, bright_yellow, bright_magenta,
]

///|
pub async fn parse_file_at_path(
  parser : @treesitter.Parser,
  language : @treesitter.Language,
  path : String,
  name : String,
  max_path_length : Int32,
  opts : ParseFileOptions,
) -> Unit {
  // Held for its `Drop` side effect: closed on every path out of this
  // function (after `stdout` is dropped, as upstream's locals are).
  let mut log_session : LogSession? = None
  defer (if log_session is Some(session) { session.close() })
  parser.set_language(language)
  let source_code = (@support.read_file(path) catch {
    e => raise with_context(e, "Error reading \{rust_debug_str(name)}")
  }).to_array()
  // Render an HTML graph if `--debug-graph` was passed
  if opts.debug_graph {
    log_session = Some(log_graphs(parser, "log.html", opts.open_log))
  } else if opts.debug != Quiet {
    // Log to stderr if `--debug` was passed
    let curr_version = Ref(0)
    let debug = opts.debug
    parser.set_logger(
      Some((log_type, message) => {
        if debug == Normal {
          if log_type is Lex {
            @support.print_err("  ")
          }
          @support.print_err("\{message}\n")
        } else {
          if message.has_prefix("process version:") {
            let comma_idx = message.find(",").unwrap()
            curr_version.val = @string.parse_int(
              message.view(start_offset=16, end_offset=comma_idx),
            ) catch {
              _ => 0
            }
          }
          let color = pretty_debug_colors[curr_version.val %
            pretty_debug_colors.length()]
          let prefix = if log_type is Lex { "  " } else { "" }
          @support.print_err("\{prefix}\{paint(Some(color), message)}\n")
        }
      }),
    )
  }
  let parse_time = @support.now_ns()
  let encoding = match opts.encoding {
    None if source_code.length() >= 2 =>
      if source_code[0] == 0xFF && source_code[1] == 0xFE {
        Some(Utf16LE)
      } else if source_code[0] == 0xFE && source_code[1] == 0xFF {
        Some(Utf16BE)
      } else {
        None
      }
    e => e
  }
  // If the `--time` flag was passed, end the parse after the specified
  // number of microseconds.
  let start_time = @support.now_ns()
  let timeout = opts.timeout
  let progress_callback = (_ : @treesitter.ParseState) => {
    if timeout > 0UL &&
      ((@support.now_ns() - start_time) / 1000L).reinterpret_as_uint64() >
      timeout {
      @treesitter.ControlFlow::Break
    } else {
      Continue
    }
  }
  let parse_opts = @treesitter.ParseOptions::new(progress_callback~)
  let source_bytes = Bytes::from_array(source_code)
  let tree = match encoding {
    Some(Utf16LE) => {
      let units = utf16_units(source_bytes, false)
      parser.parse_utf16_le_with_options(
        (i, _) => if i < units.length() { units[i:] } else { [][:] },
        options=parse_opts,
      )
    }
    Some(Utf16BE) => {
      let units = utf16_units(source_bytes, true)
      parser.parse_utf16_be_with_options(
        (i, _) => if i < units.length() { units[i:] } else { [][:] },
        options=parse_opts,
      )
    }
    _ =>
      parser.parse_with_options(
        (i, _) => {
          if i < source_bytes.length() {
            source_bytes[i:]
          } else {
            b""[:]
          }
        },
        options=parse_opts,
      )
  }
  let parse_duration = @support.now_ns() - parse_time
  let stdout = @support.BufWriter::stdout(capacity=64 * 1024)
  defer stdout.drop()
  if tree is Some(tree) {
    let mut tree = tree
    let source_code = source_code
    if opts.debug_graph && !opts.edits.is_empty() {
      log_info(
        "BEFORE:\n\{@support.utf8_lossy(Bytes::from_array(source_code))}",
      )
    }
    let edit_time = @support.now_ns()
    for i, edit in opts.edits {
      let edit = parse_edit_flag(source_code, edit)
      perform_flag_edit(tree, source_code, edit)
      tree = match parser.parse(Bytes::from_array(source_code), old_tree=tree) {
        Some(tree) => tree
        None =>
          @support.rust_panic(
            "called `Option::unwrap()` on a `None` value", "crates/cli/src/parse.rs:445:60",
          )
      }
      if opts.debug_graph {
        log_info(
          "AFTER \{i}:\n\{@support.utf8_lossy(Bytes::from_array(source_code))}",
        )
      }
    }
    let edit_duration = @support.now_ns() - edit_time
    parser.stop_printing_dot_graphs()
    let source_bytes = Bytes::from_array(source_code)
    let parse_duration_ms = (parse_duration / 1000L).to_double() / 1.0e3
    let edit_duration_ms = (edit_duration / 1000L).to_double() / 1.0e3
    let cursor = tree.walk()
    if opts.output == Normal {
      let mut needs_newline = false
      let mut indent_level = 0
      let mut did_visit_children = false
      for ;; {
        let node = cursor.node()
        let is_named = node.is_named()
        if did_visit_children {
          if is_named {
            stdout.write_string(")")
            needs_newline = true
          }
          if cursor.goto_next_sibling() {
            did_visit_children = false
          } else if cursor.goto_parent() {
            did_visit_children = true
            indent_level -= 1
          } else {
            break
          }
        } else {
          if is_named {
            if needs_newline {
              stdout.write_string("\n")
            }
            for _ in 0..<indent_level {
              stdout.write_string("  ")
            }
            let start = node.start_position()
            let end = node.end_position()
            if cursor.field_name() is Some(field_name) {
              stdout.write_string("\{field_name}: ")
            }
            stdout.write_string("(\{node.kind()}")
            if !opts.no_ranges {
              stdout.write_string(
                " [\{start.row}, \{start.column}] - [\{end.row}, \{end.column}]",
              )
            }
            needs_newline = true
          }
          if cursor.goto_first_child() {
            did_visit_children = false
            indent_level += 1
          } else {
            did_visit_children = true
          }
        }
      }
      cursor.reset(tree.root_node())
      stdout.write_string("\n")
    }
    if opts.output == Cst {
      render_cst(source_bytes, tree, cursor, opts, stdout)
    }
    if opts.output == Xml {
      let mut needs_newline = false
      let mut indent_level = 2
      let mut did_visit_children = false
      let mut had_named_children = false
      let tags : Array[String] = []
      // If we're parsing the first file, write the header
      if opts.stats.parse_summaries.is_empty() {
        stdout.write_string("<?xml version=\"1.0\"?>\n")
        stdout.write_string("<sources>\n")
      }
      stdout.write_string("  <source name=\"\{path}\">\n")
      for ;; {
        let node = cursor.node()
        let is_named = node.is_named()
        if did_visit_children {
          if is_named {
            let tag = tags.pop()
            if had_named_children {
              for _ in 0..<indent_level {
                stdout.write_string("  ")
              }
            }
            stdout.write_string("</\{tag.unwrap()}>")
            // we only write a line in the case where it's the last sibling
            if node.parent() is Some(parent) &&
              parent.child(parent.child_count() - 1).unwrap() == node {
              stdout.write_string("\n")
            }
            needs_newline = true
          }
          if cursor.goto_next_sibling() {
            did_visit_children = false
            had_named_children = false
          } else if cursor.goto_parent() {
            did_visit_children = true
            had_named_children = is_named
            indent_level -= 1
            if !is_named && needs_newline {
              stdout.write_string("\n")
              for _ in 0..<indent_level {
                stdout.write_string("  ")
              }
            }
          } else {
            break
          }
        } else {
          if is_named {
            if needs_newline {
              stdout.write_string("\n")
            }
            for _ in 0..<indent_level {
              stdout.write_string("  ")
            }
            stdout.write_string("<\{node.kind()}")
            if cursor.field_name() is Some(field_name) {
              stdout.write_string(" field=\"\{field_name}\"")
            }
            let start = node.start_position()
            let end = node.end_position()
            stdout.write_string(
              " srow=\"\{start.row}\" scol=\"\{start.column}\" erow=\"\{end.row}\" ecol=\"\{end.column}\">",
            )
            tags.push(node.kind())
            needs_newline = true
          }
          if cursor.goto_first_child() {
            did_visit_children = false
            had_named_children = false
            indent_level += 1
          } else {
            did_visit_children = true
            let start = node.start_byte()
            let end = node.end_byte()
            // `std::str::from_utf8(..).expect("has a string")`
            let value = source_bytes[start:end]
            if @support.utf8_error_debug(value) is Some(error) {
              @support.rust_panic(
                "has a string: \{error}",
                "crates/cli/src/parse.rs:599:75",
              )
            }
            let value = @support.utf8_lossy(value)
            if !is_named && needs_newline {
              stdout.write_string("\n")
              for _ in 0..<indent_level {
                stdout.write_string("  ")
              }
            }
            stdout.write_string(html_encode_text(value))
          }
        }
      }
      stdout.write_string("\n")
      stdout.write_string("  </source>\n")
      // If we parsed the last file, write the closing tag for the `sources`
      // header
      if opts.stats.parse_summaries.length() == opts.stats.source_count - 1 {
        stdout.write_string("</sources>\n")
      }
      cursor.reset(tree.root_node())
    }
    if opts.output == Dot {
      print_tree_graph(tree, "log.html", opts.open_log) catch {
        e =>
          @support.rust_panic(
            "called `Result::unwrap()` on an `Err` value: \{CliError(error_chain(e)).debug()}",
            "crates/cli/src/parse.rs:621:70",
          )
      }
    }
    let first_error = find_first_error(cursor)
    if first_error is Some(_) || opts.print_time {
      let bytes_per_ms = if parse_duration > 0L {
        (source_code.length().to_int64() * 1000000L / parse_duration).to_string()
      } else {
        "0"
      }
      stdout.write_string(
        "\{pad_right(name, max_path_length)}\tParse: \{pad_left(format_fixed2(parse_duration_ms), 7)} ms\t\{pad_left(bytes_per_ms, 6)} bytes/ms",
      )
      if first_error is Some(node) {
        let node_kind = node.kind()
        let node_text = StringBuilder()
        for c in node_kind {
          match escape_invisible(c) {
            Some(escaped) => node_text.write_string(escaped)
            None => node_text.write_char(c)
          }
        }
        let node_text = node_text.to_string()
        stdout.write_string("\t(")
        if node.is_missing() {
          if node.is_named() {
            stdout.write_string("MISSING \{node_text}")
          } else {
            stdout.write_string("MISSING \"\{node_text}\"")
          }
        } else {
          stdout.write_string(node_text)
        }
        let start = node.start_position()
        let end = node.end_position()
        stdout.write_string(
          " [\{start.row}, \{start.column}] - [\{end.row}, \{end.column}])",
        )
      }
      if !opts.edits.is_empty() {
        stdout.write_string(
          "\n\{pad_right(" ".repeat(@support.utf8_len(path)), max_path_length)}\tEdit:  \{pad_left(format_fixed2(edit_duration_ms), 7)} ms",
        )
      }
      stdout.write_string("\n")
    }
    opts.stats.parse_summaries.push({
      file: path,
      successful: first_error is None,
      start: Some(tree.root_node().start_position()),
      end: Some(tree.root_node().end_position()),
      duration: Some(parse_duration),
      bytes: Some(source_code.length()),
    })
    return
  }
  parser.stop_printing_dot_graphs()
  if opts.print_time {
    let duration = @support.now_ns() - parse_time
    let duration_ms = (duration / 1000L).to_double() / 1.0e3
    stdout.write_string(
      "\{pad_right(path, max_path_length)}\tParse: \{pad_left(format_fixed2(duration_ms), 7)} ms\t(timed out)\n",
    )
  }
  opts.stats.parse_summaries.push({
    file: path,
    successful: false,
    start: None,
    end: None,
    duration: None,
    bytes: Some(source_code.length()),
  })
}

///|
/// The first `ERROR` or `MISSING` node, walking as upstream does.
fn find_first_error(cursor : @treesitter.TreeCursor) -> @treesitter.Node? {
  let mut first_error = None
  let mut earliest_node_with_error = None
  while true {
    let node = cursor.node()
    if node.has_error() {
      if earliest_node_with_error is None {
        earliest_node_with_error = Some(node)
      }
      if node.is_error() || node.is_missing() {
        first_error = Some(node)
        break
      }
      // If there's no more children, even though some outer node has an
      // error, then that means that the first error is hidden, but the later
      // error could be visible. So, we walk back up to the child of the
      // first node with an error, and then check its siblings for errors.
      if !cursor.goto_first_child() {
        let earliest = earliest_node_with_error.unwrap()
        let mut continue_outer = false
        while cursor.goto_parent() {
          if cursor.node().parent() is Some(p) && p == earliest {
            while cursor.goto_next_sibling() {
              let sibling = cursor.node()
              if sibling.is_error() || sibling.is_missing() {
                return Some(sibling)
              }
              if sibling.has_error() && cursor.goto_first_child() {
                continue_outer = true
                break
              }
            }
            break
          }
        }
        if continue_outer {
          continue
        }
        break
      }
    } else if !cursor.goto_next_sibling() {
      break
    }
  }
  first_error
}

///|
/// `html_escape::encode_text`.
fn html_encode_text(s : String) -> String {
  let sb = StringBuilder()
  for c in s {
    match c {
      '&' => sb.write_string("&amp;")
      '<' => sb.write_string("&lt;")
      '>' => sb.write_string("&gt;")
      _ => sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
fn escape_invisible(c : Char) -> String? {
  match c {
    '\n' => Some("\\n")
    '\r' => Some("\\r")
    '\t' => Some("\\t")
    '\u{0}' => Some("\\0")
    '\\' => Some("\\\\")
    '\u{b}' => Some("\\v")
    '\u{c}' => Some("\\f")
    _ => None
  }
}

///|
fn escape_delimiter(c : Char) -> String? {
  match c {
    '`' => Some("\\`")
    '"' => Some("\\\"")
    _ => None
  }
}

///|
/// `checked_ilog10(n).unwrap_or(0)`.
fn ilog10_or_zero(n : Int32) -> Int32 {
  let mut n = n
  let mut result = 0
  while n >= 10 {
    n /= 10
    result += 1
  }
  result
}

///|
/// `str::lines` over the lossy source, with each line's UTF-8 length.
fn line_lengths(text : String) -> Array[Int32] {
  rust_lines(text).map(@support.utf8_len)
}

///|
pub fn render_cst(
  source_code : Bytes,
  tree : @treesitter.Tree,
  cursor : @treesitter.TreeCursor,
  opts : ParseFileOptions,
  out : @support.BufWriter,
) -> Unit raise {
  let lossy_source_code = @support.utf8_lossy(source_code)
  let mut total_width = 0
  let mut any_line = false
  for row, len in line_lengths(lossy_source_code) {
    any_line = true
    total_width = total_width.max(ilog10_or_zero(row) + ilog10_or_zero(len) + 1)
  }
  if !any_line {
    total_width = 1
  }
  let mut indent_level = if opts.no_ranges { 0 } else { 1 }
  let mut did_visit_children = false
  let mut in_error = false
  for ;; {
    if did_visit_children {
      if cursor.goto_next_sibling() {
        did_visit_children = false
      } else if cursor.goto_parent() {
        did_visit_children = true
        indent_level -= 1
        if !cursor.node().has_error() {
          in_error = false
        }
      } else {
        break
      }
    } else {
      cst_render_node(
        opts, cursor, source_code, out, total_width, indent_level, in_error,
      )
      if cursor.goto_first_child() {
        did_visit_children = false
        indent_level += 1
        if cursor.node().has_error() {
          in_error = true
        }
      } else {
        did_visit_children = true
      }
    }
  }
  cursor.reset(tree.root_node())
}

///|
/// `Display for CstNodeText`.
fn cst_node_text(s : String) -> String {
  let sb = StringBuilder()
  for c in s {
    match escape_invisible(c) {
      Some(esc) => sb.write_string(esc)
      None =>
        match escape_delimiter(c) {
          Some(esc) => sb.write_string(esc)
          None => sb.write_char(c)
        }
    }
  }
  sb.to_string()
}

///|
/// `Display for CstLineFeed`.
fn cst_line_feed(source : String, opts : ParseFileOptions) -> String {
  let painted = paint(opts.parse_theme.line_feed, cst_node_text("\n"))
  let parts = source.split("\n").map(p => p.to_owned()).collect()
  let sb = StringBuilder()
  sb.write_string(cst_node_text(parts[0]))
  for part in parts[1:] {
    sb.write_string(painted)
    sb.write_string(cst_node_text(part))
  }
  sb.to_string()
}

///|
/// `Display for CstNodeRange`.
fn cst_node_range(
  opts : ParseFileOptions,
  has_field_name : Bool,
  is_named : Bool,
  is_multiline : Bool,
  total_width : Int32,
  range : @treesitter.Range,
) -> String {
  let start = range.start_point
  let end = range.end_point
  let range_color = if is_named && !is_multiline && !has_field_name {
    opts.parse_theme.row_color_named
  } else {
    opts.parse_theme.row_color
  }
  let remaining_width = (row : Int32, col : Int32) => {
    let w = total_width - ilog10_or_zero(row) - ilog10_or_zero(col)
    if w < 1 {
      1
    } else {
      w
    }
  }
  let ws = remaining_width(start.row, start.column)
  let we = remaining_width(end.row, end.column)
  paint(
    range_color,
    "\{start.row}:\{start.column}\{" ".repeat(ws)}- \{end.row}:\{end.column}\{" ".repeat(we)}",
  )
}

///|
fn write_node_text(
  opts : ParseFileOptions,
  out : @support.BufWriter,
  cursor : @treesitter.TreeCursor,
  is_named : Bool,
  source : String,
  color : Color?,
  total_width : Int32,
  indent_level : Int32,
) -> Unit raise {
  let (quote, quote_color) = if is_named {
    ("`", opts.parse_theme.backtick)
  } else {
    ("\"", color)
  }
  if !is_named {
    out.write_string(
      "\{paint(quote_color, quote)}\{paint(color, cst_node_text(source))}\{paint(quote_color, quote)}",
    )
  } else {
    let multiline = source.contains("\n")
    for i, line in split_inclusive_newline(source) {
      if line.is_empty() {
        break
      }
      let node_range = cursor.node().range()
      // For each line of text, adjust the row by shifting it down `i` rows,
      // and adjust the column by setting it to the length of *this* line.
      let start_row = node_range.start_point.row + i
      let end_column = @support.utf8_len(line) +
        (if i == 0 { node_range.start_point.column } else { 0 })
      let node_range = {
        ..node_range,
        start_point: { ..node_range.start_point, row: start_row, },
        end_point: { row: start_row, column: end_column, },
      }
      if multiline {
        out.write_string("\n")
        if !opts.no_ranges {
          out.write_string(
            cst_node_range(
              opts,
              cursor.field_name() is Some(_),
              is_named,
              true,
              total_width,
              node_range,
            ),
          )
        }
        for _ in 0..<=indent_level {
          out.write_string("  ")
        }
      } else {
        out.write_string(" ")
      }
      out.write_string(
        "\{paint(quote_color, quote)}\{paint(color, cst_line_feed(line, opts))}\{paint(quote_color, quote)}",
      )
    }
  }
}

///|
fn cst_render_node(
  opts : ParseFileOptions,
  cursor : @treesitter.TreeCursor,
  source_code : Bytes,
  out : @support.BufWriter,
  total_width : Int32,
  indent_level : Int32,
  in_error : Bool,
) -> Unit raise {
  let node = cursor.node()
  let is_named = node.is_named()
  if !opts.no_ranges {
    out.write_string(
      cst_node_range(
        opts,
        cursor.field_name() is Some(_),
        is_named,
        false,
        total_width,
        node.range(),
      ),
    )
  }
  out.write_string("  ".repeat(indent_level))
  if in_error && !node.has_error() {
    out.write_string(" ")
  }
  if is_named {
    if cursor.field_name() is Some(field_name) {
      out.write_string(paint(opts.parse_theme.field, "\{field_name}: "))
    }
    if node.has_error() || node.is_error() {
      out.write_string(paint(opts.parse_theme.error, "•"))
    }
    let kind_color = if node.is_error() {
      opts.parse_theme.error
    } else if node.is_extra() ||
      (node.parent() is Some(p) && p.is_extra() && !p.is_error()) {
      opts.parse_theme.extra
    } else {
      opts.parse_theme.node_kind
    }
    out.write_string(paint(kind_color, node.kind()))
    if node.child_count() == 0 {
      // Node text from a pattern or external scanner
      write_node_text(
        opts,
        out,
        cursor,
        is_named,
        @support.utf8_lossy(source_code[node.start_byte():node.end_byte()]),
        opts.parse_theme.node_text,
        total_width,
        indent_level,
      )
    }
  } else if node.is_missing() {
    out.write_string("\{paint(opts.parse_theme.missing, "MISSING")}: ")
    out.write_string("\"\{paint(opts.parse_theme.missing, node.kind())}\"")
  } else {
    // Terminal literals, like "fn"
    write_node_text(
      opts,
      out,
      cursor,
      is_named,
      node.kind(),
      opts.parse_theme.literal,
      total_width,
      indent_level,
    )
  }
  out.write_string("\n")
}

///|
/// `fuzz::edits::Edit` as `parse_edit_flag` makes it: `usize` offsets
/// (`UInt64`), which `perform_flag_edit` checks before converting.
priv struct FlagEdit {
  position : UInt64
  deleted_length : UInt64
  inserted_text : Array[Byte]
}

///|
fn parse_edit_flag(
  source_code : Array[Byte],
  flag : String,
) -> FlagEdit raise CliError {
  let error = () => {
    anyhow(
      "Invalid edit string '\{flag}'. Edit strings must match the pattern '<START_BYTE_OR_POSITION> <REMOVED_LENGTH> <NEW_TEXT>'",
    )
  }
  // Three whitespace-separated parts: edit position, deleted length,
  // inserted text.
  let parts = flag.split(" ").map(p => p.to_owned()).collect()
  guard parts.length() >= 2 else { raise error() }
  let position = parts[0]
  let deleted_length = parts[1]
  let inserted_text = @support.utf8(parts[2:].to_owned().join(" ")).to_array()
  // Position can either be a byte_offset or row,column pair, separated by a
  // comma
  let position = if position == "$" {
    source_code.length().to_uint64()
  } else if position.contains(",") {
    let ps = position.split(",").map(p => p.to_owned()).collect()
    let row = @cli_test.parse_usize(ps[0]).or_raise(error())
    guard ps.length() >= 2 else { raise error() }
    let column = @cli_test.parse_usize(ps[1]).or_raise(error())
    offset_for_usize_position(source_code, row, column).to_uint64()
  } else {
    @cli_test.parse_usize(position).or_raise(error())
  }
  // Deleted length must be a byte count.
  let deleted_length = @cli_test.parse_usize(deleted_length).or_raise(error())
  { position, deleted_length, inserted_text, }
}

///|
/// `perform_edit(tree, input, edit)` for an edit of `parse_edit_flag`: the
/// endpoints are computed with `usize` arithmetic (wrapping, as in release
/// builds) and checked as upstream's `position_for_offset` and
/// `Vec::splice` check them, before the input or the tree changes.
fn perform_flag_edit(
  tree : @treesitter.Tree,
  input : Array[Byte],
  edit : FlagEdit,
) -> Unit raise {
  let (start_byte, deleted_length) = check_flag_edit(input.length(), edit)
  ignore(
    @cli_test.perform_edit(tree, input, {
      position: start_byte,
      deleted_length,
      inserted_text: edit.inserted_text,
    }),
  )
}

///|
/// The checks of `perform_edit` for an input of `len` bytes, before it
/// changes: the start byte and the deleted length.
fn check_flag_edit(len : Int32, edit : FlagEdit) -> (Int32, Int32) raise {
  let len = len.to_uint64()
  let start_byte = edit.position
  let old_end_byte = edit.position + edit.deleted_length
  if start_byte > len {
    raise @cli_test.ParseError("Failed to address an offset: \{start_byte}")
  }
  if old_end_byte > len {
    raise @cli_test.ParseError("Failed to address an offset: \{old_end_byte}")
  }
  if start_byte > old_end_byte {
    // `input.splice(start_byte..old_end_byte, ..)` (`slice::range`)
    @support.rust_panic(
      "slice index starts at \{start_byte} but ends at \{old_end_byte}",
      "/rustc/8bab26f4f68e0e26f0bb7960be334d5b520ea452/library/core/src/slice/index.rs:1031:55",
    )
  }
  (start_byte.to_int(), edit.deleted_length.to_int())
}

///|
fn[T] Option::or_raise(self : T?, err : CliError) -> T raise CliError {
  match self {
    Some(v) => v
    None => raise err
  }
}

///|
pub fn offset_for_position(
  input : Array[Byte],
  position : @treesitter.Point,
) -> Int32 raise CliError {
  offset_for_usize_position(
    input,
    position.row.to_uint64(),
    position.column.to_uint64(),
  )
}

///|
/// `offset_for_position` for a `Point` of `usize` coordinates.
fn offset_for_usize_position(
  input : Array[Byte],
  row : UInt64,
  column : UInt64,
) -> Int32 raise CliError {
  let mut current_row = 0UL
  let mut line_start = 0
  for line_end, b in input {
    if b != b'\n' {
      continue
    }
    if current_row == row {
      if column > (line_end - line_start).to_uint64() {
        raise anyhow("Failed to address a column: \{column}")
      }
      return line_start + column.to_int()
    }
    current_row += 1
    line_start = line_end + 1
  }
  if current_row != row {
    raise anyhow("Failed to address a row: \{row}")
  }
  if column > (input.length() - line_start).to_uint64() {
    raise anyhow("Failed to address a column over the end")
  }
  line_start + column.to_int()
}
