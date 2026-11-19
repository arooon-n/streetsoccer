class_name Match
extends Node3D
## Match director: rules, set pieces, user control, keeper saves, replays, results.

const REC_HZ := 30.0
const REPLAY_SECS := 8.0
const PASS_KINDS := ["pass", "through", "lob", "cross", "clear", "throw", "corner", "goalkick", "goalkick_long", "freekick_pass", "kickoff", "gk_throw"]

var params: Dictionary = {}
var stadium: Stadium
var ball: Ball
var teams: Array = []
var cam: CameraRig
var hud: MatchHUD
var controls: Controls
var layer: CanvasLayer
var user_team: TeamCtl = null
var state := "intro"
var state_t := 0.0
var time_now := 0.0
var clock := 0.0
var half := 1
var added := 0.0
var clock_mult := 9.0
var finished := false
var difficulty := 2
var fmt := "11"
var offside_on := true
var sp := {}
var first_kickoff: TeamCtl
var offside_flags := {}
var offside_team: TeamCtl = null
var last_pass := {}
var last_shot := {}
var goals_log: Array = []
var replay_buf: Array = []
var clips: Array = []
var extra_time := false
var et_half := 0
var headless := false
var _rec_acc := 0.0
var _path_acc := 0.0
var ball_path := PackedVector3Array()
var _icpt := {}
var _icpt_best := {}
var _threat := {}
var _queued := {}
var _charge_t := 0.0
var _replay := {}
var _slides := {}
var _celebrant: Footballer = null
var _switch_cool := 0.0
var _user_dive := {}
var _fouls_half := 0
var _goals_half := 0
var shootout := {}
var _hl_index := 0


# ======================================================================= setup
func _ready() -> void:
	if params.is_empty():
		params = Game.match_request
	headless = params.get("headless_test", false)
	difficulty = int(params.get("difficulty", 2))
	fmt = str(params.get("format", "11"))
	offside_on = bool(params.get("offside", true)) and fmt != "5"
	clock_mult = 2700.0 / (float(params.get("half_minutes", 5)) * 60.0)
	BallSim.wet = params.get("weather", "clear") == "rain"
	BallSim.wind = Vector3.ZERO
	stadium = Stadium.new()
	add_child(stadium)
	stadium.build(params.get("venue", "harbor"), params.get("time", "night"), params.get("weather", "clear"))
	ball = Ball.new()
	ball.stadium = stadium
	add_child(ball)
	ball.goal_line_crossed.connect(_on_goal_line)
	ball.touchline_crossed.connect(_on_touchline)
	ball.kicked.connect(_on_kicked)
	ball.hit_post.connect(_on_post)
	var user_side := int(params.get("user_side", 0))
	for s in 2:
		var t = TeamCtl.new()
		t.setup(self, s, params.home if s == 0 else params.away, user_side == s, fmt)
		t.dir = 1 if s == 0 else -1
		t.level = 3 if user_side == s else difficulty
		teams.append(t)
	teams[0].opp = teams[1]
	teams[1].opp = teams[0]
	if user_side >= 0:
		user_team = teams[user_side]
	_spawn_players()
	cam = CameraRig.new()
	add_child(cam)
	cam.setup(self, stadium.L, stadium.W, stadium.is_cage)
	ball.set_camera(cam)
	_build_ui()
	stadium.set_crowd_colors(teams[0].kit.shirt, teams[1].kit.shirt)
	if not headless:
		Sfx.start_crowd()
		Sfx.set_excitement(0.25)
	first_kickoff = teams[randi() % 2]
	_setup_kickoff(first_kickoff)
	state = "intro"
	state_t = 0.0
	cam.mode = "orbit"
	cam.snap()
	hud.banner("KICK OFF", "%s · %s" % [Game.VENUES.get(params.get("venue", "harbor"), {"name": "Arena"}).name, params.get("time", "night")], Game.C_CARD, 2.4)


func cage_mode() -> bool:
	return stadium.is_cage


func all_players() -> Array:
	return teams[0].players + teams[1].players


func _gk_kit(t: TeamCtl) -> Dictionary:
	var choices := [["8E6CF0", "20163F"], ["F08A24", "2A1A08"], ["2BD18B", "0E2B1F"], ["1E1E1E", "FFCF33"]]
	var other: Color = t.opp.kit.shirt if t.opp else Color.WHITE
	for c in choices:
		var col := Color(c[0])
		if Vector3(col.r - t.kit.shirt.r, col.g - t.kit.shirt.g, col.b - t.kit.shirt.b).length() > 0.45 and Vector3(col.r - other.r, col.g - other.g, col.b - other.b).length() > 0.45:
			if t.side == 1 and c == choices[0]:
				continue
			return {"shirt": col, "shirt2": Color(c[1]), "pattern": 0, "shorts": Color(c[1]), "socks": col}
	return {"shirt": Color("1E1E1E"), "shirt2": Color("FFCF33"), "pattern": 0, "shorts": Color("1E1E1E"), "socks": Color("1E1E1E")}


func _spawn_players() -> void:
	var nums_11 := [1, 2, 5, 4, 3, 6, 8, 10, 7, 9, 11]
	var nums_5 := [1, 4, 8, 7, 9]
	var eq_boots: Dictionary = Game.BOOTS.get(Game.save.equipped.get("boots", "black"), Game.BOOTS.black)
	for t in teams:
		var gk_kit := _gk_kit(t)
		var names: Array = t.data.get("names", [])
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(t.data.get("id", "x")) + str(t.side))
		for i in t.formation.size():
			var f: Array = t.formation[i]
			var p := Footballer.new()
			p.team = t
			p.idx = i
			p.role = f[2]
			p.keeper = f[2] == "GK"
			p.number = (nums_5 if fmt == "5" else nums_11)[i]
			p.pname = str(names[i]) if i < names.size() else "Player %d" % (i + 1)
			p.stats = _make_stats(int(t.data.get("ovr", 75)), p.role, rng)
			var skin := Color(Game.SKIN_TONES[rng.randi() % Game.SKIN_TONES.size()])
			var hair := Color(Game.HAIR[rng.randi() % Game.HAIR.size()])
			var boots := Color(eq_boots.c) if t.is_user else Color(["151515", "F2F2F2", "151515", "D7F43A", "FF5B4A"][rng.randi() % 5])
			add_child(p)
			p.setup(t.kit, skin, hair, boots, gk_kit)
			t.players.append(p)


func _make_stats(ovr: int, role: String, rng: RandomNumberGenerator) -> Dictionary:
	var s := {"pace": ovr, "shoot": ovr - 6, "pass": ovr - 2, "drib": ovr - 3, "def": ovr - 10, "gk": 30}
	match role:
		"GK":
			s = {"pace": ovr - 20, "shoot": 40, "pass": ovr - 15, "drib": 40, "def": 40, "gk": ovr + 3}
		"DF":
			s.def = ovr + 6
			s.shoot = ovr - 20
			s.pace = ovr - 3
		"MF":
			s.pass = ovr + 5
			s.drib = ovr + 2
		"FW":
			s.shoot = ovr + 6
			s.pace = ovr + 4
			s.def = ovr - 25
	for k in s.keys():
		s[k] = clamp(int(s[k]) + rng.randi_range(-4, 4), 25, 99)
	return s


func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var root := UI.screen_root()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	controls = Controls.new()
	root.add_child(controls)
	hud = MatchHUD.new()
	hud.mt = self
	root.add_child(hud)
	hud.set_teams(teams[0].data, teams[1].data, teams[0].kit.shirt, teams[1].kit.shirt)
	hud.resume_pressed.connect(resume_game)
	hud.quit_pressed.connect(_quit)
	hud.restart_pressed.connect(_restart)
	hud.continue_pressed.connect(_on_continue)
	hud.highlights_pressed.connect(_play_highlights)
	hud.skip_pressed.connect(_skip_replay)
	controls.swiped.connect(_on_swipe)
	if user_team == null:
		controls.visible = false
	var wl: String = "Rain" if params.get("weather", "clear") == "rain" else ("Day" if params.get("time", "night") == "day" else ("Dusk" if params.get("time", "") == "dusk" else "Night"))
	hud.pill_text = "%s · %s" % [wl, ["Amateur", "Semi-pro", "Pro", "World class", "Legend"][difficulty]]


# ===================================================================== main loop
func _physics_process(dt: float) -> void:
	time_now += dt
	state_t += dt
	_switch_cool -= dt
	match state:
		"intro":
			if state_t > (0.2 if headless else 3.0):
				_go_state("kickoff")
				cam.mode = "broadcast"
				hud.flash(0.4)
				cam.snap()
		"kickoff":
			_st_kickoff(dt)
		"play":
			_st_play(dt)
		"dead":
			_st_dead(dt)
		"setpiece":
			_st_setpiece(dt)
		"goal":
			_st_goal(dt)
		"replay":
			_st_replay(dt)
		"shootout":
			_st_shootout(dt)
		"halftime", "fulltime":
			if headless and state == "halftime" and state_t > 0.5:
				_on_continue()
	if state != "replay":
		var t0 := Time.get_ticks_usec()
		for p in all_players():
			p.tick(dt)
		t0 = _pt("players", t0)
		_separate()
		_clamp_players()
		_record(dt)
		t0 = _pt("misc", t0)
	cam.update(dt)
	stadium.follow_camera(cam)
	_update_hud()
	controls.consume()


func _go_state(s: String) -> void:
	if headless and OS.get_cmdline_user_args().has("verbose"):
		print("[%.1f] %s -> %s  clock=%d sp=%s ball=%s holder=%s" % [time_now, state, s, int(clock), sp.get("type", ""), ball.pos, ball.holder.pname if ball.holder else "-"])
	state = s
	state_t = 0.0


var _prof := {}
var _prof_n := 0


func _pt(key: String, t0: int) -> int:
	var t1 := Time.get_ticks_usec()
	_prof[key] = _prof.get(key, 0) + (t1 - t0)
	return t1


func _st_play(dt: float) -> void:
	clock += dt * clock_mult
	var t0 := Time.get_ticks_usec()
	_predict(dt)
	t0 = _pt("predict", t0)
	if user_team:
		_user_play(dt)
	for t in teams:
		t.tick(dt)
	t0 = _pt("ai", t0)
	_prof_n += 1
	if headless and OS.get_cmdline_user_args().has("dump") and _prof_n % 120 == 0:
		var parts: Array = []
		for t in teams:
			for q in t.players:
				parts.append("%d,%.1f,%.1f,%s" % [t.side, q.pos.x, q.pos.z, "H" if ball.holder == q else ("K" if q.keeper else q.role)])
		print("DUMP %.1f|%.1f,%.1f,%.1f|%s|%d" % [time_now, ball.pos.x, ball.pos.z, ball.pos.y, ";".join(parts), teams[0].dir])
	if headless and _prof_n % 300 == 0 and OS.get_cmdline_user_args().has("verbose"):
		var out := {}
		for k in _prof.keys():
			out[k] = _prof[k] / _prof_n
		print("prof us/tick: ", out)
	_resolve_ball()
	_check_slides()
	_check_blocks()
	_check_saves()
	_check_time()
	var dmin: float = min(ball.pos.distance_to(Vector3(stadium.L, 0, 0)), ball.pos.distance_to(Vector3(-stadium.L, 0, 0)))
	var ex: float = 0.2 + 0.6 * clamp(1.0 - dmin / 35.0, 0.0, 1.0)
	Sfx.set_excitement(ex)
	stadium.set_excitement(ex * 0.35)


# ================================================================== predictions
func _predict(dt: float) -> void:
	_path_acc -= dt
	if _path_acc > 0.0:
		return
	_path_acc = 0.1
	ball_path = ball.predict(3.0, 0.05)
	_icpt.clear()
	_icpt_best.clear()
	_threat.clear()
	if ball.holder != null:
		return
	for t in teams:
		var best: Footballer = null
		var bt := INF
		for p in t.active():
			if p.busy() and p.action != "":
				continue
			if p.keeper and not in_penalty_area(ball.pos, t) and ball.pos.distance_to(p.pos) > 6.0:
				continue
			var r := _time_to_ball(p)
			_icpt[p] = r
			if r[0] < bt:
				bt = r[0]
				best = p
		_icpt_best[t] = best
		_threat[t] = _compute_threat(t)


func _time_to_ball(p: Footballer) -> Array:
	var sp_max := 6.6 + float(p.stats.pace) * 0.024
	for i in ball_path.size():
		var bp: Vector3 = ball_path[i]
		var t := i * 0.05
		if bp.y > (2.4 if p.keeper else 1.9):
			continue
		var d := Vector2(bp.x - p.pos.x, bp.z - p.pos.z).length() - 0.6
		if d / sp_max + 0.15 <= t:
			return [t, Vector3(bp.x, 0, bp.z)]
	var last: Vector3 = ball_path[ball_path.size() - 1] if ball_path.size() > 0 else ball.pos
	return [3.0 + p.pos.distance_to(last) / sp_max, Vector3(last.x, 0, last.z)]


func best_interceptor(t: TeamCtl) -> Footballer:
	return _icpt_best.get(t, null)


func intercept_point(p: Footballer) -> Vector3:
	if _icpt.has(p):
		return _icpt[p][1]
	return Vector3(ball.pos.x, 0, ball.pos.z)


func _compute_threat(t: TeamCtl) -> Dictionary:
	if ball.speed() < 6.0 or ball_path.size() < 2:
		return {}
	var gx = -t.dir * stadium.L
	var prev: Vector3 = ball_path[0]
	for i in range(1, ball_path.size()):
		var p: Vector3 = ball_path[i]
		if (prev.x - gx) * (p.x - gx) <= 0.0 and abs(p.x - prev.x) > 0.0001:
			var k: float = (gx - prev.x) / (p.x - prev.x)
			var c := prev.lerp(p, k)
			if abs(c.z) < stadium.goal_hw + 0.9 and c.y < stadium.goal_h + 0.5:
				return {"point": c, "t": (i - 1 + k) * 0.05, "speed": ball.speed(), "at": time_now}
			return {}
		prev = p
	return {}


func goal_threat(t: TeamCtl) -> Dictionary:
	if ball.holder != null:
		return {}
	var lt = ball.last_touch
	if lt != null and lt.team == t and ball.last_kick_kind != "header":
		return {}
	return _threat.get(t, {})


