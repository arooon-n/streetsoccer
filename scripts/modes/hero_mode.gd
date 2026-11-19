extends Node3D
## Hero Challenge gameplay: draw passes and shots with your finger; time slows near each touch.

var params := {}
var lv: Dictionary
var stadium: Stadium
var ball: Ball
var cam: Camera3D
var attackers: Array = []
var defenders: Array = []
var keeper: Footballer
var def_pos: Array = []           # Vector3 positions used by the sim
var carrier := 0
var moves := 0
var touched := {}
var pass_log: Array = []
var used_lob_into := false
var phase := "aim"                 # aim, flight, shot, done
var flight := {}
var queued := {}
var drawing := false
var draw_pts := PackedVector2Array()
var ground_pts := PackedVector3Array()
var goal_target = null
var first_time_ok := true
var _imesh: ImmediateMesh
var _line: MeshInstance3D
var _ui: Control
var _hint: Label
var _move_lbl: Label
var _obj_box: VBoxContainer
var _slowmo: PanelContainer
var _overlay: Control = null
var _speed := 1.0
var _done_reason := ""
var _bonus_hit := false
var _last_shot_bend := 0.0


func _ready() -> void:
	lv = HeroLevels.level(params.get("level", "1-1"))
	if lv.is_empty():
		lv = HeroLevels.all_levels()[0]
	BallSim.wet = false
	stadium = Stadium.new()
	add_child(stadium)
	stadium.build("harbor", lv.time, "clear")
	ball = Ball.new()
	ball.stadium = stadium
	add_child(ball)
	ball.frozen = true
	var home := Game.kit_colors(Game.save.club.home)
	var opp_t: Dictionary = Game.TEAMS[(lv.chapter * 3 + lv.n) % (Game.TEAMS.size() - 1) + 1]
	var away := Game.kit_colors(opp_t.home)
	if Vector3(home.shirt.r - away.shirt.r, home.shirt.g - away.shirt.g, home.shirt.b - away.shirt.b).length() < 0.4:
		away = Game.kit_colors(opp_t.away)
	stadium.set_crowd_colors(home.shirt, away.shirt)
	var i := 0
	for a in lv.attackers:
		var p := _spawn(home, Vector3(a[0], 0, a[1]), [9, 10, 7][i % 3], i)
		p.pname = a[2]
		p.yaw = PI * 0.5
		attackers.append(p)
		i += 1
	for d in lv.defenders:
		var p := _spawn(away, Vector3(d[0], 0, d[1]), [4, 5, 3, 2, 6, 8][defenders.size() % 6], i)
		p.yaw = -PI * 0.5
		defenders.append(p)
		def_pos.append(Vector3(d[0], 0, d[1]))
		i += 1
	var gk_kit := {"shirt": Color("F08A24"), "shirt2": Color("2A1A08"), "pattern": 0, "shorts": Color("2A1A08"), "socks": Color("F08A24")}
	keeper = Footballer.new()
	keeper.keeper = true
	keeper.number = 1
	keeper.setup(away, Color(Game.SKIN_TONES[3]), Color(Game.HAIR[2]), Color("151515"), gk_kit)
	add_child(keeper)
	keeper.ready_amt = 1.0
	carrier = int(lv.carrier)
	touched[carrier] = true
	_place_keeper()
	_imesh = ImmediateMesh.new()
	_line = MeshInstance3D.new()
	_line.mesh = _imesh
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.vertex_color_use_as_albedo = true
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	lm.no_depth_test = true
	_line.material_override = lm
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	ball.set_camera(cam)
	_frame_camera()
	_build_ui()
	Sfx.start_crowd()
	Sfx.set_excitement(0.3)
	_give_ball(carrier)


func _spawn(kit: Dictionary, at: Vector3, num: int, i: int) -> Footballer:
	var p := Footballer.new()
	p.number = num
	p.setup(kit, Color(Game.SKIN_TONES[i % 8]), Color(Game.HAIR[(i * 3) % 8]), Color("151515"))
	add_child(p)
	p.pos = at
	return p


func _place_keeper() -> void:
	var c: Footballer = attackers[carrier]
	keeper.pos = HeroSim.keeper_spot(c.pos)
	keeper.face_towards(c.pos, true)


