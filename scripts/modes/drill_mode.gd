extends Node3D
## Training ground drills: freekick, penalty, corner, shooting, dribble, keeper.

const INFO := {
	"freekick": {"name": "Free kicks", "medals": [400, 900, 1400], "unit": "pts", "rounds": 5},
	"penalty": {"name": "Penalties", "medals": [5, 7, 9], "unit": "/ 10", "rounds": 10},
	"corner": {"name": "Corners & crosses", "medals": [2, 4, 6], "unit": "headers", "rounds": 8},
	"shooting": {"name": "Shooting gallery", "medals": [600, 1000, 1400], "unit": "pts", "rounds": 0},
	"dribble": {"name": "Dribble run", "medals": [22.0, 19.0, 17.0], "unit": "s", "rounds": 1},
	"keeper": {"name": "Keeper reflexes", "medals": [5, 8, 11], "unit": "saves", "rounds": 15},
}

var params := {}
var drill := "freekick"
var stadium: Stadium
var ball: Ball
var cam: CameraRig
var kicker: Footballer
var keeper: Footballer
var others: Array = []
var cones: Array = []
var controls: Controls
var hud: MatchHUD
var ui: Control
var score := 0.0
var round := 0
var phase := "ready"        # ready, aim, flight, wait, done
var phase_t := 0.0
var rings: Array = []       # [Vector3 centre, radius, points, MeshInstance3D]
var _ring_root: Node3D
var _score_lbl: Label
var _round_lbl: Label
var _hint_lbl: Label
var _shot := {}
var _gk_plan := {}
var _time_left := 60.0
var _timer := 0.0
var _gates_passed := 0
var _cone_hits := 0
var _user_dive := {}
var _pen_phase := "take"
var _ring_hits := 0
var _goals := 0
var _saves := 0
var _overlay: Control = null
var _dribble_shot_done := false
var _corner := {}


func _ready() -> void:
	drill = params.get("drill", "freekick")
	BallSim.wet = false
	BallSim.wind = Vector3.ZERO
	stadium = Stadium.new()
	add_child(stadium)
	stadium.build("harbor", ["night", "dusk", "day"][(Time.get_date_dict_from_system().day) % 3], "clear")
	stadium.set_crowd_colors(Game.kit_colors(Game.save.club.home).shirt, Color("E5493C"))
	ball = Ball.new()
	ball.stadium = stadium
	add_child(ball)
	ball.goal_line_crossed.connect(_on_goal_line)
	ball.hit_post.connect(func(_p): Sfx.near_miss())
	cam = CameraRig.new()
	add_child(cam)
	cam.setup(self, stadium.L, stadium.W, false)
	ball.set_camera(cam)
	_ring_root = Node3D.new()
	add_child(_ring_root)
	var home := Game.kit_colors(Game.save.club.home)
	var eq_boots: Dictionary = Game.BOOTS.get(Game.save.equipped.get("boots", "black"), Game.BOOTS.black)
	kicker = Footballer.new()
	kicker.number = 10
	kicker.stats = {"pace": 82, "shoot": 80, "pass": 78, "drib": 82, "def": 50, "gk": 30}
	kicker.setup(home, Color(Game.SKIN_TONES[1]), Color(Game.HAIR[0]), Color(eq_boots.c))
	add_child(kicker)
	var gk_kit := {"shirt": Color("F08A24"), "shirt2": Color("2A1A08"), "pattern": 0, "shorts": Color("2A1A08"), "socks": Color("F08A24")}
	var user_gk := {"shirt": Color("8E6CF0"), "shirt2": Color("20163F"), "pattern": 0, "shorts": Color("20163F"), "socks": Color("8E6CF0")}
	keeper = Footballer.new()
	keeper.keeper = true
	keeper.number = 1
	keeper.stats = {"pace": 60, "shoot": 40, "pass": 50, "drib": 40, "def": 40, "gk": 76}
	keeper.setup(Game.kit_colors(Game.TEAMS[1].home), Color(Game.SKIN_TONES[3]), Color(Game.HAIR[2]), Color("151515"), user_gk if drill == "keeper" else gk_kit)
	add_child(keeper)
	_build_ui()
	Sfx.start_crowd()
	Sfx.set_excitement(0.2)
	match drill:
		"dribble":
			_setup_dribble()
		"corner":
			for i in 6:
				var p := Footballer.new()
				p.number = [9, 5, 11, 4, 3, 6][i]
				p.setup(home if i < 3 else Game.kit_colors(Game.TEAMS[1].home), Color(Game.SKIN_TONES[i]), Color(Game.HAIR[i]), Color("151515"))
				add_child(p)
				others.append(p)
	_next_round()


# ================================================================ UI
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = UI.screen_root()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	controls = Controls.new()
	ui.add_child(controls)
	controls.swiped.connect(_on_swipe)
	controls.show_buttons = drill == "dribble"
	controls.show_joystick = drill == "dribble"
	controls.swipe_mode = drill != "dribble"
	if drill == "dribble":
		controls.set_labels({"shoot": "Shoot", "pass": "Pass", "through": "Through", "sprint": "Sprint"})
	var m := UI.safe_margin()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(m)
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(c)
	var top := UI.hbox(0)
	var tag := UI.panel(false)
	tag.pad = 8
	var tv := UI.hbox(14)
	_round_lbl = UI.label("", 17, "disp", Game.C_CHALK, true)
	tv.add_child(_round_lbl)
	_score_lbl = UI.label("", 17, "disp_x", Game.C_CARD, true)
	tv.add_child(_score_lbl)
	tag.add_child(tv)
	top.add_child(tag)
	c.add_child(top)
	var pause := UI.icon_button("pause", "Pause")
	pause.pressed.connect(_pause)
	c.add_child(pause)
	var hp := UI.pill("")
	_hint_lbl = hp.find_child("Text", true, false)
	c.add_child(hp)
	await get_tree().process_frame
	pause.position = Vector2(c.size.x - 40, 0)
	hp.position = Vector2((c.size.x - hp.size.x) * 0.5, c.size.y - hp.size.y - (90 if drill == "dribble" else 0))
	hp.resized.connect(func(): hp.position = Vector2((c.size.x - hp.size.x) * 0.5, c.size.y - hp.size.y - (90 if drill == "dribble" else 0)))


