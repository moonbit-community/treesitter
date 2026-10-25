// Prints the inclusive code point ranges of the characters that Rust's
// `<str as Debug>::fmt` writes as a `\u{...}` escape.
fn main() {
    let mut out: Vec<(u32, u32)> = Vec::new();
    for cp in 0..=0x10FFFFu32 {
        let Some(c) = char::from_u32(cp) else { continue };
        let s = format!("{:?}", c.to_string());
        let inner = &s[1..s.len() - 1];
        let escaped = if inner.starts_with("\\u{") {
            let expected = format!("\\u{{{:x}}}", cp);
            assert_eq!(inner, expected);
            true
        } else {
            match c {
                '\0' => assert_eq!(inner, "\\0"),
                '\t' => assert_eq!(inner, "\\t"),
                '\r' => assert_eq!(inner, "\\r"),
                '\n' => assert_eq!(inner, "\\n"),
                '\\' => assert_eq!(inner, "\\\\"),
                '"' => assert_eq!(inner, "\\\""),
                _ => assert_eq!(inner, c.to_string()),
            }
            false
        };
        if escaped {
            if let Some(last) = out.last_mut() {
                if last.1 + 1 == cp {
                    last.1 = cp;
                    continue;
                }
            }
            out.push((cp, cp));
        }
    }
    // Context independence: escaping a character does not depend on its
    // neighbours.
    for &(a, b) in &[("a", "\u{300}"), ("\u{300}", "\u{300}"), ("\u{1100}", "\u{1161}")] {
        let s = format!("{}{}", a, b);
        let joined = format!("{:?}", s);
        let separate = format!("{:?}{:?}", a, b).replace("\"\"", "");
        assert_eq!(joined, separate);
    }
    let (maj, min, upd) = char::UNICODE_VERSION;
    println!("// Generated from Rust 1.97.1 (Unicode {maj}.{min}.{upd}) by");
    println!("// tools/oracle/rust_debug_escapes.rs. Do not edit.");
    println!();
    println!("///|");
    println!("/// Inclusive code point ranges of the characters that `<str as Debug>::fmt`");
    println!("/// writes as `\\u{{...}}`.");
    println!("let rust_debug_escaped_ranges : FixedArray[(Int, Int)] = [");
    for (a, b) in out {
        println!("  ({a}, {b}),");
    }
    println!("]");
}