func _give_ball(i: int) -> void:
	carrier = i
	var p: Footballer = attackers[i]
	ball.frozen = true
	ball.holder = null
	ball.pos = p.pos + Vector3(1, 0, 0) * 0.55 + Vector3(0, BallSim.R, 0)
	ball.place(ball.pos)
	ball.frozen = true
	p.face_towards(Vector3(HeroSim.GOAL_X, 0, 0), true)
	_place_keeper()


func _frame_camera() -> void:
	# frame every attacker and defender plus the goal mouth
	var minx := 60.0
	var zmin := -4.0
	var zmax := 4.0
	for p in attackers:
		minx = min(minx, p.pos.x)
		zmin = min(zmin, p.pos.z)
		zmax = max(zmax, p.pos.z)
	for p in def_pos:
		zmin = min(zmin, p.z)
		zmax = max(zmax, p.z)
	var cz := (zmin + zmax) * 0.5
	var spread := zmax - zmin
	var back := minx - 11.0 - spread * 0.12
	var h := 9.5 + spread * 0.28
	cam.fov = 56.0
	cam.position = Vector3(back, h, cz * 0.7)
	cam.look_at(Vector3((minx + HeroSim.GOAL_X) * 0.5 + 3.0, 0, cz * 0.85), Vector3.UP)


# ================================================================== UI
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = UI.screen_root()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	var m := UI.safe_margin()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(m)
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(c)
	var tl := UI.panel(false)
	tl.pad = 9
	var tv := UI.vbox(1)
	_move_lbl = UI.eyebrow("Level %s · Move 1 of %d" % [lv.id, lv.par])
	tv.add_child(_move_lbl)
	tv.add_child(UI.label(lv.title, 19, "disp_x", Game.C_CHALK, true))
	tl.add_child(tv)
	c.add_child(tl)
	var tr := UI.hbox(8)
	tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	var op := UI.panel(false)
	op.pad = 8
	_obj_box = UI.vbox(3)
	op.add_child(_obj_box)
	tr.add_child(op)
	var pause := UI.icon_button("pause", "Pause")
	pause.pressed.connect(_pause_menu)
	tr.add_child(pause)
	c.add_child(tr)
	_slowmo = UI.pill("0.2× slow motion")
	(_slowmo.find_child("Text", true, false) as Label).add_theme_color_override("font_color", Game.C_CARD)
	_slowmo.visible = false
	c.add_child(_slowmo)
	var hp := UI.pill("Drag from %s to draw a pass or a shot" % attackers[carrier].pname)
	_hint = hp.find_child("Text", true, false)
	c.add_child(hp)
	_update_objectives()
	await get_tree().process_frame
	tr.position = Vector2(c.size.x - tr.size.x, 0)
	hp.position = Vector2((c.size.x - hp.size.x) * 0.5, c.size.y - hp.size.y)
	_slowmo.position = Vector2(0, c.size.y - 70)
	hp.resized.connect(func(): hp.position = Vector2((c.size.x - hp.size.x) * 0.5, c.size.y - hp.size.y))


func _update_objectives() -> void:
	for ch in _obj_box.get_children():
		ch.queue_free()
	var lines := [["Score", phase == "done" and _done_reason == "goal"],
		["Score in %d move%s or fewer" % [lv.par, "" if lv.par == 1 else "s"], phase == "done" and _done_reason == "goal" and moves <= int(lv.par)],
		[HeroLevels.BONUS_TEXT.get(lv.bonus, ""), _bonus_hit and _done_reason == "goal"]]
	for l in lines:
		var row := UI.hbox(6)
		var ic := Icon.new()
		ic.kind = "check" if l[1] else "star"
		ic.color = Game.C_CARD if l[1] else Game.C_DIM
		ic.custom_minimum_size = Vector2(12, 12)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
		row.add_child(UI.label(l[0], 12, "body_m", Game.C_CHALK if l[1] else Game.C_DIM))
		_obj_box.add_child(row)