func _hud() -> void:
	var info: Dictionary = INFO[drill]
	match drill:
		"freekick":
			_round_lbl.text = "Free kick · %d / %d" % [min(round, 5), 5]
			_score_lbl.text = "%d" % score
		"penalty":
			_round_lbl.text = ("Take · %d / 5" % min(round, 5)) if round <= 5 else ("Save · %d / 5" % (round - 5))
			_score_lbl.text = "%d / 10" % score
		"corner":
			_round_lbl.text = "Corner · %d / 8" % min(round, 8)
			_score_lbl.text = "%d headers" % score
		"shooting":
			_round_lbl.text = "Shooting · %d s" % int(ceil(_time_left))
			_score_lbl.text = "%d" % score
		"dribble":
			_round_lbl.text = "Gates %d / %d" % [_gates_passed, cones.size()]
			_score_lbl.text = "%.2f s" % _timer
		"keeper":
			_round_lbl.text = "Shot · %d / 15" % min(round, 15)
			_score_lbl.text = "%d saves" % score
	if info.has("name"):
		pass


func hint(t: String) -> void:
	_hint_lbl.text = t


# ================================================================ rounds
func _next_round() -> void:
	round += 1
	phase = "aim"
	phase_t = 0.0
	_shot = {}
	_gk_plan = {}
	_user_dive = {}
	for r in rings:
		r[3].queue_free()
	rings.clear()
	for p in others:
		p.cancel_action()
	keeper.cancel_action()
	keeper.stun = 0.0
	keeper.vel = Vector3.ZERO
	match drill:
		"freekick":
			if round > 5:
				_finish()
				return
			_setup_freekick()
		"penalty":
			if round > 10:
				_finish()
				return
			_setup_penalty()
		"corner":
			if round > 8:
				_finish()
				return
			_setup_corner()
		"shooting":
			if round == 1:
				_time_left = 60.0
			_setup_shooting()
		"keeper":
			if round > 15:
				_finish()
				return
			_setup_keeper()
	_hud()


func _behind_ball_cam() -> void:
	var goal := Vector3(stadium.L, 0, 0)
	var dn := (goal - ball.pos)
	dn.y = 0.0
	dn = dn.normalized()
	var cp := ball.pos - dn * 4.4 + Vector3(0, 2.0, 0)
	cam.set_fixed(cp, ball.pos.lerp(goal + Vector3(0, 0.6, 0), 0.62), 44.0, true)


func _place_keeper(on_line := true) -> void:
	keeper.pos = Vector3(stadium.L - (0.3 if on_line else 1.5), 0, clamp(ball.pos.z * 0.08, -1.0, 1.0))
	keeper.face_towards(ball.pos, true)
	keeper.ready_amt = 1.0


# ---------------------------------------------------------------- free kick
func _setup_freekick() -> void:
	var d := randf_range(18.0, 29.0)
	var ang := deg_to_rad(randf_range(-28.0, 28.0))
	var bp := Vector3(stadium.L - cos(ang) * d, BallSim.R, sin(ang) * d)
	ball.place(bp)
	ball.frozen = true
	var to_goal := (Vector3(stadium.L, 0, 0) - bp)
	to_goal.y = 0.0
	to_goal = to_goal.normalized()
	kicker.pos = bp - to_goal * 1.3 + Vector3(to_goal.z, 0, -to_goal.x) * 1.9
	kicker.face_towards(bp, true)
	kicker.vel = Vector3.ZERO
	# wall
	for p in others:
		p.queue_free()
	others.clear()
	var n := 3 if d < 24.0 else 2
	var perp := Vector3(-to_goal.z, 0, to_goal.x)
	var near: float = sign(bp.z) if abs(bp.z) > 1.0 else 1.0
	var center = bp + to_goal * 9.15 + perp * 0.4 * sign(perp.z * near)
	for i in n:
		var p := Footballer.new()
		p.number = [4, 5, 6, 8][i]
		p.setup(Game.kit_colors(Game.TEAMS[1].home), Color(Game.SKIN_TONES[i + 2]), Color(Game.HAIR[i]), Color("151515"))
		add_child(p)
		p.pos = center + perp * ((i - (n - 1) * 0.5) * 0.6)
		p.pos.y = 0.0
		p.face_towards(bp, true)
		others.append(p)
	_place_keeper()
	keeper.pos.z = -near * 0.7
	BallSim.wind = Vector3(0, 0, randf_range(-3.5, 3.5))
	_make_rings([[Vector3(stadium.L, 1.95, near * -3.0), 0.5, 300], [Vector3(stadium.L, 1.95, near * 3.0), 0.5, 200], [Vector3(stadium.L, 0.55, -near * 3.0), 0.55, 100]])
	_behind_ball_cam()
	hint("Swipe from the ball · bend your swipe to curl · wind %.1f m/s %s" % [abs(BallSim.wind.z), "→" if BallSim.wind.z > 0 else "←"])


