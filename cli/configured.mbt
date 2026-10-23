///|
async fn configured_highlights(
  location : @loader.GrammarLocation,
  language : @language.Language,
  scanners : (String) -> @ts.ExternalScanner?,
) -> @highlight.Configuration {
  @highlight.Configuration::new(
    language,
    scanner?=scanners(language.name),
    location.queries("highlights"),
    locals=location.queries("locals"),
    injections=location.queries("injections"),
  )
}

///|
async fn configured_html(
  location : @loader.GrammarLocation,
  locations : Array[@loader.GrammarLocation],
  tree : @ts.Tree,
  root : String,
  scanners : (String) -> @ts.ExternalScanner?,
) -> String {
  let config = configured_highlights(location, tree.language, scanners)
  let loaded : Map[String, @highlight.Configuration] = Map([])
  let absent : Map[String, Bool] = Map([])
  // Injection callbacks are synchronous. Resolve only languages requested by
  // the current query pass, then repeat with those configurations available.
  // This avoids compiling unrelated grammars during language discovery.
  for pass = 0; pass <= 32; pass = pass + 1 {
    let requested : Array[String] = []
    let html = config.html(tree, injection=name => {
      if loaded.get(name) is Some(config) {
        return Some(config)
      }
      if !absent.contains(name) && !requested.contains(name) {
        requested.push(name)
      }
      None
    })
    if requested.is_empty() {
      return html
    }
    for name in requested {
      match @config.select_injection(locations.map(l => l.grammar), name) {
        Some(grammar) => {
          let next = locations[locations
            .search_by(l => physical_equal(l.grammar, grammar))
            .unwrap()]
          loaded[name] = configured_highlights(
            next,
            next.language(root),
            scanners,
          )
        }
        None => absent[name] = true
      }
    }
  }
  raise Usage("injection language resolution exceeded 32 levels")
}

///|
fn print_tags(tags : Array[@tags.Tag]) -> Unit {
  for tag in tags {
    println(
      Json::object({
        "name": Json(tag.name),
        "kind": Json(tag.syntax_type),
        "definition": Json(tag.is_definition),
        "range": Json(tag.range),
        "name_range": Json(tag.name_range),
        "line_range": Json(tag.line_range),
        "utf16_column_range": Json(tag.utf16_column_range),
        "docs": Json(tag.docs),
      }).stringify(),
    )
  }
}
