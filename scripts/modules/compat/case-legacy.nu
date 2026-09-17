# Only imported on Nushell 0.109.1 through 0.113.x.
# The syntax validator explicitly reports this adapter as inactive on >=0.114.
export def text-lower []: string -> string { $in | str downcase }
export def text-upper []: string -> string { $in | str upcase }
