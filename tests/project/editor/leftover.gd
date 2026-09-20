##
## A file an export drops, under a directory `export_overrides.cfg` excludes. Nothing an
## export keeps may reach it through an `[ext_resource]` header; `main.tscn` holds its
## uid as a string, which is what `export-ref` has to let through.
##

extends Node
