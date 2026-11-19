class_name BallSim
extends RefCounted
## Football flight model + trajectory solvers (no collisions; used by the ball and the AI).

const R := 0.11
const G := 9.81
const DRAG := 0.0128        # a = -DRAG * |v| * v   (rho*Cd*A / 2m)
const MAGNUS := 0.0062      # a = MAGNUS * (spin x v)
const SPIN_DECAY := 0.25
const BOUNCE := 0.58
const DT := 1.0 / 120.0

static var wet := false
static var wind := Vector3.ZERO


static func roll_decel(speed: float) -> float:
	if wet:
		return 1.05 + 0.0055 * speed * speed
	return 1.45 + 0.0075 * speed * speed


## Advances one state [pos, vel, spin] by dt. Returns the new values in-place via an Array.
static func step(s: Array, dt: float) -> void:
	var p: Vector3 = s[0]
	var v: Vector3 = s[1]
	var w: Vector3 = s[2]
	var airborne := p.y > R + 0.005 or v.y > 0.05
	if airborne:
		var sp := v.length()
		var a := Vector3(0, -G, 0) - v * (DRAG * sp) + w.cross(v) * MAGNUS + wind
		v += a * dt
		p += v * dt
		w *= exp(-SPIN_DECAY * dt)
		if p.y < R:
			p.y = R
			if v.y < -0.9:
				v.y = -v.y * (BOUNCE - (0.06 if wet else 0.0))
				var h := Vector3(v.x, 0, v.z) * (0.9 if wet else 0.84)
				v.x = h.x
				v.z = h.z
				w *= 0.6
			else:
				v.y = 0.0
	else:
		p.y = R
		v.y = 0.0
		var hv := Vector3(v.x, 0, v.z)
		var sp := hv.length()
		if sp > 0.0001:
			var dec := roll_decel(sp) * dt
			if dec >= sp:
				hv = Vector3.ZERO
			else:
				hv -= hv / sp * dec
			# slight curl on the ground from side-spin
			hv += Vector3(w.y, 0, 0).cross(hv) * 0.0
			v.x = hv.x
			v.z = hv.z
		p += v * dt
		w = Vector3.UP.cross(v) / R
	s[0] = p
	s[1] = v
	s[2] = w


## Samples a trajectory every sample_dt for up to t seconds.
static func simulate(pos: Vector3, vel: Vector3, spin: Vector3, t: float, sample_dt := 0.05) -> PackedVector3Array:
	var out := PackedVector3Array()
	var s := [pos, vel, spin]
	var elapsed := 0.0
	var next_sample := 0.0
	out.append(pos)
	while elapsed < t:
		step(s, DT)
		elapsed += DT
		if elapsed >= next_sample + sample_dt:
			next_sample += sample_dt
			out.append(s[0])
	return out


## Finds the launch velocity (fixed speed) that makes the ball pass through `target`.
## Returns Vector3.ZERO if the target is out of reach.
static func solve(from: Vector3, target: Vector3, speed: float, spin: Vector3, prefer_low := true) -> Vector3:
	var to := target - from
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()
	if dist < 0.5:
		return to.normalized() * speed
	var yaw := atan2(to.x, to.z)
	var pitch := atan2(to.y, dist) + (0.02 if prefer_low else 0.6)
	var best := Vector3.ZERO
	var best_err := INF
	for it in 14:
		var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
		var v0 := dir * speed
		var hit := _closest_at_range(from, v0, spin, flat.normalized(), dist)
		if hit.is_empty():
			pitch += 0.08
			continue
		var p: Vector3 = hit[0]
		var err_v := target - p
		var err := err_v.length()
		if err < best_err:
			best_err = err
			best = v0
		if err < 0.05:
			break
		# lateral error -> yaw, vertical error -> pitch
		var side := Vector3(flat.z, 0, -flat.x).normalized()
		var lat := err_v.dot(side)
		yaw += lat / max(dist, 1.0) * 0.95
		pitch += err_v.y / max(dist, 1.0) * 0.9
		pitch = clamp(pitch, -0.3, 1.3)
	return best if best_err < 1.2 else Vector3.ZERO


## Simulates until the ball has travelled `range_d` along `axis` (horizontal). Returns [pos, time].
static func _closest_at_range(from: Vector3, v0: Vector3, spin: Vector3, axis: Vector3, range_d: float) -> Array:
	var s := [from, v0, spin]
	var t := 0.0
	var prev: Vector3 = from
	while t < 4.0:
		step(s, DT)
		t += DT
		var p: Vector3 = s[0]
		var d := (p - from).dot(axis)
		if d >= range_d:
			var pd := (prev - from).dot(axis)
			var k = (range_d - pd) / max(0.0001, d - pd)
			return [prev.lerp(p, k), t]
		var vv: Vector3 = s[1]
		if vv.length() < 0.3:
			return []
		prev = p
	return []


## Ground pass: speed so the ball arrives at `to` with roughly `arrive` m/s.
static func ground_pass_speed(dist: float, arrive := 5.0) -> float:
	# integrate v dv = -a(v) ds backwards from arrive speed
	var v := arrive
	var ds := 0.25
	var d := 0.0
	while d < dist:
		v += roll_decel(v) * ds / max(v, 0.5)
		d += ds
	return clamp(v, 4.0, 32.0)


## Lofted ball that lands at `target` (y ignored) with the given launch angle.
static func lob_velocity(from: Vector3, target: Vector3, angle_deg: float, spin := Vector3.ZERO) -> Vector3:
	var flat := Vector3(target.x - from.x, 0, target.z - from.z)
	var dist := flat.length()
	var dir := flat.normalized()
	var a := deg_to_rad(angle_deg)
	var lo := 3.0
	var hi := 40.0
	var v0 := Vector3.ZERO
	for it in 22:
		var sp := (lo + hi) * 0.5
		v0 = (dir * cos(a) + Vector3.UP * sin(a)) * sp
		var land := _landing(from, v0, spin)
		var d := (land - from).dot(dir)
		if d < dist:
			lo = sp
		else:
			hi = sp
	return v0


static func _landing(from: Vector3, v0: Vector3, spin: Vector3) -> Vector3:
	var s := [from + Vector3(0, 0.01, 0), v0, spin]
	var t := 0.0
	while t < 5.0:
		step(s, DT)
		t += DT
		var p: Vector3 = s[0]
		if p.y <= R + 0.001 and t > 0.05:
			return p
	return s[0]


## Time for the ball to reach horizontal distance d when rolling from speed v0 (approx).
static func roll_time(v0: float, d: float) -> float:
	var v := v0
	var x := 0.0
	var t := 0.0
	var dt := 0.05
	while x < d and t < 6.0:
		x += v * dt
		v = max(0.3, v - roll_decel(v) * dt)
		t += dt
	return t
