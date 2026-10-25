// Port of the file-system entry points of tree-sitter
// crates/generate/src/generate.rs (`generate_parser_in_directory`,
// `load_grammar_file`, `load_js_grammar_file`), which the `generate` command
// drives. The table generation itself is generate. In addition to
// upstream's outputs, `generate` writes the portable language tables to
// `src/language.json`, which the loader uses instead of compiling `parser.c`,
// and accepts grammars written as `.mbtx` MoonBit programs.

///|
/// `GenerateError`: its `Display` text and its `Serialize` form (for the
/// `--json-summary` envelope; enums are externally tagged).
pub(all) suberror GenerateError {
  GenerateError(json~ : Json, message~ : String)
}

///|
pub impl Show for GenerateError with fn output(self, logger) {
  let GenerateError(message~, ..) = self
  logger.write_string(message)
}

///|
/// An externally tagged enum variant with a payload.
fn variant(name : String, payload : Json) -> Json {
  Json::object(Map::from_array([(name, payload)]))
}

///|
/// `Serialize for IoError` (`IoErrorRepr`): `{"message", "raw_os_error",
/// "path"}`.
fn io_error_json(e : Error, path : String?) -> Json {
  {
    "message": Json::string(@support.io_error_message(e)),
    "raw_os_error": match e {
      @os_error.OSError(errno, ..) => Json::number(errno.to_double())
      _ => Json::null()
    },
    "path": match path {
      Some(p) => Json::string(p)
      None => Json::null()
    },
  }
}

///|
/// `GenerateError::IO(IoError::new(e, path))`.
fn io_error(e : Error, path : String?) -> GenerateError {
  GenerateError(
    json=variant("IO", io_error_json(e, path)),
    message=@support.io_error_with_path(e, path),
  )
}

///|
/// An error of the generate package's generation functions
/// (`ParseGrammar`, `Prepare`, `VariableInfo`, `BuildTables`, `Render`,
/// `SuperTypeCycle`).
fn generation_error(e : Error) -> GenerateError {
  let message = error_message(e)
  let json = match @generate.generate_error_json(e) {
    Some(json) => json
    // Not an error of upstream's `GenerateError` (a bug of the port).
    None => Json::string(message)
  }
  GenerateError(json~, message~)
}

///|
/// `ParseVersionError` as a `GenerateError::ParseVersion`.
fn parse_version_error(e : @loader.ParseVersionError) -> GenerateError {
  let payload = match e {
    VersionError(s) => variant("Version", Json::string(s))
    JSONError(s) => variant("JSON", Json::string(s))
    IOError(e, path) => variant("IO", io_error_json(e, Some(path)))
  }
  GenerateError(json=variant("ParseVersion", payload), message=e.to_string())
}

///|
/// `LoadGrammarError` as a `GenerateError::LoadGrammarFile`.
fn load_grammar_error(payload : Json, message : String) -> GenerateError {
  GenerateError(json=variant("LoadGrammarFile", payload), message~)
}

///|
/// `Path::try_exists`: `Ok(false)` only when the path does not exist.
async fn try_exists(path : String) -> Bool {
  ignore(@fs.kind(path, follow_symlink=true)) catch {
    e => if @support.is_not_found(e) { return false } else { raise e }
  }
  true
}

///|
/// `Path::is_dir` (errors are `false`).
async fn path_is_dir(path : String) -> Bool {
  (@fs.kind(path, follow_symlink=true) catch { _ => @fs.FileKind::Unknown })
  is Directory
}

