# JavaScript compatibility scanner

`scanner.mbtx` is a pure MoonBit translation of the external scanner in
[tree-sitter-javascript v0.25.0](https://github.com/tree-sitter/tree-sitter-javascript/tree/v0.25.0).
It implements automatic semicolon insertion, template text, ternary question
marks, HTML comments, and JSX text. It uses the port's Unicode Alphabetic table
instead of the host C library's locale-dependent `iswalpha`.

From the repository root, run:

```sh
python3 tools/audit_grammars.py --fetch javascript
```

The audit verifies the upstream commit, generates parsing tables from the
upstream grammar JSON using the MoonBit generator, compiles this scanner, and
runs the unchanged upstream corpus. Logs and a machine-readable report are
written to `_build/grammar-matrix/`. A failure exits nonzero. The JSON and C
corpora can be included by omitting the language argument.

This is a compatibility test fixture, not a claim of complete JavaScript support.
Remaining failures are recorded in the audit report and project plan. Original
copyright and license terms are preserved in `LICENSE`.
