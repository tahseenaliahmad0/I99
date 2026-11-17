class_name DriveInput
extends RefCounted
## One tick of player input (GDD 13.3).
##
## Everything is in reference pixels: the pixels of a 1080-high view (GDD 4.3).
## The drive controller scales real mouse motion by reference_height / window
## height before it gets here, so the simulation never sees the window.
##
## The mouse is captured and the simulation keeps the pointer itself from
## `pointer_delta` (GDD 4.1). `pointer` is only read when `pointer_is_absolute`
## is true: touch input, where the thumb names a place instead of a motion.

var pointer: Vector2 = Vector2.ZERO
var pointer_delta: Vector2 = Vector2.ZERO
var pointer_is_absolute: bool = false
var lmb: bool = false
var rmb: bool = false
var pad_horn: bool = false
var pad_wiper: bool = false


func clear() -> void:
	pointer = Vector2.ZERO
	pointer_delta = Vector2.ZERO
	pointer_is_absolute = false
	lmb = false
	rmb = false
	pad_horn = false
	pad_wiper = false


func copy_from(other: DriveInput) -> void:
	pointer = other.pointer
	pointer_delta = other.pointer_delta
	pointer_is_absolute = other.pointer_is_absolute
	lmb = other.lmb
	rmb = other.rmb
	pad_horn = other.pad_horn
	pad_wiper = other.pad_wiper
