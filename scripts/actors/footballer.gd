class_name Footballer
extends Node3D
## A player on the pitch: kinematics, actions (kicks, tackles, dives), model + procedural rig.

var team = null                 # TeamCtl
var idx := 0
var role := "MF"                # GK / DF / MF / FW
var number := 9
var pname := "Player"
var stats := {"pace": 75, "shoot": 70, "pass": 70, "drib": 70, "def": 60, "gk": 40}
var keeper := false

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var yaw := 0.0
var desired := Vector3.ZERO
var face_point = null           # Vector3 or null: look at this while moving
var sprint := false
var stamina := 1.0
var phase := 0.0
var time := 0.0
var ready_amt := 0.0

var action := ""
var action_t := 0.0
var action_dur := 0.0
var action_contact := 0.5
var action_side := 1.0
var action_height := 0.35
var action_cb := Callable()
var action_face = null          # Vector3: rotate towards during the wind-up
var _contact_done := false
var slide_vel := Vector3.ZERO
var dive_vel := Vector3.ZERO
var ball_cooldown := 0.0
var stun := 0.0
var yellow := 0
var sent_off := false
var celebrate := ""
var puppet := false             # replays drive the rig directly

# match stats
var m_goals := 0
var m_assists := 0
var m_shots := 0
var m_passes := 0
var m_passes_ok := 0
var m_tackles := 0
var m_fouls := 0
var m_saves := 0

var skel: Skeleton3D
var mesh_i: MeshInstance3D
var rig: PlayerRig
var marker: MeshInstance3D
var _marker_mat: ShaderMaterial
var _state := {}

const RADIUS := 0.38


func setup(kit: Dictionary, skin: Color, hair: Color, boots: Color, gk_kit = null) -> void:
	skel = PlayerModel.make_skeleton()
	add_child(skel)
	mesh_i = MeshInstance3D.new()
	mesh_i.mesh = PlayerModel.shared_mesh()
	mesh_i.material_override = PlayerModel.shared_material()
	skel.add_child(mesh_i)
	mesh_i.skeleton = mesh_i.get_path_to(skel)
	mesh_i.skin = skel.create_skin_from_rest_transforms()
	mesh_i.extra_cull_margin = 2.0
	rig = PlayerRig.new(skel)
	set_kit(kit, gk_kit)
	mesh_i.set_instance_shader_parameter("c_skin", skin)
	mesh_i.set_instance_shader_parameter("c_hair", hair)
	mesh_i.set_instance_shader_parameter("c_boots", boots)
	mesh_i.set_instance_shader_parameter("number", float(number))
	if Game.settings.get("shadows", 2) == 0:
		mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add_blob()
	_add_marker()
	top_level = true


func set_kit(kit: Dictionary, gk_kit = null) -> void:
	var k: Dictionary = gk_kit if keeper and gk_kit != null else kit
	mesh_i.set_instance_shader_parameter("c_shirt", k.shirt)
	mesh_i.set_instance_shader_parameter("c_shirt2", k.shirt2)
	mesh_i.set_instance_shader_parameter("c_shorts", k.shorts)
	mesh_i.set_instance_shader_parameter("c_socks", k.socks)
	mesh_i.set_instance_shader_parameter("pattern", float(k.pattern))
	if keeper:
		mesh_i.set_instance_shader_parameter("c_gloves", Color(0.95, 0.95, 0.92, 1.0))


func set_number(n: int) -> void:
	number = n
	if mesh_i:
		mesh_i.set_instance_shader_parameter("number", float(n))


func _add_blob() -> void:
	var b := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 1.1)
	q.orientation = PlaneMesh.FACE_Y
	b.mesh = q
	var m := ShaderMaterial.new()
	var s := Shader.new()
	s.code = "shader_type spatial; render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled; void fragment(){ float r = length(UV*2.0-1.0); ALBEDO = vec3(0.0); ALPHA = 0.45 * smoothstep(1.0, 0.1, r); }"
	m.shader = s
	b.material_override = m
	b.position = Vector3(0, 0.015, 0)
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(b)