func in_penalty_area(pos: Vector3, t: TeamCtl) -> bool:
	var own_x = -t.dir * stadium.L
	if stadium.is_cage:
		return Vector2(pos.x - own_x, pos.z).length() < 6.0
	return abs(pos.z) < 20.16 and abs(pos.x - own_x) < 16.5 and sign(pos.x) == sign(own_x)


func shot_xg(pos: Vector3, t: TeamCtl) -> float:
	var g = t.opp_goal()
	var a := Vector2(g.x - pos.x, stadium.goal_hw - pos.z)
	var b := Vector2(g.x - pos.x, -stadium.goal_hw - pos.z)
	var ang: float = abs(a.angle_to(b))
	var d := pos.distance_to(g)
	var block := 0.0
	for q in t.opp.active():
		if q.keeper:
			continue
		var rel = q.pos - pos
		var to_g = (g - pos).normalized()
		var along = rel.dot(to_g)
		if along > 0.0 and along < d and (rel - to_g * along).length() < 1.2:
			block += 0.35
	var scale := 1.0 if not stadium.is_cage else 1.7
	return clamp((1.1 * ang - 0.012 * d * scale + 0.06) * (1.0 - min(block, 0.8)), 0.01, 0.85)


# ================================================================ ball contact
func _resolve_ball() -> void:
	if ball.frozen:
		return
	if ball.holder != null:
		var h: Footballer = ball.holder
		if h.sent_off or h.action in ["fall", "stumble"] or (h.stun > 0.0 and not ball.held_in_hands):
			ball.holder = null
			ball.held_in_hands = false
			ball.vel = h.vel * 0.8
		return
	var best: Footballer = null
	var best_d := INF
	var how := ""
	for p in all_players():
		if not p.can_touch_ball():
			continue
		var flat := Vector2(ball.pos.x - p.pos.x, ball.pos.z - p.pos.z).length()
		var h := ball.pos.y
		var kind := ""
		if not p.keeper and _in_cage_d(ball.pos):
			continue
		# a lofted ball can't be taken off the kicker's boot by a defender standing next to him
		if ball.last_touch != null and p.team != ball.last_touch.team and ball.time - ball.last_kick_time < 0.25 and ball.pos.y > 0.35:
			continue
		if p.keeper and in_penalty_area(ball.pos, p.team) and flat < 1.05 and h < 2.5 and p.action != "dive" and (ball.last_touch == null or ball.last_touch.team != p.team or ball.speed() < 6.0):
			kind = "hands"
		elif h < 0.95 and flat < (0.95 if h < 0.5 else 0.78):
			kind = "feet"
		elif h < 1.6 and flat < 0.6:
			kind = "chest"
		elif h >= 1.6 and h < 2.55 and flat < 0.8:
			kind = "head"
		if kind != "" and flat < best_d:
			best_d = flat
			best = p
			how = kind
	if headless and OS.get_cmdline_user_args().has("trace") and int(time_now * 10) % 5 == 0 and fmod(time_now, 0.5) < 0.07:
		var near: Array = []
		for p in all_players():
			var fl := Vector2(ball.pos.x - p.pos.x, ball.pos.z - p.pos.z).length()
			if fl < 3.0:
				near.append("%s(%s d=%.2f cd=%.2f st=%.2f a=%s)" % [p.pname.substr(3), p.team.side, fl, p.ball_cooldown, p.stun, p.action])
		print("LOOSE t=%.1f ball=%s v=%.1f h=%.2f near=%s chosen=%s" % [time_now, ball.pos, ball.speed(), ball.pos.y, near, best.pname if best else "-"])
	if best:
		_take(best, how)


func _take(p: Footballer, how: String) -> void:
	# offside
	if offside_on and offside_team == p.team and offside_flags.has(p) and not ball.last_kick_kind in ["throw", "corner", "goalkick"]:
		_offside(p)
		return
	offside_flags.clear()
	offside_team = null
	var prev_team = ball.last_touch.team if ball.last_touch != null else null
	match how:
		"hands":
			if ball.speed() > 24.0 and randf() < 0.6:
				_parry(p, Vector3.ZERO)
				return
			ball.holder = p
			ball.held_in_hands = true
			ball.touch_by(p)
			p.play_action("catch", 0.45, 2.0)
			p.vel = Vector3.ZERO
			Sfx.play("catch", 0.8)
			if not last_shot.is_empty() and last_shot.get("live", false) and last_shot.team != p.team:
				p.m_saves += 1
				last_shot.live = false
			_after_possession(p, prev_team)
			return
		"head":
			_header(p)
			return
	# feet / chest control
	var rel := (ball.vel - p.vel).length()
	var limit := 17.0 + float(p.stats.drib) * 0.08 + (4.0 if how == "chest" else 0.0)
	var fresh = ball.time - ball.last_kick_time < 0.12 and ball.last_touch == p
	if fresh:
		return
	# queued first-time action for the user
	if user_team and p == user_team.controlled and not _queued.is_empty() and time_now - _queued.t < 1.3:
		var q := _queued
		_queued = {}
		ball.touch_by(p)
		match q.kind:
			"shoot":
				_user_shoot(p, q.power, q.aim, true)
			"pass":
				_user_pass(p, q.aim, q.get("lob", false), true)
			"through":
				_user_through(p, q.aim, true)
		return
	if rel > limit and randf() < clamp((rel - limit) / 10.0, 0.0, 0.85):
		# heavy touch
		var dv := ball.vel * 0.35 + Vector3(randf_range(-2.5, 2.5), 0.6, randf_range(-2.5, 2.5))
		ball.vel = dv
		ball.touch_by(p)
		p.ball_cooldown = 0.35
		Sfx.play("bounce", 0.4)
		return
	ball.holder = p
	ball.held_in_hands = false
	ball.touch_by(p)
	if not last_shot.is_empty() and last_shot.get("live", false) and last_shot.team != p.team:
		last_shot.live = false
	_after_possession(p, prev_team)


var dbg := {"recv": 0, "int": 0, "self": 0, "out": 0}


func _after_possession(p: Footballer, prev_team) -> void:
	p.set_meta("got_ball", time_now)
	if not last_pass.is_empty() and last_pass.get("pending", false):
		if last_pass.team == p.team and last_pass.p != p:
			dbg.recv += 1
		elif last_pass.team != p.team:
			dbg.int += 1
			if OS.get_cmdline_user_args().has("trace2"):
				var ex = last_pass.team.expect
				var rdist: float = ex.p.pos.distance_to(ball.pos) if ex != null else -1.0
				var tgt_d: float = (ex.target as Vector3).distance_to(ball.pos) if ex != null else -1.0
				print("INT kind=%s from_passer=%.1f recv_to_ball=%.1f target_to_ball=%.1f flight=%.2fs v=%.1f role=%s" % [last_pass.get("kind", "?"), last_pass.p.pos.distance_to(p.pos), rdist, tgt_d, time_now - last_pass.t, ball.speed(), p.role])
		else:
			dbg.self += 1
		last_pass.pending = false
		if last_pass.team == p.team and last_pass.p != p:
			p.team.st.passes_ok += 1
			last_pass.p.m_passes_ok += 1
			last_pass["recv_t"] = time_now
	if user_team == null:
		return
	if p.team == user_team:
		_set_control(p)
		user_team.expect = null
	elif prev_team != p.team and Game.settings.get("auto_switch", true):
		_auto_switch(true)


func _header(p: Footballer) -> void:
	var t: TeamCtl = p.team
	var user_kind := ""
	if user_team and p == user_team.controlled:
		if _queued.is_empty() or time_now - _queued.t > 1.3:
			user_kind = "control"
		else:
			user_kind = _queued.kind
			_queued = {}
	if user_kind == "control":
		# cushion it down
		ball.vel = Vector3(ball.vel.x * 0.15, -1.0, ball.vel.z * 0.15)
		ball.touch_by(p)
		p.ball_cooldown = 0.25
		p.play_action("header", 0.4, 2.0, Callable(), 1.0, 0.05)
		return
	var goal := t.opp_goal()
	var d := ball.pos.distance_to(goal)
	var shoot := user_kind == "shoot" or (user_kind == "" and d < 17.0 and not p.keeper and t.dir * (ball.pos.x) > 0.0)
	# unpressured AI players cushion the ball down instead of heading it on
	if user_kind == "" and not shoot and not p.keeper and _pressure_on(p) < 0.8 and ball.pos.y < 2.3:
		ball.vel = Vector3(ball.vel.x * 0.12, -1.5, ball.vel.z * 0.12)
		ball.spin = Vector3.ZERO
		ball.touch_by(p)
		p.ball_cooldown = 0.12
		p.play_action("header", 0.35, 2.0, Callable(), 1.0, 0.05)
		return
	var v: Vector3
	if p.keeper:
		v = BallSim.lob_velocity(ball.pos, ball.pos + Vector3(t.dir * 30.0, 0, 0), 40.0)
	elif shoot:
		var gk = t.opp.keeper()
		var zs: float = -sign(gk.pos.z) if gk and abs(gk.pos.z) > 0.3 else (1.0 if randf() < 0.5 else -1.0)
		var target := Vector3(goal.x, randf_range(0.2, 1.4), zs * (stadium.goal_hw - randf_range(0.4, 1.2)))
		v = BallSim.solve(ball.pos, target, randf_range(13.0, 17.0), Vector3.ZERO)
		if v == Vector3.ZERO:
			v = (target - ball.pos).normalized() * 15.0
		v = _apply_error(v, 0.05 + (1.0 - float(p.stats.shoot) / 100.0) * 0.05)
		_register_shot(p, shot_xg(ball.pos, t) * 0.6)
	else:
		var mate = _forward_mate(p)
		var defending: bool = in_penalty_area(ball.pos, t)
		var target: Vector3 = mate.pos if mate else ball.pos + Vector3(t.dir * 22.0, 0, 0)
		if defending and mate == null:
			v = BallSim.lob_velocity(ball.pos, target, 30.0).limit_length(17.0)
		else:
			# flat header towards a team-mate's feet
			var flat := Vector3(target.x - ball.pos.x, 0, target.z - ball.pos.z)
			var spd: float = clamp(flat.length() * 0.75 + 4.0, 7.0, 13.0)
			v = flat.normalized() * spd + Vector3(0, 1.2, 0)
		if mate:
			t.expect = {"p": mate, "target": target, "until": time_now + 2.0}
	p.play_action("header", 0.45, 2.0, Callable(), 1.0, clamp(ball.pos.y - 1.6, 0.0, 0.6) + 0.15)
	ball.kick(v, Vector3.ZERO, p, "header" if not shoot else "shot")
	Game.haptic(15)


func _forward_mate(p: Footballer):
	var best = null
	var bs := -INF
	for m in p.team.active():
		if m == p or m.keeper:
			continue
		var s: float = (m.pos.x - p.pos.x) * p.team.dir - abs(m.pos.z - p.pos.z) * 0.3
		var d = m.pos.distance_to(p.pos)
		if d > 30.0 or d < 5.0:
			continue
		if s > bs:
			bs = s
			best = m
	return best


# ====================================================================== kicks
func _apply_error(v: Vector3, err: float) -> Vector3:
	if err <= 0.0:
		return v
	v = v.rotated(Vector3.UP, randfn(0.0, err))
	var ax := v.cross(Vector3.UP)
	if ax.length() > 0.001:
		v = v.rotated(ax.normalized(), randfn(0.0, err * 0.6))
	return v * (1.0 + randfn(0.0, err * 0.4))


func _foot_side(p: Footballer, target: Vector3) -> float:
	var left := Vector3(cos(p.yaw), 0, -sin(p.yaw))
	return -1.0 if (target - p.pos).normalized().dot(left) > 0.45 else 1.0


## Plays a kick animation and launches the ball at contact. `compute` returns [velocity, spin, kind].
func _kick(p: Footballer, anim: String, dur: float, target: Vector3, compute: Callable, instant := false) -> void:
	if instant:
		p.play_action(anim, dur * 0.7, 0.05, _do_kick.bind(p, compute), _foot_side(p, target), 0.35, null)
		p.face_towards(target, true)
		return
	p.play_action(anim, dur, 0.5 if anim != "pass" else 0.45, _do_kick.bind(p, compute), _foot_side(p, target), 0.35, target)


func _do_kick(p: Footballer, compute: Callable) -> void:
	var owns = ball.holder == p
	if not owns:
		var reach := 2.8 if ball.frozen else 1.6
		if ball.holder != null or ball.pos.distance_to(p.pos + Vector3(0, 0.3, 0)) > reach:
			return
	if ball.held_in_hands and ball.holder == p:
		ball.held_in_hands = false
	var r: Array = compute.call()
	ball.holder = null
	ball.kick(r[0], r[1], p, r[2])
	p.ball_cooldown = 0.32
	if headless and OS.get_cmdline_user_args().has("verbose") and r[2] in ["shot", "freekick", "penalty"]:
		print("   SHOT by %s d=%.1f v=%.1f kind=%s" % [p.pname, p.pos.distance_to(p.team.opp_goal()), (r[0] as Vector3).length(), r[2]])


func _pass_vel(from: Vector3, target: Vector3, kind: String, err: float) -> Vector3:
	var flat := Vector3(target.x - from.x, 0, target.z - from.z)
	var d := flat.length()
	var v: Vector3
	match kind:
		"lob", "cross", "corner":
			v = BallSim.lob_velocity(from, target, 34.0 if kind == "lob" else 27.0)
		"clear", "long", "goalkick_long":
			v = BallSim.lob_velocity(from, target, 38.0)
		"through":
			v = flat.normalized() * BallSim.ground_pass_speed(d, 9.5)
		"throw":
			v = BallSim.lob_velocity(from, target, 18.0)
		_:
			v = flat.normalized() * BallSim.ground_pass_speed(d, 8.0 if d > 8.0 else 6.0)
	return _apply_error(v, err)


func _expect(t: TeamCtl, m: Footballer, target: Vector3, speed: float) -> void:
	var d := ball.pos.distance_to(target)
	t.expect = {"p": m, "target": Vector3(target.x, 0, target.z), "until": time_now + d / max(speed, 4.0) + 1.2}


