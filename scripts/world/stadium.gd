class_name Stadium
extends Node3D
## Procedurally built venue: pitch, goals, stands, crowd, LED boards, lights, weather.

signal ready_built

var venue := "harbor"
var time_of_day := "night"
var weather := "clear"
var L := 52.5          # half length (goal line x)
var W := 34.0          # half width (touchline z)
var goal_hw := 3.66    # half goal width
var goal_h := 2.44
var goal_depth := 2.0
var is_cage := false

var env: Environment
var key_light: DirectionalLight3D
var crowd_mat: ShaderMaterial
var pitch_mat: ShaderMaterial
var board_mats: Array[ShaderMaterial] = []
var net_mats := {}          # side (+1/-1) -> ShaderMaterial
var _net_amp := {1: 0.0, -1: 0.0}
var _net_phase := {1: 0.0, -1: 0.0}
var _excite := 0.0
var _excite_target := 0.0
var rain: GPUParticles3D
var quality := 2

static var _tex_cache := {}


func build(v: String, t: String, w: String) -> void:
	venue = v
	time_of_day = t
	weather = w
	quality = int(Game.settings.get("shadows", 2))
	if venue == "cage":
		is_cage = true
		L = 20.0
		W = 12.5
		goal_hw = 1.8
		goal_h = 1.8
		goal_depth = 1.2
	_environment()
	_pitch()
	_goal(1)
	_goal(-1)
	match venue:
		"harbor":
			_bowl()
			_boards()
			_corner_flags()
		"oldground":
			_old_ground()
			_boards()
			_corner_flags()
		"cage":
			_cage()
	if weather == "rain":
		_rain()
	ready_built.emit()


# =============================================================== environment
func _environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	var key_col := Color(1.0, 0.97, 0.92)
	var key_rot := Vector3(-58, 35, 0)
	var key_e := 1.35
	var amb_e := 0.55
	var fill_e := 0.5
	var fog_col := Color("0d1c24")
	match time_of_day:
		"night":
			psm.sky_top_color = Color("01030a")
			psm.sky_horizon_color = Color("0a1a28")
			psm.ground_horizon_color = Color("0a1a28")
			psm.ground_bottom_color = Color("010203")
			psm.sun_angle_max = 1.0
			psm.sky_energy_multiplier = 0.45
			amb_e = 0.32
			key_e = 1.45
			key_col = Color(0.97, 0.98, 1.0)
		"dusk":
			psm.sky_top_color = Color("1c2a52")
			psm.sky_horizon_color = Color("f39255")
			psm.ground_horizon_color = Color("c46e48")
			psm.ground_bottom_color = Color("1a1410")
			psm.sky_energy_multiplier = 1.0
			psm.sun_angle_max = 8.0
			key_col = Color(1.0, 0.74, 0.5)
			key_rot = Vector3(-16, 120, 0)
			key_e = 1.45
			amb_e = 0.75
			fill_e = 0.55
			fog_col = Color("6b4a45")
		"day":
			psm.sky_top_color = Color("2f6fbf")
			psm.sky_horizon_color = Color("b6d6ee")
			psm.ground_horizon_color = Color("b6d6ee")
			psm.ground_bottom_color = Color("3b4a3a")
			psm.sky_energy_multiplier = 1.0
			key_col = Color(1.0, 0.97, 0.9)
			key_rot = Vector3(-50, 140, 0)
			key_e = 1.6
			amb_e = 0.95
			fill_e = 0.25
			fog_col = Color("a9c4d8")
	if weather == "rain":
		psm.sky_top_color = psm.sky_top_color.darkened(0.35)
		psm.sky_horizon_color = psm.sky_horizon_color.darkened(0.35)
		key_e *= 0.85
		fog_col = fog_col.darkened(0.2)
	sky.sky_material = psm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = amb_e
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05 if time_of_day == "night" else 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = bool(Game.settings.get("bloom", true))
	env.glow_intensity = 0.85 if time_of_day == "night" else 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = fog_col
	env.fog_density = 0.0028 if weather == "rain" else 0.0016
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.04
	env.adjustment_contrast = 1.08
	we.environment = env
	add_child(we)

	key_light = DirectionalLight3D.new()
	key_light.rotation_degrees = key_rot
	key_light.light_color = key_col
	key_light.light_energy = key_e
	key_light.shadow_enabled = quality >= 1
	key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if quality == 1 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	key_light.directional_shadow_max_distance = 70.0 if is_cage else 95.0
	key_light.shadow_blur = 1.2
	key_light.shadow_normal_bias = 1.2
	add_child(key_light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-48, key_rot.y + 170.0, 0)
	fill.light_color = Color(0.85, 0.9, 1.0)
	fill.light_energy = fill_e
	fill.shadow_enabled = false
	add_child(fill)


# =============================================================== pitch
static func noise_tex(freq: float, size: int, normal := false, seed := 1) -> NoiseTexture2D:
	var key := "%s_%s_%s_%s" % [freq, size, normal, seed]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = 4
	n.seed = seed
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	if normal:
		t.as_normal_map = true
		t.bump_strength = 6.0
	_tex_cache[key] = t
	return t


