"""Extra grammar.json cases for the node-types oracle (error paths and edge
cases the upstream fixtures do not reach).

Usage: extra_node_types_grammars.py <out-dir>  (writes <out-dir>/<name>/src/grammar.json)
"""

import json
import os
import sys

root = sys.argv[1]


def S(n):
    return {"type": "SYMBOL", "name": n}


def T(v):
    return {"type": "STRING", "value": v}


def P(v):
    return {"type": "PATTERN", "value": v}


def seq(*m):
    return {"type": "SEQ", "members": list(m)}


def choice(*m):
    return {"type": "CHOICE", "members": list(m)}


def rep(c):
    return {"type": "REPEAT", "content": c}


def field(n, c):
    return {"type": "FIELD", "name": n, "content": c}


def alias(c, v, named):
    return {"type": "ALIAS", "content": c, "named": named, "value": v}


BLANK = {"type": "BLANK"}

grammars = {
    # A supertype with a multi-step production (InvalidSupertypeError, no child).
    "extra_invalid_supertype_direct": {
        "rules": {
            "doc": rep(S("_sup")),
            "_sup": choice(S("a"), seq(S("a"), S("b"))),
            "a": T("a"),
            "b": T("b"),
        },
        "supertypes": ["_sup"],
    },
    # A supertype whose hidden child expands to several nodes (with child).
    "extra_invalid_supertype_hidden_child": {
        "rules": {
            "doc": rep(S("_sup")),
            "_sup": choice(S("a"), S("_pair")),
            "_pair": seq(S("a"), S("b")),
            "a": P("a+"),
            "b": T("b"),
        },
        "supertypes": ["_sup"],
    },
    # Nested supertypes, fields through hidden rules, aliases, JSON escapes.
    "extra_nested_supertypes": {
        "rules": {
            "doc": rep(choice(S("_stmt"), S("_expr"))),
            "_stmt": choice(S("expr_stmt"), S("block")),
            "expr_stmt": seq(field("value", S("_expr")), T(";")),
            "block": seq(T("{"), rep(S("_stmt")), T("}")),
            "_expr": choice(
                S("_lit"), S("ident"), S("call"), alias(S("ident"), 'type\u0001"q"\\', True)
            ),
            "_lit": choice(
                S("number"), S("string"), alias(T("\n\t\u001f\u007fé"), "ctl\b\f\r", False)
            ),
            "call": seq(field("function", S("_expr")), T("("), choice(S("_args"), BLANK), T(")")),
            "_args": seq(field("arg", S("_expr")), rep(seq(T(","), field("arg", S("_expr"))))),
            "number": P("\\d+"),
            "string": P('"[^"]*"'),
            "ident": P("[a-z]+"),
            "comment": P("#.*"),
        },
        "supertypes": ["_stmt", "_expr", "_lit"],
        "extras": [P("\\s"), S("comment")],
    },
}

for name, g in grammars.items():
    d = os.path.join(root, name, "src")
    os.makedirs(d, exist_ok=True)
    full = {"name": name, "rules": g["rules"]}
    for key in ("supertypes", "extras"):
        if key in g:
            full[key] = g[key]
    with open(os.path.join(d, "grammar.json"), "w") as f:
        json.dump(full, f, indent=2)
