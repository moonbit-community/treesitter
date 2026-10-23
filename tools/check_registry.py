"""Verify an already published version without using the local checkout.

Usage: python3 tools/check_registry.py 0.1.0
The MoonBit toolchain and Node must be on PATH. All generated projects and
binaries live in a temporary directory outside this repository.
"""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version):
        parser.error("expected a MAJOR.MINOR.PATCH version")
    root = Path(__file__).resolve().parents[1]
    env = os.environ.copy()
    env.pop("TREESITTER_MBT_ROOT", None)
    with tempfile.TemporaryDirectory(prefix="treesitter-registry-") as directory:
        temp = Path(directory).resolve()
        if temp.is_relative_to(root):
            raise RuntimeError("temporary directory must be outside the checkout")

        def run(*command, cwd=temp):
            result = subprocess.run(command, cwd=cwd, env=env, text=True,
                                    stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=600)
            print(result.stdout, end="", flush=True)
            result.check_returncode()
            return result.stdout

        project = temp / "consumer"
        project.mkdir()
        (project / "moon.mod").write_text(
            'name = "release/consumer"\nimport { '
            f'"moonbit-community/treesitter@{args.version}" }}\n')
        (project / "moon.pkg").write_text('''import {
  "moonbit-community/treesitter" @ts,
  "moonbit-community/treesitter/grammar",
  "moonbit-community/treesitter/generate",
}
''')
        (project / "consumer_test.mbt").write_text('''///|
test "registry grammar and runtime" {
  let grammar = @grammar.Grammar::new("words", [
    ("document", Repeat(Symbol("word"))),
    ("word", @grammar.pattern("[a-z]+")),
  ])
  let language = @generate.generate(grammar)
  let tree = @ts.Parser::new(language).parse_string("hello moonbit")
  assert_eq(tree.root_node().to_sexp(), "(document (word) (word))")
}
''')
        run("moon", "update", cwd=project)
        for target in ("native", "js", "wasm-gc"):
            output = run("moon", "test", "--target", target, cwd=project)
            if not re.search(r"Total tests: 1, passed: 1, failed: 0\.", output):
                raise RuntimeError(f"missing successful {target} consumer test")
        installed = project / ".mooncakes/moonbit-community/treesitter/moon.mod"
        version = re.search(r'^version\s*=\s*"([^"]+)"',
                            installed.read_text(), re.M)
        if not version or version[1] != args.version:
            raise RuntimeError("consumer did not resolve the requested version")

        run("moon", "install",
            f"moonbit-community/treesitter/cmd/treesitter@{args.version}",
            "--bin", str(temp / "bin"))
        cli = str(temp / "bin/treesitter")
        version_output = run(cli, "--version")
        if version_output.strip() != f"treesitter.mbt {args.version}":
            raise RuntimeError("installed CLI version mismatch")
        run(cli, "init", "words", "words")
        run(cli, "generate", "words/grammar.mbtx", "words/language.json")
        output = run(cli, "test", "words/language.json", "words/test/corpus")
        if "PASS Words" not in output:
            raise RuntimeError("generated grammar corpus did not pass")

        shutil.copytree(root / "examples/quoted", temp / "quoted")
        run(cli, "generate", "quoted/grammar.mbtx", "quoted/language.json")
        output = run(cli, "--scanner", "quoted/scanner.mbtx", "parse",
                     "quoted/language.json", "quoted/sample.txt")
        expected = (temp / "quoted/expected.sexp").read_text()
        if output != expected:
            raise RuntimeError("registry scanner output differs from fixture")
        print(f"Registry verification passed for {args.version}", flush=True)


if __name__ == "__main__":
    main()
