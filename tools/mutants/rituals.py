"""Mutants of the rituals-and-timing fixes of the M6 review: a ritual's
requirements asked again at completion, the anchor that gives way to what is
carried, the gust in road time, the cigarette's calm in whole ticks. All
twelve are killed.
    python3 tools/mutants.py T-ITEM-TEA-GLASS,T-ITEM-PHONE,T-ITEM-MIXTAPE,T-STOP-01,T-ITEM-ENERGY-DRINK,T-ITEM-CIGARETTES,T-CAR-05 tools/mutants/rituals.py
(Where the night waits the cabin's anchors are not in use, so at a stop the
dial is out of the tape's way without giving way. The anchor that gives way
is held on the road: T-ITEM-MIXTAPE, with a tape that may be stowed.)
"""
D = 'src/core/drive_sim.gd'
I = 'src/core/item_sim.gd'
MUTANTS = [
 # A ritual's requirements are asked again when its gesture completes.
 (I, '\tif not _requirements_hold(ritual, owner):\n\t\treturn false\n', '', 'a ritual completes whatever became of what it requires'),
 (D, '\t\tif not items.complete(_active_ritual, gesture.direction):\n\t\t\treturn\n', '\t\titems.complete(_active_ritual, gesture.direction)\n', 'a completion that did nothing is announced'),
 # An anchor at the same place gives way to what is carried.
 (D, '\tif not hand.carrying:\n\t\treturn\n', '\tif true:\n\t\treturn\n', 'no anchor gives way to what is carried'),
 (D, 'if not _drag_destinations.has(index) and hand.anchor_pointer(index).is_equal_approx(hand.anchor_pointer(destination)):',
     'if hand.anchor_pointer(index).is_equal_approx(hand.anchor_pointer(destination)):', 'the destination gives way to itself'),
 (D, 'if not _drag_destinations.has(index) and hand.anchor_pointer(index).is_equal_approx(hand.anchor_pointer(destination)):',
     'if not _drag_destinations.has(index) and stopped and hand.anchor_pointer(index).is_equal_approx(hand.anchor_pointer(destination)):', 'an anchor gives way only at a stop'),
 (D, '\t\t\t_pinned_until_release = true\n\t\t_sync_anchors()\n', '\t\t\t_pinned_until_release = true\n', 'what gave way stays away when the carry is over'),
 # A gust lasts gust_duration of road time, in whole ticks.
 (D, '\t\t_gust_left -= _road_dt\n', '\t\t_gust_left -= DT\n', 'a gust counted in his time, not the road\'s'),
 (D, '\tif _gust_left >= _road_dt * 0.5:', '\tif _gust_left > 0.0:', 'a gust runs on while anything is left of it'),
 (D, '\tif _gust_left >= _road_dt * 0.5:', '\tif _gust_left >= _road_dt * 1.5:', 'a gust ends a tick early'),
 (D, '\t_gust_left = _gust_duration\n', '\t_gust_left = _gust_duration / effects.product(ROAD_SPEED)\n', 'a gust stretched twice under Focus'),
 # The cigarette's calm is counted in whole ticks.
 (I, '\t\tif _drip_left[index] < dt * 0.5:', '\t\tif _drip_left[index] <= 0.0:', 'a drip runs a tick over'),
 (I, '\t\tif _drip_left[index] < dt * 0.5:', '\t\tif _drip_left[index] < dt * 1.5:', 'a drip ends a tick early'),
]
