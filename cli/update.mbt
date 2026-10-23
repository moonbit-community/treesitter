///|
async fn update_corpus(
  path : String,
  language : @language.Language,
  scanner : @ts.ExternalScanner?,
) -> Unit {
  let changes : Array[(String, String)] = []
  async fn prepare(path : String) -> Unit {
    if @fs.kind(path) == Directory {
      for name in @fs.readdir(path, sort=true) {
        let child = "\{path}/\{name}"
        if @fs.kind(child) == Directory || name.has_suffix(".txt") {
          prepare(child)
        }
      }
    } else {
      let source = @fs.read_file(path).text()
      let updated = @corpus.update(language, source, scanner?)
      if updated != source {
        changes.push((path, updated))
      }
    }
  }
  // Reject invalid updates anywhere in the corpus before writing any file.
  prepare(path)
  for (file, content) in changes {
    write_file(file, content)
    println("UPDATED \{file}")
  }
  println("Updated \{changes.length()} corpus files")
}