# ================================================================== input
func _input(e: InputEvent) -> void:
	if phase == "done" or get_tree().paused or _overlay != null:
		return
	if e is InputEventScreenTouch:
		var sp: Vector2 = e.position
		if e.pressed:
			var from_idx := _draw_source()
			if from_idx < 0:
				return
			var p: Footballer = attackers[from_idx]
			var ps := cam.unproject_position(p.pos + Vector3(0, 0.9, 0))
			var bs := cam.unproject_position(ball.pos)
			if sp.distance_to(ps) < 70.0 or sp.distance_to(bs) < 70.0:
				drawing = true
				draw_pts = PackedVector2Array([sp])
				ground_pts = PackedVector3Array([Vector3(p.pos.x + 0.5, 0, p.pos.z)])
				goal_target = null
		elif drawing:
			drawing = false
			_finish_draw()
	elif e is InputEventScreenDrag and drawing:
		var sp: Vector2 = e.position
		if draw_pts.size() > 0 and draw_pts[draw_pts.size() - 1].distance_to(sp) < 6.0:
			return
		draw_pts.append(sp)
		if goal_target != null:
			return
		var o := cam.project_ray_origin(sp)
		var d := cam.project_ray_normal(sp)
		if d.y >= -0.001:
			return
		var t := -o.y / d.y
		var g := o + d * t
		if g.x >= HeroSim.GOAL_X:
			# crossed the goal line: use the goal plane for the target
			var tg := (HeroSim.GOAL_X - o.x) / d.x
			var gp := o + d * tg
			goal_target = Vector3(HeroSim.GOAL_X, clamp(gp.y, 0.15, 3.2), clamp(gp.z, -5.5, 5.5))
			ground_pts.append(Vector3(HeroSim.GOAL_X, 0, goal_target.z))
		else:
			ground_pts.append(Vector3(g.x, 0, g.z))
		_draw_preview()


## A stroke that ends on the goal mouth on screen (or just in front of the goal) is a shot.
func _forgiving_goal_target():
	if draw_pts.is_empty():
		return null
	var last := draw_pts[draw_pts.size() - 1]
	var corners := [Vector3(HeroSim.GOAL_X, 0, -HeroSim.HW), Vector3(HeroSim.GOAL_X, 0, HeroSim.HW), Vector3(HeroSim.GOAL_X, HeroSim.GH, HeroSim.HW), Vector3(HeroSim.GOAL_X, HeroSim.GH, -HeroSim.HW)]
	var rect := Rect2(cam.unproject_position(corners[0]), Vector2.ZERO)
	for c in corners:
		rect = rect.expand(cam.unproject_position(c))
	rect = rect.grow(22.0)
	var o := cam.project_ray_origin(last)
	var d := cam.project_ray_normal(last)
	if rect.has_point(last) and abs(d.x) > 0.0001:
		var t := (HeroSim.GOAL_X - o.x) / d.x
		var gp := o + d * t
		return Vector3(HeroSim.GOAL_X, clamp(gp.y, 0.2, 2.6), clamp(gp.z, -HeroSim.HW + 0.15, HeroSim.HW - 0.15))
	var end: Vector3 = ground_pts[ground_pts.size() - 1]
	if end.x > HeroSim.GOAL_X - 3.0 and abs(end.z) < HeroSim.HW + 1.0:
		return Vector3(HeroSim.GOAL_X, 0.35, clamp(end.z, -HeroSim.HW + 0.3, HeroSim.HW - 0.3))
	return null


## Index of the attacker the player may draw from now (carrier, or the receiver mid-flight).
func _draw_source() -> int:
	if phase == "aim":
		return carrier
	if phase == "flight" and queued.is_empty() and flight.get("ok", false):
		return int(flight.to)
	return -1


func _draw_preview() -> void:
	_imesh.clear_surfaces()
	if ground_pts.size() < 2:
		return
	var col := Game.C_CARD if goal_target != null else Game.C_HOME
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in ground_pts.size():
		var p: Vector3 = ground_pts[i]
		var nxt: Vector3 = ground_pts[min(i + 1, ground_pts.size() - 1)]
		var prv: Vector3 = ground_pts[max(i - 1, 0)]
		var dv := (nxt - prv)
		dv.y = 0.0
		var side := Vector3(-dv.z, 0, dv.x).normalized() * 0.14
		var a: float = 0.35 + 0.6 * float(i) / ground_pts.size()
		_imesh.surface_set_color(Color(col.r, col.g, col.b, a))
		_imesh.surface_add_vertex(p + side + Vector3(0, 0.06, 0))
		_imesh.surface_set_color(Color(col.r, col.g, col.b, a))
		_imesh.surface_add_vertex(p - side + Vector3(0, 0.06, 0))
	_imesh.surface_end()


func _clear_preview() -> void:
	_imesh.clear_surfaces()


