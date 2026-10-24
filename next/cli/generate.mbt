// Port of the file-system entry points of tree-sitter
// crates/generate/src/generate.rs (`generate_parser_in_directory`,
// `load_grammar_file`, `load_js_grammar_file`), which the `generate` command
// drives. The table generation itself is next/generate. In addition to
// upstream's outputs, `generate` writes the portable language tables to
// `src/language.json`, which the loader uses instead of compiling `parser.c`,
// and accepts grammars written as `.mbtx` MoonBit programs.

///|
/// `GenerateError`, carrying its display text and serde variant name.
pub(all) suberror GenerateError {
  GenerateError(variant~ : String, message~ : String)
}

///|
pub impl Show for GenerateError with output(self, logger) {
  let GenerateError(message~, ..) = self
  logger.write_string(message)
}

///|
fn gen_error(variant : String, message : String) -> GenerateError {
  GenerateError(variant~, message~)
}

///|
/// The serde variant name of a generation error of next/generate, for the
/// `--json-summary` envelope.
fn generate_error_variant(e : Error) -> String {
  let message = error_message(e)
  if message.has_prefix("Unresolved conflict") ||
    message.contains("conflict") {
    "BuildTables"
  } else if message.has_prefix("Failed to parse grammar") {
    "ParseGrammar"
  } else {
    "Prepare"
  }
}

///|
/// `generate_parser_in_directory`.
pub async fn generate_parser_in_directory(
  repo_path : String,
  out_path : String?,
  grammar_path : String?,
  abi_version : Int,
  report_symbol_name : String?,
  js_runtime : String?,
  generate_parser : Bool,
  optimizations : @generate.OptLevel,
  diagnostics : Array[@generate.Diagnostic],
) -> Unit {
  let mut repo_path = repo_path
  // Populate a new empty grammar directory.
  let grammar_path = match grammar_path {
    Some(path_buf) =>
      if !@fs.exists(path_buf) {
        // A nonexistent path with an extension (i.e.
        // tree-sitter-foo/grammar.json) is a missing input file, not a
        // directory to create.
        if @support.extension(path_buf) is Some(_) {
          raise gen_error(
            "GrammarFileNotFound",
            "Grammar file `\{path_buf}` not found",
          )
        }
        @fs.mkdir(path_buf, recursive=true) catch {
          e =>
            raise gen_error(
              "IO",
              @support.io_error_with_path(e, Some(path_buf)),
            )
        }
        repo_path = path_buf
        @support.path_join(repo_path, "grammar.js")
      } else {
        // Given an _explicit_ path to an input file, derive the repo root
        // from the conventional locations:
        //     - grammar.js (or grammar.mbtx) sits inside <root>/
        //     - grammar.json sits inside <root>/src/
        let repo_root = match @support.extension(path_buf) {
          Some("js") | Some("mbtx") => @support.parent(path_buf)
          Some("json") =>
            match @support.parent(path_buf) {
              Some(p) => @support.parent(p)
              None => None
            }
          _ => None
        }
        if repo_root is Some(root) {
          repo_path = root
        }
        path_buf
      }
    None => {
      // The MoonBit port also accepts a `grammar.mbtx` program in place of
      // `grammar.js`.
      let js = @support.path_join(repo_path, "grammar.js")
      let mbtx = @support.path_join(repo_path, "grammar.mbtx")
      if !@fs.exists(js) && @fs.exists(mbtx) {
        mbtx
      } else {
        js
      }
    }
  }
  // Read the grammar file.
  let grammar_json = load_grammar_file(grammar_path, js_runtime, repo_path)
  let src_path = match out_path {
    Some(p) => p
    None => @support.path_join(repo_path, "src")
  }
  let header_path = @support.path_join(src_path, "tree_sitter")
  // Ensure that the output directory exists
  @fs.mkdir(src_path, recursive=true) catch {
    e => raise gen_error("IO", @support.io_error_with_path(e, Some(src_path)))
  }
  if @support.file_name(grammar_path) != Some("grammar.json") {
    @fs.write_file(
      @support.path_join(src_path, "grammar.json"),
      grammar_json,
      create_mode=CreateOrTruncate,
    ) catch {
      e => raise gen_error("IO", @support.io_error_with_path(e, Some(src_path)))
    }
  }
  // If our job is only to generate `grammar.json` and not `parser.c`, stop
  // here.
  let input_grammar = @generate.parse_grammar(grammar_json, diagnostics) catch {
    e => raise gen_error(generate_error_variant(e), error_message(e))
  }
  if !generate_parser {
    ignore(input_grammar)
    let node_types_json = @generate.generate_node_types_for_grammar(
      grammar_json, [],
    ) catch {
      e => raise gen_error(generate_error_variant(e), error_message(e))
    }
    write_file(@support.path_join(src_path, "node-types.json"), node_types_json)
    return
  }
  let semantic_version = @loader.read_grammar_version(repo_path) catch {
    e => raise gen_error("ParseVersion", error_message(e))
  }
  // Generate the parser and related files.
  let generated = @generate.generate_parser_for_grammar_with_opts(
    input_grammar, abi_version, semantic_version, report_symbol_name, optimizations,
    diagnostics,
  ) catch {
    e => raise gen_error(generate_error_variant(e), error_message(e))
  }
  write_file(@support.path_join(src_path, "parser.c"), generated.c_code)
  write_file(
    @support.path_join(src_path, "node-types.json"),
    generated.node_types_json,
  )
  write_file(
    @support.path_join(src_path, "language.json"),
    generated.language.to_json().stringify(),
  )
  @fs.mkdir(header_path, recursive=true) catch {
    e =>
      raise gen_error("IO", @support.io_error_with_path(e, Some(header_path)))
  }
  write_file(@support.path_join(header_path, "alloc.h"), alloc_header)
  write_file(@support.path_join(header_path, "array.h"), array_header)
  write_file(@support.path_join(header_path, "parser.h"), parser_header)
}

