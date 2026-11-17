class_name EventNames
extends RefCounted
## The signals of the Events bus (GDD 13.6). These are the only things the
## simulation may announce: DriveSim refuses any other name, and the Events
## autoload declares one signal for each.

const ALL: PackedStringArray = [
	"leg_started", "leg_ended", "fork_taken", "stop_entered", "stop_left",
	"boss_started", "boss_ended", "ritual_completed", "item_bought",
	"effect_added", "effect_expired", "nerves_threshold_crossed", "snap",
	"blink", "nod", "lamp_lit", "fault_repaired", "hit", "close_call",
	"suspicion_changed", "pulled_over", "heckle_started", "heckle_resolved",
	"passenger_boarded", "passenger_left", "call_started", "call_resolved",
	"wreck", "arrived", "line_requested", "sfx_requested",
]
