class_name HeroSolver
extends RefCounted
## Brute-force search proving a Hero level can be scored within par (used by tests and hints).

var _lv: Dictionary
var solution: Array = []
var prefer_pass := false


func solvable(lv: Dictionary) -> bool:
	_lv = lv
	var att: Array = []
	for a in lv.attackers:
		att.append(Vector3(a[0], 0, a[1]))
	var dfs: Array = []
	for d in lv.defenders:
		dfs.append(Vector3(d[0], 0, d[1]))
	solution = []
	return _search(att, dfs, int(lv.carrier), int(lv.par), [])


func _search(att: Array, dfs: Array, carrier: int, moves_left: int, seq: Array) -> bool:
	if moves_left <= 0:
		return false
	var from: Vector3 = att[carrier] + Vector3(0.55, 0, 0)   # the ball sits just ahead of the carrier
	if prefer_pass and moves_left > 1 and _try_passes(att, dfs, carrier, moves_left, seq, from):
		return true
	# try shooting
	for zt in [-3.15, -2.6, 2.6, 3.15]:
		for yt in [0.35, 1.4, 2.0]:
			for bend in [0.0, 2.5, -2.5, 5.0, -5.0]:
				var r := HeroSolverShot.try(from, Vector3(HeroSim.GOAL_X, yt, zt), bend, dfs, _lv)
				if r == "goal":
					solution = seq + [["shot", zt, yt, bend]]
					return true
	if moves_left == 1 or prefer_pass:
		return false
	return _try_passes(att, dfs, carrier, moves_left, seq, from)


func _try_passes(att: Array, dfs: Array, carrier: int, moves_left: int, seq: Array, from: Vector3) -> bool:
	for i in att.size():
		if i == carrier:
			continue
		for bend in [0.0, 3.0, -3.0, 6.0, -6.0]:
			var to: Vector3 = att[i]
			var path := HeroSim.curve(from, to, bend)
			var off_pitch := false
			for q in path:
				if abs(q.z) > 33.5 or q.x > HeroSim.GOAL_X - 0.5:
					off_pitch = true
			if off_pitch:
				continue
			var len := HeroSim.path_length(path)
			var lob := len > HeroSim.LOB_LEN
			var lifted := HeroSim.lift(HeroSim.resample(path), "lob" if lob else "ground")
			# demand a safety margin so imprecise human lines still work
			if not lob:
				var safe := HeroSim.run(lifted, HeroSim.PASS_SPEED, dfs, float(_lv.react) * 0.92, float(_lv.def_speed) * 1.06, 0.9)
				if safe.cut >= 0:
					continue
			var r := HeroSim.run(lifted, HeroSim.LOB_SPEED if lob else HeroSim.PASS_SPEED, dfs, float(_lv.react), float(_lv.def_speed), 0.8, 1.4, 0.22 if lob else 0.0)
			if r.cut >= 0:
				continue
			var att2 := att.duplicate()
			var run := (Vector3(HeroSim.GOAL_X - 6.0, 0, 0) - from)
			run.y = 0.0
			var pp: Vector3 = att[carrier]
			att2[carrier] = pp + run.normalized() * min(6.0, run.length())
			if _search(att2, r.def_end, i, moves_left - 1, seq + [["pass", i, bend]]):
				return true
	return false
