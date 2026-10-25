// Port of `Init::run` of tree-sitter crates/cli/src/main.rs: the prompts
// that build a `JsonConfigOpts` when `tree-sitter.json` is missing, the
// "Does the config above look correct?" loop, and the `--update` path that
// rewrites `tree-sitter.json`.
//
// dialoguer's terminal UI (`ColorfulTheme`, in-place editing, arrow-key
// selection) is not reproduced. Each prompt is a plain line written to
// standard error in the layout of dialoguer's default theme, and the answer
// is one line read from standard input:
//
// - `Input`: `<prompt> [<default>]: ` (`<prompt>: ` without a shown
//   default). An empty answer takes the default; without one, an empty
//   answer is re-asked unless empty input is allowed. Validation and parse
//   failures print `error: <message>` and ask again.
// - `Confirm`: `<prompt> [y/n] `, answered with `y`/`yes` or `n`/`no`.
// - `FuzzySelect` ("Which field would you like to change?"): the fields are
//   listed one per line; answer with a field name or its 1-based number.
// - `MultiSelect` ("Bindings"): the languages are listed with their default
//   `[x]`/`[ ]` state; an empty answer keeps the defaults, otherwise answer
//   with the languages to enable, separated by spaces or commas.
//
// As in dialoguer, `Input`, `Confirm` and `MultiSelect` fail with
// `IO error: not a terminal` when standard error is not a terminal
// (`Term::stderr().is_term()`); `FuzzySelect` does not check. End of input
// fails the command.
// Upstream collects the file types through a `HashSet`, so their order is
// unspecified there; here they keep their first-occurrence order.

///|
/// Read one line of standard input, without its line terminator.
async fn read_answer() -> String {
  match @stdio.stdin.read_until("\n") {
    Some(line) =>
      if line.has_suffix("\r") {
        line.view(end_offset=line.length() - 1).to_owned()
      } else {
        line
      }
    None => raise anyhow("IO error: unexpected end of input")
  }
}

///|
/// `if !term.is_term() { return Err(io::Error::new(io::ErrorKind::NotConnected,
/// "not a terminal").into()) }` (displayed through `dialoguer::Error::IO`).
fn ensure_term() -> Unit raise InitError {
  if !@support.is_terminal(2) {
    raise anyhow("IO error: not a terminal")
  }
}

///|
/// `Theme::format_error`.
fn render_error(message : String) -> Unit {
  @support.print_err("error: \{message}\n")
}

///|
/// `Input::<String>` with the options upstream uses.
async fn input(
  prompt : String,
  default? : String,
  show_default~ : Bool = true,
  allow_empty~ : Bool = false,
  validate? : (String) -> String?,
) -> String {
  ensure_term()
  for ;; {
    // `Theme::format_input_prompt`
    match (default, show_default) {
      (Some(d), true) => @support.print_err("\{prompt} [\{d}]: ")
      _ => @support.print_err("\{prompt}: ")
    }
    @support.flush()
    let answer = read_answer()
    let value = if answer.is_empty() {
      match default {
        Some(d) => d
        None => if allow_empty { "" } else { continue }
      }
    } else {
      answer
    }
    if validate is Some(validate) && validate(value) is Some(err) {
      render_error(err)
      continue
    }
    return value
  }
}

///|
/// `Confirm::interact`.
async fn confirm(prompt : String) -> Bool {
  ensure_term()
  for ;; {
    @support.print_err("\{prompt} [y/n] ")
    @support.flush()
    match read_answer().trim().to_owned() {
      "y" | "Y" | "yes" | "Yes" => return true
      "n" | "N" | "no" | "No" => return false
      _ => continue
    }
  }
}

///|
/// `FuzzySelect::interact`: the index of the chosen item.
async fn fuzzy_select(prompt : String, items : Array[String]) -> Int32 {
  for ;; {
    @support.print_err("\{prompt}:\n")
    for i, item in items {
      @support.print_err("  \{i + 1}. \{item}\n")
    }
    @support.print_err("> ")
    @support.flush()
    let answer = read_answer().trim().to_owned()
    for i, item in items {
      if item == answer || (i + 1).to_string() == answer {
        return i
      }
    }
  }
}

///|
/// `MultiSelect::items_checked(..).interact()`: the indices of the chosen
/// items, in item order.
async fn multi_select(
  prompt : String,
  items : Array[(String, Bool)],
) -> Array[Int32] {
  ensure_term()
  for ;; {
    @support.print_err("\{prompt}:\n")
    for item in items {
      let (name, checked) = item
      @support.print_err("  [\{if checked { "x" } else { " " }}] \{name}\n")
    }
    @support.print_err("> ")
    @support.flush()
    let answer = read_answer()
    if answer.trim().is_empty() {
      let checked = []
      for i, item in items {
        if item.1 {
          checked.push(i)
        }
      }
      return checked
    }
    let chosen = []
    let mut unknown = None
    for word in answer.split(" ") {
      for part in word.split(",") {
        let part = part.trim().to_owned()
        if part.is_empty() {
          continue
        }
        match items.search_by(item => item.0 == part) {
          Some(i) => if !chosen.contains(i) { chosen.push(i) }
          None => unknown = Some(part)
        }
      }
    }
    if unknown is Some(part) {
      render_error("unknown item `\{part}`")
      continue
    }
    chosen.sort()
    return chosen
  }
}

///|
/// The field names of `JsonConfigOpts` offered by the prompts, in order.
let choices : Array[String] = [
  "name", "camelcase", "title", "description", "repository", "funding", "scope",
  "file_types", "version", "license", "author", "email", "url", "namespace", "bindings",
  "exit",
]

