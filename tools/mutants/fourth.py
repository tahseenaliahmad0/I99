"""Mutants of rule 6 (never a sealed wall in fourth, D-074) for T-GEN-04:
    python3 tools/mutants.py T-GEN-04 tools/mutants/fourth.py

The generator keeps the skill line twice over (at every beat and vehicle it
places, and once more over the whole leg), so a mutant that only drops one
of the two is equivalent and is not listed: what is listed breaks what the
line is worked out from.
"""
G = 'src/core/leg_generator.gd'
MUTANTS = [
 (G, '\t_skill = kind != "two_lane" and kind != "motorcade" and not _own_road', '\t_skill = false', 'no leg keeps a skill line'),
 (G, '\t_skill = kind != "two_lane" and kind != "motorcade" and not _own_road', '\t_skill = not _own_road', 'the two-lane road and the Motorcade keep one too'),
 (G, '\t_skill = kind != "two_lane" and kind != "motorcade" and not _own_road', '\t_skill = kind != "two_lane" and kind != "motorcade"', 'a boss\'s road keeps one too'),
 (G, '\t\t"skill_path": _skill_line.to_path(0.001) if _skill else [],', '\t\t"skill_path": _line.to_path(0.001) if _skill else [],', 'the plan gives the planned line as its skill line'),
 (G, '\tplanned.skill_closing = 1.0 - float(planned.direction) * planned.speed / _skill_pace', '\tplanned.skill_closing = 1.0 - float(planned.direction) * planned.speed / _par', 'fourth gear\'s frame is third\'s'),
 (G, '\t\tfor block: Vector3 in _blocks_of(planned, skill):\n\t\t\tvar lane: int = int(block.x)', '\t\tfor block: Vector3 in _blocks_of(planned):\n\t\t\tvar lane: int = int(block.x)', 'the skill line is searched among the blocks of third gear'),
 (G, '\t_skill_line.change = _tuning.f("gen_skill_lane_change")', '\t_skill_line.change = 1.0', 'the skill line changes lane in a metre'),
 (G, '\t\tvar gaining: float = vehicle.skill_closing - follower.skill_closing', '\t\tvar gaining: float = 0.0', 'in fourth nothing comes up behind anything: every vehicle runs free'),
 (G, '\treturn planned.half_length + holder.half_length + _follow_gap', '\treturn planned.half_length + holder.half_length + 3.0 * _follow_gap', 'a vehicle held up stays three follow gaps back'),
 (G, '\t\t\tchange_to = moves_from + clampf(beside / across, 0.0, 1.0) * _change_time * _skill_ms', '\t\t\tchange_to = moves_from', 'the lane a merger leaves is free the moment it begins to move'),
 (G, '\t\t\tchange_from = moves_from + clampf((across - beside) / across, 0.0, 1.0) * _change_time * _skill_ms', '\t\t\tchange_from = _change_end(planned, true)', 'the lane a merger moves into is free until it has arrived'),
 (G, '\t\tif model == HELD or not member.changes_lane():', '\t\tif not member.changes_lane():', 'a merger holds up nothing in the lane it leaves'),
 (G, '\t\t\tif ahead > gap - need and ahead < gap_free + need:\n\t\t\t\treturn false', '\t\t\tif ahead > gap - need and ahead < gap_free + need:\n\t\t\t\tpass', 'in fourth a vehicle may appear on top of another'),
 (G, '\t\t\t\t_skill_fixed.append(Vector3(float(strewn), first - melon_reach, last + melon_reach))', '\t\t\t\tpass', 'no melons lie on the skill line\'s road'),
 (G, '\tfor block: Vector3 in (_skill_fixed if skill else _par_fixed):', '\tfor block: Vector3 in _par_fixed:', 'the skill line takes the melons to lie where third gear finds them'),
 (G, '\t\t\tvar from_held: float = _skill_reaches(planned, _reach(planned, true), HELD)', '\t\t\tvar from_held: float = _skill_reaches(planned, _reach(planned, true), FREE)', 'a block begins where the vehicle is if nothing has held it up'),
 (G, '\t\t\tvar to_free: float = _skill_reaches(planned, -_reach(planned, true), FREE)', '\t\t\tvar to_free: float = _skill_reaches(planned, -_reach(planned, true), HELD)', 'a block ends where the vehicle is if all that can has held it up'),
 (G, '\t\tif changer.change_to == lane and _skill_joins_at(changer) < changer.skill_passed:', '\t\tif false:', 'a merger holds up nothing in the lane it joins'),
 (G, '\t\t\t\tif _skill_catch_at(follower, order[index - 1], since, model) < follower.skill_passed:\n\t\t\t\t\treturn false', '\t\t\t\tif _skill_catch_at(follower, order[index - 1], since, model) < follower.skill_passed:\n\t\t\t\t\tpass', 'a merger may be held up in the lane it joins'),
 (G, '\t\t\t\tand member.skill_catch[HELD] < minf(member.skill_passed, _change_end(member, true)):\n\t\t\treturn false', '\t\t\t\tand member.skill_catch[HELD] < minf(member.skill_passed, _change_end(member, true)):\n\t\t\tpass', 'a merger may be held up before it has left its lane'),
 (G, '\treturn planned.half_length + _car_length * 0.5 + (_skill_margin if skill else _margin)', '\treturn planned.half_length + _car_length * 0.5 + (-_car_length if skill else _margin)', 'on the skill line a vehicle is passed through its tail'),
]
