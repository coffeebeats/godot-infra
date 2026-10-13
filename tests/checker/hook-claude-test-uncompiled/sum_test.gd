##
## The test beside `sum.gd`, which does not compile.
##

extends RefCounted


func test_sum() -> int:
	return Sum.missing()
