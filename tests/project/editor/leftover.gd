##
## A file an export drops, under a directory `export_overrides.cfg` excludes. Nothing an
## export keeps may reach it through an `[ext_resource]` header; `main.tscn` holds its
## uid as a string, which is what `export-ref` has to let through.
##
## NOTE: `leftover.gd.uid` is committed. Without it an import assigns a fresh uid and
## the string in `main.tscn` resolves to nothing, which `path-ref` then reports.
##

extends Node