func ai_pass(p: Footballer, m: Footballer, target: Vector3, kind: String) -> void:
	var err: float = TeamCtl.AIM_ERR[p.team.level] * (1.35 - float(p.stats.pass) / 100.0) * 0.5
	var k := kind if kind != "ground" else "pass"
	_kick(p, "pass" if k in ["pass", "through"] else "lob", 0.32 if k in ["pass", "through"] else 0.42, target, _calc_pass.bind(p, target, k, err))
	_expect(p.team, m, target, 14.0)
	if k == "through":
		p.team._runs[m] = [target, 2.2]


func _calc_pass(p: Footballer, target: Vector3, kind: String, err: float) -> Array:
	return [_pass_vel(ball.pos, target, kind, err), Vector3.ZERO, kind]


func ai_cross(p: Footballer, m: Footballer) -> void:
	var target := m.pos + m.vel * 0.8
	_expect(p.team, m, target, 16.0)
	var spin := Vector3(0, -p.team.dir * sign(p.pos.z) * 25.0, 0)
	_kick(p, "cross", 0.45, target, _calc_cross_from.bind(p, target, spin))


func _calc_cross_from(p: Footballer, target: Vector3, spin: Vector3) -> Array:
	var v := BallSim.lob_velocity(ball.pos, target, 24.0, spin)
	return [_apply_error(v, 0.04), spin, "cross"]


func ai_clear(p: Footballer) -> void:
	var t: TeamCtl = p.team
	var target := Vector3(clamp(p.pos.x + t.dir * 40.0, -stadium.L + 5, stadium.L - 5), 0, clamp(p.pos.z + randf_range(-15, 15), -stadium.W + 4, stadium.W - 4))
	_kick(p, "lob", 0.4, target, _calc_pass.bind(p, target, "clear", 0.06))


func ai_shoot(p: Footballer) -> void:
	var t: TeamCtl = p.team
	var goal = t.opp_goal()
	var gk = t.opp.keeper()
	var hw := stadium.goal_hw
	var zs: float
	if gk and abs(gk.pos.z) > 0.25:
		zs = -sign(gk.pos.z)
	else:
		zs = -sign(p.pos.z) if abs(p.pos.z) > 1.0 else (1.0 if randf() < 0.5 else -1.0)
	var y := randf_range(0.2, 1.0) if randf() < 0.65 else randf_range(1.0, stadium.goal_h - 0.35)
	var target := Vector3(goal.x, y, zs * (hw - randf_range(0.35, 1.0)))
	var d := p.pos.distance_to(goal)
	var speed: float = clamp(20.0 + float(p.stats.shoot) * 0.1 + randf_range(-2, 2), 17.0, 32.0)
	if stadium.is_cage:
		speed = clamp(15.0 + float(p.stats.shoot) * 0.08 + randf_range(-1.5, 1.5), 15.0, 23.0)
	var spin := Vector3.ZERO
	if d > 16.0 and randf() < 0.5:
		spin = Vector3(0, -zs * t.dir * randf_range(25, 50), 0)
	var err: float = TeamCtl.AIM_ERR[t.level] * (1.45 - float(p.stats.shoot) / 100.0) * (1.0 + _pressure_on(p) * 0.6)
	_kick(p, "kick", 0.42, target, _calc_shot.bind(p, target, speed, spin, err))


func _calc_shot(p: Footballer, target: Vector3, speed: float, spin: Vector3, err: float) -> Array:
	var v := BallSim.solve(ball.pos, target, speed, spin)
	if v == Vector3.ZERO:
		var d := target - ball.pos
		v = Vector3(d.x, d.y + d.length() * 0.1, d.z).normalized() * speed
	v = _apply_error(v, err)
	_register_shot(p, shot_xg(p.pos, p.team))
	return [v, spin, "shot"]


func _register_shot(p: Footballer, xg: float) -> void:
	var t: TeamCtl = p.team
	t.st.shots += 1
	t.st.xg += xg
	p.m_shots += 1
	last_shot = {"team": t, "p": p, "t": time_now, "live": true, "xg": xg, "counted": false}


func _pressure_on(p: Footballer) -> float:
	var nd := INF
	for q in p.team.opp.active():
		nd = min(nd, q.pos.distance_to(p.pos))
	return clamp(1.0 - (nd - 1.0) / 5.0, 0.0, 1.0)


func keeper_distribute(p: Footballer) -> void:
	var t: TeamCtl = p.team
	var best = null
	var bs := -INF
	for m in t.active():
		if m == p:
			continue
		var d = m.pos.distance_to(p.pos)
		if d < 8.0 or d > 32.0:
			continue
		var space := 20.0
		for q in t.opp.active():
			space = min(space, q.pos.distance_to(m.pos))
		var s = space - d * 0.1
		if s > bs:
			bs = s
			best = m
	if best != null and bs > 3.0:
		var target: Vector3 = best.pos + best.vel * 0.5
		_expect(t, best, target, 12.0)
		p.play_action("gk_throw", 0.6, 0.62, _do_kick.bind(p, _calc_pass.bind(p, target, "throw", 0.03)), 1.0, 0.35, target)
	else:
		var target := Vector3(clamp(p.pos.x + t.dir * randf_range(40, 52), -stadium.L + 6, stadium.L - 6), 0, randf_range(-stadium.W * 0.6, stadium.W * 0.6))
		if stadium.is_cage:
			target = Vector3(p.pos.x + t.dir * 18.0, 0, randf_range(-6, 6))
		_kick(p, "kick", 0.45, target, _calc_pass.bind(p, target, "clear", 0.05))


# ===================================================================== keepers
func keeper_react(p: Footballer, threat: Dictionary, reach: float) -> void:
	if p.busy():
		return
	var pt: Vector3 = threat.point
	var t_at_line: float = float(threat.t) - (time_now - float(threat.get("at", time_now)))
	# where will the ball be when it reaches the keeper's depth?
	var tleft := t_at_line
	for i in ball_path.size():
		var bp: Vector3 = ball_path[i]
		if (bp.x - p.pos.x) * p.team.dir <= 0.3:
			pt = bp
			tleft = i * 0.05 - (time_now - float(threat.get("at", time_now)))
			break
	p.face_towards(p.pos + Vector3(p.team.dir, 0, 0), true)
	var left := Vector3(cos(p.yaw), 0, -sin(p.yaw))
	var lat := (pt - p.pos).dot(left)
	tleft = max(0.08, tleft)
	p.ready_amt = 1.0
	if abs(lat) < 0.55 and pt.y < 2.0:
		if tleft < 0.35:
			p.play_action("catch", 0.5, 2.0)
		p.desired = left * lat * 3.0
		return
	# shuffle across first, then explode into the dive at the last moment
	if tleft > 0.55:
		p.desired = left * sign(lat) * min(3.6, abs(lat) * 2.5)
		p.face_point = null
		return
	var side: float = sign(lat)
	var need: float = abs(lat) - 0.6
	var spd: float = clamp(need / max(0.15, tleft - 0.05), 4.2, 6.8 * reach)
	p.dive_vel = left * side * spd
	p.play_action("dive", clamp(tleft * 1.9, 0.6, 0.95), 2.0, Callable(), side, clamp(pt.y / 2.4, 0.0, 1.0))


func _keeper_segment(k: Footballer) -> Array:
	var up := Vector3.UP
	if k.action == "dive":
		var t := k.action_t
		var lay := PlayerRig._k(t, [[0, 0.0], [0.15, 0.65], [0.38, 1.0], [1, 1.0]])
		var air := PlayerRig._k(t, [[0, 0.0], [0.12, 0.4], [0.4, 1.0], [0.62, 1.0], [0.78, 0.0]])
		var left := Vector3(cos(k.yaw), 0, -sin(k.yaw))
		var a := 1.35 * lay
		var axis := (up * cos(a) + left * k.action_side * sin(a)).normalized()
		var hip := k.pos + Vector3(0, max(0.25, 0.96 - 0.3 * lay + air * (0.25 + k.action_height * 0.6)), 0)
		return [hip - axis * 0.9, hip + axis * 1.5, 0.46]
	var r := 0.46 if k.action == "catch" else 0.38
	return [k.pos + up * 0.1, k.pos + up * (2.2 if k.ready_amt > 0.5 else 2.05), r]


