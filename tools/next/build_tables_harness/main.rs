fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args[1] == "--fixtures" { tree_sitter_generate::harness::fixtures::dump_for_moonbit(); return; }
    let grammar = std::fs::read_to_string(&args[1]).unwrap();
    let out_dir = std::path::Path::new(&args[2]);
    std::fs::create_dir_all(out_dir).unwrap();
    let (inputs, out, micros) = tree_sitter_generate::harness::run(&grammar);
    if let Some(inputs) = inputs {
        std::fs::write(out_dir.join("inputs.json"), inputs).unwrap();
    }
    std::fs::write(out_dir.join("tables.txt"), out).unwrap();
    println!("{micros}");
}
