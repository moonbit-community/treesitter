fn main() {
    let args: Vec<String> = std::env::args().collect();
    let (ref_dir, out_dir) = (&args[1], &args[2]);
    std::fs::create_dir_all(out_dir).unwrap();
    let mut entries: Vec<_> = std::fs::read_dir(ref_dir)
        .unwrap()
        .map(|e| e.unwrap().path())
        .collect();
    entries.sort();
    for dir in entries {
        let grammar = dir.join("src/grammar.json");
        let Ok(text) = std::fs::read_to_string(&grammar) else {
            continue;
        };
        let name = dir.file_name().unwrap().to_string_lossy().to_string();
        let (inputs, expected) = tree_sitter_generate::harness::dump_node_types(&text);
        if let Some(inputs) = inputs {
            std::fs::write(format!("{out_dir}/{name}.input.json"), inputs).unwrap();
        }
        std::fs::write(format!("{out_dir}/{name}.expected.json"), expected).unwrap();
        println!("{name}");
    }
}