func _check_saves() -> void:
	if ball.holder != null or ball.speed() < 3.0:
		return
	for t in teams:
		var k = t.keeper()
		if k == null or k.stun > 0.0:
			continue
		if ball.last_touch == k and ball.time - ball.last_kick_time < 0.4:
			continue
		var toward_goal: bool = ball.vel.x * -t.dir > 1.0
		if not toward_goal:
			continue
		var seg := _keeper_segment(k)
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var ab := b - a
		var tt: float = clamp((ball.pos - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var c := a + ab * tt
		var gk_skill: float = float(k.stats.gk) / 100.0
		var reach: float = seg[2] * (0.85 + gk_skill * 0.3) * (1.2 if stadium.is_cage else 1.0)
		# reflex stop: shot struck close to a set keeper (one roll per shot)
		var depth_gap: float = abs(ball.pos.x - k.pos.x)
		var lat_gap: float = abs(ball.pos.z - k.pos.z)
		if not last_shot.is_empty() and last_shot.get("live", false) and not last_shot.get("reflex", false) and depth_gap < 0.45 and lat_gap < 1.15 and ball.pos.y < 2.0 and k.action != "dive":
			last_shot["reflex"] = true
			var p_save: float = (0.25 + gk_skill * 0.55) * clamp(1.25 - ball.speed() / 32.0, 0.2, 1.0) * (1.0 - lat_gap / 1.6)
			if TeamCtl.GK_REACH.size() > 0 and not t.is_user:
				p_save *= TeamCtl.GK_REACH[t.level]
			if randf() < p_save:
				_parry(k, ball.pos - Vector3(t.dir * 0.3, 0, 0))
				return
		if headless and OS.get_cmdline_user_args().has("verbose") and ball.pos.distance_to(k.pos) < 4.0:
			print("     gk %s act=%s t=%.2f dist=%.2f reach=%.2f ball=%s kpos=%s" % [k.pname, k.action, k.action_t, ball.pos.distance_to(c), reach, ball.pos, k.pos])
		if ball.pos.distance_to(c) < reach:
			var catch_ok := ball.speed() < 15.0 + gk_skill * 9.0 and tt > 0.3 and randf() < 0.45 + gk_skill * 0.4
			if k.action == "dive" and k.action_t > 0.35:
				catch_ok = catch_ok and ball.speed() < 13.0
			if headless and OS.get_cmdline_user_args().has("verbose"):
				print("   SAVE %s by %s (%s) speed=%.1f" % ["catch" if catch_ok else "parry", k.pname, k.action, ball.speed()])
			if catch_ok:
				ball.holder = k
				ball.held_in_hands = true
				ball.touch_by(k)
				if k.action != "dive":
					k.play_action("catch", 0.45, 2.0)
				Sfx.play("catch", 0.9)
				k.m_saves += 1
				if not last_shot.is_empty():
					last_shot.live = false
				_after_possession(k, ball.last_touch.team if ball.last_touch else null)
			else:
				_parry(k, c)
			return


func _parry(k: Footballer, contact: Vector3) -> void:
	# always push the ball away from goal and out wide
	var sp_in := ball.speed()
	var out := Vector3(k.team.dir, 0, 0)
	var wide: float = sign(ball.pos.z) if abs(ball.pos.z) > 0.2 else (1.0 if randf() < 0.5 else -1.0)
	var v := out * randf_range(0.18, 0.32) * sp_in + Vector3(0, randf_range(2.0, 5.0), wide * randf_range(2.5, 6.0))
	if ball.pos.y > stadium.goal_h - 0.4 and randf() < 0.5:
		# tipped over the bar
		v = Vector3(-k.team.dir * 3.0, randf_range(4.5, 6.5), wide * 1.0)
	ball.vel = v
	ball.spin = Vector3.ZERO
	ball.pos.x += k.team.dir * 0.15
	ball.touch_by(k)
	ball.last_kick_time = ball.time
	ball.last_kick_kind = "save"
	k.m_saves += 1
	Sfx.play("catch", 0.9, 0.85)
	Sfx.near_miss()
	if not last_shot.is_empty():
		last_shot.live = false
	hud.message("Save! " + k.pname, 1.4)


func _check_blocks() -> void:
	if ball.holder != null or ball.last_kick_kind != "shot" or ball.speed() < 10.0:
		return
	if ball.time - ball.last_kick_time < 0.1:
		return
	var shooter = ball.last_touch
	if shooter == null:
		return
	for q in shooter.team.opp.active():
		if q.keeper:
			continue
		var flat := Vector2(ball.pos.x - q.pos.x, ball.pos.z - q.pos.z).length()
		if flat < 0.42 and ball.pos.y < 1.75:
			var v := ball.vel * 0.3
			v.x = -v.x * 0.5
			v += Vector3(randf_range(-3, 3), randf_range(0.5, 3.0), randf_range(-3, 3))
			ball.vel = v
			ball.touch_by(q)
			ball.last_kick_kind = "block"
			Sfx.play("tackle", 0.7)
			return


# ===================================================================== tackles
func try_tackle(p: Footballer, kind: String) -> void:
	if p.busy():
		return
	match kind:
		"stand":
			p.face_towards(ball.pos, true)
			p.play_action("tackle", 0.45, 0.35, _resolve_tackle.bind(p, "stand"), 1.0)
		"slide":
			var h = ball.holder
			var aim: Vector3 = (h.pos + h.vel * 0.25) if h != null else ball.pos
			p.face_towards(aim, true)
			p.slide_vel = p.forward() * 7.6 + p.vel * 0.25
			p.play_action("slide", 0.95, 2.0, Callable(), 1.0)
			_slides[p] = {"won": false, "done": false}
		"smother":
			var h = ball.holder
			if h == null:
				return
			p.face_towards(h.pos, true)
			var left := Vector3(cos(p.yaw), 0, -sin(p.yaw))
			var lat = (h.pos - p.pos).dot(left)
			p.dive_vel = (h.pos - p.pos).normalized() * 4.0
			p.play_action("dive", 0.75, 0.3, _resolve_tackle.bind(p, "smother"), sign(lat) if abs(lat) > 0.1 else 1.0, 0.0)


func _resolve_tackle(p: Footballer, kind: String) -> void:
	var h = ball.holder
	if h == null or h.team == p.team:
		if ball.holder == null and Vector2(ball.pos.x - p.pos.x, ball.pos.z - p.pos.z).length() < 1.4 and ball.pos.y < 0.8:
			ball.kick(p.forward() * randf_range(4, 7), Vector3.ZERO, p, "tackle")
		return
	var rel: Vector3 = h.pos - p.pos
	var d := rel.length()
	var reach := 1.9 if kind == "stand" else 2.0
	if d > reach or (kind == "stand" and p.forward().dot(rel.normalized()) < 0.2):
		p.stun = 0.35
		return
	var from_behind: bool = h.forward().dot((p.pos - h.pos).normalized()) < -0.35
	var chance: float = 0.48 + (float(p.stats.def) - float(h.stats.drib)) / 140.0
	if not p.team.is_user:
		chance += (p.team.level - 2) * 0.05
	if kind == "smother":
		chance = 0.55 + float(p.stats.gk) / 300.0
	if from_behind:
		chance -= 0.25
	if randf() < chance:
		p.m_tackles += 1
		Sfx.play("tackle", 0.8)
		if randf() < 0.5 or kind == "smother":
			ball.holder = p if kind != "smother" else null
			ball.held_in_hands = false
			if kind == "smother":
				ball.kick(Vector3(p.team.dir * 5.0, 1.0, randf_range(-3, 3)), Vector3.ZERO, p, "tackle")
			ball.touch_by(p)
			if ball.holder == p:
				_after_possession(p, h.team)
		else:
			ball.holder = null
			ball.kick(p.forward() * randf_range(4.0, 7.0) + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), Vector3.ZERO, p, "tackle")
		h.play_action("stumble", 0.5, 2.0)
	elif from_behind and randf() < 0.45:
		_foul(p, h, kind)
	else:
		p.stun = 0.4
		p.play_action("stumble", 0.45, 2.0)


func _check_slides() -> void:
	for p in _slides.keys():
		var s: Dictionary = _slides[p]
		if p.action != "slide":
			_slides.erase(p)
			continue
		if s.done or p.action_t < 0.08 or p.action_t > 0.75:
			continue
		var foot: Vector3 = p.pos + p.forward() * 0.85
		var h = ball.holder
		if (h == null or h.team != p.team) and ball.pos.y < 0.7 and Vector2(ball.pos.x - foot.x, ball.pos.z - foot.z).length() < 0.85:
			s.won = true
			ball.holder = null
			ball.held_in_hands = false
			ball.kick(p.forward() * randf_range(5.0, 9.0) + p.right() * randf_range(-3, 3), Vector3.ZERO, p, "tackle")
			p.m_tackles += 1
			if h != null:
				h.play_action("fall", 1.2, 2.0)
			continue
		for q in p.team.opp.active():
			if Vector2(q.pos.x - foot.x, q.pos.z - foot.z).length() < 0.7 and q.action != "fall":
				if not s.won:
					s.done = true
					_foul(p, q, "slide")
					return
				else:
					q.play_action("fall", 1.2, 2.0)


func _foul(by: Footballer, victim: Footballer, kind: String) -> void:
	if state != "play":
		return
	by.m_fouls += 1
	by.team.st.fouls += 1
	_fouls_half += 1
	victim.cancel_action()
	victim.play_action("fall", 1.4, 2.0)
	if ball.holder == victim:
		ball.holder = null
		ball.held_in_hands = false
	Sfx.play("whistle", 0.9)
	var from_behind: bool = victim.forward().dot((by.pos - victim.pos).normalized()) < -0.3
	var pc := 0.06
	if kind == "slide":
		pc = 0.5 if from_behind else 0.2
	elif from_behind:
		pc = 0.18
	var card := ""
	if randf() < pc:
		card = "yellow"
	if kind == "slide" and from_behind and randf() < 0.04:
		card = "red"
	if card == "yellow":
		by.yellow += 1
		by.team.st.yellow += 1
		if by.yellow >= 2:
			card = "red"
	var pen := in_penalty_area(victim.pos, by.team)
	_dead("penalty" if pen else "freekick", victim.team, victim.pos, 1.6)
	if card == "red":
		by.team.st.red += 1
		hud.banner("RED CARD", by.pname, Game.C_AWAY, 2.4)
		_send_off.call_deferred(by)
	elif card == "yellow":
		hud.banner("YELLOW CARD", by.pname, Game.C_CARD, 2.0)
	else:
		hud.message(("Penalty! " if pen else "Foul · ") + by.pname, 1.8)


func _send_off(p: Footballer) -> void:
	await get_tree().create_timer(1.4).timeout
	if not is_instance_valid(p):
		return
	p.sent_off = true
	p.visible = false
	p.pos = Vector3(0, 0, stadium.W + 8.0)
	if user_team and user_team.controlled == p:
		_auto_switch(true)


# ================================================================ out of play
func _dead(type: String, team: TeamCtl, pos: Vector3, delay := 1.2, indirect := false) -> void:
	if state == "goal" or finished:
		return
	_go_state("dead")
	sp = {"type": type, "team": team, "pos": pos, "delay": delay, "indirect": indirect}
	_queued = {}
	controls.power = 0.0
	_charge_t = 0.0


func _on_touchline(pos: Vector3) -> void:
	if state != "play":
		return
	var lt = ball.last_touch
	var t: TeamCtl = teams[0] if lt == null else lt.team.opp
	_dead("throw", t, Vector3(clamp(pos.x, -stadium.L + 0.6, stadium.L - 0.6), 0, sign(pos.z) * stadium.W))
	hud.message("Throw-in · " + t.data.name, 1.6)


func _on_goal_line(side: int, scored: bool, pos: Vector3) -> void:
	if state == "shootout":
		if scored:
			shootout.result = "goal"
		return
	if state != "play":
		return
	if scored:
		_goal(side)
		return
	var defending: TeamCtl = teams[0] if teams[0].dir == -side else teams[1]
	var lt = ball.last_touch
	if not last_shot.is_empty() and last_shot.live and abs(pos.z) < stadium.goal_hw + 3.0:
		Sfx.near_miss()
	if not last_shot.is_empty():
		last_shot.live = false
	var zs: float = sign(pos.z) if abs(pos.z) > 0.1 else 1.0
	if lt != null and lt.team == defending:
		defending.opp.st.corners += 1
		_dead("corner", defending.opp, Vector3(side * stadium.L, 0, zs * stadium.W))
		hud.message("Corner · " + defending.opp.data.name, 1.6)
	else:
		_dead("goalkick", defending, Vector3(side * (stadium.L - 5.5), 0, zs * 3.5))
		hud.message("Goal kick", 1.4)


func _on_post(_pos: Vector3) -> void:
	if state == "play":
		Sfx.near_miss()


func _offside(p: Footballer) -> void:
	p.team.st.offsides += 1
	Sfx.play("whistle", 0.8)
	hud.message("Offside · " + p.pname, 1.8)
	ball.holder = null
	_dead("freekick", p.team.opp, p.pos, 1.4, true)


func _on_kicked(by, kind: String) -> void:
	if state in ["kickoff", "setpiece"]:
		_go_state("play")
		controls.swipe_mode = false
		ball.frozen = false
		if sp.get("type", "") == "penalty":
			_penalty_keeper_guess()
	if by == null:
		return
	var t: TeamCtl = by.team
	if kind in ["throw", "corner", "goalkick", "goalkick_long"]:
		offside_flags.clear()
		offside_team = null
	elif offside_on and kind != "tackle":
		_snapshot_offside(t, by)
	if kind in PASS_KINDS or kind == "header":
		if kind != "header":
			t.st.passes += 1
			by.m_passes += 1
		last_pass = {"p": by, "t": time_now, "team": t, "pending": true, "kind": kind}
	if user_team and t == user_team and t.expect != null and kind in PASS_KINDS:
		_set_control(t.expect.p)
	if not ["shot", "penalty", "freekick"].has(kind):
		pass
	elif not last_shot.is_empty():
		# on target if the predicted path enters the goal
		var th := _compute_threat_for_kick(t.opp)
		if not th.is_empty() and abs(th.point.z) < stadium.goal_hw and th.point.y < stadium.goal_h:
			t.st.on_target += 1


func _compute_threat_for_kick(t: TeamCtl) -> Dictionary:
	var saved := ball_path
	ball_path = ball.predict(3.0, 0.05)
	var r := _compute_threat(t)
	ball_path = saved
	return r


func _snapshot_offside(t: TeamCtl, kicker: Footballer) -> void:
	offside_flags.clear()
	offside_team = t
	var line = t.offside_line_x()
	for m in t.active():
		if m == kicker:
			continue
		var x: float = m.pos.x * t.dir
		if x > 0.0 and x > line + 0.25 and x > ball.pos.x * t.dir:
			offside_flags[m] = true


# ======================================================================= goals
func _goal(side: int) -> void:
	var scoring: TeamCtl = teams[0] if teams[0].dir == side else teams[1]
	scoring.score += 1
	_goals_half += 1
	var scorer = ball.last_touch
	var og: bool = scorer != null and scorer.team != scoring
	var minute := _minute()
	var pen := ball.last_kick_kind == "penalty"
	if scorer and not og:
		scorer.m_goals += 1
		if not last_pass.is_empty() and last_pass.p.team == scoring and last_pass.p != scorer and time_now - last_pass.t < 10.0:
			last_pass.p.m_assists += 1
	var name: String = scorer.pname if scorer else "Unknown"
	if headless and OS.get_cmdline_user_args().has("verbose"):
		var gk := scoring.opp.keeper()
		print("   GOAL %s kind=%s keeper_action=%s gk_pos=%s ball=%s" % [name, ball.last_kick_kind, gk.action if gk else "-", gk.pos if gk else Vector3.ZERO, ball.pos])
	goals_log.append({"side": scoring.side, "name": name, "minute": minute, "og": og, "pen": pen})
	if not last_shot.is_empty():
		last_shot.live = false
	_go_state("goal")
	controls.reset()
	controls.power = 0.0
	if not headless:
		Sfx.goal_roar()
	Sfx.set_excitement(1.0)
	stadium.set_excitement(1.0, 1.0 if scoring.side == 0 else -1.0)
	Game.haptic(60)
	hud.banner("GOAL!", "%s  %s'%s" % [name, minute, " (OG)" if og else (" (pen)" if pen else "")], Game.C_CARD, 3.0)
	_celebrant = scorer if (scorer and not og) else _nearest_of(scoring, ball.pos)
	clips.append({"frames": replay_buf.duplicate(), "side": side, "title": name + " " + minute + "'"})
	if _celebrant:
		_celebrant.cancel_action()


func _nearest_of(t: TeamCtl, pt: Vector3) -> Footballer:
	var best: Footballer = null
	var bd := INF
	for p in t.active():
		var d = p.pos.distance_to(pt)
		if d < bd:
			bd = d
			best = p
	return best


func _minute() -> String:
	var m := int(clock / 60.0) + 1
	if not extra_time:
		if half == 1 and clock > 2700.0:
			return "45+%d" % int((clock - 2700.0) / 60.0 + 1)
		if half == 2 and clock > 5400.0:
			return "90+%d" % int((clock - 5400.0) / 60.0 + 1)
	return str(min(m, 120))


func _st_goal(dt: float) -> void:
	var scoring_side: int = goals_log[goals_log.size() - 1].side
	var sc: TeamCtl = teams[scoring_side]
	if _celebrant and is_instance_valid(_celebrant):
		cam.mode = "follow"
		cam.follow_node = _celebrant
		var corner := Vector3(sign(_celebrant.pos.x) * (stadium.L - 5.0), 0, stadium.W - 4.0)
		if _celebrant.action == "":
			if state_t < 2.0 and _celebrant.pos.distance_to(corner) > 2.0:
				_celebrant.desired = (corner - _celebrant.pos).normalized() * 7.5
				_celebrant.sprint = true
			else:
				_celebrant.desired = Vector3.ZERO
				var cel: String = Game.save.equipped.get("celebration", "fist") if sc.is_user else ["fist", "airplane", "arms", "kneeslide"][randi() % 4]
				if cel == "airplane":
					_celebrant.play_action("cel_airplane", 1.0, 2.0)
					_celebrant.desired = (corner - _celebrant.pos).normalized() * 3.0
				else:
					_celebrant.play_action("cel_" + cel, 1.0, 2.0)
		for p in sc.active():
			if p == _celebrant or p.keeper:
				continue
			var d = p.pos.distance_to(_celebrant.pos)
			p.desired = (_celebrant.pos - p.pos).normalized() * (6.0 if d > 3.0 else 0.0)
			if d < 3.0 and p.action == "" and randf() < 0.02:
				p.play_action("cheer", 0.8, 2.0)
		for p in sc.opp.active():
			p.desired = Vector3.ZERO
			if p.action == "" and randf() < 0.01:
				p.play_action("dejected", 2.5, 2.0)
	if state_t > (0.3 if headless else 4.6):
		for p in all_players():
			p.cancel_action()
		stadium.set_excitement(0.3)
		if headless or clips.is_empty():
			_after_goal()
		else:
			_start_replay(clips[clips.size() - 1], _after_goal)


func _after_goal() -> void:
	var scoring_side: int = goals_log[goals_log.size() - 1].side
	cam.mode = "broadcast"
	_setup_kickoff(teams[1 - scoring_side])
	hud.flash()
	cam.snap()
	_go_state("kickoff")


# ==================================================================== set pieces
func _setup_kickoff(t: TeamCtl) -> void:
	ball.place(Vector3(0, BallSim.R, 0))
	ball.frozen = true
	ball.last_touch = null
	for tm in teams:
		tm.kickoff_positions(tm == t)
		tm.expect = null
		tm._runs.clear()
	var taker = t.kickoff_taker()
	taker.pos = Vector3(-t.dir * 0.5, 0, 0.05)
	taker.yaw = atan2(float(t.dir), 0.0)
	sp = {"type": "kickoff", "team": t, "taker": taker, "pos": Vector3.ZERO, "user": t == user_team, "done": false, "wait": 1.0}
	offside_flags.clear()
	_queued = {}
	last_shot = {}
	if t == user_team:
		_set_control(taker)
	elif user_team:
		_set_control(_nearest_of(user_team, Vector3.ZERO))


func _st_kickoff(dt: float) -> void:
	_idle_all()
	if sp.done:
		if state_t > 5.0 and ball.frozen and sp.taker.action == "":
			sp.done = false
			state_t = 0.0
		return
	var taker: Footballer = sp.taker
	if sp.user:
		hud.message("Tap PASS to kick off", 0.2)
		controls.set_labels({"pass": "Pass", "shoot": "Shoot", "through": "Through"})
		if controls.just_pressed("pass") or controls.just_pressed("through") or controls.just_pressed("shoot"):
			sp.done = true
			_kickoff_pass(taker)
	elif state_t > (0.3 if headless else 1.1):
		sp.done = true
		_kickoff_pass(taker)


func _kickoff_pass(taker: Footballer) -> void:
	var t: TeamCtl = taker.team
	var best: Footballer = null
	var bd := INF
	for m in t.active():
		if m == taker or m.keeper:
			continue
		var d = m.pos.distance_to(Vector3.ZERO)
		if d < bd and m.pos.x * t.dir < 0.0:
			bd = d
			best = m
	if best == null:
		best = _nearest_of(t, Vector3(-t.dir * 10.0, 0, 0))
	var target := best.pos
	_expect(t, best, target, 10.0)
	_kick(taker, "pass", 0.3, target, _calc_pass.bind(taker, target, "kickoff", 0.01))


func _idle_all() -> void:
	for p in all_players():
		if p.action == "" or p.action in ["hold"]:
			p.desired = Vector3.ZERO
			p.face_point = ball.pos
			p.sprint = false


func _st_dead(dt: float) -> void:
	# players drift back into shape while the ball rolls out
	for t in teams:
		for p in t.active():
			if p.action != "":
				p.desired = p.desired * 0.9
				continue
			var tgt = t.shape_target(p, t == sp.team) if not p.keeper else p.pos
			var d = tgt - p.pos
			p.desired = d.normalized() * min(3.5, d.length()) if d.length() > 0.5 else Vector3.ZERO
			p.face_point = ball.pos
	if state_t > float(sp.get("delay", 1.2)) * (0.3 if headless else 1.0):
		_place_setpiece()


func _place_setpiece() -> void:
	hud.flash(0.5)
	var t: TeamCtl = sp.team
	var o: TeamCtl = t.opp
	var L := stadium.L
	var W := stadium.W
	var R := BallSim.R
	var taker: Footballer = null
	for p in all_players():
		p.cancel_action()
		p.vel = Vector3.ZERO
		p.desired = Vector3.ZERO
		p.stun = 0.0
	if ball.holder:
		ball.holder = null
	ball.held_in_hands = false
	var type: String = sp.type
	var direct := false
	match type:
		"throw":
			ball.place(Vector3(sp.pos.x, R, sp.pos.z))
			_shape_all(t)
			taker = _nearest_non_gk(t, sp.pos)
			taker.pos = Vector3(sp.pos.x, 0, sign(sp.pos.z) * (W + 0.45))
			taker.yaw = atan2(0.0, -sign(sp.pos.z))
			ball.holder = taker
			ball.held_in_hands = true
			taker.play_action("hold", 1.0, 2.0)
			_push_away(o, sp.pos, 3.0)
		"corner":
			var zs: float = sign(sp.pos.z)
			var bx = t.dir * (L - 0.35)
			ball.place(Vector3(bx, R, zs * (W - 0.35)))
			_shape_all(t)
			taker = _best_of(t, "pass", true)
			taker.pos = ball.pos + Vector3(t.dir * 0.7, 0, zs * 0.7)
			taker.face_towards(Vector3(t.dir * (L - 11.0), 0, 0), true)
			_corner_positions(t, o, zs, taker)
		"goalkick":
			ball.place(Vector3(sp.pos.x, R, sp.pos.z))
			_shape_all(t)
			taker = t.keeper()
			if taker == null:
				taker = _nearest_non_gk(t, sp.pos)
			taker.pos = ball.pos - Vector3(t.dir * 1.2, 0, 0)
			taker.face_towards(Vector3(0, 0, 0), true)
			for q in o.active():
				if not q.keeper and in_penalty_area(q.pos, t):
					q.pos.x = -t.dir * (L - 20.0)
		"freekick", "penalty":
			var p: Vector3 = sp.pos
			p.x = clamp(p.x, -L + 0.5, L - 0.5)
			p.z = clamp(p.z, -W + 0.5, W - 0.5)
			var goal = t.opp_goal()
			if type == "penalty":
				var spot_x = t.dir * (L - (6.0 if stadium.is_cage else 11.0))
				ball.place(Vector3(spot_x, R, 0))
				taker = _best_of(t, "shoot", true)
				taker.pos = ball.pos - Vector3(t.dir * 1.4, 0, 1.6)
				taker.face_towards(goal, true)
				_penalty_positions(t, o, taker)
				direct = true
			else:
				ball.place(Vector3(p.x, R, p.z))
				_shape_all(t)
				var d := ball.pos.distance_to(goal)
				direct = not sp.indirect and not stadium.is_cage and d < 32.0 and abs((goal - ball.pos).normalized().x) > 0.5
				taker = _best_of(t, "shoot" if direct else "pass", true)
				var to_goal = (goal - ball.pos).normalized() if direct else Vector3(t.dir, 0, 0)
				taker.pos = ball.pos - to_goal * 1.3 + Vector3(to_goal.z, 0, -to_goal.x) * 1.8
				taker.face_towards(ball.pos + to_goal * 5.0, true)
				_push_away(o, ball.pos, 9.15)
				if direct:
					_build_wall(o, t, d)
		"kickoff":
			_setup_kickoff(t)
			_go_state("kickoff")
			cam.mode = "broadcast"
			cam.snap()
			return
	sp.taker = taker
	sp.direct = direct
	sp.wait = randf_range(0.9, 1.6) if not headless else 0.1
	sp.done = false
	sp.user = t == user_team
	ball.frozen = type != "throw"
	if type == "throw":
		ball.frozen = false
	controls.swipe_mode = false
	_user_dive = {}
	if user_team:
		if sp.user:
			_set_control(taker)
		else:
			_set_control(_nearest_of(user_team, ball.pos) if user_team.active().size() > 0 else null)
	_setpiece_camera(type, direct, t)
	_setpiece_hint()
	_go_state("setpiece")


func _setpiece_camera(type: String, direct: bool, t: TeamCtl) -> void:
	var goal = t.opp_goal()
	if (type == "penalty" or (type == "freekick" and direct)):
		var to_goal = (goal - ball.pos)
		to_goal.y = 0.0
		var dn = to_goal.normalized()
		var cp = ball.pos - dn * 4.4 + Vector3(0, 2.0, 0)
		var look := ball.pos.lerp(goal + Vector3(0, 0.6, 0), 0.62)
		cam.set_fixed(cp, look, 44.0, true)
	elif type == "corner":
		var c := ball.pos
		var cp := c + Vector3(t.dir * 7.0, 7.5, sign(c.z) * 9.0)
		cam.set_fixed(cp, Vector3(t.dir * (stadium.L - 12.0), 0, 0), 50.0, true)
	else:
		cam.mode = "broadcast"
		cam.snap()


func _setpiece_hint() -> void:
	var type: String = sp.type
	if user_team == null:
		return
	if sp.user:
		match type:
			"throw":
				controls.set_labels({"pass": "Throw", "shoot": "Throw", "through": "Long"})
				hud.message("Aim with the stick · tap THROW", 2.5)
			"corner":
				controls.set_labels({"pass": "Cross", "shoot": "Cross", "through": "Short"})
				hud.message("Aim near / far post · tap CROSS", 2.5)
			"goalkick":
				controls.set_labels({"pass": "Short", "shoot": "Long", "through": "Long"})
				hud.message("SHORT to a defender · LONG upfield", 2.5)
			"freekick":
				if sp.direct:
					controls.swipe_mode = true
					controls.set_labels({"pass": "Pass", "shoot": "Shoot", "through": "Through"})
					hud.message("Swipe from the ball to shoot · bend it to curl", 3.0)
				else:
					controls.set_labels({"pass": "Pass", "shoot": "Long", "through": "Through"})
					hud.message("Free kick · pass it", 2.0)
			"penalty":
				controls.swipe_mode = true
				hud.message("Penalty · swipe to shoot", 3.0)
	elif type == "penalty":
		controls.swipe_mode = true
		hud.message("Swipe left, right or up to dive", 3.0)


func _shape_all(t: TeamCtl) -> void:
	for tm in teams:
		for p in tm.active():
			if p.keeper:
				var g = tm.own_goal()
				p.pos = g + Vector3(tm.dir * 1.2, 0, 0)
			else:
				p.pos = tm.shape_target(p, tm == t)
			p.face_towards(ball.pos, true)


func _push_away(o: TeamCtl, pt: Vector3, r: float) -> void:
	for q in o.active():
		var d = q.pos - pt
		d.y = 0.0
		if d.length() < r:
			if d.length() < 0.1:
				d = Vector3(-o.opp.dir, 0, 0.3)
			q.pos = pt + d.normalized() * (r + 0.3)


func _nearest_non_gk(t: TeamCtl, pt: Vector3) -> Footballer:
	var best: Footballer = null
	var bd := INF
	for p in t.active():
		if p.keeper:
			continue
		var d = p.pos.distance_to(pt)
		if d < bd:
			bd = d
			best = p
	return best


func _best_of(t: TeamCtl, stat: String, no_gk: bool) -> Footballer:
	var best: Footballer = null
	var bv := -1
	for p in t.active():
		if no_gk and p.keeper:
			continue
		if int(p.stats[stat]) > bv:
			bv = int(p.stats[stat])
			best = p
	return best


func _corner_positions(t: TeamCtl, o: TeamCtl, zs: float, taker: Footballer) -> void:
	var L := stadium.L
	var att_spots := [Vector3(t.dir * (L - 11.0), 0, 0), Vector3(t.dir * (L - 6.0), 0, zs * 3.0), Vector3(t.dir * (L - 6.5), 0, -zs * 4.0),
		Vector3(t.dir * (L - 4.5), 0, 0.5), Vector3(t.dir * (L - 17.0), 0, zs * 5.0)]
	var def_spots := [Vector3(t.dir * (L - 5.5), 0, zs * 2.5), Vector3(t.dir * (L - 5.5), 0, -zs * 2.5), Vector3(t.dir * (L - 10.5), 0, 1.0),
		Vector3(t.dir * (L - 7.0), 0, -zs * 5.0), Vector3(t.dir * (L - 9.0), 0, zs * 5.5), Vector3(t.dir * (L - 1.0), 0, zs * 4.2)]
	var attackers: Array = []
	for p in t.active():
		if p != taker and not p.keeper and p.role != "DF":
			attackers.append(p)
	for p in t.active():
		if p != taker and not p.keeper and p.role == "DF" and attackers.size() < 5:
			attackers.append(p)
	for i in min(attackers.size(), att_spots.size()):
		attackers[i].pos = att_spots[i] + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
		attackers[i].face_towards(ball.pos, true)
	var defenders: Array = []
	for p in o.active():
		if not p.keeper:
			defenders.append(p)
	defenders.sort_custom(func(a, b): return a.role < b.role)
	for i in min(defenders.size(), def_spots.size()):
		defenders[i].pos = def_spots[i]
		defenders[i].face_towards(ball.pos, true)
	var k = o.keeper()
	if k:
		k.pos = Vector3(t.dir * (L - 0.6), 0, zs * 0.5)
		k.face_towards(ball.pos, true)


func _penalty_positions(t: TeamCtl, o: TeamCtl, taker: Footballer) -> void:
	var L := stadium.L
	var depth := (L - 21.0) if not stadium.is_cage else (L - 10.0)
	var i := 0
	for tm in teams:
		for p in tm.active():
			if p == taker:
				continue
			if p.keeper and tm == o:
				p.pos = Vector3(t.dir * (L - 0.15), 0, 0)
				p.face_towards(Vector3(0, 0, 0), true)
				continue
			if p.keeper:
				p.pos = tm.own_goal() + Vector3(tm.dir * 1.5, 0, 0)
				continue
			p.pos = Vector3(t.dir * (depth - (i % 2) * 2.0), 0, -12.0 + (i * 2.4) if not stadium.is_cage else -8.0 + i * 1.6)
			p.face_towards(ball.pos, true)
			i += 1


func _build_wall(o: TeamCtl, t: TeamCtl, d: float) -> void:
	var n := 2 if d > 28.0 else (3 if d > 22.0 else 4)
	var goal = t.opp_goal()
	var dirv = (goal - ball.pos).normalized()
	var perp := Vector3(-dirv.z, 0, dirv.x)
	var near_post = Vector3(goal.x, 0, sign(ball.pos.z) * stadium.goal_hw) if abs(ball.pos.z) > 1.0 else goal
	var shift: float = sign((near_post - goal).dot(perp)) * 0.4
	var center = ball.pos + dirv * 9.15 + perp * shift
	var wall: Array = []
	for q in o.active():
		if not q.keeper:
			wall.append([q.pos.distance_to(center), q])
	wall.sort_custom(func(a, b): return a[0] < b[0])
	for i in min(n, wall.size()):
		var q: Footballer = wall[i][1]
		q.pos = center + perp * ((i - (n - 1) * 0.5) * 0.58)
		q.pos.y = 0.0
		q.face_towards(ball.pos, true)
		q.set_meta("wall", true)
	var k = o.keeper()
	if k:
		k.pos = Vector3(goal.x - t.dir * 0.4, 0, -sign(ball.pos.z) * 0.8 if abs(ball.pos.z) > 1.0 else 0.0)
		k.face_towards(ball.pos, true)


func _st_setpiece(dt: float) -> void:
	_idle_all()
	var taker: Footballer = sp.get("taker")
	if taker == null:
		return
	if sp.done:
		# watchdog: if the restart never happened (e.g. kicker was interrupted), take it again
		if state_t > float(sp.get("wait", 1.0)) + 4.0 and (ball.frozen or ball.holder == taker) and taker.action == "":
			sp.done = false
			state_t = 0.0
		return
	if sp.type == "throw" and ball.holder == taker:
		taker.desired = Vector3.ZERO
	if sp.user:
		_user_setpiece(taker)
	elif state_t > sp.wait:
		sp.done = true
		_bot_setpiece(taker)


func _bot_setpiece(taker: Footballer) -> void:
	var t: TeamCtl = taker.team
	match sp.type:
		"throw":
			var m := _open_mate(taker, 4.0, 20.0)
			var target: Vector3 = m.pos + m.vel * 0.3 if m else taker.pos + Vector3(t.dir * 8.0, 0, -sign(taker.pos.z) * 6.0)
			_throw_in(taker, m, target)
		"corner":
			var mates: Array = []
			for p in t.active():
				if p != taker and not p.keeper and in_penalty_area(p.pos, t.opp):
					mates.append(p)
			var m = mates[randi() % mates.size()] if mates.size() > 0 else null
			var target: Vector3 = m.pos if m else Vector3(t.dir * (stadium.L - 9.0), 0, 0)
			_cross(taker, m, target)
		"goalkick":
			_goal_kick(taker, randf() < 0.75)
		"freekick":
			if sp.direct:
				var goal = t.opp_goal()
				var zs: float = -sign(ball.pos.z) if abs(ball.pos.z) > 1.0 else (1.0 if randf() < 0.5 else -1.0)
				var target := Vector3(goal.x, randf_range(1.55, 2.15), zs * (stadium.goal_hw - randf_range(0.4, 0.8)))
				var curl: float = -zs * t.dir * randf_range(35.0, 60.0)
				var err: float = TeamCtl.AIM_ERR[t.level] * (1.4 - float(taker.stats.shoot) / 100.0)
				_kick(taker, "kick", 0.45, target, _calc_fk.bind(taker, target, randf_range(23.0, 28.0), Vector3(0, curl, 0), err))
			else:
				var best = t._best_pass(taker, 0.0)
				if best != null:
					ai_pass(taker, best[1], best[2], best[3])
				else:
					ai_clear(taker)
		"penalty":
			var goal = t.opp_goal()
			var zs := 1.0 if randf() < 0.5 else -1.0
			var y := randf_range(0.25, 0.9) if randf() < 0.6 else randf_range(1.2, 2.1)
			var target := Vector3(goal.x, y, zs * (stadium.goal_hw - randf_range(0.45, 1.1)))
			var err: float = TeamCtl.AIM_ERR[t.level] * (1.4 - float(taker.stats.shoot) / 100.0) * 0.6
			_kick(taker, "kick", 0.5, target, _calc_pen.bind(taker, target, randf_range(22.0, 27.0), err))


func _goal_kick(taker: Footballer, short: bool) -> void:
	var t: TeamCtl = taker.team
	var m := _open_mate(taker, 8.0, 26.0) if short else null
	if m:
		ai_pass(taker, m, m.pos, "ground")
		return
	var target := Vector3(clamp(taker.pos.x + t.dir * randf_range(42, 55), -stadium.L + 6, stadium.L - 6), 0, randf_range(-stadium.W * 0.55, stadium.W * 0.55))
	if stadium.is_cage:
		target = Vector3(taker.pos.x + t.dir * 18.0, 0, randf_range(-6, 6))
	_kick(taker, "kick", 0.45, target, _calc_pass.bind(taker, target, "goalkick_long", 0.05))


func _calc_fk(p: Footballer, target: Vector3, speed: float, spin: Vector3, err: float) -> Array:
	var r := _calc_shot(p, target, speed, spin, err)
	r[2] = "freekick"
	_wall_jump(p.team.opp)
	return r


func _calc_pen(p: Footballer, target: Vector3, speed: float, err: float) -> Array:
	var r := _calc_shot(p, target, speed, Vector3.ZERO, err)
	r[2] = "penalty"
	return r


func _wall_jump(o: TeamCtl) -> void:
	for q in o.active():
		if q.has_meta("wall"):
			q.remove_meta("wall")
			q.play_action("header", 0.55, 2.0, Callable(), 1.0, 0.45)


func _open_mate(p: Footballer, dmin: float, dmax: float) -> Footballer:
	var best: Footballer = null
	var bs := -INF
	for m in p.team.active():
		if m == p or m.keeper:
			continue
		var d = m.pos.distance_to(p.pos)
		if d < dmin or d > dmax:
			continue
		var space := 15.0
		for q in p.team.opp.active():
			space = min(space, q.pos.distance_to(m.pos))
		var s = space - d * 0.05 + (m.pos.x - p.pos.x) * p.team.dir * 0.05
		if s > bs:
			bs = s
			best = m
	return best


func _throw_in(taker: Footballer, m, target: Vector3) -> void:
	if m:
		_expect(taker.team, m, target, 10.0)
	taker.play_action("throw", 0.75, 0.62, _do_throw.bind(taker, target), 1.0, 0.35, target)


func _do_throw(taker: Footballer, target: Vector3) -> void:
	ball.held_in_hands = false
	ball.holder = null
	ball.pos = taker.pos + taker.forward() * 0.3 + Vector3(0, 2.0, 0)
	var v := BallSim.lob_velocity(ball.pos, target, 12.0).limit_length(16.0)
	ball.kick(v, Vector3.ZERO, taker, "throw")
	taker.ball_cooldown = 0.6


func _cross(taker: Footballer, m, target: Vector3) -> void:
	if m:
		_expect(taker.team, m, target, 16.0)
	var spin := Vector3(0, -taker.team.dir * sign(ball.pos.z) * 30.0, 0)
	_kick(taker, "cross", 0.45, target, _calc_cross.bind(target, spin))


func _calc_cross(target: Vector3, spin: Vector3) -> Array:
	var v := BallSim.lob_velocity(ball.pos, target + Vector3(0, 0, 0), 26.0, spin)
	return [_apply_error(v, 0.03), spin, "corner"]


func _penalty_keeper_guess() -> void:
	var t: TeamCtl = sp.team
	var k = t.opp.keeper()
	if k == null:
		return
	var left := Vector3(cos(k.yaw), 0, -sin(k.yaw))
	var side := 0.0
	var height := 0.3
	if user_team and t.opp == user_team and not _user_dive.is_empty():
		side = _user_dive.side
		height = _user_dive.height
	else:
		var th := _compute_threat_for_kick(t.opp)
		var correct := 0.0
		if not th.is_empty():
			correct = sign((th.point - k.pos).dot(left))
		var guess_right = 0.36 + t.opp.level * 0.04
		var r := randf()
		if r < guess_right:
			side = correct
		elif r < guess_right + 0.12:
			side = 0.0
		else:
			side = -correct if correct != 0.0 else 1.0
		height = randf_range(0.1, 0.6)
	if side == 0.0:
		k.play_action("catch", 0.6, 2.0)
	else:
		k.dive_vel = left * side * 5.6
		k.play_action("dive", 0.95, 2.0, Callable(), side, height)


func _user_setpiece(taker: Footballer) -> void:
	var aim = controls.move_world(cam)
	var type: String = sp.type
	match type:
		"throw":
			if controls.just_pressed("pass") or controls.just_pressed("shoot") or controls.just_pressed("through"):
				sp.done = true
				var long = controls.just_pressed("through")
				var m := _pick_receiver(taker, aim if aim.length() > 0.2 else Vector3(taker.team.dir, 0, 0), 4.0, 26.0 if long else 18.0)
				var target: Vector3 = m.pos + m.vel * 0.3 if m else taker.pos + (aim if aim.length() > 0.2 else Vector3(0, 0, -sign(taker.pos.z))) * 12.0
				_throw_in(taker, m, target)
		"corner":
			if controls.just_pressed("pass") or controls.just_pressed("shoot"):
				sp.done = true
				var t = taker.team
				var zs: float = sign(ball.pos.z)
				var target := Vector3(t.dir * (stadium.L - 10.0), 0, 0)
				if aim.length() > 0.3:
					var lateral: float = aim.z * -zs
					if lateral < -0.3:
						target = Vector3(t.dir * (stadium.L - 6.0), 0, zs * 3.0)
					elif lateral > 0.3:
						target = Vector3(t.dir * (stadium.L - 6.5), 0, -zs * 4.0)
				var m := _nearest_non_gk_except(t, target, taker)
				_cross(taker, m, target)
			elif controls.just_pressed("through"):
				sp.done = true
				var m := _open_mate(taker, 3.0, 15.0)
				if m:
					ai_pass(taker, m, m.pos, "ground")
		"goalkick":
			if controls.just_pressed("pass"):
				sp.done = true
				_goal_kick(taker, true)
			elif controls.just_pressed("shoot") or controls.just_pressed("through"):
				sp.done = true
				var target := Vector3(taker.pos.x + taker.team.dir * 50.0, 0, (aim.z if aim.length() > 0.2 else 0.0) * 15.0)
				_kick(taker, "kick", 0.45, target, _calc_pass.bind(taker, target, "clear", 0.05))
		"freekick", "penalty":
			if type == "freekick" and not sp.direct:
				if controls.just_pressed("pass") or controls.just_pressed("through"):
					sp.done = true
					_user_pass(taker, aim, false, false)
				elif controls.just_pressed("shoot"):
					sp.done = true
					_user_pass(taker, aim, true, false)
			elif controls.just_pressed("pass") and type == "freekick":
				sp.done = true
				_user_pass(taker, aim, false, false)
			elif controls.held.shoot:
				_charge_t += get_physics_process_delta_time()
				controls.power = min(1.0, _charge_t / 0.9)
			elif controls.just_released("shoot"):
				sp.done = true
				_user_shoot(taker, controls.power, aim, false)
				controls.power = 0.0
				_charge_t = 0.0
		"kickoff":
			pass


func _on_swipe(pts: PackedVector2Array, dur: float) -> void:
	if state == "setpiece" and not sp.get("done", true):
		if sp.user and sp.type in ["freekick", "penalty"] and sp.get("direct", false):
			var goal: Vector3 = sp.team.opp_goal()
			var r = SwipeShot.compute(cam, ball.pos, pts, dur, goal.x, stadium.goal_hw, stadium.goal_h)
			if r.is_empty():
				return
			sp.done = true
			var taker: Footballer = sp.taker
			var err: float = 0.012 + (1.0 - float(taker.stats.shoot) / 100.0) * 0.03
			var kind := "penalty" if sp.type == "penalty" else "freekick"
			_kick(taker, "kick", 0.45, r.target, _calc_swipe.bind(taker, r, err, kind))
		elif not sp.user and sp.type == "penalty":
			var d := pts[pts.size() - 1] - pts[0]
			var cam_right = cam.global_transform.basis.x
			var k: Footballer = sp.team.opp.keeper()
			if k == null:
				return
			var left := Vector3(cos(k.yaw), 0, -sin(k.yaw))
			var screen_side: float = sign(d.x) if abs(d.x) > abs(d.y) * 0.4 else 0.0
			var world_dir = cam_right * screen_side
			_user_dive = {"side": sign(world_dir.dot(left)) if screen_side != 0.0 else 0.0, "height": clamp(-d.y / 200.0, 0.0, 1.0)}
			hud.message("Ready…", 0.8)
	elif state == "shootout":
		_shootout_swipe(pts, dur)


func _calc_swipe(p: Footballer, r: Dictionary, err: float, kind: String) -> Array:
	var v = SwipeShot.velocity(ball.pos, r, err)
	_register_shot(p, shot_xg(p.pos, p.team) if kind != "penalty" else 0.76)
	if kind == "freekick":
		_wall_jump(p.team.opp)
	return [v, r.spin, kind]


func _nearest_non_gk_except(t: TeamCtl, pt: Vector3, ex: Footballer) -> Footballer:
	var best: Footballer = null
	var bd := INF
	for p in t.active():
		if p.keeper or p == ex:
			continue
		var d = p.pos.distance_to(pt)
		if d < bd:
			bd = d
			best = p
	return best


# ================================================================== user input
func user_has_control() -> bool:
	return state == "play"


func _set_control(p) -> void:
	if user_team == null:
		return
	if user_team.controlled and is_instance_valid(user_team.controlled):
		user_team.controlled.set_marker(false)
	user_team.controlled = p
	if p:
		p.set_marker(true)
	_charge_t = 0.0
	controls.power = 0.0


func _auto_switch(force := false) -> void:
	if user_team == null or (_switch_cool > 0.0 and not force):
		return
	var target := ball.pos
	var best: Footballer = null
	var bs := INF
	for p in user_team.active():
		if p.keeper:
			continue
		var d = p.pos.distance_to(target)
		# prefer players between the ball and our goal
		var goal_side: float = (ball.pos.x - p.pos.x) * user_team.dir
		if goal_side > 0.0:
			d -= 2.5
		if d < bs:
			bs = d
			best = p
	if best and best != user_team.controlled:
		_set_control(best)
		_switch_cool = 0.8


func _pick_receiver(p: Footballer, aim: Vector3, dmin := 3.0, dmax := 50.0) -> Footballer:
	var aimn := aim.normalized() if aim.length() > 0.01 else p.forward()
	var best: Footballer = null
	var bs := INF
	for m in p.team.active():
		if m == p:
			continue
		var to = m.pos - p.pos
		to.y = 0.0
		var d = to.length()
		if d < dmin or d > dmax:
			continue
		var ang := acos(clamp(to.normalized().dot(aimn), -1.0, 1.0))
		if ang > deg_to_rad(55.0):
			continue
		var s = ang * 2.2 + d / 35.0 + (0.8 if m.keeper else 0.0)
		if s < bs:
			bs = s
			best = m
	return best


func _user_play(dt: float) -> void:
	var p = user_team.controlled
	if p == null or p.sent_off:
		_auto_switch(true)
		return
	var mv = controls.move_world(cam)
	var has = ball.holder == p
	var we_have = user_team.has_ball()
	# labels
	if has or (ball.holder == null and ball.last_touch and ball.last_touch.team == user_team):
		controls.set_labels({"shoot": "Shoot", "pass": "Pass", "through": "Through", "sprint": "Sprint"})
	else:
		controls.set_labels({"shoot": "Slide", "pass": "Switch", "through": "Tackle", "sprint": "Press"})
	if ball.holder and ball.holder.team == user_team and ball.holder != p:
		_set_control(ball.holder)
		p = ball.holder
		has = true
	if p.keeper and not has:
		_auto_switch(true)
		return
	if not p.busy():
		p.sprint = controls.held.sprint and (mv.length() > 0.2 or not has)
		p.desired = mv * p.max_speed()
		p.face_point = null
		if not has and not we_have and controls.held.sprint and mv.length() < 0.1:
			# press: run at the ball carrier / ball
			var tgt: Vector3 = ball.holder.pos if ball.holder else ball.pos
			var d = tgt - p.pos
			d.y = 0.0
			p.desired = d.normalized() * p.max_speed() if d.length() > 1.2 else Vector3.ZERO
		if not has and mv.length() < 0.1 and not controls.held.sprint:
			p.face_point = ball.pos
	if has and not p.busy():
		if p.keeper:
			if controls.just_pressed("pass") or controls.just_pressed("shoot") or controls.just_pressed("through"):
				keeper_distribute(p)
			return
		if controls.held.shoot:
			_charge_t += dt
			controls.power = min(1.0, _charge_t / 0.9)
		if controls.just_released("shoot"):
			_user_shoot(p, max(controls.power, 0.15), mv, false)
			controls.power = 0.0
			_charge_t = 0.0
		elif controls.just_released("pass"):
			_user_pass(p, mv, controls.hold_t.pass > 0.32, false)
		elif controls.just_pressed("through"):
			_user_through(p, mv, false)
		return
	if not controls.held.shoot:
		controls.power = 0.0
		_charge_t = 0.0
	if ball.holder == null:
		# first-time actions and headers while the ball is coming
		var near := ball.pos.distance_to(p.pos) < 9.0
		var ours: bool = ball.last_touch != null and ball.last_touch.team == user_team
		if near or ours:
			for k in ["shoot", "pass", "through"]:
				if controls.just_pressed(k):
					_queued = {"kind": k, "t": time_now, "power": 0.75, "aim": mv, "lob": false}
		if not ours:
			if controls.just_pressed("pass"):
				_auto_switch(true)
			elif controls.just_pressed("shoot") and ball.pos.distance_to(p.pos) < 5.0:
				try_tackle(p, "slide")
			elif controls.just_pressed("through"):
				try_tackle(p, "stand")
		return
	if not we_have:
		if controls.just_pressed("pass"):
			var cur = user_team.controlled
			var best: Footballer = null
			var bd := INF
			for q in user_team.active():
				if q == cur or q.keeper:
					continue
				var d = q.pos.distance_to(ball.pos)
				if d < bd:
					bd = d
					best = q
			if best:
				_set_control(best)
				_switch_cool = 1.0
		elif controls.just_pressed("shoot"):
			try_tackle(p, "slide")
		elif controls.just_pressed("through"):
			try_tackle(p, "stand")
		if Game.settings.get("auto_switch", true) and mv.length() < 0.1:
			var d_me = p.pos.distance_to(ball.pos)
			for q in user_team.active():
				if q != p and not q.keeper and q.pos.distance_to(ball.pos) + 9.0 < d_me:
					_auto_switch()
					break


func _user_pass(p: Footballer, aim: Vector3, lob: bool, instant: bool) -> void:
	var a := aim if aim.length() > 0.2 else p.forward()
	var m := _pick_receiver(p, a)
	var err: float = 0.015 + (1.0 - float(p.stats.pass) / 100.0) * 0.03
	var target: Vector3
	if m:
		var d := m.pos.distance_to(p.pos)
		target = m.pos + m.vel * clamp(d / 16.0, 0.2, 1.4)
		_expect(p.team, m, target, 14.0)
	else:
		target = p.pos + a.normalized() * (22.0 if lob else 14.0)
	target.x = clamp(target.x, -stadium.L + 1.0, stadium.L - 1.0)
	target.z = clamp(target.z, -stadium.W + 1.0, stadium.W - 1.0)
	var kind := "lob" if lob else "pass"
	_kick(p, "pass" if not lob else "lob", 0.3 if not lob else 0.4, target, _calc_pass.bind(p, target, kind, err), instant)


func _user_through(p: Footballer, aim: Vector3, instant: bool) -> void:
	var t: TeamCtl = p.team
	var a := aim if aim.length() > 0.2 else Vector3(t.dir, 0, 0)
	var best: Footballer = null
	var bs := INF
	for m in t.active():
		if m == p or m.keeper:
			continue
		var to = m.pos - p.pos
		var ahead: float = to.x * t.dir
		if ahead < -2.0 or to.length() > 45.0:
			continue
		var ang := acos(clamp(to.normalized().dot(a.normalized()), -1.0, 1.0))
		var s := ang * 1.8 - ahead * 0.03
		if s < bs:
			bs = s
			best = m
	if best == null:
		_user_pass(p, aim, false, instant)
		return
	var run := (Vector3(t.dir, 0, 0) * 0.7 + a.normalized() * 0.3).normalized()
	var target := best.pos + run * 9.0 + best.vel * 0.4
	target.x = clamp(target.x, -stadium.L + 2.0, stadium.L - 2.0)
	target.z = clamp(target.z, -stadium.W + 1.5, stadium.W - 1.5)
	t._runs[best] = [target, 2.4]
	_expect(t, best, target, 14.0)
	var err: float = 0.02 + (1.0 - float(p.stats.pass) / 100.0) * 0.03
	_kick(p, "pass", 0.3, target, _calc_pass.bind(p, target, "through", err), instant)


func _user_shoot(p: Footballer, power: float, aim: Vector3, instant: bool) -> void:
	var t: TeamCtl = p.team
	var goal = t.opp_goal()
	var hw := stadium.goal_hw
	var zs: float
	if aim.length() > 0.3 and abs(aim.z) > 0.3:
		zs = sign(aim.z)
	elif abs(p.pos.z) > 1.0:
		zs = -sign(p.pos.z)
	else:
		var gk = t.opp.keeper()
		zs = -sign(gk.pos.z) if gk and abs(gk.pos.z) > 0.2 else 1.0
	var y: float = lerp(0.3, stadium.goal_h - 0.35, pow(clamp(power, 0.0, 1.0), 1.4))
	if power > 0.93:
		y = stadium.goal_h + 0.3 + (power - 0.93) * 12.0
	var target := Vector3(goal.x, y, zs * (hw - 0.5))
	var speed: float = lerp(16.0, 32.0, power) if not stadium.is_cage else lerp(14.0, 25.0, power)
	var spin := Vector3.ZERO
	if power > 0.35 and power < 0.8 and abs(p.pos.z) > 6.0 and not stadium.is_cage:
		spin = Vector3(0, -zs * t.dir * 35.0, 0)
	var err: float = 0.018 + (1.0 - float(p.stats.shoot) / 100.0) * 0.05 + _pressure_on(p) * 0.025 + max(0.0, power - 0.8) * 0.08
	if Game.settings.get("aim_assist", true):
		err *= 0.75
	_kick(p, "kick" if not instant else "volley", 0.42, target, _calc_shot.bind(p, target, speed, spin, err), instant)
	Game.haptic(25)


# ================================================================ time & ends
func _check_time() -> void:
	var end: float
	if not extra_time:
		end = half * 2700.0
	else:
		end = 5400.0 + et_half * 900.0
	if clock >= end and added <= 0.0:
		added = clamp(60.0 + _goals_half * 30.0 + _fouls_half * 8.0, 60.0, 300.0) if not extra_time else 60.0
		hud.message("+%d minute%s added" % [int(added / 60.0), "" if added < 120.0 else "s"], 2.0)
	if added > 0.0 and clock >= end + added:
		Sfx.play("whistle_long", 1.0)
		if not extra_time:
			if half == 1:
				_halftime()
			else:
				_end_regulation()
		else:
			if et_half == 1:
				_halftime("End of extra time first half")
			else:
				_end_extra()


func _halftime(title := "Half time") -> void:
	_go_state("halftime")
	controls.reset()
	if headless:
		return
	var lines := ["Shots %d – %d" % [teams[0].st.shots, teams[1].st.shots], "Possession %d%% – %d%%" % _poss_pct()]
	hud.show_halftime(title, teams[0].data.name, teams[1].data.name, lines)


func _on_continue() -> void:
	match state:
		"halftime":
			hud.clear_overlay()
			for t in teams:
				t.dir = -t.dir
			added = 0.0
			_goals_half = 0
			_fouls_half = 0
			if not extra_time:
				half = 2
				clock = 2700.0
			else:
				et_half = 2
				clock = 5400.0 + 900.0
			var kt: TeamCtl = first_kickoff.opp if (half == 2 and not extra_time) or et_half == 2 else first_kickoff
			_setup_kickoff(kt)
			cam.mode = "broadcast"
			cam.snap()
			_go_state("kickoff")
		"fulltime":
			_leave()


func _end_regulation() -> void:
	var draw: bool = teams[0].score == teams[1].score
	if draw and params.get("knockout", false):
		if params.get("extra_time", true) and not headless:
			extra_time = true
			et_half = 1
			clock = 5400.0
			added = 0.0
			clock_mult = 900.0 / (float(params.get("half_minutes", 5)) * 20.0)
			_go_state("halftime")
			hud.show_halftime("Extra time", teams[0].data.name, teams[1].data.name, ["Two halves of 15 minutes. Penalties if it's still level."], "Start extra time")
			et_half = 0
			return
		_start_shootout()
		return
	_finish()


func _end_extra() -> void:
	if teams[0].score == teams[1].score:
		_start_shootout()
	else:
		_finish()


func _poss_pct() -> Array:
	var tot: float = max(0.001, teams[0].st.poss + teams[1].st.poss)
	var a := int(round(teams[0].st.poss / tot * 100.0))
	return [a, 100 - a]


func _finish() -> void:
	finished = true
	_go_state("fulltime")
	controls.visible = false
	Sfx.play("whistle_long")
	if headless:
		return
	var rewards := _apply_results()
	var pct := _poss_pct()
	var stats := [["Possession", pct[0], pct[1], "%"], ["Shots", teams[0].st.shots, teams[1].st.shots, ""],
		["On target", teams[0].st.on_target, teams[1].st.on_target, ""], ["xG", snapped(teams[0].st.xg, 0.1), snapped(teams[1].st.xg, 0.1), ""],
		["Passes", teams[0].st.passes_ok, teams[1].st.passes_ok, ""], ["Corners", teams[0].st.corners, teams[1].st.corners, ""],
		["Fouls", teams[0].st.fouls, teams[1].st.fouls, ""], ["Cards", teams[0].st.yellow + teams[0].st.red, teams[1].st.yellow + teams[1].st.red, ""]]
	var pens := ""
	if not shootout.is_empty():
		pens = "%s win %d – %d on penalties" % [teams[0].data.name if teams[0].pen_score > teams[1].pen_score else teams[1].data.name, max(teams[0].pen_score, teams[1].pen_score), min(teams[0].pen_score, teams[1].pen_score)]
	hud.show_fulltime({"venue": Game.VENUES.get(params.get("venue", "harbor"), {"name": "Arena"}).name, "home": teams[0].data, "away": teams[1].data,
		"score": [teams[0].score, teams[1].score], "scorers_home": _scorers(0), "scorers_away": _scorers(1), "stats": stats,
		"potm": _potm(), "coins": rewards.coins, "pens": pens, "can_highlights": clips.size() > 0})


func _scorers(side: int) -> String:
	var parts: Array = []
	for g in goals_log:
		if g.side == side:
			parts.append("%s %s'%s" % [g.name, g.minute, " (og)" if g.og else (" (pen)" if g.pen else "")])
	return ", ".join(parts)


func rating(p: Footballer) -> float:
	var r := 6.0 + p.m_goals * 1.0 + p.m_assists * 0.6 + p.m_passes_ok * 0.012 - (p.m_passes - p.m_passes_ok) * 0.03 + p.m_tackles * 0.15 + p.m_saves * 0.35 - p.m_fouls * 0.15 + p.m_shots * 0.05
	var t: TeamCtl = p.team
	if t.score > t.opp.score:
		r += 0.4
	elif t.score < t.opp.score:
		r -= 0.3
	if p.keeper:
		r -= t.opp.score * 0.3
	return clamp(r, 4.0, 10.0)


func _potm() -> String:
	var best: Footballer = null
	var br := -1.0
	for p in all_players():
		var r := rating(p)
		if r > br:
			br = r
			best = p
	return "%s · %.1f" % [best.pname, br] if best else "-"


func _apply_results() -> Dictionary:
	if user_team == null:
		return {"coins": 0}
	var us = user_team.score
	var them = user_team.opp.score
	var res := 0 if us == them else (1 if us > them else -1)
	if res == 0 and not shootout.is_empty():
		res = 1 if user_team.pen_score > user_team.opp.pen_score else -1
	var mult: float = [0.6, 0.8, 1.0, 1.25, 1.6][difficulty]
	var coins := int(([150, 250, 400][res + 1] + us * 40) * mult)
	Game.add_coins(coins)
	Game.add_xp(60 + 30 * (res + 1))
	var rec: Dictionary = Game.save.records
	rec.played = int(rec.played) + 1
	if res > 0:
		rec.won = int(rec.won) + 1
	elif res < 0:
		rec.lost = int(rec.lost) + 1
	else:
		rec.drawn = int(rec.drawn) + 1
	rec.gf = int(rec.gf) + us
	rec.ga = int(rec.ga) + them
	if res > 0 and (rec.best_win == "" or us - them > int(rec.get("best_margin", 0))):
		rec.best_win = "%d – %d vs %s" % [us, them, user_team.opp.data.name]
		rec.best_margin = us - them
	if params.get("mode", "quick") in ["league", "cup"]:
		Competition.record_user_result(params, teams[0].score, teams[1].score, teams[0].pen_score, teams[1].pen_score, _scorer_names(user_team.side))
	Game.write_save()
	return {"coins": coins}


func _scorer_names(side: int) -> Array:
	var out: Array = []
	for g in goals_log:
		if g.side == side and not g.og:
			out.append(g.name)
	return out


func _leave() -> void:
	get_tree().paused = false
	Sfx.stop_crowd()
	Game.goto(params.get("return_to", "home"))


func _quit() -> void:
	get_tree().paused = false
	if params.get("mode", "quick") in ["league", "cup"] and not finished and user_team:
		var a := 0 if user_team.side == 0 else 3
		var b := 3 if user_team.side == 0 else 0
		Competition.record_user_result(params, a, b, 0, 0, [])
	Sfx.stop_crowd()
	Game.goto(params.get("return_to", "home"))


func _restart() -> void:
	get_tree().paused = false
	Sfx.stop_crowd()
	Game.main.show_screen("match", params, false)


func pause_game() -> void:
	if finished or state in ["halftime", "fulltime"]:
		return
	get_tree().paused = true
	hud.show_pause(teams[0].data.short, teams[1].data.short)


func resume_game() -> void:
	get_tree().paused = false
	hud.clear_overlay()


func on_back() -> bool:
	if state == "fulltime":
		_leave()
	elif get_tree().paused:
		resume_game()
	else:
		pause_game()
	return true


func on_app_paused() -> void:
	if not get_tree().paused and not finished:
		pause_game()


# ================================================================== shootout
func _start_shootout() -> void:
	_go_state("shootout")
	controls.reset()
	shootout = {"kicks": [0, 0], "first": randi() % 2, "turn": 0, "phase": "setup", "result": "", "t": 0.0, "order": [[], []]}
	for s in 2:
		var arr: Array = []
		for p in teams[s].active():
			if not p.keeper:
				arr.append(p)
		arr.sort_custom(func(a, b): return a.stats.shoot > b.stats.shoot)
		shootout.order[s] = arr
	hud.banner("PENALTIES", "Sudden death after five each", Game.C_CARD, 2.4)


func _shootout_team() -> int:
	return (shootout.first + shootout.turn) % 2


func _st_shootout(dt: float) -> void:
	shootout.t += dt
	match shootout.phase:
		"setup":
			if shootout.t < 1.0:
				return
			var s := _shootout_team()
			var t: TeamCtl = teams[s]
			var o: TeamCtl = t.opp
			# every kick is taken at the +x goal
			t.dir = 1
			o.dir = -1
			var order: Array = shootout.order[s]
			var taker: Footballer = order[shootout.kicks[s] % order.size()]
			sp = {"type": "penalty", "team": t, "taker": taker, "user": t == user_team, "done": false, "direct": true, "wait": 1.2}
			hud.flash(0.5)
			for p in all_players():
				p.cancel_action()
				p.vel = Vector3.ZERO
				p.desired = Vector3.ZERO
			ball.place(Vector3(stadium.L - (6.0 if stadium.is_cage else 11.0), BallSim.R, 0))
			ball.frozen = true
			taker.pos = ball.pos - Vector3(1.4, 0, 1.6)
			taker.face_towards(Vector3(stadium.L, 0, 0), true)
			var k = o.keeper()
			if k:
				k.pos = Vector3(stadium.L - 0.15, 0, 0)
				k.face_towards(Vector3.ZERO, true)
			var i := 0
			for tm in teams:
				for p in tm.active():
					if p == taker or (p.keeper and tm == o):
						continue
					p.pos = Vector3(-2.0 + (i % 2) * 1.5, 0, -12.0 + i * 1.3)
					p.face_towards(ball.pos, true)
					i += 1
			_setpiece_camera("penalty", true, t)
			_user_dive = {}
			controls.swipe_mode = user_team != null
			if user_team:
				hud.message("Swipe to shoot" if t == user_team else "Swipe left, right or up to dive", 3.0)
				_set_control(taker if t == user_team else null)
			shootout.phase = "aim"
			shootout.t = 0.0
			shootout.result = ""
		"aim":
			_idle_all()
			if not sp.user and shootout.t > sp.wait and not sp.done:
				sp.done = true
				_bot_setpiece(sp.taker)
			if sp.done and ball.last_kick_kind == "penalty" and not ball.frozen:
				shootout.phase = "flight"
				shootout.t = 0.0
				_penalty_keeper_guess()
		"flight":
			_check_saves()
			_resolve_ball_shootout()
			var done: bool = shootout.result != "" or shootout.t > 2.6 or (ball.speed() < 0.5 and shootout.t > 1.0)
			if done:
				var s := _shootout_team()
				var scored: bool = shootout.result == "goal"
				if scored:
					teams[s].pen_score += 1
					if not headless:
						Sfx.goal_roar()
					hud.banner("SCORED", sp.taker.pname, Game.C_CARD, 1.4)
				else:
					Sfx.near_miss()
					hud.banner("MISSED", sp.taker.pname, Game.C_AWAY, 1.4)
				shootout.kicks[s] += 1
				shootout.turn += 1
				shootout.phase = "result"
				shootout.t = 0.0
		"result":
			if shootout.t > 1.8:
				if _shootout_decided():
					_finish()
				else:
					shootout.phase = "setup"
					shootout.t = 0.0


func _resolve_ball_shootout() -> void:
	if ball.holder == null:
		return
	ball.holder = null


func _shootout_decided() -> bool:
	var a: int = teams[0].pen_score
	var b: int = teams[1].pen_score
	var ka: int = shootout.kicks[0]
	var kb: int = shootout.kicks[1]
	if ka <= 5 and kb <= 5:
		var rem_a := 5 - ka
		var rem_b := 5 - kb
		if a + rem_a < b or b + rem_b < a:
			return true
		if ka == 5 and kb == 5:
			return a != b
		return false
	return ka == kb and a != b


func _shootout_swipe(pts: PackedVector2Array, dur: float) -> void:
	if shootout.get("phase", "") != "aim" or sp.get("done", true):
		return
	_on_swipe_shootout(pts, dur)


func _on_swipe_shootout(pts: PackedVector2Array, dur: float) -> void:
	if sp.user:
		var r = SwipeShot.compute(cam, ball.pos, pts, dur, stadium.L, stadium.goal_hw, stadium.goal_h)
		if r.is_empty():
			return
		sp.done = true
		var taker: Footballer = sp.taker
		_kick(taker, "kick", 0.45, r.target, _calc_swipe.bind(taker, r, 0.015, "penalty"))
	else:
		var d := pts[pts.size() - 1] - pts[0]
		var k: Footballer = sp.team.opp.keeper()
		if k == null:
			return
		var left := Vector3(cos(k.yaw), 0, -sin(k.yaw))
		var screen_side: float = sign(d.x) if abs(d.x) > abs(d.y) * 0.4 else 0.0
		var world_dir = cam.global_transform.basis.x * screen_side
		_user_dive = {"side": sign(world_dir.dot(left)) if screen_side != 0.0 else 0.0, "height": clamp(-d.y / 200.0, 0.0, 1.0)}
		hud.message("Ready…", 0.8)


# ===================================================================== replays
func _record(dt: float) -> void:
	if headless:
		return
	_rec_acc += dt
	if _rec_acc < 1.0 / REC_HZ:
		return
	_rec_acc -= 1.0 / REC_HZ
	var ps: Array = []
	for p in all_players():
		ps.append(p.snapshot())
	replay_buf.append({"b": ball.pos, "r": Quaternion(ball._rot), "p": ps})
	while replay_buf.size() > int(REPLAY_SECS * REC_HZ):
		replay_buf.pop_front()


func _start_replay(clip: Dictionary, done: Callable) -> void:
	if clip.frames.size() < 10:
		done.call()
		return
	_replay = {"frames": clip.frames, "f": 0.0, "done": done, "side": clip.side}
	for p in all_players():
		p.puppet = true
	controls.visible = false
	hud.set_replay(true)
	hud.flash(0.4)
	_go_state("replay")


func _st_replay(dt: float) -> void:
	var frames: Array = _replay.frames
	_replay.f += dt * REC_HZ * 0.55
	var fi := int(_replay.f)
	if fi >= frames.size() - 1:
		_end_replay()
		return
	var k: float = _replay.f - fi
	var a: Dictionary = frames[fi]
	var b: Dictionary = frames[fi + 1]
	var plist := all_players()
	for i in min(plist.size(), a.p.size()):
		plist[i].apply_snapshot(a.p[i], b.p[i], k, dt)
	var bp: Vector3 = (a.b as Vector3).lerp(b.b, k)
	ball.pos = bp
	ball._rot = Basis((a.r as Quaternion).slerp(b.r, k))
	ball.global_position = bp
	var prog := float(fi) / frames.size()
	var side: int = _replay.side
	if prog < 0.55:
		cam.set_fixed(Vector3(side * (stadium.L + 6.0), 2.4, bp.z * 0.5 + 3.0), bp + Vector3(0, 0.3, 0), 38.0)
	else:
		cam.set_fixed(Vector3(bp.x - side * 7.0, 1.7, (stadium.W + 2.0) if bp.z < stadium.W - 8.0 else bp.z - 10.0), bp + Vector3(0, 0.4, 0), 40.0)
	cam.smooth = 5.0


func _skip_replay() -> void:
	if state == "replay":
		_end_replay()


func _end_replay() -> void:
	for p in all_players():
		p.puppet = false
	hud.set_replay(false)
	controls.visible = user_team != null and not finished
	var done: Callable = _replay.done
	_replay = {}
	done.call()


func _play_highlights() -> void:
	if clips.is_empty():
		return
	hud.clear_overlay()
	_hl_index = 0
	_next_highlight()


func _next_highlight() -> void:
	if _hl_index >= clips.size():
		_go_state("fulltime")
		finished = false
		_finish_overlay_again()
		return
	var c: Dictionary = clips[_hl_index]
	_hl_index += 1
	hud.message(c.title, 2.0)
	_start_replay(c, _next_highlight)


func _finish_overlay_again() -> void:
	finished = true
	var pct := _poss_pct()
	var stats := [["Possession", pct[0], pct[1], "%"], ["Shots", teams[0].st.shots, teams[1].st.shots, ""],
		["On target", teams[0].st.on_target, teams[1].st.on_target, ""], ["xG", snapped(teams[0].st.xg, 0.1), snapped(teams[1].st.xg, 0.1), ""],
		["Passes", teams[0].st.passes_ok, teams[1].st.passes_ok, ""], ["Corners", teams[0].st.corners, teams[1].st.corners, ""],
		["Fouls", teams[0].st.fouls, teams[1].st.fouls, ""], ["Cards", teams[0].st.yellow + teams[0].st.red, teams[1].st.yellow + teams[1].st.red, ""]]
	hud.show_fulltime({"venue": Game.VENUES.get(params.get("venue", "harbor"), {"name": "Arena"}).name, "home": teams[0].data, "away": teams[1].data,
		"score": [teams[0].score, teams[1].score], "scorers_home": _scorers(0), "scorers_away": _scorers(1), "stats": stats,
		"potm": _potm(), "coins": 0, "pens": "", "can_highlights": true})


# ================================================================== physics misc
func _separate() -> void:
	var ps := all_players()
	var n := ps.size()
	for i in n:
		var a: Footballer = ps[i]
		if a.sent_off or a.action in ["dive", "slide", "fall"]:
			continue
		for j in range(i + 1, n):
			var b: Footballer = ps[j]
			if b.sent_off or b.action in ["dive", "slide", "fall"]:
				continue
			var d := b.pos - a.pos
			d.y = 0.0
			var l := d.length()
			if l < 0.72 and l > 0.0001:
				var push := d / l * (0.72 - l) * 0.5
				a.pos -= push
				b.pos += push


const CAGE_D := 6.0


func _in_cage_d(pos: Vector3) -> bool:
	return stadium.is_cage and (Vector2(pos.x - stadium.L, pos.z).length() < CAGE_D or Vector2(pos.x + stadium.L, pos.z).length() < CAGE_D)


func _clamp_players() -> void:
	var mx: float = stadium.L + (4.0 if not stadium.is_cage else -0.35)
	var mz: float = stadium.W + (4.0 if not stadium.is_cage else -0.35)
	for p in all_players():
		if p.sent_off:
			continue
		if stadium.is_cage and not p.keeper and state in ["play", "dead"]:
			# 5-a-side rule: only keepers may stand in the D
			for gx in [stadium.L, -stadium.L]:
				var v := Vector2(p.pos.x - gx, p.pos.z)
				if v.length() < CAGE_D:
					var o := v.normalized() * CAGE_D if v.length() > 0.01 else Vector2(-sign(gx) * CAGE_D, 0)
					p.pos.x = gx + o.x
					p.pos.z = o.y
		p.pos.x = clamp(p.pos.x, -mx - (2.0 if p.keeper else 0.0), mx + (2.0 if p.keeper else 0.0))
		p.pos.z = clamp(p.pos.z, -mz, mz)


func _update_hud() -> void:
	hud.score = [teams[0].score, teams[1].score]
	var c := clock
	if not extra_time:
		var cap := half * 2700.0
		c = min(clock, cap)
		hud.added_text = ("+%d" % int(ceil(added / 60.0))) if clock >= cap and added > 0.0 else ""
	else:
		hud.added_text = ""
	if state == "shootout":
		hud.clock_text = "PENS %d-%d" % [teams[0].pen_score, teams[1].pen_score]
	else:
		hud.clock_text = "%02d:%02d" % [int(c / 60.0), int(fmod(c, 60.0))]
	if user_team and user_team.controlled and state in ["play", "setpiece", "kickoff"] and not finished:
		var p = user_team.controlled
		var sp3 = p.pos + Vector3(0, 2.25, 0)
		if not cam.is_position_behind(sp3):
			hud.tag_pos = cam.unproject_position(sp3)
			hud.tag_text = p.pname.to_upper()
			hud.tag_stamina = p.stamina
		p.set_marker(true, Game.C_CARD, controls.power)
	else:
		hud.tag_text = ""
	hud.show_radar = state in ["play", "kickoff", "setpiece", "dead"]
	controls.show_buttons = state in ["play", "setpiece", "kickoff"] and not finished
	controls.show_joystick = state == "play" or (state == "setpiece" and sp.get("user", false) and not sp.get("direct", false))


func summary() -> Dictionary:
	var pct := _poss_pct()
	return {"shots": [teams[0].st.shots, teams[1].st.shots], "on_target": [teams[0].st.on_target, teams[1].st.on_target],
		"passes": [teams[0].st.passes, teams[1].st.passes], "passes_ok": [teams[0].st.passes_ok, teams[1].st.passes_ok],
		"poss": pct, "corners": [teams[0].st.corners, teams[1].st.corners], "fouls": [teams[0].st.fouls, teams[1].st.fouls],
		"offsides": [teams[0].st.offsides, teams[1].st.offsides], "goals": goals_log.size(), "xg": [snapped(teams[0].st.xg, 0.01), snapped(teams[1].st.xg, 0.01)],
		"tackles": [_sum(teams[0], "m_tackles"), _sum(teams[1], "m_tackles")], "dbg": dbg, "saves": [_sum(teams[0], "m_saves"), _sum(teams[1], "m_saves")]}


func _sum(t: TeamCtl, f: String) -> int:
	var n := 0
	for p in t.players:
		n += int(p.get(f))
	return n
