class_name ErrorTrap
extends Logger
## Counts engine and script errors while a test runs.
##
## GDScript has no exceptions: a runtime error aborts the current function and
## the caller carries on. Without this trap, a test that crashed half-way
## could still be reported as passing. The runner registers one ErrorTrap and
## fails any test during which an error was logged.
##
## Logger callbacks may arrive from any thread and must not log themselves.

var _mutex: Mutex = Mutex.new()
var _count: int = 0
var _first: String = ""


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	_mutex.lock()
	_count += 1
	if _first.is_empty():
		var message: String = rationale if not rationale.is_empty() else code
		_first = "%s (%s:%d in %s)" % [message, file, line, function]
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


func reset() -> void:
	_mutex.lock()
	_count = 0
	_first = ""
	_mutex.unlock()


func count() -> int:
	_mutex.lock()
	var out: int = _count
	_mutex.unlock()
	return out


func first() -> String:
	_mutex.lock()
	var out: String = _first
	_mutex.unlock()
	return out
