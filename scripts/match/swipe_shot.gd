class_name SwipeShot
extends RefCounted
## Turns a finger swipe (screen space) into a shot: target on the goal face, speed and curl.
## The swipe's direction picks the side, its length picks the height, its speed the power,
## and the sideways bend of the swipe becomes side-spin (curl).

## Returns {target: Vector3, speed: float, spin: Vector3, curl: float, power: float}
static func compute(cam: Camera3D, ball_pos: Vector3, pts: PackedVector2Array, duration: float, goal_x: float, goal_hw: float, goal_h: float) -> Dictionary:
	var s := pts[0]
	var e := pts[pts.size() - 1]
	var chord := e - s
	var chord_len := chord.length()
	if chord_len < 10.0:
		return {}
	# screen positions of the goal (centre bottom and centre top)
	var g_bottom := cam.unproject_position(Vector3(goal_x, 0, 0))
	var g_top := cam.unproject_position(Vector3(goal_x, goal_h, 0))
	var ball_s := cam.unproject_position(ball_pos)
	var to_goal_px: float = max(40.0, ball_s.y - (g_bottom.y + g_top.y) * 0.5)
	# extend the swipe line to the goal's mid-height row
	var row: float = (g_bottom.y + g_top.y) * 0.5
	var k: float = (s.y - row) / max(1.0, s.y - e.y) if s.y - e.y > 1.0 else 1.0
	var x_at_goal: float = s.x + chord.x * k
	# height from swipe length relative to the distance to the goal on screen
	var reach: float = clamp(chord_len / to_goal_px, 0.0, 1.6)
	var y: float = lerp(0.15, 2.75, clamp((reach - 0.25) / 1.05, 0.0, 1.0))
	# z from unprojecting x_at_goal at the goal row
	var from := cam.project_ray_origin(Vector2(x_at_goal, row))
	var dirv := cam.project_ray_normal(Vector2(x_at_goal, row))
	var z := 0.0
	if abs(dirv.x) > 0.0001:
		var t: float = (goal_x - from.x) / dirv.x
		z = from.z + dirv.z * t
	z = clamp(z, -goal_hw - 2.5, goal_hw + 2.5)
	# curl: max sideways deviation of the path from the straight chord
	var n := Vector2(-chord.y, chord.x) / chord_len
	var dev := 0.0
	for p in pts:
		var d: float = (p - s).dot(n)
		if abs(d) > abs(dev):
			dev = d
	var curl: float = clamp(dev / chord_len, -0.6, 0.6)
	# speed from swipe velocity (screen heights per second)
	var vps: float = chord_len / max(duration, 0.05) / 390.0
	var power: float = clamp((vps - 0.6) / 3.0, 0.0, 1.0)
	var speed: float = lerp(17.0, 32.0, power)
	# a swipe bulging to the right curls the ball back to the left (and vice versa):
	# with spin w about +Y, Magnus accel = w * speed * (-camera right), so w = +curl.
	var spin := Vector3(0, curl * 150.0, 0)
	var target := Vector3(goal_x, y, z)
	return {"target": target, "speed": speed, "spin": spin, "curl": curl, "power": power}


## Launch velocity for a swipe result, with skill-based error.
static func velocity(from: Vector3, r: Dictionary, err := 0.02) -> Vector3:
	var v := BallSim.solve(from, r.target, r.speed, r.spin)
	if v == Vector3.ZERO:
		var d: Vector3 = (r.target - from)
		v = Vector3(d.x, d.y + d.length() * 0.12, d.z).normalized() * float(r.speed)
	if err > 0.0:
		v = v.rotated(Vector3.UP, randfn(0.0, err))
		var ax := v.cross(Vector3.UP).normalized()
		v = v.rotated(ax, randfn(0.0, err * 0.7))
	return v
