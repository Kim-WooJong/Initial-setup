# Only imported on Nushell >=0.114.0.
# Native Unicode case conversion; no ASCII-only path/hash substitution.
export def text-lower []: string -> string { $in | str lowercase }
export def text-upper []: string -> string { $in | str uppercase }
