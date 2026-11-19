class_name HeroSolverShot
extends RefCounted
## Shared shot evaluation: builds the shot path the same way gameplay does and judges it.

static func build(from: Vector3, target: Vector3, bend: float) -> PackedVector3Array:
	var ground_end := Vector3(target.x, 0, target.z)
	var path := HeroSim.curve(from, ground_end, bend)
	return HeroSim.lift(HeroSim.resample(path), "shot", HeroSim.R, target.y)


static func judge(path: PackedVector3Array, target: Vector3, carrier_pos: Vector3, dfs: Array, lv: Dictionary) -> Dictionary:
	# a curl that leaves the pitch before reaching the goal mouth is out of play
	for i in max(0, path.size() - 3):
		var q: Vector3 = path[i]
		if q.x > HeroSim.GOAL_X - 0.05 or abs(q.z) > 34.0:
			return {"result": "miss", "t": 0.4, "def_end": dfs, "speed": HeroSim.SHOT_SPEED, "keeper_target": target}
	var speed := HeroSim.SHOT_SPEED if abs(HeroSim.bend_of(path)) < 2.0 else HeroSim.SHOT_SPEED - 3.0
	var blk := HeroSim.run(path, speed, dfs, float(lv.react) + 0.08, float(lv.def_speed) * 0.7, 0.55, 1.9)
	if blk.cut >= 0:
		return {"result": "blocked", "t": blk.t, "point": blk.point, "def_end": blk.def_end, "speed": speed}
	var kp := HeroSim.keeper_spot(carrier_pos)
	var out := HeroSim.shot_outcome(target, blk.total, kp, float(lv.keeper_skill), abs(HeroSim.bend_of(path)) >= 2.0)
	out["t"] = blk.total
	out["def_end"] = blk.def_end
	out["speed"] = speed
	out["keeper_pos"] = kp
	return out


static func try(from: Vector3, target: Vector3, bend: float, dfs: Array, lv: Dictionary) -> String:
	var p := build(from, target, bend)
	# margin: a slightly better keeper and wider blocks than in play, so human lines still score
	var hard: Dictionary = lv.duplicate()
	hard.keeper_skill = float(lv.keeper_skill) + 0.07
	hard.def_speed = float(lv.def_speed) * 1.1
	var r := judge(p, target, from, dfs, hard)
	if r.result != "goal":
		return r.result
	# hand-drawn lines come out flatter after smoothing: the shot must also work with less bend
	if abs(bend) > 0.1:
		var flatter := build(from, target, bend * 0.65)
		var r2 := judge(flatter, target, from, dfs, lv)
		if r2.result != "goal":
			return r2.result
	return judge(p, target, from, dfs, lv).result
