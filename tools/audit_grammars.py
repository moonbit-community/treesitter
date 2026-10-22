"""Run pinned public grammar corpora through the pure MoonBit implementation.

Usage: python3 tools/audit_grammars.py [--fetch] [json c javascript go]
Clones live under .repos; generated tables, complete logs and results.json live
under _build/grammar-matrix. No JavaScript or C grammar code is executed: the
upstream grammar JSON is input to the MoonBit generator, and external scanners
are compiled from the checked-in MoonBit translations.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "_build/grammar-matrix"
MANIFEST = json.loads((ROOT / "tools/grammar_matrix.json").read_text())


def run_logged(command, path, timeout):
    with path.open("w") as log:
        try:
            return subprocess.run(command, cwd=ROOT, stdout=log,
                                  stderr=subprocess.STDOUT, timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            log.write(f"\nAUDIT TIMEOUT after {timeout} seconds\n")
            return 124


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", action="store_true", help="fetch missing pinned checkouts")
    parser.add_argument("names", nargs="*")
    args = parser.parse_args()
    known = {entry["name"] for entry in MANIFEST}
    if set(args.names) - known:
        parser.error("unknown grammar: " + ", ".join(sorted(set(args.names) - known)))
    OUT.mkdir(parents=True, exist_ok=True)
    subprocess.run(["moon", "build", "--target", "native", "--release", "cmd/treesitter"],
                   cwd=ROOT, check=True)
    cli = ROOT / "_build/native/release/build/cmd/treesitter/treesitter.exe"
    results = []
    for entry in MANIFEST:
        name = entry["name"]
        if args.names and name not in args.names:
            continue
        result = dict(entry)
        start = time.monotonic()
        repo = ROOT / ".repos" / ("tree-sitter-" + name)
        try:
            if not repo.exists():
                if not args.fetch:
                    raise RuntimeError("missing checkout; rerun with --fetch")
                repo.parent.mkdir(parents=True, exist_ok=True)
                subprocess.run(["git", "init", str(repo)], check=True, capture_output=True)
                subprocess.run(["git", "-C", str(repo), "fetch", "--depth=1",
                                entry["repository"], entry["revision"]], check=True,
                               capture_output=True)
                subprocess.run(["git", "-C", str(repo), "checkout", "--detach", "FETCH_HEAD"],
                               check=True, capture_output=True)
            revision = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"],
                                               text=True).strip()
            if revision != entry["revision"]:
                raise RuntimeError(f"checkout revision {revision} differs from pinned revision")
            dirty = subprocess.check_output(["git", "-C", str(repo), "status", "--porcelain",
                                             "--untracked-files=no"], text=True)
            if dirty:
                raise RuntimeError("checkout has modified tracked files")
            table = OUT / (name + ".language.json")
            code = run_logged([str(cli), "generate", str(repo / "src/grammar.json"), str(table)],
                              OUT / (name + "-generate.log"), 600)
            if code:
                result.update(status="generation-failed", exit_code=code)
            else:
                command = [str(cli)]
                if "scanner" in entry:
                    command += ["--scanner", str(ROOT / entry["scanner"])]
                command += ["test", str(table), str(repo / "test/corpus")]
                log = OUT / (name + "-corpus.log")
                code = run_logged(command, log, 600)
                lines = log.read_text().splitlines()
                counts = {status.lower(): sum(line.startswith(status + " ") for line in lines)
                          for status in ["PASS", "FAIL", "SKIP"]}
                result.update(status="passed" if code == 0 and counts["pass"] > 0
                              and counts["fail"] == 0 else "corpus-failed", exit_code=code,
                              counts=counts, failures=[line[5:] for line in lines
                                                      if line.startswith("FAIL ")])
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            result.update(status="setup-failed", error=str(error))
        result["seconds"] = round(time.monotonic() - start, 2)
        results.append(result)
        print(json.dumps(result), flush=True)
        (OUT / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    return 0 if all(result["status"] == "passed" for result in results) else 1


if __name__ == "__main__":
    sys.exit(main())
