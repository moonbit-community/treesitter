fn ranges(f: impl Fn(char) -> bool) -> Vec<(u32, u32)> {
    let mut out: Vec<(u32, u32)> = Vec::new();
    for cp in 0..=0x10FFFFu32 {
        if let Some(c) = char::from_u32(cp) {
            if f(c) {
                if let Some(last) = out.last_mut() {
                    if last.1 + 1 == cp {
                        last.1 = cp;
                        continue;
                    }
                }
                out.push((cp, cp));
            }
        }
    }
    out
}

fn emit(name: &str, doc: &str, r: &[(u32, u32)]) {
    println!("///|");
    println!("/// {doc}");
    println!("let {name} : FixedArray[(Int, Int)] = [");
    for (a, b) in r {
        println!("  ({a}, {b}),");
    }
    println!("]");
    println!();
}

fn main() {
    let (maj, min, upd) = char::UNICODE_VERSION;
    println!("// Generated from Rust 1.97.1's `char` methods (Unicode {maj}.{min}.{upd}), which");
    println!("// regex-syntax's parser calls for capture names and whitespace. Do not edit.");
    println!();
    emit(
        "rust_alphabetic_ranges",
        "Inclusive code point ranges of `char::is_alphabetic`.",
        &ranges(|c| c.is_alphabetic()),
    );
    emit(
        "rust_numeric_ranges",
        "Inclusive code point ranges of `char::is_numeric`.",
        &ranges(|c| c.is_numeric()),
    );
    emit(
        "rust_whitespace_ranges",
        "Inclusive code point ranges of `char::is_whitespace`.",
        &ranges(|c| c.is_whitespace()),
    );
    for cp in 0..=0x10FFFFu32 {
        if let Some(c) = char::from_u32(cp) {
            assert_eq!(c.is_alphanumeric(), c.is_alphabetic() || c.is_numeric());
        }
    }
}
