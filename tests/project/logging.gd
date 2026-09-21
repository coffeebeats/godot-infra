##
## A file the `logging` rule must report nothing in. Every line below names a function
## the rule matches, in a position where naming it is not calling it: a doc comment, a
## string, a multi-line string, and a method on an object.
##
## NOTE: A green run proves only that the rule raises no false positive. Nothing here
## can prove it still reports a real call, because CI asserts this project is clean.
##

extends Node

## PATTERN holds the opening of a `print()` call as data. This comment names one too.
const PATTERN := "print("

## BANNER holds two more call openings across a span the mask has to cover at once.
const BANNER := """
push_error(
push_warning(
"""

## _logger stands in for a logger, so the call below is dotted rather than bare.
var _logger: Variant = null


## describe hands the logger a message rather than printing one.
func describe() -> void:
	_logger.print_rich(PATTERN + BANNER)