func _pitch() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	var ext := 26.0 if not is_cage else 40.0
	pm.size = Vector2((L + ext) * 2.0, (W + ext) * 2.0)
	mi.mesh = pm
	pitch_mat = ShaderMaterial.new()
	pitch_mat.shader = load("res://shaders/pitch.gdshader")
	pitch_mat.set_shader_parameter("half_len", L)
	pitch_mat.set_shader_parameter("half_wid", W)
	pitch_mat.set_shader_parameter("noise_tex", noise_tex(0.012, 256, false, 3))
	pitch_mat.set_shader_parameter("detail_tex", noise_tex(0.09, 256, false, 7))
	pitch_mat.set_shader_parameter("detail_nrm", noise_tex(0.09, 256, true, 7))
	pitch_mat.set_shader_parameter("detail", 1.0 if int(Game.settings.get("grass", 1)) >= 1 else 0.0)
	pitch_mat.set_shader_parameter("wet", 1.0 if weather == "rain" else 0.0)
	if is_cage:
		pitch_mat.set_shader_parameter("layout", 1)
		pitch_mat.set_shader_parameter("stripe_w", 4.0)
		pitch_mat.set_shader_parameter("grass_a", Color(0.2, 0.55, 0.26))
		pitch_mat.set_shader_parameter("grass_b", Color(0.17, 0.5, 0.23))
		pitch_mat.set_shader_parameter("surround", Color(0.17, 0.48, 0.23))
		pitch_mat.set_shader_parameter("surround_dist", 0.6)
		pitch_mat.set_shader_parameter("track_col", Color(0.2, 0.21, 0.22))
		pitch_mat.set_shader_parameter("wear_amt", 0.4)
	elif venue == "oldground":
		pitch_mat.set_shader_parameter("grass_a", Color(0.27, 0.5, 0.2))
		pitch_mat.set_shader_parameter("grass_b", Color(0.23, 0.44, 0.18))
		pitch_mat.set_shader_parameter("wear_amt", 1.4)
		pitch_mat.set_shader_parameter("track_col", Color(0.14, 0.16, 0.13))
	if time_of_day == "night":
		pitch_mat.set_shader_parameter("pool", 1.0)
	elif time_of_day == "dusk":
		pitch_mat.set_shader_parameter("pool", 0.5)
	mi.material_override = pitch_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# =============================================================== goals
func _goal(side: int) -> void:
	var root := Node3D.new()
	root.position = Vector3(side * L, 0, 0)
	if side < 0:
		root.rotation.y = PI
	add_child(root)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.96, 0.97, 0.95)
	post_mat.roughness = 0.35
	post_mat.emission_enabled = true
	post_mat.emission = Color(0.2, 0.2, 0.2)
	var r := 0.06
	for z in [-goal_hw - r, goal_hw + r]:
		var p := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = goal_h + r
		cm.radial_segments = 12
		p.mesh = cm
		p.material_override = post_mat
		p.position = Vector3(r, (goal_h + r) * 0.5, z)
		root.add_child(p)
	var bar := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = r
	bm.bottom_radius = r
	bm.height = goal_hw * 2.0 + r * 4.0
	bm.radial_segments = 12
	bar.mesh = bm
	bar.material_override = post_mat
	bar.rotation.x = PI * 0.5
	bar.position = Vector3(r, goal_h + r, 0)
	root.add_child(bar)
	# support frame
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.85, 0.86, 0.84)
	var dt := goal_depth * 0.5
	var db := goal_depth
	for z in [-goal_hw, goal_hw]:
		root.add_child(_bar(Vector3(0.05, goal_h, z), Vector3(dt, goal_h, z), 0.025, frame_mat))
		root.add_child(_bar(Vector3(dt, goal_h, z), Vector3(db, 0.02, z), 0.025, frame_mat))
		root.add_child(_bar(Vector3(0.05, 0.02, z), Vector3(db, 0.02, z), 0.025, frame_mat))
	root.add_child(_bar(Vector3(db, 0.02, -goal_hw), Vector3(db, 0.02, goal_hw), 0.025, frame_mat))
	# net
	var nm := ShaderMaterial.new()
	nm.shader = load("res://shaders/net.gdshader")
	nm.set_shader_parameter("cell", 0.12)
	nm.set_shader_parameter("thickness", 0.07)
	net_mats[side] = nm
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := goal_h
	# top panel
	_grid(st, func(u, v): return Vector3(lerp(0.06, dt, v), h, lerp(-goal_hw, goal_hw, u)), 14, 4, Vector3.UP, Vector2(goal_hw * 2.0, dt))
	# back panel
	var slant := Vector2(db - dt, h).length()
	_grid(st, func(u, v): return Vector3(lerp(dt, db, v), lerp(h, 0.0, v), lerp(-goal_hw, goal_hw, u)), 14, 8, Vector3(1, 0.35, 0).normalized(), Vector2(goal_hw * 2.0, slant))
	# sides
	for s in [-1.0, 1.0]:
		_grid(st, func(u, v): return Vector3(lerp(0.06, lerp(db, dt, v), u), lerp(0.0, h, v), s * goal_hw), 6, 8, Vector3(0, 0, s), Vector2(db, h))
	var mesh := st.commit()
	var net := MeshInstance3D.new()
	net.mesh = mesh
	net.material_override = nm
	net.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(net)


func _grid(st: SurfaceTool, f: Callable, nu: int, nv: int, n: Vector3, uv_scale: Vector2) -> void:
	var start := 0
	for j in nv:
		for i in nu:
			var u0 := float(i) / nu
			var u1 := float(i + 1) / nu
			var v0 := float(j) / nv
			var v1 := float(j + 1) / nv
			var a: Vector3 = f.call(u0, v0)
			var b: Vector3 = f.call(u1, v0)
			var c: Vector3 = f.call(u1, v1)
			var d: Vector3 = f.call(u0, v1)
			for tri in [[a, b, c, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1)], [a, c, d, Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1)]]:
				for k in 3:
					st.set_normal(n)
					st.set_uv(tri[3 + k] * uv_scale)
					st.add_vertex(tri[k])


