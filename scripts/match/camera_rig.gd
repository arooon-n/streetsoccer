class_name CameraRig
extends Camera3D
## Broadcast / close / set-piece / follow / free cameras with smoothing.

var mt = null
var mode := "broadcast"
var focus := Vector3.ZERO
var want_pos := Vector3.ZERO
var want_look := Vector3.ZERO
var look := Vector3.ZERO
var follow_node: Node3D = null
var smooth := 3.0
var L := 52.5
var W := 34.0
var cage := false
var orbit_t := 0.0


func setup(m, l: float, w: float, is_cage: bool) -> void:
	mt = m
	L = l
	W = w
	cage = is_cage
	fov = 36.0
	near = 0.1
	far = 600.0
	current = true


func set_fixed(p: Vector3, target: Vector3, f := 45.0, snap_now := false) -> void:
	mode = "fixed"
	want_pos = p
	want_look = target
	fov = f
	if snap_now:
		snap()


func snap() -> void:
	_compute(0.0)
	global_position = want_pos
	look = want_look
	look_at(look, Vector3.UP)


func update(dt: float) -> void:
	_compute(dt)
	var k := 1.0 - exp(-dt * smooth)
	global_position = global_position.lerp(want_pos, k)
	look = look.lerp(want_look, 1.0 - exp(-dt * smooth * 1.4))
	if global_position.distance_to(look) > 0.1:
		look_at(look, Vector3.UP)


func _compute(dt: float) -> void:
	match mode:
		"broadcast", "close":
			var close: bool = mode == "close" or Game.settings.get("camera", "broadcast") == "close"
			var b: Vector3 = mt.ball.pos
			var lead: Vector3 = mt.ball.vel * 0.22
			lead.y = 0.0
			var f := b + lead
			f.y = 0.0
			f.x = clamp(f.x, -L + (6.0 if not cage else 4.0), L - (6.0 if not cage else 4.0))
			f.z = clamp(f.z * 0.65, -W * 0.45, W * 0.45)
			if dt == 0.0:
				focus = f
			else:
				focus = focus.lerp(f, 1.0 - exp(-dt * 2.2))
			var h: float
			var back: float
			if cage:
				h = 11.0 if not close else 8.5
				back = W + 9.5 if not close else W + 6.5
				fov = 46.0 if not close else 42.0
			else:
				h = 15.5 if not close else 11.0
				back = W + 15.0 if not close else W + 9.0
				fov = 37.0 if not close else 34.0
			want_pos = Vector3(focus.x * 0.9, h, back + focus.z * 0.25)
			want_look = focus + Vector3(0, 0, -1.5)
			smooth = 3.2
		"follow":
			if follow_node:
				var p := follow_node.global_position
				want_pos = Vector3(p.x * 0.92, 5.5, p.z + (10.0 if p.z < W - 6.0 else -10.0))
				want_pos.z = clamp(want_pos.z, -W - 6.0, W + 8.0)
				want_look = p + Vector3(0, 1.1, 0)
				fov = 34.0
				smooth = 2.5
		"orbit":
			orbit_t += dt
			var a := orbit_t * 0.12 + 0.6
			want_pos = Vector3(cos(a) * (L + 10.0), 20.0 + sin(orbit_t * 0.2) * 4.0, sin(a) * (W + 22.0))
			want_look = Vector3(0, 0, 0)
			fov = 42.0
			smooth = 6.0
		"fixed":
			pass
