"""Compare public example trees with hashes frozen from the pinned C runtime.

The normal audit executes only the MoonBit CLI. Reference hash generation is a
separate development operation; see freeze_public_examples.py.
"""
import hashlib
import subprocess
import time


def audit(root, out, entry, repo, table, prefix):
    results = []
    for case in entry.get("examples", []):
        source = repo / case["path"]
        log = out / (entry["name"] + "-example-" + source.name)
        start = time.monotonic()
        with log.with_suffix(log.suffix + ".sexp").open("wb") as stdout, \
                log.with_suffix(log.suffix + ".stderr").open("wb") as stderr:
            try:
                code = subprocess.run(prefix + ["parse", str(table), str(source)],
                                      cwd=root, stdout=stdout, stderr=stderr,
                                      timeout=120).returncode
            except subprocess.TimeoutExpired:
                code = 124
                stderr.write(b"AUDIT TIMEOUT after 120 seconds\n")
        actual = hashlib.sha256(log.with_suffix(log.suffix + ".sexp").read_bytes()).hexdigest()
        results.append({"file": case["path"], "bytes": source.stat().st_size,
                        "exit_code": code, "sexp_sha256": actual,
                        "passed": code == 0 and actual == case["sexp_sha256"],
                        "seconds": round(time.monotonic() - start, 3)})
    return {"pass": sum(row["passed"] for row in results),
            "fail": sum(not row["passed"] for row in results), "files": results}