func _finish_draw() -> void:
	var src := _draw_source()
	if src < 0 or ground_pts.size() < 3:
		_clear_preview()
		return
	var mv := {}
	if goal_target == null:
		goal_target = _forgiving_goal_target()
		if goal_target != null:
			ground_pts.append(Vector3(HeroSim.GOAL_X, 0, goal_target.z))
	if goal_target != null:
		mv = {"kind": "shot", "ground": ground_pts.duplicate(), "target": goal_target}
	else:
		var end: Vector3 = ground_pts[ground_pts.size() - 1]
		var best := -1
		var bd := 3.2
		for i in attackers.size():
			if i == src:
				continue
			var d: float = Vector2(end.x - attackers[i].pos.x, end.z - attackers[i].pos.z).length()
			if d < bd:
				bd = d
				best = i
		if best < 0:
			_hint.text = "Finish your line on a teammate, or carry it into the goal"
			_clear_preview()
			return
		mv = {"kind": "pass", "ground": ground_pts.duplicate(), "to": best}
	if phase == "flight":
		queued = mv
		_hint.text = "First time! Released when the ball arrives"
		return
	_execute(mv, false)


# ================================================================== moves
func _execute(mv: Dictionary, first_time: bool) -> void:
	_clear_preview()
	moves += 1
	_move_lbl.text = "Level %s · Move %d of %d" % [lv.id, min(moves + 1, max(int(lv.par), moves + 1)), lv.par]
	var from_p: Footballer = attackers[carrier]
	var start := ball.pos
	var g: PackedVector3Array = mv.ground
	g[0] = Vector3(start.x, 0, start.z)
	if mv.kind == "pass":
		var to_p: Footballer = attackers[mv.to]
		g[g.size() - 1] = Vector3(to_p.pos.x, 0, to_p.pos.z)
		var rs := HeroSim.resample(g)
		var len := HeroSim.path_length(rs)
		var lob := len > HeroSim.LOB_LEN
		var path := HeroSim.lift(rs, "lob" if lob else "ground", start.y)
		# the receiver wins the dropping ball at the end of a lofted pass
		var r := HeroSim.run(path, HeroSim.LOB_SPEED if lob else HeroSim.PASS_SPEED, def_pos, float(lv.react), float(lv.def_speed), 0.8, 1.4, 0.22 if lob else 0.0)
		if OS.get_cmdline_user_args().has("--test"):
			print("      PASS exec len=%.1f lob=%s cut=%d pts=%d start=%s end=%s" % [len, lob, r.cut, path.size(), path[0], path[path.size() - 1]])
		pass_log.append([carrier, int(mv.to)])
		touched[int(mv.to)] = true
		from_p.play_action("lob" if lob else "pass", 0.32, 0.4, Callable(), 1.0, 0.35, to_p.pos)
		Sfx.kick(0.5)
		var run_dir := Vector3(HeroSim.GOAL_X - 6.0, 0, 0) - (from_p.pos + Vector3(0.55, 0, 0))
		var run_to = from_p.pos + run_dir.normalized() * min(6.0, run_dir.length())
		flight = {"path": path, "speed": HeroSim.LOB_SPEED if lob else HeroSim.PASS_SPEED, "t": 0.0, "r": r, "ok": r.cut < 0,
			"to": int(mv.to), "lob": lob, "kind": "pass", "def_start": def_pos.duplicate(), "runner": carrier, "run_from": from_p.pos, "run_to": run_to,
			"first_time": first_time}
		phase = "flight"
		_hint.text = "Draw the next move from %s now for a first-time finish" % to_p.pname
	else:
		var target: Vector3 = mv.target
		var rs := HeroSim.resample(g)
		var path := HeroSim.lift(rs, "shot", start.y, target.y)
		_last_shot_bend = HeroSim.bend_of(rs)
		var res := HeroSolverShot.judge(path, target, Vector3(start.x, 0, start.z), def_pos, lv)
		if OS.get_cmdline_user_args().has("--test"):
			var solver_r := HeroSolverShot.judge(HeroSolverShot.build(Vector3(start.x, 0, start.z), target, HeroSim.bend_of(rs)), target, Vector3(start.x, 0, start.z), def_pos, lv)
			print("      drawn ground pts=%d first=%s mid=%s last=%s" % [g.size(), g[0], g[g.size() / 2], g[g.size() - 1]])
			print("      SHOT exec result=%s target=%s bend=%.2f len=%.1f t=%.2f | rebuilt=%s" % [res.result, target, HeroSim.bend_of(rs), HeroSim.path_length(rs), float(res.t), solver_r.result])
		var header: bool = first_time and flight.get("lob", false)
		if header:
			from_p.play_action("header", 0.45, 2.0, Callable(), 1.0, 0.4)
		else:
			from_p.play_action("volley" if first_time else "kick", 0.4, 0.4, Callable(), 1.0, 0.35, target)
		Sfx.kick(0.95)
		var kt: Vector3 = res.get("keeper_target", target)
		var side = sign(kt.z - keeper.pos.z) * -1.0
		var lat: float = abs(kt.z - keeper.pos.z)
		if res.result in ["goal", "save"] and lat > 0.6:
			keeper.dive_vel = Vector3(0, 0, sign(kt.z - keeper.pos.z)) * min(6.0, lat / max(0.3, float(res.t)))
			keeper.face_towards(Vector3(0, 0, 0), true)
			var left := Vector3(cos(keeper.yaw), 0, -sin(keeper.yaw))
			keeper.play_action("dive", clamp(float(res.t) * 1.6, 0.6, 0.95), 2.0, Callable(), sign(left.dot(Vector3(0, 0, sign(kt.z - keeper.pos.z)))), clamp(kt.y / 2.4, 0.0, 1.0))
		elif res.result in ["goal", "save"]:
			keeper.play_action("catch", 0.6, 2.0)
		_bonus_hit = _check_bonus(target, first_time, header, from_p)
		flight = {"path": path, "speed": float(res.speed), "t": 0.0, "res": res, "kind": "shot", "target": target, "def_start": def_pos.duplicate()}
		phase = "shot"
		_hint.text = ""


