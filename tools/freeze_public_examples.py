"""Reproduce public-example S-expression hashes with the pinned C reference.

Development only: requires cc and clean pinned checkouts from the grammar matrix,
plus .repos/tree-sitter at the port's baseline. Writes reference trees and a hash
report under _build/public-examples, never changes the committed expectations.
Normal CI consumes those hashes without compiling or executing C.
"""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "_build/public-examples"
BASELINE = "4a412a01a0147d0f50bf7e749572fa632d1ab203"


def checked_checkout(path, revision):
    actual = subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"],
                                     text=True).strip()
    dirty = subprocess.check_output(["git", "-C", str(path), "status", "--porcelain",
                                     "--untracked-files=no"], text=True)
    if actual != revision or dirty:
        raise RuntimeError(f"{path} must be a clean checkout at {revision}")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    runtime = ROOT / ".repos/tree-sitter"
    checked_checkout(runtime, BASELINE)
    common = ["cc", "-O2", "-I" + str(runtime / "lib/include")]
    subprocess.run(common + ["-I" + str(runtime / "lib/src"), "-c",
                            str(runtime / "lib/src/lib.c"), "-o", str(OUT / "runtime.o")],
                   check=True)
    rows = []
    for entry in json.loads((ROOT / "tools/grammar_matrix.json").read_text()):
        if not entry.get("examples"):
            continue
        name = entry["name"]
        repo = ROOT / ".repos" / ("tree-sitter-" + name)
        checked_checkout(repo, entry["revision"])
        command = common + ["-I" + str(repo / "src"), "-DLANGUAGE=tree_sitter_" + name,
                            str(ROOT / "tools/reference_examples.c"), str(OUT / "runtime.o"),
                            str(repo / "src/parser.c")]
        if (repo / "src/scanner.c").exists():
            command.append(str(repo / "src/scanner.c"))
        executable = OUT / name
        subprocess.run(command + ["-o", str(executable)], check=True)
        for case in entry["examples"]:
            source = repo / case["path"]
            result = subprocess.run([str(executable), str(source)], check=True,
                                    capture_output=True, timeout=120)
            digest = hashlib.sha256(result.stdout).hexdigest()
            (OUT / (name + "-" + source.name + ".sexp")).write_bytes(result.stdout)
            row = {"grammar": name, "file": case["path"], "sexp_sha256": digest,
                   "matches_expected": digest == case["sexp_sha256"]}
            rows.append(row)
            print(json.dumps(row), flush=True)
    (OUT / "reference-hashes.json").write_text(json.dumps(rows, indent=2) + "\n")
    return 0 if all(row["matches_expected"] for row in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