func _make_rings(defs: Array) -> void:
	for d in defs:
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = d[1] - 0.05
		tm.outer_radius = d[1]
		tm.rings = 24
		tm.ring_segments = 8
		mi.mesh = tm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.81, 0.2) * 2.2
		mi.material_override = m
		mi.position = d[0] - Vector3(0.05, 0, 0)
		mi.rotation = Vector3(0, 0, PI * 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ring_root.add_child(mi)
		var lbl := Label3D.new()
		lbl.text = str(d[2])
		lbl.font = UI.font("disp_x")
		lbl.font_size = 64
		lbl.pixel_size = 0.006
		lbl.modulate = Game.C_CARD
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0, d[1] + 0.25, 0)
		lbl.no_depth_test = true
		mi.add_child(lbl)
		rings.append([d[0], d[1], d[2], mi])


# ---------------------------------------------------------------- penalty
func _setup_penalty() -> void:
	_pen_phase = "take" if round <= 5 else "save"
	ball.place(Vector3(stadium.L - 11.0, BallSim.R, 0))
	ball.frozen = true
	keeper.set_kit(Game.kit_colors(Game.TEAMS[1].home), {"shirt": Color("8E6CF0") if _pen_phase == "save" else Color("F08A24"), "shirt2": Color("20163F"), "pattern": 0, "shorts": Color("20163F"), "socks": Color("8E6CF0")})
	kicker.set_kit(Game.kit_colors(Game.save.club.home) if _pen_phase == "take" else Game.kit_colors(Game.TEAMS[1].home))
	kicker.pos = ball.pos - Vector3(1.4, 0, 1.6)
	kicker.face_towards(ball.pos, true)
	_place_keeper()
	_behind_ball_cam()
	if _pen_phase == "take":
		hint("Swipe to shoot · aim for the corners")
	else:
		hint("You're in goal · swipe left, right or up to dive")
		phase_t = 0.0


# ---------------------------------------------------------------- corner
func _setup_corner() -> void:
	var zs := 1.0 if round % 2 == 0 else -1.0
	ball.place(Vector3(stadium.L - 0.35, BallSim.R, zs * (stadium.W - 0.35)))
	ball.frozen = true
	kicker.pos = ball.pos + Vector3(0.7, 0, zs * 0.7)
	kicker.face_towards(Vector3(stadium.L - 11, 0, 0), true)
	var att := [Vector3(stadium.L - 11.0, 0, 0), Vector3(stadium.L - 6.0, 0, zs * 2.5), Vector3(stadium.L - 7.0, 0, -zs * 4.0)]
	var dfn := [Vector3(stadium.L - 5.0, 0, zs * 1.0), Vector3(stadium.L - 9.5, 0, -zs * 1.5), Vector3(stadium.L - 6.0, 0, -zs * 5.0)]
	for i in 6:
		var p: Footballer = others[i]
		p.pos = (att[i] if i < 3 else dfn[i - 3]) + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
		p.vel = Vector3.ZERO
		p.desired = Vector3.ZERO
		p.face_towards(ball.pos, true)
	_place_keeper()
	keeper.pos.z = zs * 0.6
	var c := ball.pos
	cam.set_fixed(c + Vector3(6.5, 7.0, zs * 8.0), Vector3(stadium.L - 11.0, 0, 0), 50.0, true)
	_corner = {"zs": zs, "stage": "cross"}
	hint("Swipe from the ball into the box to cross")


# ---------------------------------------------------------------- shooting
func _setup_shooting() -> void:
	var spot := Vector3(stadium.L - randf_range(14.0, 22.0), 0, randf_range(-9.0, 9.0))
	kicker.pos = spot
	kicker.face_towards(Vector3(stadium.L, 0, 0), true)
	var from := spot + Vector3(-randf_range(6, 10), 0, randf_range(-8, 8))
	ball.place(from + Vector3(0, BallSim.R, 0))
	var to := spot + Vector3(0.6, 0, 0)
	var dv := to - ball.pos
	dv.y = 0.0
	ball.kick(dv.normalized() * BallSim.ground_pass_speed(dv.length(), 3.0), Vector3.ZERO, null, "feed")
	_place_keeper(false)
	var zs := 1.0 if randf() < 0.5 else -1.0
	_make_rings([[Vector3(stadium.L, randf_range(0.5, 1.9), zs * randf_range(2.2, 3.0)), 0.55, 150]])
	var goal := Vector3(stadium.L, 0, 0)
	var dn := (goal - spot).normalized()
	cam.set_fixed(spot - dn * 5.0 + Vector3(0, 2.4, 0), spot.lerp(goal, 0.6) + Vector3(0, 0.4, 0), 50.0, round == 1)
	hint("Swipe to strike first time · hit the ring for bonus points")


# ---------------------------------------------------------------- dribble
func _setup_dribble() -> void:
	var cone_m := StandardMaterial3D.new()
	cone_m.albedo_color = Color("FF7A1A")
	cone_m.emission_enabled = true
	cone_m.emission = Color("FF7A1A") * 0.3
	for i in 9:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.02
		cm.bottom_radius = 0.16
		cm.height = 0.45
		mi.mesh = cm
		mi.material_override = cone_m
		mi.position = Vector3(-6.0 + i * 4.0, 0.225, 2.0 if i % 2 == 0 else -2.0)
		add_child(mi)
		cones.append(mi)
	kicker.pos = Vector3(-12, 0, 0)
	kicker.yaw = PI * 0.5
	ball.place(kicker.ball_anchor())
	ball.holder = kicker
	keeper.pos = Vector3(-60, 0, 30)
	keeper.visible = false
	cam.mode = "fixed"
	hint("Weave through the cones · pass each on the marked side · then SHOOT")