func _check_bonus(target: Vector3, first_time: bool, header: bool, shooter: Footballer) -> bool:
	match lv.bonus:
		"first_time":
			return first_time
		"header":
			return header
		"curl":
			return abs(_last_shot_bend) >= 2.0
		"top_corner":
			return target.y > 1.6 and abs(target.z) > HeroSim.HW - 1.0
		"low":
			return target.y < 0.6
		"far_post":
			return sign(target.z) != sign(shooter.pos.z) and abs(target.z) > HeroSim.HW - 1.2
		"one_two":
			for i in range(1, pass_log.size()):
				if pass_log[i][0] == pass_log[i - 1][1] and pass_log[i][1] == pass_log[i - 1][0]:
					return true
			return false
		"all_players":
			return touched.size() >= attackers.size()
	return false


func _process(delta: float) -> void:
	for p in attackers + defenders + [keeper]:
		p.tick(delta * _speed)
	match phase:
		"flight":
			_tick_pass(delta)
		"shot":
			_tick_shot(delta)
	_slowmo.visible = phase == "flight" and _speed < 0.5


func _ball_at(path: PackedVector3Array, dist: float) -> Vector3:
	var acc := 0.0
	for i in range(1, path.size()):
		var seg := path[i - 1].distance_to(path[i])
		if acc + seg >= dist:
			return path[i - 1].lerp(path[i], (dist - acc) / max(seg, 0.0001))
		acc += seg
	return path[path.size() - 1]


func _move_defenders(t: float) -> void:
	var r: Dictionary = flight.r if flight.has("r") else {}
	var ends: Array = r.get("def_end", flight.get("res", {}).get("def_end", def_pos))
	var stop_t: float = r.get("t", flight.get("res", {}).get("t", 1.0))
	var react: float = float(lv.react)
	var spd: float = float(lv.def_speed)
	for k in defenders.size():
		var s: Vector3 = flight.def_start[k]
		var e: Vector3 = ends[k]
		var moved: float = max(0.0, min(t, stop_t) - react) * spd
		var total := s.distance_to(e)
		var p := s.lerp(e, clamp(moved / max(total, 0.0001), 0.0, 1.0)) if total > 0.01 else s
		var dp: Footballer = defenders[k]
		var v = (p - dp.pos) / max(get_process_delta_time(), 0.001)
		dp.pos = p
		dp.vel = v.limit_length(8.0)
		if v.length() > 0.3:
			dp.face_towards(p + v, false)


