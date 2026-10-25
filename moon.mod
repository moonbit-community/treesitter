name = "moonbit-community/treesitter"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/moonbit-community/treesitter"

license = "MIT"

description = "An experimental pure MoonBit port of Tree-sitter, with mbtx grammar definitions."

import {
  "moonbitlang/async@0.20.2",
}

options(
  exclude: [ "grammars", "moon.work" ],
)