func _add_marker() -> void:
	marker = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	q.orientation = PlaneMesh.FACE_Y
	marker.mesh = q
	_marker_mat = ShaderMaterial.new()
	var s := Shader.new()
	s.code = """shader_type spatial; render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled, cull_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.81, 0.2, 1.0);
uniform float power = 0.0;
void fragment(){
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring = smoothstep(0.06, 0.0, abs(r - 0.62));
	float a = atan(p.x, -p.y);
	float arrow = step(abs(p.x), 0.18 - (-p.y - 0.62) * 0.6) * step(0.66, -p.y) * step(-p.y, 0.95);
	float pw = smoothstep(0.08, 0.0, abs(r - 0.78)) * step(a / 6.2831 + 0.5, power);
	ALBEDO = col.rgb;
	ALPHA = clamp(ring * 0.95 + arrow + pw, 0.0, 1.0) * col.a;
}"""
	_marker_mat.shader = s
	marker.material_override = _marker_mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.position = Vector3(0, 0.03, 0)
	marker.visible = false
	add_child(marker)


func set_marker(on: bool, col := Color("FFCF33"), power := 0.0) -> void:
	if marker == null:
		return
	marker.visible = on
	if on:
		_marker_mat.set_shader_parameter("col", col)
		_marker_mat.set_shader_parameter("power", power)


# ------------------------------------------------------------------ helpers
func forward() -> Vector3:
	return Vector3(sin(yaw), 0, cos(yaw))


func right() -> Vector3:
	return Vector3(-cos(yaw), 0, sin(yaw))


func speed() -> float:
	return Vector3(vel.x, 0, vel.z).length()


func max_speed() -> float:
	var pace: float = stats.pace
	var base := 5.6 + pace * 0.008
	if sprint:
		base = 6.6 + pace * 0.024
		base *= lerp(0.86, 1.0, stamina)
	if has_ball():
		base *= 0.9
	if keeper:
		base *= 0.92
	return base


func has_ball() -> bool:
	return team != null and team.mt != null and team.mt.ball.holder == self


func ball_anchor() -> Vector3:
	var s := speed()
	return pos + forward() * (0.46 + clamp(s * 0.045, 0.0, 0.36)) + Vector3(0, BallSim.R, 0)


func hand_point() -> Vector3:
	return pos + forward() * 0.32 + Vector3(0, 1.12, 0)


func busy() -> bool:
	return action != "" or stun > 0.0 or sent_off


func can_touch_ball() -> bool:
	return ball_cooldown <= 0.0 and stun <= 0.0 and not sent_off and action not in ["fall", "slide_end", "dejected"]


func play_action(a: String, dur: float, contact := 0.5, cb := Callable(), side := 1.0, height := 0.35, face = null) -> void:
	action = a
	action_t = 0.0
	action_dur = max(0.05, dur)
	action_contact = contact
	action_cb = cb
	action_side = side
	action_height = height
	action_face = face
	_contact_done = false


func cancel_action() -> void:
	action = ""
	action_cb = Callable()
	action_face = null


func face_towards(p: Vector3, instant := false) -> void:
	var d := p - pos
	if Vector2(d.x, d.z).length() < 0.01:
		return
	var target = atan2(d.x, d.z)
	if instant:
		yaw = target
	else:
		yaw = rotate_toward(yaw, target, 0.4)


