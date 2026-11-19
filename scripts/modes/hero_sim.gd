class_name HeroSim
extends RefCounted
## Deterministic flight model for Hero Challenges (used by gameplay and the level solver).

const GOAL_X := 52.5
const HW := 3.66
const GH := 2.44
const R := 0.11
const PASS_SPEED := 17.0
const LOB_SPEED := 15.0
const SHOT_SPEED := 25.0
const LOB_LEN := 20.0


## Smooths and resamples ground control points to ~0.35 m spacing.
static func resample(pts: PackedVector3Array, step := 0.35) -> PackedVector3Array:
	if pts.size() < 2:
		return pts
	var smooth := PackedVector3Array()
	smooth.append(pts[0])
	for i in range(1, pts.size() - 1):
		smooth.append(pts[i - 1] * 0.25 + pts[i] * 0.5 + pts[i + 1] * 0.25)
	smooth.append(pts[pts.size() - 1])
	var out := PackedVector3Array()
	out.append(smooth[0])
	var carry := 0.0
	for i in range(1, smooth.size()):
		var a := smooth[i - 1]
		var b := smooth[i]
		var seg := a.distance_to(b)
		var d := step - carry
		while d <= seg:
			out.append(a.lerp(b, d / seg))
			d += step
		carry = seg - (d - step)
	if out[out.size() - 1].distance_to(smooth[smooth.size() - 1]) > 0.05:
		out.append(smooth[smooth.size() - 1])
	return out


static func path_length(p: PackedVector3Array) -> float:
	var s := 0.0
	for i in range(1, p.size()):
		s += p[i - 1].distance_to(p[i])
	return s


## Quadratic curve from a -> b with a sideways bend (metres) — used by the solver.
static func curve(a: Vector3, b: Vector3, bend: float, n := 24) -> PackedVector3Array:
	var mid := (a + b) * 0.5
	var d := b - a
	var side := Vector3(-d.z, 0, d.x).normalized()
	var c := mid + side * bend
	var out := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / n
		out.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return out


## Adds heights to a ground path. kind: "ground", "lob", "shot" (rises to target_y at the end).
static func lift(path: PackedVector3Array, kind: String, start_y := R, target_y := R) -> PackedVector3Array:
	var out := PackedVector3Array()
	var total := path_length(path)
	var acc := 0.0
	for i in path.size():
		if i > 0:
			acc += path[i - 1].distance_to(path[i])
		var u = acc / max(total, 0.001)
		var y := R
		match kind:
			"lob":
				var peak: float = clamp(total * 0.13, 2.5, 5.0)
				y = lerp(start_y, R, u) + 4.0 * peak * u * (1.0 - u)
			"shot":
				y = lerp(start_y, target_y, u * u * (3.0 - 2.0 * u)) + 0.6 * u * (1.0 - u) * (1.0 if target_y > 1.2 else 0.0)
			_:
				y = lerp(start_y, R, min(1.0, u * 4.0))
		out.append(Vector3(path[i].x, y, path[i].z))
	return out


## Bend of a path: max sideways deviation from the straight chord (signed metres).
static func bend_of(path: PackedVector3Array) -> float:
	if path.size() < 3:
		return 0.0
	var a := path[0]
	var b := path[path.size() - 1]
	var d := Vector3(b.x - a.x, 0, b.z - a.z)
	var len := d.length()
	if len < 0.1:
		return 0.0
	var side := Vector3(-d.z, 0, d.x) / len
	var best := 0.0
	for p in path:
		var dev := (p - a).dot(side)
		if abs(dev) > abs(best):
			best = dev
	return best


