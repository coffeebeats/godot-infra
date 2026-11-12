##
## A script preloading a scene whose root carries the script preloading this one. Its
## loop closes through that script's preload, which the script cache allows.
##

extends RefCounted

const Scene := preload("chain.tscn")
