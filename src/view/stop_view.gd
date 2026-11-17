class_name StopView
extends Node3D
## A stop (GDD 9.6, 16.1): the vendor at the passenger window, his tray, and
## on it what he offers, each with its name and price. A second, darker
## figure is the shady guy. Sits in the cabin frame. Reads the snapshot;
## changes nothing.

var _factory: PlaceholderFactory
var _vendor: Node3D
var _shady: Node3D
var _tray: Node3D
## tray anchor id -> [the thing, its label].
var _places: Dictionary = {}
var _anchor_pos: Dictionary = {}
var _label_lift: float = 0.0


func setup(data: GameData, factory: PlaceholderFactory) -> void:
	_factory = factory
	var tuning: Tuning = data.tuning
	_label_lift = tuning.f("stop_label_lift")
	_vendor = factory.make("stop_vendor")
	_vendor.position = _vec(tuning, "stop_vendor_pos")
	add_child(_vendor)
	_shady = factory.make("stop_shady")
	_shady.position = _vec(tuning, "stop_shady_pos")
	add_child(_shady)
	_tray = factory.make("stop_tray")
	_tray.position = _vec(tuning, "stop_tray_pos")
	add_child(_tray)
	var shelf: Node3D = factory.make("stop_tray")
	shelf.position = _vec(tuning, "stop_shelf_pos")
	add_child(shelf)
	for anchor: Dictionary in data.records("anchors"):
		_anchor_pos[GameData.as_string(anchor.get("id"))] = GameData.as_vec3(anchor.get("pos"))
	for place: int in StopSim.TRAY.size():
		var anchor: String = StopSim.TRAY[place]
		var thing: Node3D = factory.make("stop_offer")
		var label: Label3D = factory.make("stop_offer_text") as Label3D
		var at: Vector3 = _anchor_pos.get(anchor, Vector3.ZERO)
		thing.position = at
		add_child(thing)
		if label != null:
			# Every other label a line higher, so that neighbours can be read.
			label.position = at + Vector3(0.0, _label_lift * (1.0 + 0.6 * float(place % 2)), 0.0)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			add_child(label)
		_places[anchor] = [thing, label]
	visible = false


func apply(snapshot: Dictionary) -> void:
	visible = snapshot["stopped"]
	if not visible:
		return
	var offers: Array[Dictionary] = snapshot["offers"]
	var shady: bool = false
	var on_tray: Dictionary = {}
	for offer: Dictionary in offers:
		on_tray[GameData.as_string(offer["anchor"])] = offer
		if offer["shady"]:
			shady = true
	_shady.visible = shady
	for anchor: Variant in _places:
		var pair: Array = _places[anchor]
		var thing: Node3D = pair[0]
		var label: Label3D = pair[1]
		var shown: bool = on_tray.has(anchor)
		thing.visible = shown
		if label != null:
			label.visible = shown
			if shown:
				label.text = _label_of(GameData.as_dict(on_tray[anchor]))


## "Worry beads: 30", "Repair Rattle: 15", "Tea: free", "Thermos: yours".
func _label_of(offer: Dictionary) -> String:
	var id: String = GameData.as_string(offer["id"])
	var price: String = "%d" % roundi(GameData.as_float(offer["price"]))
	var kind: StringName = offer["kind"]
	if kind == StopSim.REPAIR:
		return Lines.format("stop.offer.repair", [Lines.get_text("fault.%s.name" % id), price])
	if kind == StopSim.RESTOCK:
		return Lines.format("stop.offer.restock", [Lines.get_text("item.%s.name" % id), price])
	if kind == StopSim.SERVICE:
		return Lines.format("stop.offer.free", [Lines.get_text("stop.%s.name" % id)])
	var name_text: String = Lines.get_text("item.%s.name" % id)
	if offer["bought"]:
		return Lines.format("stop.offer.bought", [name_text])
	if offer["free"]:
		return Lines.format("stop.offer.free", [name_text])
	return Lines.format("stop.offer.price", [name_text, price])


func _vec(tuning: Tuning, key: String) -> Vector3:
	return Vector3(tuning.fi(key, 0), tuning.fi(key, 1), tuning.fi(key, 2))
