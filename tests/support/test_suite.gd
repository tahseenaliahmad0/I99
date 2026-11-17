class_name TestSuite
extends RefCounted
## Base class of every tests/test_*.gd script.
##
## A test is a method named after its id in tests/tests.json:
##   T-HAND-01        -> func test_hand_01() -> void
##   T-ITEM-TEA-GLASS -> func test_item_tea_glass() -> void
## A test passes when every check passes, at least one check ran, and no engine
## or script error was logged while it ran. Tests read numbers from tuning and
## data, never from literals of their own (GDD 1.4, rule 4).

## Shared, read-only game data. Use fresh_data() before changing anything.
var data: GameData
var tuning: Tuning

var _failures: PackedStringArray = []
var _notes: PackedStringArray = []
var _checks: int = 0


## Optional hooks.
func before_each() -> void:
	pass


func after_each() -> void:
	pass


## A private copy of the game data, safe to modify.
func fresh_data() -> GameData:
	return GameData.load_from(data.dir)


func check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
	return condition


func check_eq(actual: Variant, expected: Variant, message: String) -> bool:
	_checks += 1
	var same: bool = typeof(actual) == typeof(expected) and actual == expected
	if not same and GameData.is_number(actual) and GameData.is_number(expected):
		same = GameData.as_float(actual) == GameData.as_float(expected)
	if not same:
		_failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])
	return same


func check_near(actual: float, expected: float, tolerance: float, message: String) -> bool:
	_checks += 1
	var ok: bool = absf(actual - expected) <= tolerance
	if not ok:
		_failures.append("%s: expected %s within %s, got %s" % [message, str(expected), str(tolerance), str(actual)])
	return ok


func check_between(actual: float, low: float, high: float, message: String) -> bool:
	_checks += 1
	var ok: bool = actual >= low and actual <= high
	if not ok:
		_failures.append("%s: expected %s to %s, got %s" % [message, str(low), str(high), str(actual)])
	return ok


func fail(message: String) -> void:
	_checks += 1
	_failures.append(message)


## Extra information printed with the test's result line.
func note(message: String) -> void:
	_notes.append(message)


# --- Used by the runner ------------------------------------------------------

func reset_case() -> void:
	_failures = PackedStringArray()
	_notes = PackedStringArray()
	_checks = 0


func case_failures() -> PackedStringArray:
	return _failures


func case_notes() -> PackedStringArray:
	return _notes


func case_checks() -> int:
	return _checks
