"""Patch a copy of upstream crates/generate so `render_c_code` dumps its inputs.

Usage: python3 -I patch.py <copy>/crates/generate/src
Development-only differential harness for generate/render.mbt.
"""

import sys

src = sys.argv[1]


def patch(name, old, new):
    path = f"{src}/{name}"
    with open(path) as f:
        text = f.read()
    if new in text:
        return
    assert old in text, (path, old)
    with open(path, "w") as f:
        f.write(text.replace(old, new, 1))


patch(
    "nfa.rs",
    "impl CharacterSet {\n",
    "impl CharacterSet {\n"
    "    pub fn dump_raw_ranges(&self) -> Vec<(u32, u32)> {\n"
    "        self.ranges.iter().map(|r| (r.start, r.end)).collect()\n"
    "    }\n\n",
)
patch(
    "strpool.rs",
    "impl StrPool {\n",
    "impl StrPool {\n"
    "    pub fn dump_strings(&self) -> Vec<&str> {\n"
    "        (0..self.spans.len())\n"
    "            .map(|i| Self::span_str(&self.buf, &self.spans, StrId::from_raw(i as u32 + 1)))\n"
    "            .collect()\n"
    "    }\n\n",
)
patch("generate.rs", "mod render;\n", "mod render;\nmod render_dump;\n")
patch(
    "render.rs",
    """        Err(RenderError::ABI(abi_version))?;
    }
""",
    """        Err(RenderError::ABI(abi_version))?;
    }
    if let Ok(path) = std::env::var("TS_RENDER_DUMP") {
        let json = crate::render_dump::dump(
            name,
            &tables,
            &syntax_grammar,
            &lexical_grammar,
            &default_aliases,
            &str_pool,
            abi_version,
            semantic_version,
            &supertype_symbol_map,
        );
        std::fs::write(path, json).unwrap();
    }
""",
)
