class_name Ball
extends Node3D
## The match ball: physics against pitch, posts, nets and cage walls; dribbling; visuals.

signal kicked(by, kind: String)
signal goal_line_crossed(side: int, scored: bool, pos: Vector3)
signal touchline_crossed(pos: Vector3)
signal hit_post(pos: Vector3)
signal hit_net(side: int, pos: Vector3)

const R := BallSim.R
const POST_R := 0.06

var pos := Vector3(0, R, 0)
var vel := Vector3.ZERO
var spin := Vector3.ZERO
var holder = null              # Footballer currently dribbling / holding
var held_in_hands := false     # keeper holding
var last_touch = null
var last_kick_time := -10.0
var last_kick_kind := ""
var stadium: Stadium
var frozen := false            # set pieces: ball is placed and waits
var in_goal_side := 0          # side whose net the ball is in
var out_reported := false
var time := 0.0
var _rot := Basis()
var _mesh: MeshInstance3D
var _shadow: MeshInstance3D
var _trail: MeshInstance3D
var _trail_pts: Array[Vector3] = []
var _imesh: ImmediateMesh
var _cam: Camera3D
var _ball_mat: ShaderMaterial


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = R
	sm.height = R * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	_mesh.mesh = sm
	_ball_mat = ShaderMaterial.new()
	_ball_mat.shader = load("res://shaders/ball.gdshader")
	var b: Dictionary = Game.BALLS.get(Game.save.equipped.get("ball", "classic"), Game.BALLS.classic)
	_ball_mat.set_shader_parameter("col_a", Color(b.a))
	_ball_mat.set_shader_parameter("col_b", Color(b.b))
	_mesh.material_override = _ball_mat
	add_child(_mesh)
	_shadow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	q.orientation = PlaneMesh.FACE_Y
	_shadow.mesh = q
	var sh := ShaderMaterial.new()
	var s := Shader.new()
	s.code = "shader_type spatial; render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled; uniform float a = 0.5; void fragment(){ float r = length(UV*2.0-1.0); ALBEDO = vec3(0.0); ALPHA = a * smoothstep(1.0, 0.2, r); }"
	sh.shader = s
	_shadow.material_override = sh
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)
	_imesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.mesh = _imesh
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.vertex_color_use_as_albedo = true
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail.material_override = tm
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.top_level = true
	add_child(_trail)
	top_level = true


func set_camera(c: Camera3D) -> void:
	_cam = c


func place(p: Vector3) -> void:
	pos = Vector3(p.x, max(R, p.y), p.z)
	vel = Vector3.ZERO
	spin = Vector3.ZERO
	holder = null
	held_in_hands = false
	in_goal_side = 0
	out_reported = false
	_trail_pts.clear()
	_sync()


func speed() -> float:
	return vel.length()


func is_loose() -> bool:
	return holder == null and not frozen


func kick(v: Vector3, s: Vector3, by, kind: String) -> void:
	holder = null
	held_in_hands = false
	frozen = false
	vel = v
	spin = s
	if pos.y < R + 0.02 and v.y > 0.3:
		pos.y = R + 0.03
	last_touch = by
	last_kick_time = time
	last_kick_kind = kind
	out_reported = false
	Sfx.kick(clamp(v.length() / 30.0, 0.0, 1.0))
	kicked.emit(by, kind)


func touch_by(p) -> void:
	last_touch = p


func _physics_process(delta: float) -> void:
	time += delta
	if frozen:
		_sync()
		return
	if holder != null:
		_follow_holder(delta)
		_sync()
		return
	var sub := 2
	var dt := delta / sub
	for i in sub:
		_integrate(dt)
	_sync()


func _follow_holder(delta: float) -> void:
	if held_in_hands:
		pos = holder.hand_point()
		vel = holder.vel
		spin = Vector3.ZERO
		return
	var target: Vector3 = holder.ball_anchor()
	var k: float = 1.0 - exp(-delta * 16.0)
	var new_pos := pos.lerp(target, k)
	new_pos.y = R
	vel = (new_pos - pos) / max(delta, 0.0001)
	pos = new_pos
	spin = Vector3.UP.cross(vel) / R


