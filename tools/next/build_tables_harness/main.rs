// Usage: dump <grammar.json> <out dir> [report symbol name]
//        dump --fixtures
fn main() {
    if std::env::args().nth(3).is_some() {
        log::set_boxed_logger(Box::new(InfoLogger)).unwrap();
        log::set_max_level(log::LevelFilter::Info);
    }
    let args: Vec<String> = std::env::args().collect();
    if args[1] == "--fixtures" { tree_sitter_generate::harness::fixtures::dump_for_moonbit(); return; }
    let grammar = std::fs::read_to_string(&args[1]).unwrap();
    let out_dir = std::path::Path::new(&args[2]);
    std::fs::create_dir_all(out_dir).unwrap();
    let (inputs, out, micros) = tree_sitter_generate::harness::run(&grammar, args.get(3).map(String::as_str));
    if let Some(inputs) = inputs {
        std::fs::write(out_dir.join("inputs.json"), inputs).unwrap();
    }
    std::fs::write(out_dir.join("tables.txt"), out).unwrap();
    println!("{micros}");
}

/// Prints info-level records like the CLI's logger (which uses stderr).
struct InfoLogger;

impl log::Log for InfoLogger {
    fn enabled(&self, _: &log::Metadata) -> bool {
        true
    }

    fn log(&self, record: &log::Record) {
        if record.level() <= log::Level::Info {
            println!("{}", record.args());
        }
    }

    fn flush(&self) {}
}