## Simulates a ball travelling along `path` (with heights). Defenders start reacting after `react`.
## Returns {cut: int (defender index or -1), t: time, point: Vector3, def_end: Array[Vector3]}.
static func run(path: PackedVector3Array, speed: float, defenders: Array, react: float, def_speed: float, radius := 0.8, max_h := 1.4, tail_guard := 0.0) -> Dictionary:
	var n := path.size()
	var times := PackedFloat32Array()
	times.resize(n)
	var acc := 0.0
	for i in n:
		if i > 0:
			acc += path[i - 1].distance_to(path[i])
		times[i] = acc / speed
	var total_t: float = times[n - 1] if n > 0 else 0.0
	# each defender heads for the point on the path they can reach soonest
	var targets: Array = []
	for d in defenders:
		var dp: Vector3 = d
		var best_i := -1
		var best_slack := INF
		for i in n:
			if path[i].y > max_h or (tail_guard > 0.0 and i > n * (1.0 - tail_guard)):
				continue
			var need: float = Vector2(path[i].x - dp.x, path[i].z - dp.z).length() - radius
			var arrive: float = react + max(0.0, need) / def_speed
			var slack: float = arrive - times[i]
			if slack < best_slack:
				best_slack = slack
				best_i = i
		targets.append(best_i)
	var cut := -1
	var cut_t := INF
	var cut_pt := Vector3.ZERO
	for k in defenders.size():
		var i: int = targets[k]
		if i < 0:
			continue
		var dp: Vector3 = defenders[k]
		var need: float = Vector2(path[i].x - dp.x, path[i].z - dp.z).length() - radius
		var arrive: float = react + max(0.0, need) / def_speed
		if arrive <= times[i] and times[i] < cut_t:
			cut = k
			cut_t = times[i]
			cut_pt = path[i]
	var ends: Array = []
	var stop_t: float = cut_t if cut >= 0 else total_t
	for k in defenders.size():
		var dp: Vector3 = defenders[k]
		var i: int = targets[k]
		if i < 0:
			ends.append(dp)
			continue
		var tgt := Vector3(path[i].x, 0, path[i].z)
		var moved: float = max(0.0, stop_t - react) * def_speed
		var dv := tgt - dp
		dv.y = 0.0
		ends.append(dp + dv.limit_length(moved))
	return {"cut": cut, "t": cut_t if cut >= 0 else total_t, "point": cut_pt, "def_end": ends, "total": total_t}


## Keeper model. Returns {"result": "goal"/"save"/"miss"/"post", "keeper_target": Vector3}
static func shot_outcome(target: Vector3, flight_t: float, keeper_pos: Vector3, skill: float, curled := false) -> Dictionary:
	var y := target.y
	var z := target.z
	if abs(z) > HW + 0.11 or y > GH + 0.11 or y < 0.0:
		return {"result": "miss", "keeper_target": Vector3(GOAL_X - 0.5, 1.0, clamp(z, -HW, HW))}
	if abs(z) > HW - 0.11 or y > GH - 0.11:
		return {"result": "post", "keeper_target": Vector3(GOAL_X - 0.5, 1.0, clamp(z, -HW, HW))}
	var react: float = 0.32 - skill * 0.12 + (0.14 if curled else 0.0)
	var dive_speed: float = 4.8 + skill * 1.6
	var reach: float = min(4.6, 0.65 + dive_speed * max(0.0, flight_t - react) + 1.2 * min(flight_t, react))
	var lateral: float = abs(z - keeper_pos.z)
	# corners tucked in are out of reach unless the shot is slow / from distance
	var quick: bool = flight_t < 0.78
	var top_corner: bool = quick and abs(z) > HW - 0.75 and y > 1.75 and lateral > 1.5
	var low_corner: bool = quick and abs(z) > HW - 0.6 and y < 0.45 and lateral > 1.6
	var saved: bool = lateral <= reach and y <= 2.3 + (0.2 if not quick else 0.0) and not top_corner and not low_corner
	return {"result": "save" if saved else "goal", "keeper_target": Vector3(GOAL_X - 0.4, y, z)}


static func keeper_spot(ball: Vector3) -> Vector3:
	var g := Vector3(GOAL_X, 0, 0)
	var to := Vector3(ball.x, 0, ball.z) - g
	var d: float = clamp(0.8 + to.length() * 0.05, 0.8, 2.5)
	var p := g + to.normalized() * d
	p.z = clamp(p.z, -HW + 0.4, HW - 0.4)
	return p