func _integrate(dt: float) -> void:
	var s := [pos, vel, spin]
	var prev := pos
	var vy_before := vel.y
	BallSim.step(s, dt)
	pos = s[0]
	vel = s[1]
	spin = s[2]
	if vy_before < -2.5 and vel.y > 0.0 and pos.y <= R + 0.01:
		Sfx.play("bounce", clamp(-vy_before / 12.0, 0.1, 0.6))
	_collide_frame(prev)
	if stadium and stadium.is_cage:
		_collide_cage()
	_check_lines(prev)


func _collide_frame(prev: Vector3) -> void:
	if stadium == null:
		return
	var L := stadium.L
	var hw := stadium.goal_hw
	var h := stadium.goal_h
	for side in [1, -1]:
		var gx: float = side * (L + POST_R)
		if abs(pos.x - gx) > 3.0:
			continue
		var segs := [
			[Vector3(gx, 0, -hw - POST_R), Vector3(gx, h + POST_R, -hw - POST_R)],
			[Vector3(gx, 0, hw + POST_R), Vector3(gx, h + POST_R, hw + POST_R)],
			[Vector3(gx, h + POST_R, -hw - POST_R), Vector3(gx, h + POST_R, hw + POST_R)],
		]
		for sg in segs:
			var a: Vector3 = sg[0]
			var b: Vector3 = sg[1]
			var ab := b - a
			var t: float = clamp((pos - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var c := a + ab * t
			var d := pos - c
			var dist = d.length()
			if dist < R + POST_R and dist > 0.0001:
				var n = d / dist
				pos = c + n * (R + POST_R + 0.001)
				var vn := vel.dot(n)
				if vn < 0.0:
					vel -= n * vn * 1.62
					vel *= 0.92
					spin *= 0.5
					if abs(vn) > 3.0:
						Sfx.play("post", clamp(abs(vn) / 20.0, 0.3, 1.0))
						hit_post.emit(pos)
		_collide_net(side, prev)


func _collide_net(side: int, prev: Vector3) -> void:
	var L := stadium.L
	var hw := stadium.goal_hw
	var h := stadium.goal_h
	var dt_ := stadium.goal_depth * 0.5
	var db := stadium.goal_depth
	var lx: float = (pos.x * side) - L      # depth behind the goal line
	if lx < 0.0 or lx > db + 0.5:
		return
	var inside := in_goal_side == side
	if not inside and (prev.x * side) - L < 0.0 and abs(pos.z) < hw and pos.y < h:
		inside = true
		in_goal_side = side
	# back net plane through (dt_, h) and (db, 0) in (depth, y)
	var back_depth_at_y: float = lerp(db, dt_, clamp(pos.y / h, 0.0, 1.0))
	var hit := false
	if inside:
		if abs(pos.z) > hw - R:
			pos.z = sign(pos.z) * (hw - R)
			vel.z *= -0.15
			vel.x *= 0.6
			hit = true
		if pos.y > h - R:
			pos.y = h - R
			vel.y = -abs(vel.y) * 0.15
			hit = true
		if lx > back_depth_at_y - R:
			var nx: float = back_depth_at_y - R + L
			pos.x = side * nx
			if vel.x * side > 0.0:
				vel.x = -vel.x * 0.08
			vel.z *= 0.5
			vel.y *= 0.5
			hit = true
		if hit and vel.length() > 2.0:
			stadium.net_hit(side, pos, vel.length() + 6.0)
			hit_net.emit(side, pos)
			Sfx.play("net", clamp(vel.length() / 12.0, 0.3, 1.0))
	else:
		# outside netting: side panels and roof
		if lx < back_depth_at_y + R and pos.y < h + R:
			var dz: float = abs(pos.z) - hw
			if dz > -R and dz < R and abs(prev.z) >= hw:
				pos.z = sign(pos.z) * (hw + R)
				vel.z = -vel.z * 0.2
				vel.x *= 0.7
				stadium.net_hit(side, pos, vel.length())
			elif abs(pos.z) < hw and pos.y < h + R and prev.y >= h:
				pos.y = h + R
				vel.y = abs(vel.y) * 0.25
				stadium.net_hit(side, pos, vel.length())


func _collide_cage() -> void:
	var X := stadium.L
	var Z := stadium.W
	var e := 0.55
	if abs(pos.z) > Z - R:
		pos.z = sign(pos.z) * (Z - R)
		if vel.z * sign(pos.z) > 0.0:
			vel.z = -vel.z * e
			vel.x *= 0.9
			if abs(vel.z) > 3.0:
				Sfx.play("tackle", clamp(abs(vel.z) / 15.0, 0.2, 0.7))
	var in_mouth: bool = abs(pos.z) < stadium.goal_hw and pos.y < stadium.goal_h
	if abs(pos.x) > X - R and not in_mouth and in_goal_side == 0:
		pos.x = sign(pos.x) * (X - R)
		if vel.x * sign(pos.x) > 0.0:
			vel.x = -vel.x * e
			vel.z *= 0.9
			if abs(vel.x) > 3.0:
				Sfx.play("tackle", clamp(abs(vel.x) / 15.0, 0.2, 0.7))
	if pos.y > 7.0:
		pos.y = 7.0
		vel.y = -abs(vel.y) * 0.4


func _check_lines(prev: Vector3) -> void:
	if stadium == null or out_reported:
		return
	var L := stadium.L
	for side in [1, -1]:
		if pos.x * side > L + R and prev.x * side <= L + R:
			var scored: bool = abs(pos.z) < stadium.goal_hw and pos.y < stadium.goal_h and in_goal_side == side
			if scored or not stadium.is_cage:
				out_reported = true
				goal_line_crossed.emit(side, scored, pos)
				return
	if not stadium.is_cage and abs(pos.z) > stadium.W + R and abs(prev.z) <= stadium.W + R:
		out_reported = true
		touchline_crossed.emit(pos)


func _process(delta: float) -> void:
	# visual roll
	var w := spin
	var ang := w.length() * delta
	if ang > 0.0001:
		_rot = Basis(w.normalized(), ang) * _rot
		_rot = _rot.orthonormalized()
	_update_trail()


func _sync() -> void:
	global_position = pos
	if _mesh:
		_mesh.basis = _rot
	if _shadow:
		_shadow.global_position = Vector3(pos.x, 0.012, pos.z)
		var hgt: float = clamp((pos.y - R) / 6.0, 0.0, 1.0)
		_shadow.scale = Vector3.ONE * (1.0 + hgt * 1.5)
		(_shadow.material_override as ShaderMaterial).set_shader_parameter("a", 0.55 * (1.0 - hgt * 0.8))


func _update_trail() -> void:
	var sp := vel.length()
	if holder == null and sp > 17.0 and not frozen:
		_trail_pts.append(pos)
	elif _trail_pts.size() > 0:
		_trail_pts.remove_at(0)
	while _trail_pts.size() > 12:
		_trail_pts.remove_at(0)
	_imesh.clear_surfaces()
	if _trail_pts.size() < 2 or _cam == null:
		return
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var cam_pos := _cam.global_position
	var n := _trail_pts.size()
	for i in n:
		var p: Vector3 = _trail_pts[i]
		var nxt: Vector3 = _trail_pts[min(i + 1, n - 1)]
		var prv: Vector3 = _trail_pts[max(i - 1, 0)]
		var dir := (nxt - prv).normalized()
		var side := dir.cross((cam_pos - p).normalized()).normalized()
		var k := float(i) / (n - 1)
		var wdt := R * 0.9 * k
		var c := Color(1.0, 0.95, 0.75, 0.35 * k)
		_imesh.surface_set_color(c)
		_imesh.surface_add_vertex(p + side * wdt)
		_imesh.surface_set_color(c)
		_imesh.surface_add_vertex(p - side * wdt)
	_imesh.surface_end()


## Predicts future ball positions (no collisions) for the AI.
func predict(t: float, sample_dt := 0.05) -> PackedVector3Array:
	if holder != null:
		var out := PackedVector3Array()
		out.append(pos)
		return out
	return BallSim.simulate(pos, vel, spin, t, sample_dt)