///|
/// `set_choice!`: prompt for one field. Returns `false` for `exit`.
async fn set_choice(opts : JsonConfigOpts, choice : String) -> Bool {
  match choice {
    "name" =>
      opts.name = input("Parser name", validate=input => {
        if input
          .iter()
          .all(c => c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_') {
          None
        } else {
          Some(
            "The name must be lowercase and contain only letters, digits, and underscores",
          )
        }
      })
    "camelcase" =>
      opts.camelcase = input(
        "CamelCase name",
        default=to_upper_camel_case(opts.name),
        validate=input => {
          if input
            .iter()
            .all(c => c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_') {
            None
          } else {
            Some("The name must contain only letters, digits, and underscores")
          }
        },
      )
    "title" =>
      opts.title = input(
        "Title (human-readable name)",
        default=to_upper_camel_case(opts.name),
      )
    "description" =>
      opts.description = input(
        "Description",
        default="\{to_upper_camel_case(opts.name)} grammar for tree-sitter",
        show_default=false,
        allow_empty=true,
      )
    "repository" =>
      opts.repository = Some(
        input(
          "Repository URL",
          allow_empty=true,
          default="https://github.com/tree-sitter/tree-sitter-\{opts.name}",
          show_default=false,
        ),
      )
    "funding" =>
      opts.funding = Some(
        rust_trim(input("Funding URL", allow_empty=true)),
      )
    "scope" =>
      opts.scope = input("TextMate scope", default="source.\{opts.name}", validate=input => {
        if input.has_prefix("source.") || input.has_prefix("text.") {
          None
        } else {
          Some("The scope must start with 'source.' or 'text.'")
        }
      })
    "file_types" => {
      let ft = input("File types (space-separated)", default=opts.name)
      let set = []
      for ext in ft.split(" ") {
        let ext = rust_trim(ext.to_owned())
        if !ext.is_empty() && !set.contains(ext) {
          set.push(ext)
        }
      }
      opts.file_types = set
    }
    "version" => opts.version = initial_version()
    "license" =>
      opts.license = input("License", default="MIT", allow_empty=true)
    "author" => opts.author = input("Author name")
    "email" => {
      let e = input("Author email", allow_empty=true)
      opts.email = if !rust_trim(e).is_empty() { Some(e) } else { None }
    }
    "url" =>
      opts.url = Some(rust_trim(input("Author URL", allow_empty=true)))
    "namespace" =>
      opts.namespace = Some(
        input(
          "Package namespace",
          default="io.github.tree-sitter",
          allow_empty=true,
        ),
      )
    "bindings" => {
      let languages = @loader.Bindings::default().languages()
      let enabled = multi_select("Bindings", languages).map(i => languages[i].0)
      opts.bindings = match @loader.Bindings::with_enabled_languages(enabled) {
        Ok(b) => b
        Err(_) => abort("unexpected unsupported language")
      }
    }
    "exit" => return false
    _ => abort("internal error: entered unreachable code")
  }
  true
}

///|
/// `Input::<SemverVersion>` with the default `0.1.0`.
async fn initial_version() -> @loader.SemverVersion {
  let default = @loader.SemverVersion::new(0, 1, 0)
  ensure_term()
  for ;; {
    @support.print_err("Version [\{default}]: ")
    @support.flush()
    let answer = read_answer()
    if answer.is_empty() {
      return default
    }
    return @loader.SemverVersion::parse(answer) catch {
      @loader.SemverError(e) => {
        render_error(e)
        continue
      }
    }
  }
}

///|
/// `Init::run`.
pub async fn run_init(current_dir : String, update : Bool) -> Unit {
  let tree_sitter_json_path = @support.path_join(
    current_dir, "tree-sitter.json",
  )
  let configure_json = !path_exists(tree_sitter_json_path)
  let (language_name, json_config_opts) = if configure_json {
    let opts = JsonConfigOpts::default()

    // Initial configuration
    for choice in choices[:choices.length() - 1] {
      ignore(set_choice(opts, choice))
    }

    // Loop for editing the configuration
    for ;; {
      @support.log_info(
        "Your current configuration:\n\{@support.to_string_pretty(opts.to_json())}",
      )
      if confirm("Does the config above look correct?") {
        break
      }
      let idx = fuzzy_select("Which field would you like to change?", choices)
      if !set_choice(opts, choices[idx]) {
        break
      }
    }
    (opts.name, Some(opts))
  } else {
    let old_config = read_to_string(tree_sitter_json_path) catch {
      IoError(e) => raise with_context(e, "Failed to read tree-sitter.json")
    }
    let json = parse_tree_sitter_json(old_config)
    let json = if json.schema is None {
      { ..json, schema: Some(tree_sitter_json_schema), }
    } else {
      json
    }
    let new_config = "\{@support.to_string_pretty(json.to_json())}\n"
    // Write the re-serialized config back, as newly added optional boolean
    // fields will be included with explicit `false`s rather than implicit
    // `null`s
    if update && rust_trim(old_config) != rust_trim(new_config) {
      @support.log_info("Updating tree-sitter.json")
      fs_write(tree_sitter_json_path, @support.to_string_pretty(json.to_json())) catch {
        IoError(e) => raise with_context(e, "Failed to write tree-sitter.json")
      }
    }
    (json.grammars[0].name, None)
  }
  generate_grammar_files(current_dir, language_name, update, json_config_opts)
}