///|
/// `generate_parser_in_directory`.
pub async fn generate_parser_in_directory(
  repo_path : String,
  out_path : String?,
  grammar_path : String?,
  abi_version : UInt64,
  report_symbol_name : String?,
  js_runtime : String?,
  generate_parser : Bool,
  optimizations : @generate.OptLevel,
  diagnostics : Array[@generate.Diagnostic],
) -> Unit {
  let mut repo_path = repo_path
  // Populate a new empty grammar directory.
  let grammar_path = match grammar_path {
    Some(path_buf) => {
      let exists = try_exists(path_buf) catch {
        e =>
          raise GenerateError(
            json=variant("GrammarPath", io_error_json(e, Some(path_buf))),
            message="Error with specified path -- \{@support.io_error_with_path(e, Some(path_buf))}",
          )
      }
      if !exists {
        // A nonexistent path with an extension (i.e.
        // tree-sitter-foo/grammar.json) is a missing input file, not a
        // directory to create.
        if @support.extension(path_buf) is Some(_) {
          raise GenerateError(
            json=variant("GrammarFileNotFound", Json::string(path_buf)),
            message="Grammar file `\{path_buf}` not found",
          )
        }
        @support.create_dir_all(path_buf) catch {
          e => raise io_error(e, Some(path_buf))
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
  @support.create_dir_all(src_path) catch {
    e => raise io_error(e, Some(src_path))
  }
  if @support.file_name(grammar_path) != Some("grammar.json") {
    @fs.write_file(
      @support.path_join(src_path, "grammar.json"),
      grammar_json,
      create_mode=CreateOrTruncate,
    ) catch {
      e => raise io_error(e, Some(src_path))
    }
  }
  // If our job is only to generate `grammar.json` and not `parser.c`, stop
  // here.
  let input_grammar = @generate.parse_grammar(grammar_json, diagnostics) catch {
    e => raise generation_error(e)
  }
  if !generate_parser {
    let node_types_json = @generate.generate_node_types_for_input_grammar(
      input_grammar, diagnostics,
    ) catch {
      e => raise generation_error(e)
    }
    write_file(@support.path_join(src_path, "node-types.json"), node_types_json)
    return
  }
  let semantic_version = @loader.read_grammar_version(repo_path) catch {
    e => raise parse_version_error(e)
  }
  // Generate the parser and related files.
  //
  // `abi_version` is a `usize` upstream; the generator takes an `Int32`.
  // It only reaches `render_c_code`'s range check (every version above
  // `Int32::max_value()` is out of range), so a larger version is passed
  // as `Int32::max_value()`, which takes the same path, and the resulting
  // `RenderError::ABI` reports the original value.
  let generator_abi_version = if abi_version > 0x7FFFFFFFUL {
    2147483647
  } else {
    abi_version.to_int()
  }
  let generated = @generate.generate_parser_for_grammar_with_opts(
    input_grammar, generator_abi_version, semantic_version, report_symbol_name, optimizations,
    diagnostics,
  ) catch {
    @generate.RenderError::ABI(_) if abi_version > 0x7FFFFFFFUL =>
      raise GenerateError(
        json=variant(
          "Render",
          variant("ABI", Json::number(abi_version.to_double(), repr=abi_version.to_string())),
        ),
        message="This version of Tree-sitter can only generate parsers with ABI version \{@generate.abi_version_min} - \{@generate.abi_version_max}, not \{abi_version}",
      )
    e => raise generation_error(e)
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
  @support.create_dir_all(header_path) catch {
    e => raise io_error(e, Some(header_path))
  }
  write_file(@support.path_join(header_path, "alloc.h"), alloc_header)
  write_file(@support.path_join(header_path, "array.h"), array_header)
  write_file(@support.path_join(header_path, "parser.h"), parser_header)
}

///|
/// `write_file`.
async fn write_file(path : String, body : String) -> Unit {
  @fs.write_file(path, body, create_mode=CreateOrTruncate) catch {
    e => raise io_error(e, Some(path))
  }
}

///|
/// `load_grammar_file`.
pub async fn load_grammar_file(
  grammar_path : String,
  js_runtime : String?,
  current_dir : String,
) -> String {
  if path_is_dir(grammar_path) {
    raise load_grammar_error(
      Json::string("InvalidPath"),
      "Path to a grammar file with `.js` or `.json` extension is required",
    )
  }
  match @support.extension(grammar_path) {
    Some("js") =>
      load_js_grammar_file(grammar_path, js_runtime) catch {
        JSError(json~, message~) =>
          raise load_grammar_error(
            variant("LoadJSGrammarFile", json),
            "Failed to load grammar.js -- \{message}",
          )
      }
    Some("json") =>
      @support.read_to_string(grammar_path) catch {
        e =>
          raise load_grammar_error(
            variant("IO", io_error_json(e, Some(grammar_path))),
            "Failed to load grammar.json -- \{@support.io_error_with_path(e, Some(grammar_path))}",
          )
      }
    Some("mbtx") => {
      // MoonBit-specific: a grammar written as a `.mbtx` program.
      let mbtx_error = (message : String) => {
        let message = "Failed to load grammar.mbtx -- \{message}"
        load_grammar_error(
          variant("LoadMbtxGrammarFile", Json::string(message)),
          message,
        )
      }
      let output = @loader.run_grammar_script(grammar_path, current_dir) catch {
        e => raise mbtx_error(error_message(e))
      }
      let json = @support.parse_json(output) catch {
        e =>
          raise mbtx_error(
            "Failed to serialize grammar JSON -- \{@config.json_error_message(e)}",
          )
      }
      @support.to_string_pretty(json)
    }
    _ =>
      raise load_grammar_error(
        variant("FileExtension", Json::string(grammar_path)),
        "Unknown grammar file extension: \{@loader.rust_debug_str(grammar_path)}",
      )
  }
}

///|
/// `JSError`: its `Display` text and its `Serialize` form.
priv suberror JSError {
  JSError(json~ : Json, message~ : String)
}

///|
/// A `JSError` variant whose fields are `runtime` and then `fields`.
fn js_error(
  name : String,
  runtime : String,
  fields : Array[(String, Json)],
  message : String,
) -> JSError {
  let payload = Map::from_array([("runtime", Json::string(runtime))])
  for field in fields {
    payload[field.0] = field.1
  }
  JSError(json=variant(name, Json::object(payload)), message~)
}

///|
/// `JSError::IO(IoError::new(e, path))`.
fn js_io_error(e : Error, path : String?) -> JSError {
  JSError(
    json=variant("IO", io_error_json(e, path)),
    message=@support.io_error_with_path(e, path),
  )
}

///|
/// `load_js_grammar_file`: run the grammar with a JavaScript runtime and the
/// grammar DSL, which is written to the runtime's standard input. (QuickJS,
/// `--js-runtime native`, is not available.)
async fn load_js_grammar_file(
  grammar_path : String,
  js_runtime : String?,
) -> String raise JSError {
  let grammar_path = @fs.realpath(grammar_path) catch {
    e => raise js_io_error(e, Some(grammar_path))
  }
  let js_runtime = js_runtime.unwrap_or("node")
  let args = match js_runtime {
    "node" => ["--input-type=module", "-"]
    "bun" => ["-"]
    "deno" => ["run", "--allow-all", "-"]
    _ => []
  }
  let spawn_error = (e : Error) => {
    let error = @support.io_error_message(e)
    js_error(
      "JSRuntimeSpawn",
      js_runtime,
      [("error", Json::string(error))],
      "Failed to run `\{js_runtime}` -- \{error}",
    )
  }
  // `Stdio::piped()` for stdin and stdout; stderr is inherited.
  let (stdin_read, js_stdin) = @pipe.pipe() catch { e => raise spawn_error(e) }
  let (js_stdout, stdout_write) = @pipe.pipe() catch {
    e => {
      stdin_read.close()
      js_stdin.close()
      raise spawn_error(e)
    }
  }
  let pid = @process.spawn_orphan(
    js_runtime,
    args,
    extra_env=Map::from_array([("TREE_SITTER_GRAMMAR_PATH", grammar_path)]),
    stdin=stdin_read,
    stdout=stdout_write,
  ) catch {
    e => {
      stdin_read.close()
      js_stdin.close()
      js_stdout.close()
      stdout_write.close()
      raise spawn_error(e)
    }
  }
  stdin_read.close()
  stdout_write.close()
  defer js_stdout.close()
  let write_error = (item : String, e : Error) => {
    let error = @support.io_error_message(e)
    js_error(
      "JSRuntimeWrite",
      js_runtime,
      [("item", Json::string(item)), ("error", Json::string(error))],
      "Failed to write \{item} to `\{js_runtime}`'s stdin -- \{error}",
    )
  }
  let (major, minor, patch) = (0, 28, 0)
  let written = try {
    js_stdin.write(
      "globalThis.TREE_SITTER_CLI_VERSION_MAJOR = \{major};\n         globalThis.TREE_SITTER_CLI_VERSION_MINOR = \{minor};\n         globalThis.TREE_SITTER_CLI_VERSION_PATCH = \{patch};",
    ) catch {
      e => raise write_error("tree-sitter version", e)
    }
    js_stdin.write(dsl_js) catch {
      e => raise write_error("grammar dsl", e)
    }
  } catch {
    e => Err(e)
  } noraise {
    _ => Ok(())
  }
  // `drop(js_stdin)`
  js_stdin.close()
  let read_error = (e : Error) => {
    let error = @support.io_error_message(e)
    js_error(
      "JSRuntimeRead",
      js_runtime,
      [("error", Json::string(error))],
      "Failed to read output from `\{js_runtime}` -- \{error}",
    )
  }
  if written is Err(e) {
    // Upstream returns here, dropping the child without waiting for it.
    raise e
  }
  // `wait_with_output`: read standard output to its end, then wait.
  let output = js_stdout.read_all() catch { e => raise read_error(e) }
  let code = @support.wait_exit_code(pid) catch { e => raise read_error(e) }
  let stdout = output.binary()
  match code {
    Some(0) => ()
    // A process ended by a signal has no exit code.
    code =>
      raise js_error(
        "JSRuntimeExit",
        js_runtime,
        [("code", Json::number(code.unwrap_or(-1).to_double()))],
        "`\{js_runtime}` process exited with status \{code.unwrap_or(-1)}",
      )
  }
  if @support.utf8_error(stdout) is Some(error) {
    raise js_error(
      "JSRuntimeUtf8",
      js_runtime,
      [("error", Json::string(error))],
      "Got invalid UTF8 from `\{js_runtime}` -- \{error}",
    )
  }
  let stdout = @support.utf8_lossy(stdout)
  let mut grammar_json = stdout
  match stdout.rev_find("\n") {
    Some(pos) => {
      // If there's a newline, split the last line from the rest of the
      // output
      let node_output = stdout.unsafe_substring(start=0, end=pos)
      grammar_json = stdout.unsafe_substring(start=pos + 1, end=stdout.length())
      @support.stdout_write_string(node_output) catch {
        e => raise js_io_error(e, None)
      }
      @support.stdout_write_string("\n") catch {
        e => raise js_io_error(e, None)
      }
      @support.stdout_flush() catch { e => raise js_io_error(e, None) }
    }
    None => ()
  }
  let json = @support.parse_json(grammar_json) catch {
    e => {
      let message = @config.json_error_message(e)
      raise JSError(
        json=variant("Serialization", Json::string(message)),
        message="Failed to serialize grammar JSON -- \{message}",
      )
    }
  }
  @support.to_string_pretty(json)
}
