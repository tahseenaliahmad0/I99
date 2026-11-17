extends Node
## The Events bus (GDD 13.6).
##
## The simulation is pure and reports what happened as plain dictionaries. The
## drive controller forwards each one here by name, and views, audio and
## subtitles listen. Every signal carries one Dictionary payload, so this list
## is the whole contract between the simulation and everything that shows it.

signal leg_started(data: Dictionary)
signal leg_ended(data: Dictionary)
signal fork_taken(data: Dictionary)
signal stop_entered(data: Dictionary)
signal stop_left(data: Dictionary)
signal boss_started(data: Dictionary)
signal boss_ended(data: Dictionary)
signal ritual_completed(data: Dictionary)
signal item_bought(data: Dictionary)
signal effect_added(data: Dictionary)
signal effect_expired(data: Dictionary)
signal nerves_threshold_crossed(data: Dictionary)
signal snap(data: Dictionary)
signal blink(data: Dictionary)
signal nod(data: Dictionary)
signal lamp_lit(data: Dictionary)
signal fault_repaired(data: Dictionary)
signal hit(data: Dictionary)
signal close_call(data: Dictionary)
signal suspicion_changed(data: Dictionary)
signal pulled_over(data: Dictionary)
signal heckle_started(data: Dictionary)
signal heckle_resolved(data: Dictionary)
signal passenger_boarded(data: Dictionary)
signal passenger_left(data: Dictionary)
signal call_started(data: Dictionary)
signal call_resolved(data: Dictionary)
signal wreck(data: Dictionary)
signal arrived(data: Dictionary)
signal line_requested(data: Dictionary)
signal sfx_requested(data: Dictionary)

const NAMES: PackedStringArray = [
	"leg_started", "leg_ended", "fork_taken", "stop_entered", "stop_left",
	"boss_started", "boss_ended", "ritual_completed", "item_bought",
	"effect_added", "effect_expired", "nerves_threshold_crossed", "snap",
	"blink", "nod", "lamp_lit", "fault_repaired", "hit", "close_call",
	"suspicion_changed", "pulled_over", "heckle_started", "heckle_resolved",
	"passenger_boarded", "passenger_left", "call_started", "call_resolved",
	"wreck", "arrived", "line_requested", "sfx_requested",
]


## Forwards one simulation event. `event_name` must be one of NAMES.
func emit_event(event_name: String, data: Dictionary) -> void:
	if not NAMES.has(event_name):
		push_error("Events: '%s' is not a signal on the bus (GDD 13.6)" % event_name)
		return
	emit_signal(event_name, data)