func _tick_dribble(dt: float) -> void:
	if phase == "done":
		return
	var mv := controls.move_world(cam)
	kicker.sprint = controls.held.sprint
	kicker.desired = mv * kicker.max_speed()
	if phase == "aim" and mv.length() > 0.1:
		phase = "flight"
	if phase == "flight":
		_timer += dt
	# gates: pass each cone on the side opposite its offset (zig-zag)
	if _gates_passed < cones.size():
		var c: MeshInstance3D = cones[_gates_passed]
		if kicker.pos.x > c.position.x:
			var want_side: float = -sign(c.position.z)
			if sign(kicker.pos.z) == want_side or abs(kicker.pos.z) < 0.3:
				_gates_passed += 1
				Sfx.ui("tap")
			else:
				_timer += 2.0
				_gates_passed += 1
				hint("Missed gate · +2 s")
	for c in cones:
		var cn: MeshInstance3D = c
		if Vector2(ball.pos.x - cn.position.x, ball.pos.z - cn.position.z).length() < 0.3 and not cn.has_meta("hit"):
			cn.set_meta("hit", true)
			_timer += 1.0
			_cone_hits += 1
			hint("Clipped a cone · +1 s")
			var tw := create_tween()
			tw.tween_property(cn, "rotation:z", 1.4, 0.25)
	if ball.holder == null and ball.speed() < 1.5 and not _dribble_shot_done and kicker.pos.distance_to(ball.pos) < 1.2:
		ball.holder = kicker
	if controls.just_pressed("shoot") and ball.holder == kicker and not _dribble_shot_done:
		if _gates_passed < cones.size():
			hint("Clear all the gates first")
		else:
			_dribble_shot_done = true
			var target := Vector3(stadium.L, 0.6, randf_range(-2.5, 2.5))
			kicker.play_action("kick", 0.4, 0.5, _dribble_kick.bind(target), 1.0, 0.35, target)
	var f := kicker.pos + Vector3(-7.0, 4.2, 0.0)
	cam.want_pos = f
	cam.want_look = kicker.pos + Vector3(6.0, 0.5, 0.0)
	cam.fov = 55.0
	cam.smooth = 4.0
	if round == 1 and phase_t < 0.1:
		cam.snap()


func _dribble_kick(target: Vector3) -> void:
	ball.holder = null
	var v := BallSim.solve(ball.pos, target, 24.0, Vector3.ZERO)
	if v == Vector3.ZERO:
		v = (target - ball.pos).normalized() * 24.0
	ball.kick(v, Vector3.ZERO, kicker, "shot")


# ---------------------------------------------------------------- keeper
func _setup_keeper() -> void:
	var d := randf_range(11.0, 22.0)
	var z := randf_range(-10.0, 10.0)
	ball.place(Vector3(stadium.L - d, BallSim.R, z))
	ball.frozen = true
	kicker.set_kit(Game.kit_colors(Game.TEAMS[1].home))
	kicker.pos = ball.pos - Vector3(1.6, 0, 0.4)
	kicker.face_towards(ball.pos, true)
	keeper.pos = Vector3(stadium.L - 0.6, 0, z * 0.12)
	keeper.face_towards(ball.pos, true)
	keeper.ready_amt = 1.0
	cam.set_fixed(Vector3(stadium.L + 4.5, 2.6, 0.0), Vector3(stadium.L - 14.0, 0.8, z * 0.5), 58.0, true)
	phase_t = 0.0
	hint("Get ready · swipe toward the ball's corner as it's struck")


# ================================================================ input
func _on_swipe(pts: PackedVector2Array, dur: float) -> void:
	if phase == "done" or _overlay:
		return
	match drill:
		"freekick", "shooting":
			if phase != "aim":
				return
			_swipe_shot(pts, dur, drill == "shooting")
		"penalty":
			if phase != "aim":
				return
			if _pen_phase == "take":
				_swipe_shot(pts, dur, false)
			else:
				_set_user_dive(pts)
		"keeper":
			_set_user_dive(pts)
		"corner":
			_corner_swipe(pts, dur)


func _swipe_shot(pts: PackedVector2Array, dur: float, first_time: bool) -> void:
	var r := SwipeShot.compute(cam, ball.pos, pts, dur, stadium.L, stadium.goal_hw, stadium.goal_h)
	if r.is_empty():
		return
	phase = "flight"
	phase_t = 0.0
	_shot = {"curl": r.curl}
	kicker.play_action("volley" if first_time else "kick", 0.42 if not first_time else 0.3, 0.5 if not first_time else 0.2, _do_swipe_kick.bind(r), 1.0, 0.35, r.target)
	if not first_time:
		kicker.desired = (ball.pos - kicker.pos).normalized() * 3.0


func _do_swipe_kick(r: Dictionary) -> void:
	if drill == "shooting" and kicker.pos.distance_to(ball.pos) > 2.2:
		hint("Too early! Wait for the ball to reach you")
		phase = "wait"
		phase_t = 0.0
		return
	ball.frozen = false
	ball.holder = null
	var v := SwipeShot.velocity(ball.pos, r, 0.012)
	ball.kick(v, r.spin, kicker, "shot")
	Game.haptic(25)
	for p in others:
		if drill == "freekick":
			p.play_action("header", 0.55, 2.0, Callable(), 1.0, 0.45)
	_keeper_plan(drill == "penalty")


