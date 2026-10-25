// Development-only oracle for next/regex: reads the JSON-lines corpus written
// by tools/oracle/regex_corpus.py and prints, per pattern, `ERR` when
// `regex::bytes::Regex::new` rejects it, or one `0`/`1` per haystack giving
// `is_match`. next/regex/probe prints the same format.
use std::io::{BufRead, Write};

fn unhex(s: &str) -> Vec<u8> {
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
        .collect()
}

fn main() {
    let path = std::env::args().nth(1).expect("corpus path");
    let file = std::fs::File::open(path).unwrap();
    let stdout = std::io::stdout();
    let mut out = stdout.lock();
    for line in std::io::BufReader::new(file).lines() {
        let line = line.unwrap();
        let value: serde_json::Value = serde_json::from_str(&line).unwrap();
        let pattern = value["p"].as_str().unwrap();
        match regex::bytes::Regex::new(pattern) {
            Err(_) => writeln!(out, "ERR").unwrap(),
            Ok(re) => {
                let mut s = String::new();
                for t in value["t"].as_array().unwrap() {
                    let text = unhex(t.as_str().unwrap());
                    s.push(if re.is_match(&text) { '1' } else { '0' });
                }
                writeln!(out, "{s}").unwrap();
            }
        }
    }
}
