// Port of tree-sitter crates/cli/src/tags.rs.

///|
pub struct TagsOptions {
  scope : String?
  quiet : Bool
  print_time : Bool
}

///|
/// Rust's `{:<width}`: left-align to `width` characters.
fn left(s : String, width : Int) -> String {
  pad_right(s, width)
}

///|
pub async fn generate_tags(
  path : String,
  name : String,
  config : @tags.TagsConfiguration,
  indent : Bool,
  opts : TagsOptions,
) -> Unit {
  let context = @tags.TagsContext::new()
  let stdout = StringBuilder()
  let indent_str = if indent {
    if !opts.quiet {
      stdout.write_string("\{name}\n")
    }
    "\t"
  } else {
    ""
  }
  let source = @fs.read_file(path).binary()
  let start = @support.now_ns()
  let (tags, _) = context.generate_tags(config, source)
  for tag in tags.iter() {
    let tag = match tag {
      Ok(tag) => tag
      Err(e) => {
        @support.print_out(stdout.to_string())
        raise e
      }
    }
    if !opts.quiet {
      let text = (range : (Int, Int)) => @support.utf8_strict(
          source[range.0:range.1],
        ).unwrap_or("")
      stdout.write_string(
        "\{indent_str}\{left(text(tag.name_range), 10)}\t | \{left(config.syntax_type_name(tag.syntax_type_id), 8)}\t\{if tag.is_definition { "def" } else { "ref" }} \{tag.span.0} - \{tag.span.1} `\{text(tag.line_range)}`",
      )
      if tag.docs is Some(docs) {
        if @support.utf8_len(docs) > 120 {
          stdout.write_string(
            "\t\{@loader.rust_debug_str(utf8_prefix(docs, 120))}...",
          )
        } else {
          stdout.write_string("\t\{@loader.rust_debug_str(docs)}")
        }
      }
      stdout.write_string("\n")
    }
  }
  if opts.print_time {
    stdout.write_string(
      "\{indent_str}time: \{(@support.now_ns() - start) / 1000000L}ms\n",
    )
  }
  @support.print_out(stdout.to_string())
}

///|
/// `str::get(0..n).unwrap_or("")`: the first `n` UTF-8 bytes, or `""` when
/// `n` is not a character boundary.
fn utf8_prefix(s : String, n : Int) -> String {
  let mut bytes = 0
  let sb = StringBuilder()
  for c in s {
    if bytes == n {
      return sb.to_string()
    }
    let len = @support.utf8_len(c.to_string())
    if bytes + len > n {
      return ""
    }
    bytes += len
    sb.write_char(c)
  }
  sb.to_string()
}