func _bar(a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = 6
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	var dir := (b - a).normalized()
	var up := Vector3.UP
	if abs(dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var x := up.cross(dir).normalized()
	var z := x.cross(dir).normalized()
	mi.basis = Basis(x, dir, z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Called by the ball when it hits a net.
func net_hit(side: int, world_pos: Vector3, strength: float) -> void:
	if not net_mats.has(side):
		return
	var m: ShaderMaterial = net_mats[side]
	m.set_shader_parameter("hit_pos", world_pos)
	_net_amp[side] = clamp(strength * 0.022, 0.08, 0.5)
	_net_phase[side] = 0.0


func set_excitement(x: float, cheer_side := 0.0) -> void:
	_excite_target = clamp(x, 0.0, 1.0)
	if crowd_mat:
		crowd_mat.set_shader_parameter("home_cheer", cheer_side)


func _process(delta: float) -> void:
	for side in [1, -1]:
		if _net_amp[side] > 0.001 and net_mats.has(side):
			_net_amp[side] *= exp(-delta * 2.6)
			_net_phase[side] += delta * 14.0
			var m: ShaderMaterial = net_mats[side]
			m.set_shader_parameter("hit_amp", _net_amp[side])
			m.set_shader_parameter("hit_phase", _net_phase[side])
	_excite = move_toward(_excite, _excite_target, delta * (2.0 if _excite_target > _excite else 0.35))
	if crowd_mat:
		crowd_mat.set_shader_parameter("excite", _excite)


# =============================================================== stands
## Rounded-rectangle path around the pitch: Array of [Vector2 pos(x,z), Vector2 outward normal].
func _ring_path(hx: float, hz: float, rc: float, seg_len := 6.0, corner_segs := 6) -> Array:
	var pts := []
	var corners := [Vector2(hx - rc, hz - rc), Vector2(-(hx - rc), hz - rc), Vector2(-(hx - rc), -(hz - rc)), Vector2(hx - rc, -(hz - rc))]
	for c in 4:
		var a0 := c * PI * 0.5
		for k in corner_segs + 1:
			var a := a0 + k * (PI * 0.5) / corner_segs
			var n := Vector2(cos(a), sin(a))
			pts.append([corners[c] + n * rc, n])
		var n2 := Vector2(cos(a0 + PI * 0.5), sin(a0 + PI * 0.5))
		var p_from: Vector2 = corners[c] + n2 * rc
		var p_to: Vector2 = corners[(c + 1) % 4] + n2 * rc
		var steps: int = max(1, int(p_from.distance_to(p_to) / seg_len))
		for s in range(1, steps):
			pts.append([p_from.lerp(p_to, float(s) / steps), n2])
	pts.append(pts[0])
	return pts


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	_tri(st, a, b, c, n, col)
	_tri(st, a, c, d, n, col)


## Extrudes seating rows along a path. Returns info for crowd placement.
func _rows(st: SurfaceTool, path: Array, start_off: float, start_h: float, rows: int, depth: float, rise: float, seat_col: Color, rows_out: Array, fill: float, closed := true) -> Vector2:
	var off := start_off
	var h := start_h
	var conc := Color(0.09, 0.1, 0.11)
	for r in rows:
		var shade := 0.9 + 0.1 * float(r % 2)
		for i in path.size() - 1:
			var p0: Vector2 = path[i][0]
			var n0: Vector2 = path[i][1]
			var p1: Vector2 = path[i + 1][0]
			var n1: Vector2 = path[i + 1][1]
			var a := Vector3(p0.x + n0.x * off, h, p0.y + n0.y * off)
			var b := Vector3(p1.x + n1.x * off, h, p1.y + n1.y * off)
			var c := Vector3(p1.x + n1.x * (off + depth), h, p1.y + n1.y * (off + depth))
			var d := Vector3(p0.x + n0.x * (off + depth), h, p0.y + n0.y * (off + depth))
			_quad(st, a, b, c, d, Vector3.UP, seat_col * shade)
			var c2 := c + Vector3(0, rise, 0)
			var d2 := d + Vector3(0, rise, 0)
			var nn := Vector3(-(n0.x + n1.x), 0, -(n0.y + n1.y)).normalized()
			_quad(st, d, c, c2, d2, nn, conc * shade)
		rows_out.append({"off": off + depth * 0.5, "h": h, "fill": fill, "path": path})
		off += depth
		h += rise
	return Vector2(off, h)


func _wall(st: SurfaceTool, path: Array, off: float, h0: float, h1: float, col: Color, facing_in := true) -> void:
	for i in path.size() - 1:
		var p0: Vector2 = path[i][0]
		var n0: Vector2 = path[i][1]
		var p1: Vector2 = path[i + 1][0]
		var n1: Vector2 = path[i + 1][1]
		var a := Vector3(p0.x + n0.x * off, h0, p0.y + n0.y * off)
		var b := Vector3(p1.x + n1.x * off, h0, p1.y + n1.y * off)
		var nn := Vector3(n0.x + n1.x, 0, n0.y + n1.y).normalized() * (-1.0 if facing_in else 1.0)
		_quad(st, a, b, b + Vector3(0, h1 - h0, 0), a + Vector3(0, h1 - h0, 0), nn, col)


func _roof(st: SurfaceTool, path: Array, off0: float, off1: float, h0: float, h1: float, col: Color) -> void:
	for i in path.size() - 1:
		var p0: Vector2 = path[i][0]
		var n0: Vector2 = path[i][1]
		var p1: Vector2 = path[i + 1][0]
		var n1: Vector2 = path[i + 1][1]
		var a := Vector3(p0.x + n0.x * off0, h0, p0.y + n0.y * off0)
		var b := Vector3(p1.x + n1.x * off0, h0, p1.y + n1.y * off0)
		var c := Vector3(p1.x + n1.x * off1, h1, p1.y + n1.y * off1)
		var d := Vector3(p0.x + n0.x * off1, h1, p0.y + n0.y * off1)
		_quad(st, a, b, c, d, Vector3.DOWN, col * 0.55)
		_quad(st, a + Vector3(0, 0.4, 0), b + Vector3(0, 0.4, 0), c + Vector3(0, 0.4, 0), d + Vector3(0, 0.4, 0), Vector3.UP, col)


func _ribbon_mesh(path: Array, off: float, h0: float, h1: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dist := 0.0
	for i in path.size() - 1:
		var p0: Vector2 = path[i][0]
		var n0: Vector2 = path[i][1]
		var p1: Vector2 = path[i + 1][0]
		var n1: Vector2 = path[i + 1][1]
		var a := Vector3(p0.x + n0.x * off, h0, p0.y + n0.y * off)
		var b := Vector3(p1.x + n1.x * off, h0, p1.y + n1.y * off)
		var seg = a.distance_to(b)
		var nn := -Vector3(n0.x + n1.x, 0, n0.y + n1.y).normalized()
		var verts := [a, b, b + Vector3(0, h1 - h0, 0), a, b + Vector3(0, h1 - h0, 0), a + Vector3(0, h1 - h0, 0)]
		var uvs := [Vector2(dist, 1), Vector2(dist + seg, 1), Vector2(dist + seg, 0), Vector2(dist, 1), Vector2(dist + seg, 0), Vector2(dist, 0)]
		for k in 6:
			st.set_normal(nn)
			st.set_uv(uvs[k])
			st.add_vertex(verts[k])
		dist += seg
	return st.commit()


func _stand_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	return m


func _bowl() -> void:
	var path := _ring_path(L + 8.0, W + 7.0, 16.0, 6.0, 7)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array = []
	_wall(st, path, -0.2, 0.0, 1.2, Color(0.08, 0.12, 0.15))
	var lower := _rows(st, path, 0.0, 1.2, 24, 0.8, 0.36, Color("16222f"), rows, 0.95)
	# concourse + fascia
	var conc_off := lower.x
	var conc_h := lower.y
	_roof_flat(st, path, conc_off, conc_off + 2.2, conc_h, Color(0.18, 0.19, 0.2))
	var upper_h := conc_h + 3.4
	_wall(st, path, conc_off + 2.2, conc_h, upper_h, Color(0.07, 0.09, 0.1))
	var upper := _rows(st, path, conc_off + 2.2, upper_h, 20, 0.85, 0.5, Color("1b2a3b"), rows, 0.88)
	var top_h := upper.y
	_wall(st, path, upper.x, conc_h, top_h + 6.0, Color(0.1, 0.12, 0.14), true)
	_wall(st, path, upper.x + 0.3, 0.0, top_h + 6.0, Color(0.16, 0.18, 0.2), false)
	_roof(st, path, 5.5, upper.x + 0.3, top_h + 5.6, top_h + 6.0, Color(0.42, 0.45, 0.48))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _stand_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# LED fascia between tiers
	var rib := MeshInstance3D.new()
	rib.mesh = _ribbon_mesh(path, conc_off + 2.15, conc_h + 0.7, conc_h + 2.5)
	rib.material_override = _board_material(1.3)
	rib.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rib)
	# floodlight strip on the roof edge
	_flood_strip(path, 5.6, top_h + 5.4)
	_crowd(rows)


func _roof_flat(st: SurfaceTool, path: Array, off0: float, off1: float, h: float, col: Color) -> void:
	for i in path.size() - 1:
		var p0: Vector2 = path[i][0]
		var n0: Vector2 = path[i][1]
		var p1: Vector2 = path[i + 1][0]
		var n1: Vector2 = path[i + 1][1]
		var a := Vector3(p0.x + n0.x * off0, h, p0.y + n0.y * off0)
		var b := Vector3(p1.x + n1.x * off0, h, p1.y + n1.y * off0)
		var c := Vector3(p1.x + n1.x * off1, h, p1.y + n1.y * off1)
		var d := Vector3(p0.x + n0.x * off1, h, p0.y + n0.y * off1)
		_quad(st, a, b, c, d, Vector3.UP, col)


func _flood_strip(path: Array, off: float, h: float) -> void:
	var lights_on := time_of_day != "day"
	var lamp := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in path.size() - 1:
		var p0: Vector2 = path[i][0]
		var n0: Vector2 = path[i][1]
		var p1: Vector2 = path[i + 1][0]
		var n1: Vector2 = path[i + 1][1]
		var a := Vector3(p0.x + n0.x * off, h, p0.y + n0.y * off)
		var b := Vector3(p1.x + n1.x * off, h, p1.y + n1.y * off)
		var a2 := Vector3(p0.x + n0.x * (off + 1.2), h + 0.1, p0.y + n0.y * (off + 1.2))
		var b2 := Vector3(p1.x + n1.x * (off + 1.2), h + 0.1, p1.y + n1.y * (off + 1.2))
		_quad(st, a, b, b2, a2, Vector3(-(n0.x), -1.0, -(n0.y)).normalized(), Color.WHITE)
	lamp.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.97, 0.9) * (4.5 if lights_on else 0.9)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	lamp.material_override = m
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lamp)
	if not lights_on:
		return
	var pos: Array[Vector3] = []
	var acc := 0.0
	for i in path.size() - 1:
		var p0: Vector2 = path[i][0]
		var n0: Vector2 = path[i][1]
		var p1: Vector2 = path[i + 1][0]
		var seg := p0.distance_to(p1)
		acc += seg
		if acc > 9.0:
			acc = 0.0
			pos.append(Vector3(p0.x + n0.x * (off + 0.6), h - 0.3, p0.y + n0.y * (off + 0.6)))
	_glow_sprites(pos, 9.0, 0.55)


func _glow_sprites(pos: Array[Vector3], size: float, intensity: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = pos.size()
	for i in pos.size():
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(size, size, size)), pos[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/glow_sprite.gdshader")
	m.set_shader_parameter("intensity", intensity)
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _crowd(rows: Array, standing_ground := false) -> void:
	var total_len := 0.0
	for r in rows:
		total_len += _path_len(r.path, r.off) / 1.6 * r.fill
	var target := float(Game.crowd_count())
	var prob: float = clamp(target / max(1.0, total_len), 0.05, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var xforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	for r in rows:
		var path: Array = r.path
		for i in path.size() - 1:
			var p0: Vector2 = path[i][0]
			var n0: Vector2 = path[i][1]
			var p1: Vector2 = path[i + 1][0]
			var n1: Vector2 = path[i + 1][1]
			var a = p0 + n0 * r.off
			var b = p1 + n1 * r.off
			var seg = a.distance_to(b)
			var count := int(seg / 1.6)
			for k in count:
				if rng.randf() > r.fill * prob:
					continue
				var t = (k + 0.5) / max(1, count)
				var p = a.lerp(b, t)
				var n := n0.lerp(n1, t).normalized()
				var fwd := Vector3(-n.x, 0, -n.y)
				var basis := Basis(Vector3.UP.cross(fwd).normalized(), Vector3.UP, fwd)
				xforms.append(Transform3D(basis, Vector3(p.x, r.h + 0.48, p.y)))
				var away_end: bool = p.x < -(L + 4.0) and abs(p.y) < W + 4.0
				var team := 1.0 if away_end else (0.0 if rng.randf() < 0.8 else 1.0)
				customs.append(Color(rng.randf(), rng.randf(), rng.randf(), team))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 0.96)
	mm.mesh = q
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, customs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	crowd_mat = ShaderMaterial.new()
	crowd_mat.shader = load("res://shaders/crowd.gdshader")
	var b := 0.5 if time_of_day == "night" else (0.95 if time_of_day == "day" else 0.62)
	crowd_mat.set_shader_parameter("bright", b)
	mmi.material_override = crowd_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func set_crowd_colors(home: Color, away: Color) -> void:
	if crowd_mat:
		crowd_mat.set_shader_parameter("home_col", home)
		crowd_mat.set_shader_parameter("away_col", away)


func _path_len(path: Array, off: float) -> float:
	var s := 0.0
	for i in path.size() - 1:
		var a: Vector2 = path[i][0] + path[i][1] * off
		var b: Vector2 = path[i + 1][0] + path[i + 1][1] * off
		s += a.distance_to(b)
	return s


# =============================================================== boards
func _board_material(energy := 1.6) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/led_board.gdshader")
	m.set_shader_parameter("energy", energy if time_of_day != "day" else energy * 0.8)
	board_mats.append(m)
	return m


func _boards() -> void:
	var hx := L + 6.0
	var hz := W + 4.5
	var path := [[Vector2(hx, -hz), Vector2(1, 0)], [Vector2(hx, hz), Vector2(1, 0)], [Vector2(hx, hz), Vector2(0, 1)], [Vector2(-hx, hz), Vector2(0, 1)],
		[Vector2(-hx, hz), Vector2(-1, 0)], [Vector2(-hx, -hz), Vector2(-1, 0)], [Vector2(-hx, -hz), Vector2(0, -1)], [Vector2(hx, -hz), Vector2(0, -1)]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dist := 0.0
	var back := SurfaceTool.new()
	back.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, path.size(), 2):
		var p0: Vector2 = path[i][0]
		var p1: Vector2 = path[i + 1][0]
		var n: Vector2 = path[i][1]
		var a := Vector3(p0.x, 0.02, p0.y)
		var b := Vector3(p1.x, 0.02, p1.y)
		var tilt := Vector3(n.x, 0, n.y) * 0.18
		var seg = a.distance_to(b)
		var nn := -Vector3(n.x, -0.2, n.y).normalized()
		var verts := [a, b, b + Vector3(0, 0.92, 0) + tilt, a, b + Vector3(0, 0.92, 0) + tilt, a + Vector3(0, 0.92, 0) + tilt]
		var uvs := [Vector2(dist, 1), Vector2(dist + seg, 1), Vector2(dist + seg, 0), Vector2(dist, 1), Vector2(dist + seg, 0), Vector2(dist, 0)]
		for k in 6:
			st.set_normal(nn)
			st.set_uv(uvs[k])
			st.add_vertex(verts[k])
		_quad(back, a + Vector3(n.x, 0, n.y) * 0.25, b + Vector3(n.x, 0, n.y) * 0.25, b + Vector3(0, 0.95, 0) + tilt * 1.4, a + Vector3(0, 0.95, 0) + tilt * 1.4, Vector3(n.x, 0, n.y), Color(0.06, 0.07, 0.08))
		dist += seg
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _board_material(1.6)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var bk := MeshInstance3D.new()
	bk.mesh = back.commit()
	bk.material_override = _stand_material()
	add_child(bk)
	_make_board_texture()


func _make_board_texture() -> void:
	if _tex_cache.has("board"):
		_apply_board_tex(_tex_cache["board"])
		return
	if DisplayServer.get_name() == "headless":
		return
	var sv := SubViewport.new()
	sv.size = Vector2i(2048, 96)
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	sv.transparent_bg = false
	var items := [["GOAL DIGGER", Color("FFCF33"), Color("1C1500")], ["HARBOR ARENA", Color("07141A"), Color("43C6F0")],
		["PLAY OFFLINE", Color("43C6F0"), Color("07141A")], ["KICK OFF 20:00", Color("07141A"), Color("FFCF33")],
		["NO ADS. JUST FOOTBALL", Color("FF5B4A"), Color("FFFFFF")], ["GOAL DIGGER", Color("EDF2EA"), Color("07141A")]]
	var w := 2048.0 / items.size()
	for i in items.size():
		var cr := ColorRect.new()
		cr.color = items[i][1]
		cr.position = Vector2(i * w, 0)
		cr.size = Vector2(w, 96)
		sv.add_child(cr)
		var l := Label.new()
		l.text = items[i][0]
		l.add_theme_font_override("font", UI.font("disp_x"))
		l.add_theme_font_size_override("font_size", 60 if items[i][0].length() < 16 else 44)
		l.add_theme_color_override("font_color", items[i][2])
		l.position = Vector2(i * w, 0)
		l.size = Vector2(w, 96)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sv.add_child(l)
	add_child(sv)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(sv):
		return
	var img := sv.get_texture().get_image()
	sv.queue_free()
	if img == null or img.is_empty():
		return
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["board"] = tex
	_apply_board_tex(tex)


func _apply_board_tex(tex: Texture2D) -> void:
	for m in board_mats:
		m.set_shader_parameter("board_tex", tex)
		m.set_shader_parameter("has_tex", 1.0)
		m.set_shader_parameter("tex_len", 64.0)


func _corner_flags() -> void:
	var pole_m := StandardMaterial3D.new()
	pole_m.albedo_color = Color(0.95, 0.95, 0.9)
	var flag_m := StandardMaterial3D.new()
	flag_m.albedo_color = Color("FFCF33")
	flag_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag_m.emission_enabled = true
	flag_m.emission = Color("FFCF33") * 0.25
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			add_child(_bar(Vector3(sx * L, 0, sz * W), Vector3(sx * L, 1.5, sz * W), 0.02, pole_m))
			var f := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.45, 0.32)
			f.mesh = q
			f.material_override = flag_m
			f.position = Vector3(sx * L + 0.23 * -sx, 1.33, sz * W)
			add_child(f)


# =============================================================== old ground
func _old_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array = []
	var sides := [
		{"path": [[Vector2(-L - 2, W + 6), Vector2(0, 1)], [Vector2(L + 2, W + 6), Vector2(0, 1)]], "rows": 26, "rise": 0.42, "roof": true, "col": Color("5a2230")},
		{"path": [[Vector2(L + 2, -W - 6), Vector2(0, -1)], [Vector2(-L - 2, -W - 6), Vector2(0, -1)]], "rows": 22, "rise": 0.42, "roof": true, "col": Color("5a2230")},
		{"path": [[Vector2(L + 9, W - 2), Vector2(1, 0)], [Vector2(L + 9, -W + 2), Vector2(1, 0)]], "rows": 16, "rise": 0.32, "roof": false, "col": Color("3b3f42")},
		{"path": [[Vector2(-L - 9, -W + 2), Vector2(-1, 0)], [Vector2(-L - 9, W - 2), Vector2(-1, 0)]], "rows": 16, "rise": 0.32, "roof": false, "col": Color("3b3f42")},
	]
	for s in sides:
		_wall(st, s.path, -0.2, 0.0, 1.0, Color(0.32, 0.12, 0.14))
		var top = _rows(st, s.path, 0.0, 1.0, s.rows, 0.75, s.rise, s.col, rows, 0.9)
		_wall(st, s.path, top.x, 0.0, top.y + (5.0 if s.roof else 1.2), Color(0.25, 0.2, 0.18), true)
		_wall(st, s.path, top.x + 0.3, 0.0, top.y + (5.0 if s.roof else 1.2), Color(0.3, 0.24, 0.2), false)
		if s.roof:
			_roof(st, s.path, 1.5, top.x + 0.3, top.y + 4.6, top.y + 5.0, Color(0.55, 0.5, 0.44))
			_end_caps(st, s.path, top, Color(0.28, 0.22, 0.2))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _stand_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_crowd(rows)
	# corner floodlight pylons
	var pylon_m := StandardMaterial3D.new()
	pylon_m.albedo_color = Color(0.35, 0.36, 0.37)
	pylon_m.metallic = 0.6
	var glows: Array[Vector3] = []
	var lamp_m := StandardMaterial3D.new()
	lamp_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_m.albedo_color = Color(1, 0.96, 0.85) * (4.0 if time_of_day != "day" else 0.8)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var base := Vector3(sx * (L + 14), 0, sz * (W + 14))
			var top := base + Vector3(-sx * 2.0, 34, -sz * 2.0)
			add_child(_bar(base, top, 0.5, pylon_m))
			var bank := MeshInstance3D.new()
			var bx := BoxMesh.new()
			bx.size = Vector3(5.5, 3.2, 0.4)
			bank.mesh = bx
			bank.material_override = lamp_m
			bank.position = top + Vector3(0, 1.6, 0)
			bank.look_at_from_position(bank.position, Vector3(0, 0, 0), Vector3.UP)
			add_child(bank)
			for gx in 3:
				for gy in 2:
					var lp := bank.position + bank.basis.x * ((gx - 1) * 1.7) + bank.basis.y * ((gy - 0.5) * 1.4) - bank.basis.z * 0.3
					glows.append(lp)
	if time_of_day != "day":
		_glow_sprites(glows, 6.5, 0.5)


func _end_caps(st: SurfaceTool, path: Array, top: Vector2, col: Color) -> void:
	for idx in [0, path.size() - 1]:
		var p: Vector2 = path[idx][0]
		var n: Vector2 = path[idx][1]
		var other: Vector2 = path[1 - idx if idx == 0 else idx - 1][0]
		var side_dir := (p - other).normalized()
		var a := Vector3(p.x, 0, p.y)
		var b := Vector3(p.x + n.x * (top.x + 0.3), 0, p.y + n.y * (top.x + 0.3))
		var h := top.y + 5.0
		_quad(st, a, b, b + Vector3(0, h, 0), a + Vector3(0, 1.0, 0), Vector3(side_dir.x, 0, side_dir.y), col)


# =============================================================== street cage
func _cage() -> void:
	var wall_h := 1.2
	var fence_top := 4.6
	var X := L
	var Z := W
	# kickboards
	var gm := ShaderMaterial.new()
	gm.shader = _graffiti_shader()
	var segs := [
		[Vector3(-X, 0, Z), Vector3(X, 0, Z)], [Vector3(X, 0, -Z), Vector3(-X, 0, -Z)],
		[Vector3(X, 0, Z), Vector3(X, 0, goal_hw + 0.06)], [Vector3(X, 0, -goal_hw - 0.06), Vector3(X, 0, -Z)],
		[Vector3(-X, 0, -Z), Vector3(-X, 0, -goal_hw - 0.06)], [Vector3(-X, 0, goal_hw + 0.06), Vector3(-X, 0, Z)],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dist := 0.0
	for s in segs:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var inward = -Vector3(sign(a.x) if abs(a.x) >= X - 0.01 and abs(a.x - b.x) < 0.01 else 0.0, 0, sign(a.z) if abs(a.z - b.z) < 0.01 and abs(a.z) >= Z - 0.01 else 0.0).normalized()
		var seg = a.distance_to(b)
		var verts := [a, b, b + Vector3(0, wall_h, 0), a, b + Vector3(0, wall_h, 0), a + Vector3(0, wall_h, 0)]
		var uvs := [Vector2(dist, 0), Vector2(dist + seg, 0), Vector2(dist + seg, wall_h), Vector2(dist, 0), Vector2(dist + seg, wall_h), Vector2(dist, wall_h)]
		for k in 6:
			st.set_normal(inward)
			st.set_uv(uvs[k])
			st.add_vertex(verts[k])
		dist += seg
	# above-goal panels (goal frame fills the gap)
	for sx in [-1.0, 1.0]:
		var a := Vector3(sx * X, goal_h + 0.12, goal_hw + 0.06)
		var b := Vector3(sx * X, goal_h + 0.12, -goal_hw - 0.06)
		var inward := Vector3(-sx, 0, 0)
		var verts := [a, b, b + Vector3(0, wall_h * 0.6, 0), a, b + Vector3(0, wall_h * 0.6, 0), a + Vector3(0, wall_h * 0.6, 0)]
		for k in 6:
			st.set_normal(inward)
			st.set_uv(Vector2(verts[k].z, verts[k].y))
			st.add_vertex(verts[k])
	var boards := MeshInstance3D.new()
	boards.mesh = st.commit()
	boards.material_override = gm
	add_child(boards)
	# chain-link fence
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/net.gdshader")
	fm.set_shader_parameter("pattern", 1)
	fm.set_shader_parameter("cell", 0.09)
	fm.set_shader_parameter("thickness", 0.08)
	fm.set_shader_parameter("net_col", Color(0.62, 0.64, 0.66))
	fm.set_shader_parameter("opacity", 0.85)
	var fs := SurfaceTool.new()
	fs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector3(-X, 0, Z), Vector3(X, 0, Z), Vector3(X, 0, -Z), Vector3(-X, 0, -Z), Vector3(-X, 0, Z)]
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[i + 1]
		if a.z > 0.0 and b.z > 0.0:
			continue
		var n := -Vector3(a.x + b.x, 0, a.z + b.z).normalized()
		var seg = a.distance_to(b)
		_grid(fs, func(u, v): return a.lerp(b, u) + Vector3(0, lerp(wall_h, fence_top, v), 0), 8, 2, n, Vector2(seg, fence_top - wall_h))
	var fence := MeshInstance3D.new()
	fence.mesh = fs.commit()
	fence.material_override = fm
	fence.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fence)
	var post_m := StandardMaterial3D.new()
	post_m.albedo_color = Color(0.18, 0.2, 0.22)
	post_m.metallic = 0.7
	post_m.roughness = 0.4
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[i + 1]
		if a.z > 0.0 and b.z > 0.0:
			continue
		var n := int(a.distance_to(b) / 4.0)
		for k in n + 1:
			var p = a.lerp(b, float(k) / n)
			add_child(_bar(p, p + Vector3(0, fence_top + 0.1, 0), 0.05, post_m))
		add_child(_bar(a + Vector3(0, fence_top, 0), b + Vector3(0, fence_top, 0), 0.04, post_m))
	_city()
	# spectators standing around the cage
	var rows: Array = []
	var ring := _ring_path(X + 3.0, Z + 3.0, 2.0, 2.0, 2)
	rows.append({"off": 0.0, "h": 0.0, "fill": 0.55, "path": ring})
	rows.append({"off": 1.4, "h": 0.15, "fill": 0.35, "path": ring})
	_crowd(rows)
	if crowd_mat:
		crowd_mat.set_shader_parameter("back_col", Color(0.12, 0.13, 0.14))
	# sodium floodlights on four poles
	var lamp_m := StandardMaterial3D.new()
	lamp_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_m.albedo_color = Color(1.0, 0.72, 0.38) * 4.0
	var glows: Array[Vector3] = []
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var base := Vector3(sx * (X + 1.5), 0, sz * (Z + 1.5))
			var top := base + Vector3(0, 11, 0)
			add_child(_bar(base, top, 0.12, post_m))
			var head := MeshInstance3D.new()
			var bx := BoxMesh.new()
			bx.size = Vector3(1.4, 0.3, 0.8)
			head.mesh = bx
			head.material_override = lamp_m
			head.position = top + Vector3(-sx * 0.6, 0, -sz * 0.6)
			add_child(head)
			glows.append(head.position + Vector3(0, -0.3, 0))
			var sp := SpotLight3D.new()
			sp.position = head.position
			sp.light_color = Color(1.0, 0.78, 0.5)
			sp.light_energy = 6.0
			sp.spot_range = 40.0
			sp.spot_angle = 55.0
			sp.spot_attenuation = 0.6
			sp.shadow_enabled = false
			add_child(sp)
			sp.look_at(Vector3(-sx * 4.0, 0, -sz * 2.0), Vector3.UP)
	_glow_sprites(glows, 5.0, 0.7)
	if key_light:
		key_light.light_energy *= 0.55
		key_light.light_color = Color(0.8, 0.85, 1.0)