func _tick_pass(delta: float) -> void:
	var path: PackedVector3Array = flight.path
	var total_t: float = flight.r.total
	var stop_t: float = flight.r.t
	# slow motion as the ball arrives so a first-time move can be drawn
	_speed = 1.0
	if flight.ok and queued.is_empty() and total_t - flight.t < 0.65:
		_speed = 0.2
	flight.t += delta * _speed
	var t: float = min(flight.t, stop_t)
	ball.pos = _ball_at(path, t * float(flight.speed))
	ball.global_position = ball.pos
	ball.spin = Vector3(0, 0, -12.0)
	_move_defenders(flight.t)
	# passer makes a run, receiver steps to the ball
	var runner: Footballer = attackers[flight.runner]
	var rk: float = clamp(flight.t / max(total_t, 0.1), 0.0, 1.0)
	var rp: Vector3 = (flight.run_from as Vector3).lerp(flight.run_to, rk)
	runner.vel = (rp - runner.pos) / max(delta, 0.001)
	runner.pos = rp
	var recv: Footballer = attackers[flight.to]
	recv.face_towards(ball.pos, false)
	if not flight.ok and flight.t >= stop_t:
		_fail("Intercepted! The defender read your pass.")
		return
	if flight.ok and flight.t >= total_t:
		_speed = 1.0
		def_pos = flight.r.def_end.duplicate()
		var was_lob: bool = flight.lob
		_give_ball(int(flight.to))
		ball.pos = recv.pos + Vector3(0.5, BallSim.R if not was_lob else 1.75, 0)
		ball.global_position = ball.pos
		if not queued.is_empty():
			var q := queued
			queued = {}
			flight.lob = was_lob
			_execute(q, true)
		else:
			flight = {}
			phase = "aim"
			_hint.text = "Drag from %s to draw a pass or a shot" % recv.pname


func _tick_shot(delta: float) -> void:
	_speed = 1.0
	var path: PackedVector3Array = flight.path
	var res: Dictionary = flight.res
	flight.t += delta
	var t: float = min(flight.t, float(res.t))
	ball.pos = _ball_at(path, t * float(flight.speed))
	ball.global_position = ball.pos
	ball.spin = Vector3(0, -_last_shot_bend * 8.0, 0)
	_move_defenders(flight.t)
	if flight.t >= float(res.t):
		match res.result:
			"goal":
				ball.frozen = false
				ball.pos = flight.target
				var dirv := (path[path.size() - 1] - path[max(0, path.size() - 4)]).normalized()
				ball.vel = dirv * float(flight.speed) * 0.7
				ball.in_goal_side = 1
				stadium.net_hit(1, flight.target + Vector3(1.0, 0, 0), 20.0)
				Sfx.play("net", 1.0)
				_succeed()
			"save":
				ball.frozen = false
				ball.pos = flight.target - Vector3(0.6, 0, 0)
				ball.vel = Vector3(-6.0, 3.0, sign(ball.pos.z) * 5.0)
				Sfx.play("catch")
				_fail("Saved! Aim further from the keeper, or get closer first.")
			"post":
				ball.frozen = false
				ball.vel = Vector3(-8.0, 2.0, -sign(flight.target.z) * 3.0)
				Sfx.play("post")
				_fail("Off the woodwork! Just inside the post next time.")
			"blocked":
				ball.frozen = false
				ball.vel = Vector3(-5.0, 2.0, randf_range(-4, 4))
				Sfx.play("tackle")
				_fail("Blocked! Bend your shot around the defender.")
			_:
				ball.frozen = false
				ball.vel = (path[path.size() - 1] - path[max(0, path.size() - 4)]).normalized() * 18.0
				_fail("Wide! Finish your line inside the goal frame.")


# ================================================================== results
func _succeed() -> void:
	phase = "done"
	_done_reason = "goal"
	Sfx.goal_roar()
	Sfx.set_excitement(1.0)
	stadium.set_excitement(1.0, 1.0)
	Game.haptic(50)
	var stars := 1 + (1 if moves <= int(lv.par) else 0) + (1 if _bonus_hit else 0)
	var prev := int(Game.save.hero.stars.get(lv.id, 0))
	var coins := 0
	if stars > prev:
		coins = (stars - prev) * 50
		Game.save.hero.stars[lv.id] = stars
		Game.add_coins(coins)
		Game.add_xp((stars - prev) * 20)
	Game.write_save()
	_update_objectives()
	attackers[carrier].play_action("cel_fist", 1.0, 2.0)
	await get_tree().create_timer(1.6).timeout
	_result(true, stars, coins, "")