///|
/// `write_file`.
async fn write_file(path : String, body : String) -> Unit {
  @fs.write_file(path, body, create_mode=CreateOrTruncate) catch {
    e => raise gen_error("IO", @support.io_error_with_path(e, Some(path)))
  }
}

///|
/// `load_grammar_file`.
pub async fn load_grammar_file(
  grammar_path : String,
  js_runtime : String?,
  current_dir : String,
) -> String {
  if (@fs.kind(grammar_path) catch { _ => @fs.FileKind::Unknown }) is Directory {
    raise gen_error(
      "LoadGrammarFile",
      "Path to a grammar file with `.js` or `.json` extension is required",
    )
  }
  match @support.extension(grammar_path) {
    Some("js") =>
      load_js_grammar_file(grammar_path, js_runtime) catch {
        e =>
          raise gen_error(
            "LoadGrammarFile",
            "Failed to load grammar.js -- \{error_message(e)}",
          )
      }
    Some("json") =>
      @fs.read_file(grammar_path).text() catch {
        e =>
          raise gen_error(
            "LoadGrammarFile",
            "Failed to load grammar.json -- \{@support.io_error_with_path(e, Some(grammar_path))}",
          )
      }
    Some("mbtx") => {
      let output = @loader.run_grammar_script(grammar_path, current_dir) catch {
        e =>
          raise gen_error(
            "LoadGrammarFile",
            "Failed to load grammar.mbtx -- \{error_message(e)}",
          )
      }
      let json = @support.parse_json(output) catch {
        e =>
          raise gen_error(
            "LoadGrammarFile",
            "Failed to load grammar.mbtx -- Failed to serialize grammar JSON -- \{@config.json_error_message(e)}",
          )
      }
      @support.to_string_pretty(json)
    }
    _ =>
      raise gen_error(
        "LoadGrammarFile",
        "Unknown grammar file extension: \{@loader.rust_debug_str(grammar_path)}",
      )
  }
}

///|
/// `load_js_grammar_file`: run the grammar with a JavaScript runtime and the
/// grammar DSL. (QuickJS, `--js-runtime native`, is not available.)
async fn load_js_grammar_file(
  grammar_path : String,
  js_runtime : String?,
) -> String {
  let grammar_path = @fs.realpath(grammar_path) catch {
    e => raise anyhow(@support.io_error_with_path(e, Some(grammar_path)))
  }
  let js_runtime = js_runtime.unwrap_or("node")
  let args = match js_runtime {
    "node" => ["--input-type=module", "-"]
    "bun" => ["-"]
    "deno" => ["run", "--allow-all", "-"]
    _ => []
  }
  let (major, minor, patch) = (0, 28, 0)
  let script = "globalThis.TREE_SITTER_CLI_VERSION_MAJOR = \{major};\n         globalThis.TREE_SITTER_CLI_VERSION_MINOR = \{minor};\n         globalThis.TREE_SITTER_CLI_VERSION_PATCH = \{patch};" +
    dsl_js
  let temp = @support.path_join(@support.temp_dir(), ".tree-sitter-dsl.mjs")
  @fs.write_file(temp, script, create_mode=CreateOrTruncate)
  let (code, stdout, _) = @process.collect_output(
    js_runtime,
    args,
    extra_env=Map::from_array([("TREE_SITTER_GRAMMAR_PATH", grammar_path)]),
    stdin=@process.redirect_from_file(temp),
  ) catch {
    e => {
      ignore(@fs.remove(temp) catch { _ => () })
      raise anyhow(
        "Failed to run `\{js_runtime}` -- \{@support.io_error_message(e)}",
      )
    }
  }
  ignore(@fs.remove(temp) catch { _ => () })
  if code != 0 {
    raise anyhow("`\{js_runtime}` process exited with status \{code}")
  }
  let stdout = @support.utf8_strict(stdout.binary()) catch {
    _ => None
  }
  guard stdout is Some(stdout) else {
    raise anyhow("Got invalid UTF8 from `\{js_runtime}` -- invalid utf-8")
  }
  let mut grammar_json = stdout
  match stdout.rev_find("\n") {
    Some(pos) => {
      // If there's a newline, split the last line from the rest of the
      // output
      let node_output = stdout.unsafe_substring(start=0, end=pos)
      grammar_json = stdout.unsafe_substring(start=pos + 1, end=stdout.length())
      @support.print_out(node_output + "\n")
    }
    None => ()
  }
  let json = @support.parse_json(grammar_json) catch {
    e =>
      raise anyhow(
        "Failed to serialize grammar JSON -- \{@config.json_error_message(e)}",
      )
  }
  @support.to_string_pretty(json)
}
