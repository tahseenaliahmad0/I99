class_name Guide
extends RefCounted
## What to do now, while the art is boxes (D-072): from the snapshot, the
## rows of the instruction that stands at the top of the view, each a line's
## id and the values it is formatted with; and the gear the moment asks for.
##
## It names no autoload (HintView turns the rows into words) and changes
## nothing. It says only what the rules already are: where a paper is, that
## the bar wants a car standing still, what a press on an offer does.

const GLOVEBOX_OPEN: String = "glovebox_open"
const WINDOW_OPEN: String = "window_open"
const LETTER_ASIDE: String = "letter_aside"
const GLOVEBOX_SLOT: String = "glovebox"


## The rows to show, top to bottom; none when nothing needs saying.
## `bribe` is what the soldier takes to ask nothing (tuning checkpoint_bribe).
static func rows(snapshot: Dictionary, bribe: float) -> Array[Array]:
	var out: Array[Array] = []
	var step: int = GameData.as_int(snapshot["prologue_step"])
	if step > 0:
		if GameData.as_bool(snapshot["prologue_done"]):
			out.append(["guide.prologue.done", []])
		elif step < PrologueSim.LIFT:
			out.append(["prologue.step.%d" % step, []])
		return out
	if GameData.as_bool(snapshot["wrecked"]):
		return out
	if GameData.as_bool(snapshot["stopped"]):
		out.append(["guide.stop", []])
		return out
	var phase: int = GameData.as_int(snapshot["checkpoint_phase"])
	if phase > 0:
		return _checkpoint(snapshot, phase, bribe)
	if GameData.as_bool(snapshot["pulled_over"]):
		out.append(["guide.pulled_over", []])
	elif str(snapshot["call"]) == BossSim.CALL_RINGING:
		out.append(["guide.call", []])
	elif str(snapshot["boss_now"]) == BossSim.ARRIVAL:
		out.append(["guide.arrival.key" if GameData.as_bool(snapshot["in_bay"]) else "guide.arrival", []])
	elif GameData.as_bool(snapshot["lever_blocked"]) and str(snapshot["hand_snap"]) == ActionFeedback.GEAR_LEVER:
		out.append(["guide.lever.blocked", []])
	return out


## The gear the moment asks for (0: none): third in the prologue's shift,
## first in a checkpoint's queue.
static func gear_wanted(snapshot: Dictionary) -> int:
	var step: int = GameData.as_int(snapshot["prologue_step"])
	if step == PrologueSim.SHIFT and not GameData.as_bool(snapshot["prologue_done"]):
		return PrologueSim.GEAR_TO
	if step == 0 and GameData.as_int(snapshot["checkpoint_phase"]) == BossSim.QUEUE:
		return 1
	return 0


static func _checkpoint(snapshot: Dictionary, phase: int, bribe: float) -> Array[Array]:
	var out: Array[Array] = []
	var flags: Dictionary = snapshot["flags"]
	match phase:
		BossSim.QUEUE:
			out.append(["guide.checkpoint.bar" if GameData.as_int(snapshot["queue_ahead"]) == 0 else "guide.checkpoint.queue", []])
		BossSim.STOW:
			out.append(["guide.checkpoint.stow", [str(ceili(GameData.as_float(snapshot["stow_left"])))]])
			if _contraband_in_view(snapshot) == 0:
				out.append(["guide.checkpoint.stow.clean", []])
			elif GameData.as_bool(flags.get(GLOVEBOX_OPEN)):
				out.append(["guide.checkpoint.stow.carry", []])
			else:
				out.append(["guide.checkpoint.stow.open", []])
		BossSim.PAPERS:
			var wanted: String = str(snapshot["wanted"])
			if wanted.is_empty():
				return out
			# Where the paper is, then the one thing to do next, then the
			# other way out.
			var at_hand: bool = true
			if wanted == "registration":
				if not GameData.as_bool(flags.get(GLOVEBOX_OPEN)):
					out.append(["guide.checkpoint.registration.closed", []])
					at_hand = false
				elif not GameData.as_bool(flags.get(LETTER_ASIDE)):
					out.append(["guide.checkpoint.registration.letter", []])
					at_hand = false
				else:
					out.append(["guide.checkpoint.registration", []])
			else:
				out.append(["guide.checkpoint.%s" % wanted, []])
			if not GameData.as_bool(flags.get(WINDOW_OPEN)):
				out.append(["guide.checkpoint.window", []])
			elif at_hand:
				out.append(["guide.checkpoint.hand", []])
			out.append(["guide.checkpoint.bribe", [str(roundi(bribe))]])
		BossSim.THROUGH:
			out.append(["guide.checkpoint.through", []])
	return out


## Contraband the soldier would see: not put away in a glovebox cell.
static func _contraband_in_view(snapshot: Dictionary) -> int:
	var count: int = 0
	var items: Array[Dictionary] = snapshot["items"]
	for item: Dictionary in items:
		if GameData.as_bool(item.get("contraband")) and not str(item.get("slot")).begins_with(GLOVEBOX_SLOT):
			count += 1
	return count
