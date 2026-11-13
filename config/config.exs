import Config

# Code blocks are highlighted at build time by Lumis (tree-sitter), inside the
# Markdown NIF. Each language is its own `lumis_wasm_*` dependency (mix.exs).
config :mdex_native, syntax_highlighter: :lumis
