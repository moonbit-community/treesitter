// Reference iteration orders of `FxHashSet<u32>` built by `collect()`, as
// upstream's `AmbiguousExtraError` builds its parent symbol list.
use rustc_hash::FxHashSet;

fn main() {
    let mut state: u64 = 12345;
    let mut next = || {
        state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        (state >> 33) as u32
    };
    let mut out = String::new();
    for len in 0..60u32 {
        for modulus in [8u32, 100, 3000] {
            let values: Vec<u32> = (0..len).map(|_| next() % modulus).collect();
            let set = values
                .iter()
                .filter_map(|&v| Some(v))
                .collect::<FxHashSet<u32>>();
            out.push_str(
                &set.iter()
                    .map(|v| v.to_string())
                    .collect::<Vec<_>>()
                    .join(" "),
            );
            out.push('\n');
        }
    }
    std::fs::write(std::env::args().nth(1).unwrap(), out).unwrap();
}
