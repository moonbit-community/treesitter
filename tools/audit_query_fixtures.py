"""Execute pinned public highlight/tag assertions through the MoonBit CLI.

This development harness supports the ASCII position comments present in the
pinned C and JavaScript suites. It rejects non-ASCII input instead of treating
Unicode scalar or byte columns as upstream's grapheme columns. Comments are
obtained from the MoonBit query engine, not guessed from source text.
"""
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import subprocess


class HighlightHTML(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.text = ""
        self.spans = []

    def handle_starttag(self, tag, attrs):
        if tag != "span":
            raise ValueError(f"unexpected HTML element {tag}")
        self.stack.append(dict(attrs)["class"])

    def handle_endtag(self, tag):
        if tag != "span" or not self.stack:
            raise ValueError("unbalanced highlight HTML")
        self.stack.pop()

    def handle_data(self, data):
        start = len(self.text)
        self.text += data
        if self.stack:
            self.spans.append((start, len(self.text), self.stack[-1]))


def assertions(source, comments):
    if not source.isascii():
        raise ValueError("public fixture harness requires ASCII position comments/source")
    lines = source.splitlines(keepends=True)
    offsets = [0]
    for line in lines:
        offsets.append(offsets[-1] + len(line))
    pending = []
    assertion_rows = set()
    for comment in comments:
        row = comment["range"]["start_point"]["row"]
        column = comment["range"]["start_point"]["column"]
        arrow = re.search(r"\^+|<-", comment["text"])
        if row == 0 or arrow is None:
            continue
        suffix = comment["text"][arrow.end():]
        name = re.search(r"[\w_.-]+", suffix)
        if name is None:
            continue
        negative = suffix.lstrip().startswith("!")
        if arrow.group().startswith("^"):
            column += arrow.start()
            length = len(arrow.group())
        else:
            length = 1
        assertion_rows.add(row)
        pending.append((row, column, length, name.group(), negative))
    result = []
    for row, column, length, name, negative in pending:
        original = row
        while row in assertion_rows or len(lines[row]) <= column:
            if row == 0:
                raise ValueError(f"no source line for assertion on line {original + 1}")
            row -= 1
        result.append((offsets[row] + column, length, name, negative, row + 1, column))
    return result


def audit(root, out, entry, repo, table, cli):
    files = [(kind, path) for kind in ("highlight", "tags")
             for path in sorted((repo / "test" / kind).rglob("*")) if path.is_file()]
    if not files:
        return {"pass": 0, "fail": 0, "assertions": 0, "files": []}
    fixture = out / "query-fixtures" / entry["name"]
    fixture.mkdir(parents=True, exist_ok=True)
    # Keep all upstream inputs untouched, and isolate discovery from user config.
    for name, target in [("tree-sitter.json", repo / "tree-sitter.json"),
                         ("queries", repo / "queries"), ("language.json", table)]:
        link = fixture / name
        if link.is_symlink():
            link.unlink()
        link.symlink_to(target)
    (fixture / "config.json").write_text('{"parser-directories": []}\n')
    comment_query = fixture / "comments.scm"
    comment_query.write_text("(comment) @comment\n")
    env = dict(os.environ, TREESITTER_MBT_ROOT=str(root), TREE_SITTER_DIR=str(fixture))
    command = [str(cli)]
    if "scanner" in entry:
        command += ["--scanner", str(root / entry["scanner"])]

    def run(args, log):
        result = subprocess.run(command + args, cwd=fixture, env=env,
                                capture_output=True, text=True, timeout=120)
        log.write_text(result.stdout)
        log.with_suffix(log.suffix + ".stderr").write_text(result.stderr)
        if result.returncode:
            raise ValueError(f"CLI exit {result.returncode}: {result.stderr[-1000:]}")
        return result.stdout

    results = []
    for kind, path in files:
        item = {"file": str(path.relative_to(repo)), "assertions": 0, "failures": []}
        log = out / f"{entry['name']}-{kind}-{path.stem}.log"
        try:
            source = path.read_text()
            comments = [json.loads(line) for line in run(
                ["query", str(table), str(comment_query), str(path)],
                log.with_suffix(".comments.jsonl")).splitlines()]
            expected = assertions(source, comments)
            if not expected:
                raise ValueError("fixture contains no recognized assertions")
            output = run([kind, str(path)], log)
            if kind == "highlight":
                html = HighlightHTML()
                html.feed(output)
                html.close()
                if html.stack or html.text != source + "\n":
                    raise ValueError("highlight output is unbalanced or changes source text")
                spans = html.spans
            else:
                spans = [(tag["name_range"]["start_byte"], tag["name_range"]["end_byte"],
                          ("definition." if tag["definition"] else "reference.") + tag["kind"])
                         for tag in map(json.loads, output.splitlines())]
            for start, length, name, negative, row, column in expected:
                actual = sorted({value for left, right, value in spans
                                 if left < start + length and right > start})
                if not any((value == name) != negative for value in actual):
                    item["failures"].append({"row": row, "column": column,
                                             "expected": ("!" if negative else "") + name,
                                             "actual": actual})
            item["assertions"] = len(expected)
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            item["failures"].append({"error": str(error)})
        results.append(item)
    return {"pass": sum(not item["failures"] for item in results),
            "fail": sum(bool(item["failures"]) for item in results),
            "assertions": sum(item["assertions"] for item in results), "files": results}
