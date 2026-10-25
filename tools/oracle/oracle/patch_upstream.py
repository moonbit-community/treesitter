"""Patch a scratch copy of upstream `crates/generate` for the differential oracle.

Usage: patch_upstream.py <scratch-workspace> <pinned-upstream-checkout>

Never touches the pinned checkout: it only reads its Cargo.toml.
"""

import os
import shutil
import sys

ws, upstream = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(ws, "crates/generate/src")


def edit(path, old, new):
    path = os.path.join(src, path)
    text = open(path).read()
    if new in text:
        return
    if text.count(old) != 1:
        sys.exit(f"patch anchor not found exactly once in {path}: {old!r}")
    open(path, "w").write(text.replace(old, new))


# A standalone workspace with only the generate crate.
lines = open(os.path.join(upstream, "Cargo.toml")).read().splitlines()
start = lines.index("[workspace.package]")
manifest = ['[workspace]', 'members = [ "crates/generate" ]', 'resolver = "2"', ""]
manifest += [line for line in lines[start:] if 'path = "./' not in line]
open(os.path.join(ws, "Cargo.toml"), "w").write("\n".join(manifest) + "\n")

shutil.copy(os.path.join(here, "harness.rs"), os.path.join(src, "harness.rs"))
os.makedirs(os.path.join(ws, "crates/generate/examples"), exist_ok=True)
shutil.copy(os.path.join(here, "nt_dump.rs"), os.path.join(ws, "crates/generate/examples/nt_dump.rs"))

edit("generate.rs", "mod node_types;\n", "mod node_types;\npub mod harness;\n")
edit(
    "strpool.rs",
    "    #[must_use]\n    pub fn resolve(",
    "    pub fn all_strings(&self) -> Vec<&str> {\n"
    "        (0..self.spans.len()).map(|i| self.resolve(StrId::from_raw(i as u32 + 1))).collect()\n"
    "    }\n\n"
    "    #[must_use]\n    pub fn resolve(",
)
edit(
    "node_types.rs",
    "impl ChildQuantity {\n",
    "impl ChildQuantity {\n"
    "    pub const fn exists(&self) -> bool { self.exists }\n"
    "    pub const fn required(&self) -> bool { self.required }\n"
    "    pub const fn multiple(&self) -> bool { self.multiple }\n\n",
)
# Dump the prepared grammars of the upstream unit tests (NT_TEST_DUMP_DIR).
edit(
    "node_types.rs",
    """        } = prepare_grammar(grammar, &mut Vec::new()).unwrap();
        let variable_info = get_variable_info(""",
    """        } = prepare_grammar(grammar, &mut Vec::new()).unwrap();
        if let Ok(dir) = std::env::var("NT_TEST_DUMP_DIR") {
            let name = std::thread::current().name().unwrap_or("unknown").replace("::", "_");
            let mut n = 0;
            while std::path::Path::new(&format!("{dir}/{name}_{n}.input.json")).exists() {
                n += 1;
            }
            let (inputs, expected) = crate::harness::dump_prepared(
                &syntax_grammar, &lexical_grammar, &default_aliases, &inlines, &str_pool,
            );
            std::fs::write(format!("{dir}/{name}_{n}.input.json"), inputs.unwrap()).unwrap();
            std::fs::write(format!("{dir}/{name}_{n}.expected.json"), expected).unwrap();
        }
        let variable_info = get_variable_info(""",
)
edit(
    "node_types.rs",
    """        } = prepare_grammar(grammar, &mut Vec::new()).unwrap();
        let error = get_variable_info(""",
    """        } = prepare_grammar(grammar, &mut Vec::new()).unwrap();
        if let Ok(dir) = std::env::var("NT_TEST_DUMP_DIR") {
            let (inputs, expected) = crate::harness::dump_prepared(
                &syntax_grammar, &lexical_grammar, &default_aliases, &inlines, &str_pool,
            );
            let name = "node_types_tests_test_node_types_with_alias_matching_canonical_supertype_0";
            std::fs::write(format!("{dir}/{name}.input.json"), inputs.unwrap()).unwrap();
            std::fs::write(format!("{dir}/{name}.expected.json"), expected).unwrap();
        }
        let error = get_variable_info(""",
)
print("patched", ws)
