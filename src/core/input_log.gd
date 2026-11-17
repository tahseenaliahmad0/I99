class_name InputLog
extends RefCounted
## What the player did, tick by tick (GDD 13.3). Replaying a log into a
## simulation that was started the same way gives the same Telling: the same
## final state hash.

const LMB: int = 1
const RMB: int = 2
const PAD_HORN: int = 4
const PAD_WIPER: int = 8
const ABSOLUTE: int = 16
const MARK: String = "I99-INPUT-LOG-1"

var _flags: PackedByteArray = PackedByteArray()
var _delta: PackedVector2Array = PackedVector2Array()
## Where the pointer was named to be, for ticks whose input says so (touch).
var _pointer: PackedVector2Array = PackedVector2Array()


func clear() -> void:
	_flags = PackedByteArray()
	_delta = PackedVector2Array()
	_pointer = PackedVector2Array()


## Ticks recorded.
func size() -> int:
	return _flags.size()


func record(input: DriveInput) -> void:
	var flags: int = 0
	if input.lmb:
		flags |= LMB
	if input.rmb:
		flags |= RMB
	if input.pad_horn:
		flags |= PAD_HORN
	if input.pad_wiper:
		flags |= PAD_WIPER
	if input.pointer_is_absolute:
		flags |= ABSOLUTE
	_flags.append(flags)
	_delta.append(input.pointer_delta)
	_pointer.append(input.pointer if input.pointer_is_absolute else Vector2.ZERO)


## Writes tick `index` of the log into `input`.
func read(index: int, input: DriveInput) -> void:
	var flags: int = _flags[index]
	input.lmb = flags & LMB != 0
	input.rmb = flags & RMB != 0
	input.pad_horn = flags & PAD_HORN != 0
	input.pad_wiper = flags & PAD_WIPER != 0
	input.pointer_is_absolute = flags & ABSOLUTE != 0
	input.pointer_delta = _delta[index]
	input.pointer = _pointer[index]


## The log as bytes (for a file), and back. The bytes begin with a mark, so
## that what is no log is not read as one.
func to_bytes() -> PackedByteArray:
	var bytes: PackedByteArray = MARK.to_ascii_buffer()
	bytes.append_array(var_to_bytes([_flags, _delta, _pointer]))
	return bytes


static func from_bytes(bytes: PackedByteArray) -> InputLog:
	var log: InputLog = InputLog.new()
	var mark: PackedByteArray = MARK.to_ascii_buffer()
	if bytes.size() <= mark.size() or bytes.slice(0, mark.size()) != mark:
		return log
	var parts: Variant = bytes_to_var(bytes.slice(mark.size()))
	if parts is Array and (parts as Array).size() == 3:
		var list: Array = parts
		if list[0] is PackedByteArray and list[1] is PackedVector2Array and list[2] is PackedVector2Array:
			log._flags = list[0]
			log._delta = list[1]
			log._pointer = list[2]
			if log._delta.size() != log._flags.size() or log._pointer.size() != log._flags.size():
				log.clear()
	return log