func _graffiti_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D n : repeat_enable, filter_linear_mipmap;
float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 p = UV;
	vec3 base = vec3(0.06, 0.12, 0.2);
	float cell = floor(p.x / 3.0);
	float r = h(vec2(cell, 1.0));
	vec3 c1 = mix(vec3(1.0, 0.81, 0.2), vec3(0.26, 0.78, 0.94), step(0.5, r));
	c1 = mix(c1, vec3(1.0, 0.36, 0.29), step(0.75, r));
	float lx = fract(p.x / 3.0);
	float blob = smoothstep(0.42, 0.38, length(vec2((lx - 0.5) * 1.8, (p.y - 0.6) * 1.2)) + 0.1 * sin(p.x * 9.0 + p.y * 7.0));
	float stripe = step(0.92, fract(p.x * 0.9 + p.y * 0.5)) * step(0.3, r);
	vec3 col = mix(base, c1, blob * 0.85);
	col = mix(col, vec3(0.93), stripe * 0.6);
	col = mix(col, vec3(0.93, 0.95, 0.92), step(1.12, p.y) * 0.8);
	ALBEDO = col;
	ROUGHNESS = 0.7;
}
"""
	return s


func _city() -> void:
	var s := Shader.new()
	s.code = """
shader_type spatial;
uniform vec3 wall : source_color = vec3(0.16, 0.17, 0.2);
float h(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 g = vec2(UV.x * 0.5, UV.y / 3.2);
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float win = step(0.32, f.x) * step(f.x, 0.68) * step(0.38, f.y) * step(f.y, 0.7);
	float lit = step(0.68, h(cell + vec2(COLOR.r * 31.0, 0.0)));
	vec3 warm = mix(vec3(1.0, 0.78, 0.45), vec3(0.75, 0.85, 1.0), h(cell * 1.7));
	ALBEDO = wall * (0.8 + 0.4 * COLOR.g);
	EMISSION = warm * win * lit * 0.9;
	ROUGHNESS = 0.9;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = s
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for side in 4:
		var count := 7 if side < 2 else 5
		for i in count:
			var w := rng.randf_range(9, 16)
			var d := rng.randf_range(8, 12)
			var h := rng.randf_range(10, 34)
			var c: Vector3
			var along := (float(i) / (count - 1) - 0.5)
			match side:
				0: c = Vector3(along * 110.0, 0, W + rng.randf_range(26, 34))
				1: c = Vector3(along * 110.0, 0, -W - rng.randf_range(26, 34))
				2: c = Vector3(L + rng.randf_range(28, 36), 0, along * 80.0)
				3: c = Vector3(-L - rng.randf_range(28, 36), 0, along * 80.0)
			_box_building(st, c, Vector3(w, h, d), Color(rng.randf(), rng.randf(), 0, 1))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# street lamps
	var glows: Array[Vector3] = []
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.15, 0.16, 0.17)
	for i in 10:
		var x := -60.0 + i * 13.0
		for z in [W + 15.0, -W - 15.0]:
			add_child(_bar(Vector3(x, 0, z), Vector3(x, 6.5, z), 0.07, pm))
			glows.append(Vector3(x, 6.6, z))
	_glow_sprites(glows, 3.2, 0.8)