func _fail(reason: String) -> void:
	phase = "done"
	_done_reason = "fail"
	_clear_preview()
	Sfx.near_miss()
	await get_tree().create_timer(1.4).timeout
	_result(false, 0, 0, reason)


func _result(win: bool, stars: int, coins: int, reason: String) -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.03, 0.04, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(bg)
	_ui.add_child(_overlay)
	var p := UI.panel()
	p.custom_minimum_size = Vector2(340, 0)
	_overlay.add_child(p)
	var v := UI.vbox(10)
	p.add_child(v)
	v.add_child(UI.eyebrow("Level " + lv.id, Game.C_CARD))
	v.add_child(UI.title("Goal!" if win else "Not this time", 30))
	if win:
		var sr := UI.hbox(8)
		for i in 3:
			var ic := Icon.new()
			ic.kind = "star"
			ic.color = Game.C_CARD if i < stars else Color(0.93, 0.95, 0.92, 0.2)
			ic.custom_minimum_size = Vector2(34, 34)
			ic.pivot_offset = Vector2(17, 17)
			ic.scale = Vector2.ZERO
			sr.add_child(ic)
			var tw := ic.create_tween()
			tw.tween_interval(0.15 + i * 0.18)
			tw.tween_property(ic, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		v.add_child(sr)
		if coins > 0:
			v.add_child(UI.pill("+%d" % coins, true))
		if stars < 3:
			var tip = "Tip: " + (HeroLevels.BONUS_TEXT.get(lv.bonus, "") if not _bonus_hit else "Score in %d moves or fewer" % lv.par)
			var tl := UI.label(tip, 13, "body_m", Game.C_DIM)
			tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tl.custom_minimum_size.x = 310
			v.add_child(tl)
	else:
		var l := UI.label(reason, 14, "body_m")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 310
		v.add_child(l)
	var row := UI.hbox(8)
	var lvb := UI.button("Levels", "ghost", Vector2(96, 40), 15)
	lvb.pressed.connect(func(): _leave("hero_levels", {}))
	row.add_child(lvb)
	var retry := UI.button("Retry", "ghost" if win else "primary", Vector2(96, 40), 15)
	retry.pressed.connect(func(): _leave("hero", {"level": lv.id}))
	row.add_child(retry)
	var nxt := HeroLevels.next_level(lv)
	if win and not nxt.is_empty() and HeroLevels.level_unlocked(nxt):
		var nb := UI.button("Next", "primary", Vector2(96, 40), 15)
		nb.pressed.connect(func(): _leave("hero", {"level": nxt.id}))
		row.add_child(nb)
	v.add_child(row)
	await get_tree().process_frame
	p.position = (_ui.size - p.size) * 0.5


func _leave(screen: String, prm: Dictionary) -> void:
	get_tree().paused = false
	Sfx.stop_crowd()
	if screen == "hero":
		Game.main.show_screen("hero", prm, false)
	else:
		Game.goto(screen, prm)


func _pause_menu() -> void:
	if _overlay or phase == "done":
		return
	get_tree().paused = true
	_overlay = Control.new()
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.03, 0.04, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(bg)
	_ui.add_child(_overlay)
	var p := UI.panel()
	_overlay.add_child(p)
	var v := UI.vbox(10)
	p.add_child(v)
	v.add_child(UI.eyebrow("Paused"))
	v.add_child(UI.title(lv.title, 20))
	var res := UI.button("Resume", "primary", Vector2(220, 42), 17)
	res.pressed.connect(_resume)
	v.add_child(res)
	var rt := UI.button("Restart level", "ghost", Vector2(220, 40), 15)
	rt.pressed.connect(func(): _leave("hero", {"level": lv.id}))
	v.add_child(rt)
	var q := UI.button("Back to levels", "ghost", Vector2(220, 40), 15)
	q.pressed.connect(func(): _leave("hero_levels", {}))
	v.add_child(q)
	await get_tree().process_frame
	p.position = (_ui.size - p.size) * 0.5


func _resume() -> void:
	get_tree().paused = false
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func on_back() -> bool:
	if get_tree().paused:
		_resume()
	elif phase != "done":
		_pause_menu()
	else:
		_leave("hero_levels", {})
	return true