# ------------------------------------------------------------------ simulation
func tick(dt: float) -> void:
	time += dt
	if ball_cooldown > 0.0:
		ball_cooldown -= dt
	if stun > 0.0:
		stun -= dt
	if sent_off:
		vel = Vector3.ZERO
		return
	_update_action(dt)
	var locked := false
	match action:
		"slide":
			locked = true
			slide_vel *= exp(-dt * 1.6)
			vel = slide_vel
		"dive":
			locked = true
			if action_t < 0.6:
				vel = dive_vel
			else:
				vel = vel * exp(-dt * 9.0)
		"fall", "catch", "throw", "gk_throw", "cel_kneeslide", "cel_arms", "cel_fist", "dejected":
			locked = true
			vel = vel * exp(-dt * (2.5 if action == "cel_kneeslide" else 8.0))
		"kick", "pass", "lob", "cross", "volley", "header", "tackle", "stumble":
			locked = true
			var keep := 0.55 if action in ["kick", "volley", "header"] else 0.75
			var dv := desired * keep - vel
			vel += dv.limit_length(8.0 * dt)
	if not locked:
		var target := desired.limit_length(max_speed())
		var dv := target - vel
		var acc := 10.0 + float(stats.pace) * 0.04
		if target.length() < vel.length():
			acc = 14.0
		vel += dv.limit_length(acc * dt)
	vel.y = 0.0
	pos += vel * dt
	pos.y = 0.0
	# facing
	if action_face != null and action_t < action_contact:
		var d: Vector3 = action_face - pos
		if Vector2(d.x, d.z).length() > 0.05:
			yaw = rotate_toward(yaw, atan2(d.x, d.z), dt * 14.0)
	elif not locked:
		if face_point != null:
			var d: Vector3 = face_point - pos
			if Vector2(d.x, d.z).length() > 0.2:
				yaw = rotate_toward(yaw, atan2(d.x, d.z), dt * 9.0)
		elif speed() > 0.6:
			var turn := 7.0 + (6.0 if speed() < 4.0 else 0.0)
			yaw = rotate_toward(yaw, atan2(vel.x, vel.z), dt * turn)
	# stamina
	if sprint and speed() > 5.0:
		stamina = max(0.0, stamina - dt * 0.045)
	else:
		stamina = min(1.0, stamina + dt * 0.03)
	# gait phase
	var sp := speed()
	var fwd := vel.dot(forward())
	var stride := 1.3 + 0.27 * sp
	phase += dt * (sp / stride) * TAU * (1.0 if fwd >= -0.3 else -1.0)
	phase = fmod(phase, TAU * 100.0)


func _update_action(dt: float) -> void:
	if action == "":
		return
	if action.begins_with("cel_") or action == "cheer" or action == "hold":
		action_t = fmod(action_t + dt / action_dur, 1.0)
		return
	action_t += dt / action_dur
	if not _contact_done and action_t >= action_contact:
		_contact_done = true
		if action_cb.is_valid():
			action_cb.call()
	if action_t >= 1.0:
		var was := action
		action = ""
		action_cb = Callable()
		action_face = null
		if was == "dive":
			stun = 0.3
		elif was == "slide":
			stun = 0.25


func _process(delta: float) -> void:
	if puppet:
		return
	global_position = pos
	rotation = Vector3(0, yaw, 0)
	_state.speed = speed()
	_state.fwd_speed = vel.dot(forward())
	_state.phase = phase
	_state.action = action
	_state.t = clamp(action_t, 0.0, 1.0)
	_state.side = action_side
	_state.height = action_height
	_state.time = time
	_state.keeper = keeper
	_state.ready = ready_amt
	rig.apply(_state, delta)


## Snapshot for replays.
func snapshot() -> Array:
	return [pos, yaw, speed(), vel.dot(forward()), phase, action, clamp(action_t, 0.0, 1.0), action_side, action_height, ready_amt]


func apply_snapshot(a: Array, b: Array, k: float, delta: float) -> void:
	var p: Vector3 = (a[0] as Vector3).lerp(b[0], k)
	global_position = p
	rotation = Vector3(0, lerp_angle(a[1], b[1], k), 0)
	var st = {"speed": lerp(float(a[2]), float(b[2]), k), "fwd_speed": a[3], "phase": lerp(float(a[4]), float(b[4]), k),
		"action": a[5], "t": lerp(float(a[6]), float(b[6]), k) if a[5] == b[5] else a[6], "side": a[7], "height": a[8],
		"time": time, "keeper": keeper, "ready": a[9]}
	rig.apply(st, delta)
