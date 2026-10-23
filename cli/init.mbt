///|
async fn init_grammar(name : String, directory : String) -> Unit {
  if name.is_empty() ||
    !name
    .iter()
    .all(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_') ||
    !(name.iter().next() is Some('a'..<='z' | '_')) {
    raise Usage(
      "grammar name must start with a lowercase letter or underscore and contain only lowercase letters, digits, and underscores",
    )
  }
  let grammar =
    $|///|
    $|import {
    $|  "moonbit-community/treesitter/grammar",
    $|}
    $|
    $|///|
    $|fn main raise {
    $|  let grammar = @grammar.Grammar::new("\{name}", [
    $|    ("document", @grammar.Rule::Repeat(@grammar.Rule::Symbol("word"))),
    $|    ("word", @grammar.pattern("[a-z]+")),
    $|  ])
    $|  grammar.validate()
    $|  println(Json(grammar).stringify(indent=2))
    $|}
    $|
  let config = Json::object({
    "grammars": Json::array([
      Json::object({
        "name": Json(name),
        "scope": Json("source.\{name}"),
        "path": Json("."),
        "file-types": Json([name]),
        "highlights": Json("queries/highlights.scm"),
      }),
    ]),
    "metadata": Json::object({
      "version": Json("0.1.0"),
      "license": Json("UNLICENSED"),
      "description": Json("\{name} grammar written in MoonBit"),
    }),
  })
  let readme =
    $|# \{name}
    $|
    $|Edit `grammar.mbtx` to define the language using the MoonBit grammar API.
    $|The script prints grammar JSON; the generator produces portable tables.
    $|
    $|```sh
    $|treesitter generate grammar.mbtx language.json
    $|treesitter test language.json test/corpus
    $|treesitter parse language.json example.\{name}
    $|treesitter highlight language.json queries/highlights.scm example.\{name}
    $|```
    $|
    $|Choose a license and update the metadata in `tree-sitter.json` before publishing.
    $|
  let files = [
    ("grammar.mbtx", grammar),
    ("tree-sitter.json", config.stringify(indent=2) + "\n"),
    ("queries/highlights.scm", "(word) @string\n"),
    (
      "test/corpus/words.txt", "==================\nWords\n==================\nhello world\n---\n(document (word) (word))\n",
    ),
    ("example.\{name}", "hello world\n"),
    ("README.md", readme),
    (".gitignore", "language.json\n_build/\n.mooncakes/\n"),
  ]
  // Check all destinations first; do not overwrite an existing project.
  for (path, _) in files {
    if @fs.exists("\{directory}/\{path}") {
      raise Usage("grammar file already exists: \{directory}/\{path}")
    }
  }
  for path in [directory, "\{directory}/queries", "\{directory}/test/corpus"] {
    if @fs.exists(path) {
      if @fs.kind(path) != Directory {
        raise Usage("grammar directory is not a directory: \{path}")
      }
    } else {
      @fs.mkdir(path, recursive=true)
    }
  }
  for (path, content) in files {
    @fs.write_file("\{directory}/\{path}", content, create_mode=CreateNew)
  }
  println("Created \{name} grammar in \{directory}")
}