func _set_user_dive(pts: PackedVector2Array) -> void:
	var d := pts[pts.size() - 1] - pts[0]
	var screen_side: float = sign(d.x) if abs(d.x) > abs(d.y) * 0.35 else 0.0
	var world_dir := cam.global_transform.basis.x * screen_side
	var left := Vector3(cos(keeper.yaw), 0, -sin(keeper.yaw))
	_user_dive = {"side": sign(world_dir.dot(left)) if screen_side != 0.0 else 0.0, "height": clamp(-d.y / 160.0, 0.0, 1.0), "t": phase_t}
	if phase == "flight" or (drill == "keeper" and phase == "flight"):
		_do_user_dive()
	else:
		hint("Dive locked in…")


func _do_user_dive() -> void:
	if _user_dive.is_empty() or keeper.action != "":
		return
	var left := Vector3(cos(keeper.yaw), 0, -sin(keeper.yaw))
	if _user_dive.side == 0.0:
		keeper.play_action("catch", 0.6, 2.0)
	else:
		keeper.dive_vel = left * _user_dive.side * 5.8
		keeper.play_action("dive", 0.9, 2.0, Callable(), _user_dive.side, _user_dive.height)


# ================================================================ keeper AI
func _keeper_plan(penalty: bool) -> void:
	var pts := ball.predict(2.5, 0.02)
	var cross := Vector3.ZERO
	var tc := 1.0
	for i in range(1, pts.size()):
		if pts[i].x >= stadium.L - 0.4:
			cross = pts[i]
			tc = i * 0.02
			break
	var left := Vector3(cos(keeper.yaw), 0, -sin(keeper.yaw))
	var lat := (cross - keeper.pos).dot(left)
	var react := 0.0 if penalty else randf_range(0.16, 0.26)
	if penalty:
		# keepers guess at penalties
		var guess := randf()
		if guess < 0.42:
			lat = lat
		elif guess < 0.55:
			lat = 0.0
		else:
			lat = -sign(lat) * 2.0
	_gk_plan = {"t": react, "lat": lat, "y": cross.y, "tc": tc, "left": left, "done": false}


func _tick_keeper_ai(dt: float) -> void:
	if _gk_plan.is_empty() or _gk_plan.done:
		return
	if phase_t < float(_gk_plan.t):
		return
	_gk_plan.done = true
	var lat: float = _gk_plan.lat
	if abs(lat) < 0.6:
		keeper.play_action("catch", 0.6, 2.0)
		return
	var tleft: float = max(0.15, float(_gk_plan.tc) - phase_t)
	var spd: float = clamp((abs(lat) - 0.9) / tleft, 2.5, 6.4)
	keeper.dive_vel = _gk_plan.left * sign(lat) * spd
	keeper.play_action("dive", clamp(tleft * 1.8, 0.6, 0.95), 2.0, Callable(), sign(lat), clamp(float(_gk_plan.y) / 2.4, 0.0, 1.0))


