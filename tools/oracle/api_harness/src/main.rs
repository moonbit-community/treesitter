use streaming_iterator::StreamingIterator;
use tree_sitter::{Language, Parser, Query, QueryCursor};

unsafe extern "C" {
    fn tree_sitter_json() -> *const ();
    fn tree_sitter_c() -> *const ();
    fn tree_sitter_javascript() -> *const ();
}

fn lang(f: unsafe extern "C" fn() -> *const ()) -> Language {
    let f = unsafe { tree_sitter_language::LanguageFn::from_raw(std::mem::transmute(f)) };
    Language::new(f)
}

fn err(language: &Language, source: &str) {
    match Query::new(language, source) {
        Ok(_) => println!("OK {source:?}"),
        Err(e) => println!(
            "ERR {source:?}\n  kind={:?} row={} column={} offset={}\n  message={:?}\n  display={:?}",
            e.kind, e.row, e.column, e.offset, e.message, e.to_string()
        ),
    }
}

fn main() {
    let json = lang(tree_sitter_json);
    let _c = lang(tree_sitter_c);
    let js = lang(tree_sitter_javascript);

    for p in [
        "(#eq? @id)",
        "(#not-eq? @id a b)",
        "(#any-eq? \"a\" @id)",
        "(#match? @id)",
        "(#not-match? \"a\" \"b\")",
        "(#any-match? @id @id)",
        "(#match? @id \"(\")",
        "(#match? @id \"\\\\w{500}\")",
        "(#any-of?)",
        "(#not-any-of? \"a\" \"b\")",
        "(#any-of? @id \"a\" @a)",
        "(#set!)",
        "(#is? a b c d)",
        "(#set! @id @a)",
        "(#is-not? a b c)",
        "(#set! @id)",
    ] {
        err(&js, &format!("\n(identifier) @a\n((identifier) @id {p})"));
    }
    for s in [
        "\n  (if_statement",
        "(clas)",
        "(if_statement condit: (identifier))",
        "((identifier) @id (#eq? @id @ok))",
        "(identifier (identifier))",
        "(identifier)\n(",
        "(identifier)\n(\n",
        "(héllo_wörld-x y)",
        "\"te\\\"st\"",
        "\"\\\\\" @cap",
        "fakefield: (identifier)",
        "a\r\n(clas)",
        "a\r\n  (if_statement",
    ] {
        err(&js, s);
    }

    let source = "\n\n[\n  123,\n  false,\n  {\n    \"x\": null\n  }\n]\n";
    let mut parser = Parser::new();
    parser.set_language(&json).unwrap();
    let tree = parser.parse(source, None).unwrap();
    let root = tree.root_node();
    println!("{:?}", root.child(0).unwrap());
    println!("{:?}", tree);
    println!("{}", root);
    println!("{:#}", root);
    println!("{}", tree_sitter::format_sexp(&root.to_sexp(), 0));
    println!("{}", tree_sitter::format_sexp(&root.to_sexp(), 2));
    let tree2 = parser.parse("[1, [2]]", None).unwrap();
    let query = Query::new(&json, "(array (number) @n)").unwrap();
    let mut cursor = QueryCursor::new();
    println!("match_limit {}", cursor.match_limit());
    let mut matches = cursor.matches(&query, tree2.root_node(), "[1, [2]]".as_bytes());
    println!("{:?}", matches.next().unwrap());
    let missing = parser.parse("[1, ", None).unwrap();
    println!("{}", tree_sitter::format_sexp(&missing.root_node().to_sexp(), 0));
    let bad = parser.parse("[1, @@ 2]", None).unwrap();
    println!("{}", tree_sitter::format_sexp(&bad.root_node().to_sexp(), 0));
    println!("{:?}", tree_sitter::format_sexp("(a (MISSING \"b\"))", 0));
    println!("{:?}", tree_sitter::format_sexp("(a (MISSING b) (c))", 0));
    for (bytes, label) in [(&b"ab\xffcd\xe2\x82"[..], "lossy1"), (&b"\xff\xfe"[..], "lossy2"), (&b"ok"[..], "lossy3")] {
        let chunks: Vec<&str> = tree_sitter::LossyUtf8::new(bytes).collect();
        println!("{label} {chunks:?}");
    }
}
