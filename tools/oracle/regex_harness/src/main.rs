// Development-only oracle for regex: reads the JSON-lines corpus written
// by tools/oracle/regex_corpus.py and prints, per pattern, `ERR` when the
// pattern is rejected, or the results for each haystack. regex/probe prints
// the same format.
//
// Usage: regex_harness <corpus> [is_match|find|find-utf8]
//
// - `is_match` (default), `regex::bytes::Regex`: one `0`/`1` per haystack.
// - `find`, `regex::bytes::Regex`: space-separated per haystack,
//   `<is_match>:<find>:<find_iter>` where `<find>` is `start-end` or `N` and
//   `<find_iter>` is a comma-separated list of `start-end`.
// - `find-utf8`: the same with `regex::Regex`; haystacks that are not valid
//   UTF-8 print `X`.
use std::io::{BufRead, Write};

fn unhex(s: &str) -> Vec<u8> {
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
        .collect()
}

fn span(m: Option<(usize, usize)>) -> String {
    match m {
        Some((s, e)) => format!("{s}-{e}"),
        None => "N".to_string(),
    }
}

fn spans(ms: impl Iterator<Item = (usize, usize)>) -> String {
    ms.map(|(s, e)| format!("{s}-{e}")).collect::<Vec<_>>().join(",")
}

fn main() {
    let path = std::env::args().nth(1).expect("corpus path");
    let mode = std::env::args().nth(2).unwrap_or_else(|| "is_match".to_string());
    let file = std::fs::File::open(path).unwrap();
    let stdout = std::io::stdout();
    let mut out = stdout.lock();
    for line in std::io::BufReader::new(file).lines() {
        let line = line.unwrap();
        let value: serde_json::Value = serde_json::from_str(&line).unwrap();
        let pattern = value["p"].as_str().unwrap();
        let texts: Vec<Vec<u8>> = value["t"]
            .as_array()
            .unwrap()
            .iter()
            .map(|t| unhex(t.as_str().unwrap()))
            .collect();
        match mode.as_str() {
            "is_match" => match regex::bytes::Regex::new(pattern) {
                Err(_) => writeln!(out, "ERR").unwrap(),
                Ok(re) => {
                    let s: String = texts
                        .iter()
                        .map(|text| if re.is_match(text) { '1' } else { '0' })
                        .collect();
                    writeln!(out, "{s}").unwrap();
                }
            },
            "find" => match regex::bytes::Regex::new(pattern) {
                Err(_) => writeln!(out, "ERR").unwrap(),
                Ok(re) => {
                    let s: Vec<String> = texts
                        .iter()
                        .map(|text| {
                            format!(
                                "{}:{}:{}",
                                re.is_match(text) as u8,
                                span(re.find(text).map(|m| (m.start(), m.end()))),
                                spans(re.find_iter(text).map(|m| (m.start(), m.end())))
                            )
                        })
                        .collect();
                    writeln!(out, "{}", s.join(" ")).unwrap();
                }
            },
            "find-utf8" => match regex::Regex::new(pattern) {
                Err(_) => writeln!(out, "ERR").unwrap(),
                Ok(re) => {
                    let s: Vec<String> = texts
                        .iter()
                        .map(|text| match std::str::from_utf8(text) {
                            Err(_) => "X".to_string(),
                            Ok(text) => format!(
                                "{}:{}:{}",
                                re.is_match(text) as u8,
                                span(re.find(text).map(|m| (m.start(), m.end()))),
                                spans(re.find_iter(text).map(|m| (m.start(), m.end())))
                            ),
                        })
                        .collect();
                    writeln!(out, "{}", s.join(" ")).unwrap();
                }
            },
            _ => panic!("unknown mode {mode}"),
        }
    }
}