func _box_building(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var hx = s.x * 0.5
	var hz = s.z * 0.5
	var faces := [
		[Vector3(c.x - hx, 0, c.z + hz), Vector3(c.x + hx, 0, c.z + hz), Vector3(0, 0, 1), s.x],
		[Vector3(c.x + hx, 0, c.z - hz), Vector3(c.x - hx, 0, c.z - hz), Vector3(0, 0, -1), s.x],
		[Vector3(c.x + hx, 0, c.z + hz), Vector3(c.x + hx, 0, c.z - hz), Vector3(1, 0, 0), s.z],
		[Vector3(c.x - hx, 0, c.z - hz), Vector3(c.x - hx, 0, c.z + hz), Vector3(-1, 0, 0), s.z],
	]
	for f in faces:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var n: Vector3 = f[2]
		var verts := [a, b, b + Vector3(0, s.y, 0), a, b + Vector3(0, s.y, 0), a + Vector3(0, s.y, 0)]
		var uvs = [Vector2(0, 0), Vector2(f[3], 0), Vector2(f[3], s.y), Vector2(0, 0), Vector2(f[3], s.y), Vector2(0, s.y)]
		var tri_ok = (verts[1] - verts[0]).cross(verts[2] - verts[0]).dot(n) < 0.0
		for k in 6:
			var kk: int = k if tri_ok else [0, 2, 1, 3, 5, 4][k]
			st.set_color(col)
			st.set_normal(n)
			st.set_uv(uvs[kk])
			st.add_vertex(verts[kk])
	# roof
	var r0 := Vector3(c.x - hx, s.y, c.z - hz)
	_quad(st, r0, r0 + Vector3(s.x, 0, 0), r0 + Vector3(s.x, 0, s.z), r0 + Vector3(0, 0, s.z), Vector3.UP, Color(col.r, 0.0, 0.0))


# =============================================================== rain
func _rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = [600, 1400, 2400][clamp(quality, 0, 2)]
	rain.lifetime = 0.9
	rain.preprocess = 1.0
	rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28, 2, 28)
	pm.direction = Vector3(0.1, -1, 0.05)
	pm.spread = 3.0
	pm.initial_velocity_min = 24.0
	pm.initial_velocity_max = 30.0
	pm.gravity = Vector3(0, -20, 0)
	rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.7)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.82, 0.9, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	q.material = m
	rain.draw_pass_1 = q
	add_child(rain)


## Rain follows the camera so it is always visible without covering the whole stadium.
func follow_camera(cam: Camera3D) -> void:
	if rain and cam:
		rain.global_position = cam.global_position + (-cam.global_transform.basis.z) * 14.0 + Vector3(0, 14, 0)