func _keeper_contact() -> bool:
	if ball.speed() < 3.0 or ball.vel.x < 0.5 or keeper.visible == false:
		return false
	var up := Vector3.UP
	var a: Vector3
	var b: Vector3
	var r := 0.4
	if keeper.action == "dive":
		var t := keeper.action_t
		var lay := PlayerRig._k(t, [[0, 0.0], [0.2, 0.6], [0.5, 1.0], [1, 1.0]])
		var air := PlayerRig._k(t, [[0, 0.0], [0.15, 0.3], [0.45, 1.0], [0.62, 1.0], [0.78, 0.0]])
		var left := Vector3(cos(keeper.yaw), 0, -sin(keeper.yaw))
		var ang := 1.35 * lay
		var axis := (up * cos(ang) + left * keeper.action_side * sin(ang)).normalized()
		var hip := keeper.pos + Vector3(0, max(0.25, 0.96 - 0.3 * lay + air * (0.25 + keeper.action_height * 0.6)), 0)
		a = hip - axis * 0.9
		b = hip + axis * 1.5
		r = 0.46
	else:
		a = keeper.pos + up * 0.1
		b = keeper.pos + up * 2.15
		r = 0.44 if keeper.action == "catch" else 0.36
	var ab := b - a
	var t2: float = clamp((ball.pos - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return ball.pos.distance_to(a + ab * t2) < r


# ================================================================ corner flow
func _corner_swipe(pts: PackedVector2Array, dur: float) -> void:
	if _corner.get("stage", "") == "cross" and phase == "aim":
		# swipe direction picks the line, swipe length picks the distance
		var e := pts[pts.size() - 1]
		var o := cam.project_ray_origin(e)
		var d := cam.project_ray_normal(e)
		if d.y >= -0.01:
			return
		var ge := o + d * (-o.y / d.y)
		var dirg := Vector3(ge.x - ball.pos.x, 0, ge.z - ball.pos.z)
		if dirg.length() < 0.5:
			return
		dirg = dirg.normalized()
		var chord := (e - pts[0]).length()
		var dist: float = clamp(chord / 390.0 * 75.0, 18.0, 40.0)
		var g := Vector3(ball.pos.x, 0, ball.pos.z) + dirg * dist
		g.x = clamp(g.x, stadium.L - 16.0, stadium.L - 3.0)
		g.z = clamp(g.z, -11.0, 11.0)
		phase = "flight"
		phase_t = 0.0
		var spin := Vector3(0, _corner.zs * 18.0, 0)
		kicker.play_action("cross", 0.45, 0.5, _corner_kick.bind(g, spin), 1.0, 0.35, g)
		_corner["target"] = g
	elif _corner.get("stage", "") == "header":
		# aim where the swipe ends on the goal face
		var e2 := pts[pts.size() - 1]
		var o2 := cam.project_ray_origin(e2)
		var d2 := cam.project_ray_normal(e2)
		if abs(d2.x) < 0.0001:
			return
		var tg := o2 + d2 * ((stadium.L - o2.x) / d2.x)
		var r := {"target": Vector3(stadium.L, clamp(tg.y, 0.2, 2.8), clamp(tg.z, -5.0, 5.0))}
		_corner.stage = "headed"
		var p: Footballer = _corner.header_p
		p.play_action("header", 0.45, 2.0, Callable(), 1.0, 0.45)
		var v := BallSim.solve(ball.pos, r.target, 15.5, Vector3.ZERO)
		if v == Vector3.ZERO:
			v = (r.target - ball.pos).normalized() * 15.0
		ball.kick(v, Vector3.ZERO, p, "shot")
		Engine.time_scale = 1.0
		_keeper_plan(false)
		phase_t = 0.0


func _corner_kick(g: Vector3, spin: Vector3) -> void:
	ball.frozen = false
	var v := BallSim.lob_velocity(ball.pos, g, 26.0, spin)
	ball.kick(v, spin, kicker, "corner")
	# attack the point where the dropping ball is at head height
	var land := g
	var traj := BallSim.simulate(ball.pos, v, spin, 3.0, 0.02)
	var apex := false
	for i in range(1, traj.size()):
		if traj[i].y < traj[i - 1].y:
			apex = true
		if apex and traj[i].y <= 1.85:
			land = Vector3(traj[i].x, 0, traj[i].z)
			break
	_corner["target"] = land
	if OS.get_cmdline_user_args().has("--test"):
		print("        cross g=%s land=%s v=%s from=%s" % [g, land, v, ball.pos])
	var best: Footballer = null
	var bt := INF
	for i in 6:
		var p: Footballer = others[i]
		var t := p.pos.distance_to(land) / (7.0 if i < 3 else 6.6) + (0.0 if i < 3 else 0.12)
		if t < bt:
			bt = t
			best = p
	var gk_t := keeper.pos.distance_to(land) / 5.5 if land.x > stadium.L - 6.0 and abs(land.z) < 5.0 else INF
	_corner["winner"] = best
	_corner["keeper_claims"] = gk_t < bt
	for i in 6:
		var p: Footballer = others[i]
		p.desired = (land - p.pos).normalized() * (6.5 if i < 3 else 6.0)
		p.sprint = true


func _tick_corner(dt: float) -> void:
	if phase != "flight":
		return
	if _corner.stage == "cross" and _corner.has("winner"):
		var w: Footballer = _corner.winner
		for p in others:
			var d: Vector3 = _corner.target - p.pos
			d.y = 0.0
			p.desired = d.normalized() * min(6.5, d.length() * 2.0)
		var flat := Vector2(ball.pos.x - w.pos.x, ball.pos.z - w.pos.z).length()
		if OS.get_cmdline_user_args().has("--test") and flat < 3.0:
			print("        near: flat=%.2f y=%.2f vy=%.1f w=%s tgt=%s winner_idx=%d" % [flat, ball.pos.y, ball.vel.y, w.pos, _corner.target, others.find(w)])
		if ball.pos.y < 2.6 and ball.pos.y > 1.2 and flat < 1.4 and ball.vel.y < 0.0:
			if _corner.keeper_claims:
				ball.vel = Vector3.ZERO
				ball.frozen = true
				keeper.play_action("catch", 0.5, 2.0)
				_end_attempt("Claimed by the keeper", 0)
			elif others.find(w) >= 3:
				ball.kick(Vector3(-8, 6, randf_range(-5, 5)), Vector3.ZERO, w, "clear")
				w.play_action("header", 0.45, 2.0)
				_end_attempt("Cleared by the defender", 0)
			else:
				_corner.stage = "header"
				_corner["header_p"] = w
				ball.frozen = true
				Engine.time_scale = 0.15
				hint("Swipe toward goal to head it!")
				_corner["hdr_t"] = Time.get_ticks_msec()
		elif ball.pos.y <= BallSim.R + 0.05 and phase_t > 1.5:
			_end_attempt("Nobody got on the end of it", 0)
	elif _corner.stage == "header":
		if Time.get_ticks_msec() - int(_corner.hdr_t) > 2500:
			Engine.time_scale = 1.0
			ball.frozen = false
			_end_attempt("Too slow! Swipe as soon as the ball arrives", 0)
	elif _corner.stage == "headed":
		_tick_keeper_ai(dt)
		if _keeper_contact():
			_saved()


# ================================================================ main loop
func _physics_process(dt: float) -> void:
	phase_t += dt
	kicker.tick(dt)
	keeper.tick(dt)
	for p in others:
		p.tick(dt)
	match drill:
		"dribble":
			_tick_dribble(dt)
		"corner":
			_tick_corner(dt)
		"shooting":
			if phase != "done":
				_time_left -= dt
				if _time_left <= 0.0:
					_finish()
					return
			if phase == "flight":
				_tick_keeper_ai(dt)
				if _keeper_contact():
					_saved()
			elif phase == "aim" and ball.speed() < 0.4 and phase_t > 2.5:
				_end_attempt("Too slow", 0)
		"keeper":
			_tick_keeper_drill(dt)
		_:
			if phase == "flight":
				_tick_keeper_ai(dt)
				if _keeper_contact():
					_saved()
			if drill == "penalty" and _pen_phase == "save" and phase == "aim" and phase_t > 2.2:
				_bot_penalty()
	if phase == "flight" and phase_t > 4.0 and drill != "dribble":
		_end_attempt("Missed", 0)
	if drill == "freekick":
		stadium.follow_camera(cam)
	cam.update(dt)
	_hud()
	controls.consume()


func _bot_penalty() -> void:
	phase = "flight"
	phase_t = 0.0
	var zs := 1.0 if randf() < 0.5 else -1.0
	var target := Vector3(stadium.L, randf_range(0.3, 1.9), zs * randf_range(1.8, 3.1))
	kicker.play_action("kick", 0.45, 0.5, _bot_pen_kick.bind(target), 1.0, 0.35, target)


func _bot_pen_kick(target: Vector3) -> void:
	ball.frozen = false
	var v := BallSim.solve(ball.pos, target, randf_range(21.0, 25.0), Vector3.ZERO)
	ball.kick(v if v != Vector3.ZERO else (target - ball.pos).normalized() * 22.0, Vector3.ZERO, kicker, "shot")
	phase_t = 0.0
	if _user_dive.is_empty():
		_user_dive = {"side": [-1.0, 1.0, 0.0][randi() % 3], "height": 0.3}
	_do_user_dive()


func _tick_keeper_drill(dt: float) -> void:
	if phase == "aim" and phase_t > randf_range(1.6, 2.2):
		phase = "flight"
		phase_t = 0.0
		var zs := 1.0 if randf() < 0.5 else -1.0
		var target := Vector3(stadium.L, randf_range(0.25, 2.1), zs * randf_range(0.6, 3.2))
		var spd := 18.0 + round * 0.6
		kicker.play_action("kick", 0.4, 0.5, _bot_pen_kick_keeper.bind(target, spd), 1.0, 0.35, target)
	elif phase == "flight":
		if not _user_dive.is_empty() and keeper.action == "":
			_do_user_dive()
		if _keeper_contact():
			_saved()


func _bot_pen_kick_keeper(target: Vector3, spd: float) -> void:
	ball.frozen = false
	var v := BallSim.solve(ball.pos, target, spd, Vector3(0, randf_range(-30, 30), 0))
	ball.kick(v if v != Vector3.ZERO else (target - ball.pos).normalized() * spd, Vector3.ZERO, kicker, "shot")
	phase_t = 0.0
	hint("Swipe to dive!")


func _saved() -> void:
	var v := ball.vel
	ball.vel = Vector3(-abs(v.x) * 0.25 - 2.0, randf_range(2.0, 4.0), sign(ball.pos.z) * randf_range(2, 5))
	ball.spin = Vector3.ZERO
	Sfx.play("catch")
	if drill in ["keeper"] or (drill == "penalty" and _pen_phase == "save"):
		score += 1
		_saves += 1
		Game.haptic(40)
		_end_attempt("Great save!", 0)
	else:
		Sfx.near_miss()
		_end_attempt("Saved by the keeper", 0)


func _on_goal_line(side: int, scored: bool, pos: Vector3) -> void:
	if phase != "flight" and not (drill == "corner" and _corner.get("stage", "") == "headed"):
		return
	if drill == "keeper" or (drill == "penalty" and _pen_phase == "save"):
		if scored:
			_end_attempt("Goal conceded", 0)
		else:
			score += 1
			_saves += 1
			_end_attempt("Missed the target · counts as a save", 0)
		return
	if not scored:
		Sfx.near_miss()
		_end_attempt("Missed the target", 0)
		return
	Sfx.goal_roar()
	stadium.set_excitement(1.0, 1.0)
	stadium.net_hit(1, pos + Vector3(1, 0, 0), 20.0)
	Game.haptic(50)
	var pts := 0
	var bonus := ""
	match drill:
		"freekick":
			pts = 100
			for r in rings:
				if Vector2(pos.y - r[0].y, pos.z - r[0].z).length() < r[1] + BallSim.R:
					pts += int(r[2])
					_ring_hits += 1
					bonus = " · ring +%d" % r[2]
			if abs(float(_shot.get("curl", 0.0))) > 0.2:
				pts += 50
				bonus += " · curl +50"
		"penalty":
			pts = 1
		"corner":
			pts = 1
		"shooting":
			pts = 50
			for r in rings:
				if Vector2(pos.y - r[0].y, pos.z - r[0].z).length() < r[1] + BallSim.R:
					pts += int(r[2])
					bonus = " · target +%d" % r[2]
		"dribble":
			pts = 0
	score += pts
	_goals += 1
	_end_attempt(("Goal! +%d" % pts if drill in ["freekick", "shooting"] else "Goal!") + bonus, pts)


func _end_attempt(msg: String, _pts: int) -> void:
	if phase == "done":
		return
	if OS.get_cmdline_user_args().has("--test"):
		print("      end_attempt round=%d phase=%s msg=%s corner=%s" % [round, phase, msg, _corner.get("stage", "")])
	hint(msg)
	Engine.time_scale = 1.0
	if drill == "dribble":
		_finish()
		return
	phase = "wait"
	await get_tree().create_timer(1.6 if drill != "shooting" else 0.9).timeout
	if phase == "done" or not is_inside_tree():
		return
	stadium.set_excitement(0.2)
	_next_round()


# ================================================================ results
func _finish() -> void:
	if phase == "done":
		return
	phase = "done"
	Engine.time_scale = 1.0
	BallSim.wind = Vector3.ZERO
	controls.enabled = false
	var info: Dictionary = INFO[drill]
	var value: float = score if drill != "dribble" else _timer
	var medal := 0
	var med: Array = info.medals
	for i in 3:
		if drill == "dribble":
			if _dribble_shot_done and value <= float(med[i]):
				medal = i + 1
		elif value >= float(med[i]):
			medal = i + 1
	var rec: Dictionary = Game.save.training.get(drill, {"best": 0, "medal": 0})
	var better: bool = (value < float(rec.best) or float(rec.best) == 0.0) if drill == "dribble" else value > float(rec.best)
	if drill == "dribble" and not _dribble_shot_done:
		better = false
	var coins := 0
	if better:
		rec.best = value
	if medal > int(rec.medal):
		coins += [0, 100, 200, 400][medal] - [0, 100, 200, 400][int(rec.medal)]
		rec.medal = medal
	Game.save.training[drill] = rec
	coins += int(score) / 10 if drill in ["freekick", "shooting"] else int(score) * 15
	if drill == "dribble" and _dribble_shot_done:
		coins += 40
	var daily_val := 0
	match drill:
		"freekick":
			daily_val = _ring_hits
		"penalty":
			daily_val = _goals
		"shooting":
			daily_val = int(score)
		"dribble":
			daily_val = 1 if _dribble_shot_done and _timer < 17.0 else 0
		"keeper":
			daily_val = _saves
		"corner":
			daily_val = _goals
	var daily: int = load("res://scripts/screens/home_screen.gd").daily_report(drill, daily_val)
	Game.add_coins(coins)
	Game.add_xp(30)
	Game.write_save()
	_results(value, medal, better, coins, daily)


func _results(value: float, medal: int, best: bool, coins: int, daily: int) -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.03, 0.04, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(bg)
	ui.add_child(_overlay)
	var p := UI.panel()
	p.custom_minimum_size = Vector2(340, 0)
	_overlay.add_child(p)
	var v := UI.vbox(10)
	p.add_child(v)
	var info: Dictionary = INFO[drill]
	v.add_child(UI.eyebrow(info.name, Game.C_CARD))
	var val := ("%.2f s" % value) if drill == "dribble" else ("%d %s" % [int(value), info.unit])
	if drill == "dribble" and not _dribble_shot_done:
		val = "Did not finish"
	v.add_child(UI.title(val, 34))
	var row := UI.hbox(10)
	var md := Control.new()
	md.custom_minimum_size = Vector2(40, 40)
	md.draw.connect(_draw_medal.bind(md, medal))
	row.add_child(md)
	row.add_child(UI.label(["No medal", "Bronze", "Silver", "Gold"][medal] + ("  · New best!" if best else ""), 16, "body_b"))
	v.add_child(row)
	var med: Array = info.medals
	var targets := ""
	for i in 3:
		targets += "%s %s   " % [["Bronze", "Silver", "Gold"][i], ("%.0f s" % med[i]) if drill == "dribble" else str(med[i])]
	v.add_child(UI.label(targets, 12, "body_m", Game.C_DIM))
	var cr := UI.hbox(8)
	cr.add_child(UI.pill("+%d" % coins, true))
	if daily > 0:
		cr.add_child(UI.pill("Daily drill done · +%d" % daily, true))
	v.add_child(cr)
	var br := UI.hbox(8)
	var back := UI.button("Training", "ghost", Vector2(120, 40), 15)
	back.pressed.connect(func(): _leave("training"))
	br.add_child(back)
	var again := UI.button("Play again", "primary", Vector2(140, 40), 15)
	again.pressed.connect(func(): Sfx.stop_crowd(); Game.main.show_screen("drill", {"drill": drill}, false))
	br.add_child(again)
	v.add_child(br)
	await get_tree().process_frame
	p.position = (ui.size - p.size) * 0.5


func _draw_medal(md: Control, medal: int) -> void:
	var cols := [Color(0.93, 0.95, 0.92, 0.15), Color("b8723a"), Color("a9b4b7"), Color("e3b622")]
	md.draw_circle(Vector2(20, 20), 18, cols[medal])
	if medal == 0:
		md.draw_arc(Vector2(20, 20), 18, 0, TAU, 32, Game.C_LINE2, 1.5, true)


func _leave(to: String) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	BallSim.wind = Vector3.ZERO
	Sfx.stop_crowd()
	Game.goto(to)


func _pause() -> void:
	if _overlay:
		return
	get_tree().paused = true
	_overlay = Control.new()
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.03, 0.04, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(bg)
	ui.add_child(_overlay)
	var p := UI.panel()
	_overlay.add_child(p)
	var v := UI.vbox(10)
	p.add_child(v)
	v.add_child(UI.eyebrow("Paused"))
	v.add_child(UI.title(INFO[drill].name, 20))
	var r := UI.button("Resume", "primary", Vector2(220, 42), 17)
	r.pressed.connect(_resume)
	v.add_child(r)
	var rs := UI.button("Restart drill", "ghost", Vector2(220, 40), 15)
	rs.pressed.connect(func(): get_tree().paused = false; Sfx.stop_crowd(); Game.main.show_screen("drill", {"drill": drill}, false))
	v.add_child(rs)
	var q := UI.button("Quit to training", "ghost", Vector2(220, 40), 15)
	q.pressed.connect(func(): _leave("training"))
	v.add_child(q)
	await get_tree().process_frame
	p.position = (ui.size - p.size) * 0.5


func _resume() -> void:
	get_tree().paused = false
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func on_back() -> bool:
	if phase == "done":
		_leave("training")
	elif get_tree().paused:
		_resume()
	else:
		_pause()
	return true


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	BallSim.wind = Vector3.ZERO
