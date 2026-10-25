// Compiles the upstream-generated parsers the harness links (see setup.sh).
fn main() {
    let upstream = std::env::var("UPSTREAM").expect("UPSTREAM (the pinned checkout)");
    let root = format!("{upstream}/test/fixtures/grammars");
    for (name, scanner) in [("json", false), ("c", false), ("javascript", true)] {
        let src = format!("{root}/{name}/src");
        let mut build = cc::Build::new();
        build.include(&src).file(format!("{src}/parser.c")).warnings(false);
        if scanner {
            build.file(format!("{src}/scanner.c"));
        }
        build.compile(&format!("tree-sitter-{name}"));
    }
    println!("cargo:rerun-if-env-changed=UPSTREAM");
}
