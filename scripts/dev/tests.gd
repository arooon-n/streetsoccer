extends Node
## Dev test runner.  godot --headless --path . -- --test <suite>
## Suites: parse (compile every script), physics, solver, levels, sim (bot-vs-bot match)

var args: Array = []
var _fail := 0


func _ready() -> void:
	var suite: String = args[0] if args.size() > 0 else "parse"
	match suite:
		"parse":
			_parse_all("res://scripts")
		"physics":
			_physics()
		"solver":
			_solver()
		"levels":
			await _levels()
		"sim":
			await _sim(args)
		"cheese":
			_levels_cheese()
		"tune":
			_tune()
		"herobot":
			await _herobot(args)
		"tune1":
			_tune1(args[1])
		"drillbot":
			await _drillbot(args)
		"perf":
			_perf()
		"userplay":
			await _userplay(args)
	print("TESTS DONE failures=", _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		_fail += 1
		print("  FAIL ", msg)


func _parse_all(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var p := dir + "/" + f
		if d.current_is_dir():
			_parse_all(p)
		elif f.ends_with(".gd"):
			var s = load(p)
			check(s != null and s.can_instantiate(), "compiles " + p)
		f = d.get_next()
	for sh in ["pitch", "crowd", "led_board", "net", "glow_sprite", "ball", "player"]:
		var shader = load("res://shaders/%s.gdshader" % sh)
		check(shader != null, "shader " + sh)


func _physics() -> void:
	BallSim.wet = false
	# ground pass: should travel roughly 30 m and stop
	var s := [Vector3(0, BallSim.R, 0), Vector3(15, 0, 0), Vector3.ZERO]
	var t := 0.0
	while t < 20.0:
		BallSim.step(s, BallSim.DT)
		t += BallSim.DT
	var d: float = s[0].x
	print("  15 m/s ground pass rolls ", snapped(d, 0.1), " m")
	check(d > 30.0 and d < 75.0, "ground pass distance realistic")
	# a driven shot with side spin should curl
	var s2 := [Vector3(0, BallSim.R, 0), Vector3(26, 3.5, 0), Vector3(0, 60, 0)]
	t = 0.0
	while t < 1.0:
		BallSim.step(s2, BallSim.DT)
		t += BallSim.DT
	print("  curl after 1 s: z=", snapped(s2[0].z, 0.01), " x=", snapped(s2[0].x, 0.1))
	check(abs(s2[0].z) > 1.0 and abs(s2[0].z) < 8.0, "side spin produces 1-8 m of bend")
	var sp := BallSim.ground_pass_speed(20.0, 5.0)
	var tt := BallSim.roll_time(sp, 20.0)
	print("  20 m pass speed ", snapped(sp, 0.1), " time ", snapped(tt, 0.01))
	check(sp > 8.0 and sp < 16.0, "pass speed for 20 m sensible")


func _solver() -> void:
	var from := Vector3(30, BallSim.R, 5)
	var target := Vector3(52.5, 2.0, -3.0)
	for spin in [Vector3.ZERO, Vector3(0, 55, 0), Vector3(0, -55, 0)]:
		var v := BallSim.solve(from, target, 27.0, spin)
		check(v != Vector3.ZERO, "solver finds shot spin=%s" % spin)
		var pts := BallSim.simulate(from, v, spin, 2.0, 1.0 / 240.0)
		var best := INF
		for p in pts:
			best = min(best, p.distance_to(target))
		print("    closest approach ", snapped(best, 0.01))
		check(best < 0.35, "trajectory passes within 35 cm of target")
	var lob := BallSim.lob_velocity(Vector3(0, BallSim.R, 0), Vector3(35, 0, 10), 35.0)
	var land := BallSim._landing(Vector3(0, BallSim.R, 0), lob, Vector3.ZERO)
	print("  lob lands at ", land)
	check(land.distance_to(Vector3(35, BallSim.R, 10)) < 1.0, "lob lands within 1 m")


func _levels() -> void:
	var hl = load("res://scripts/modes/hero_levels.gd")
	if hl == null:
		check(false, "hero levels script")
		return
	var levels: Array = hl.all_levels()
	check(levels.size() == 60, "60 hero levels defined (got %d)" % levels.size())
	var solver = load("res://scripts/modes/hero_solver.gd").new()
	var ok := 0
	for lv in levels:
		var r: bool = solver.solvable(lv)
		if r:
			ok += 1
		else:
			print("    unsolvable: ", lv.id, " ", lv.title)
	check(ok == levels.size(), "all levels solvable (%d/%d)" % [ok, levels.size()])


func _sim(a: Array) -> void:
	var fmt: String = a[1] if a.size() > 1 else "11"
	Game.match_request = {"mode": "quick", "home": Game.make_team("hcf"), "away": Game.make_team("rbr"),
		"user_side": -1, "format": fmt, "difficulty": 3, "half_minutes": 3,
		"venue": "cage" if fmt == "5" else "harbor", "time": "night", "weather": "clear", "offside": true, "headless_test": true}
	Game.choose_kits(Game.match_request.home, Game.match_request.away)
	var m = load("res://scripts/match/match.gd").new()
	m.params = Game.match_request
	add_child(m)
	Engine.time_scale = 4.0
	var t0 := Time.get_ticks_msec()
	var frames := 0
	while not m.finished and Time.get_ticks_msec() - t0 < 200000:
		await get_tree().create_timer(1.0).timeout
		frames += 1
		if frames % 10 == 0:
			print("  real ", frames, "s  sim ", snapped(m.time_now, 0.1), "  fps ", Engine.get_frames_per_second())
	Engine.time_scale = 1.0
	print("  final: ", m.teams[0].score, "-", m.teams[1].score, " stats=", m.summary())
	check(m.finished, "match reached full time")
	var total_shots: int = m.teams[0].st.shots + m.teams[1].st.shots
	check(total_shots >= 4, "bots create chances (shots=%d)" % total_shots)
	check(m.teams[0].st.passes + m.teams[1].st.passes > 40, "bots pass the ball")


func _levels_cheese() -> void:
	var cheap := 0
	for lv in HeroLevels.all_levels():
		if int(lv.par) <= 1:
			continue
		var l2: Dictionary = lv.duplicate()
		l2.par = 1
		var sv := HeroSolver.new()
		if sv.solvable(l2):
			cheap += 1
			print("    one-shot solvable: ", lv.id, " ", lv.kind, " ", sv.solution, " att=", lv.attackers[0], " def=", lv.defenders)
	print("  cheese count ", cheap)
	for id in ["3-6", "4-6", "4-7", "4-13"]:
		var lv = HeroLevels.level(id)
		print("  ", id, " att=", lv.attackers, " def=", lv.defenders)



func _tune() -> void:
	var fixes := {}
	for c in 4:
		for n in 15:
			var found := -1
			for off in 120:
				if _level_ok(HeroLevels._make(c, n, off)):
					found = off
					break
			var id := "%d-%d" % [c + 1, n + 1]
			if found < 0:
				print("  NO SEED FOR ", id)
			elif found > 0:
				fixes[id] = found
	print("SEED_FIX := ", JSON.stringify(fixes))


func _userplay(a: Array) -> void:
	var fmt: String = a[1] if a.size() > 1 else "11"
	var home := Game.make_team("user")
	var away := Game.make_team("rbr")
	Game.choose_kits(home, away)
	Game.match_request = {"mode": "quick", "home": home, "away": away, "user_side": 0, "format": fmt, "difficulty": 1,
		"half_minutes": 3, "venue": "cage" if fmt == "5" else "harbor", "time": "night", "weather": "clear", "offside": true, "headless_test": true}
	var m = load("res://scripts/match/match.gd").new()
	m.params = Game.match_request
	add_child(m)
	Engine.time_scale = 3.0
	var t0 := Time.get_ticks_msec()
	var user_kicks := 0
	var user_shots := 0
	var switches := 0
	var kickoffs := 0
	var last_ctrl = null
	var hold := 0
	while not m.finished and Time.get_ticks_msec() - t0 < 150000:
		await get_tree().physics_frame
		var c: Controls = m.controls
		var p = m.user_team.controlled
		if p != last_ctrl:
			switches += 1
			last_ctrl = p
		if m.state == "kickoff" and m.sp.get("user", false) and not m.sp.done:
			c._press("pass")
			kickoffs += 1
			continue
		if m.state == "setpiece" and m.sp.get("user", false) and not m.sp.done:
			c._press("pass")
			continue
		if m.state != "play" or p == null:
			c.move = Vector2.ZERO
			continue
		if m.ball.holder == p:
			# dribble toward goal, then shoot when close
			var goal: Vector3 = m.user_team.opp_goal()
			var d: Vector3 = goal - p.pos
			c.move = Vector2(d.x, d.z).normalized()
			if p.pos.distance_to(goal) < 22.0:
				if hold == 0:
					c._press("shoot")
				hold += 1
				if hold > 9:
					c._release("shoot")
					hold = 0
					user_shots += 1
			elif randf() < 0.01:
				c._press("pass")
				c._release("pass")
				user_kicks += 1
		else:
			hold = 0
			var tgt: Vector3 = m.ball.pos - p.pos
			c.move = Vector2(tgt.x, tgt.z).normalized() if tgt.length() > 1.0 else Vector2.ZERO
			if randf() < 0.004:
				c._press("through")
	Engine.time_scale = 1.0
	print("  user final ", m.teams[0].score, "-", m.teams[1].score, " user shots tried=", user_shots, " passes tried=", user_kicks, " kickoffs=", kickoffs, " switches=", switches, " stats=", m.summary())
	check(m.finished, "user match reaches full time")
	check(kickoffs >= 1, "user can kick off")
	check(m.teams[0].st.shots >= 1, "user team registers shots")
	check(switches >= 3, "control switches between players")


func _perf() -> void:
	for v in ["harbor", "oldground", "cage"]:
		var t0 := Time.get_ticks_usec()
		var s := Stadium.new()
		add_child(s)
		s.build(v, "night", "clear")
		print("  build %s: %.0f ms" % [v, (Time.get_ticks_usec() - t0) / 1000.0])
		s.queue_free()
	var t1 := Time.get_ticks_usec()
	PlayerModel._mesh = null
	PlayerModel.shared_mesh()
	print("  player mesh: %.0f ms, verts=%d" % [(Time.get_ticks_usec() - t1) / 1000.0, PlayerModel.shared_mesh().surface_get_array_len(0)])
	var t2 := Time.get_ticks_usec()
	Sfx.ensure_crowd()
	print("  crowd audio synth: %.0f ms" % [(Time.get_ticks_usec() - t2) / 1000.0])



func _herobot(a: Array) -> void:
	var ids: Array = a.slice(1) if a.size() > 1 else ["1-1", "1-2", "1-4", "1-5", "2-7", "3-8"]
	ids.erase("passfirst")
	var wins := 0
	for id in ids:
		var lv := HeroLevels.level(id)
		var sv := HeroSolver.new()
		sv.prefer_pass = args.has("passfirst")
		if not sv.solvable(lv):
			sv.prefer_pass = false
			if not sv.solvable(lv):
				check(false, "solver " + id)
				continue
		var hm = load("res://scripts/modes/hero_mode.gd").new()
		hm.params = {"level": id}
		add_child(hm)
		await get_tree().process_frame
		await get_tree().process_frame
		var att: Array = []
		for x in lv.attackers:
			att.append(Vector3(x[0], 0, x[1]))
		var carrier := int(lv.carrier)
		for mv in sv.solution:
			while hm.phase != "aim" and hm.phase != "done":
				await get_tree().process_frame
			if hm.phase == "done":
				break
			var from: Vector3 = hm.attackers[hm.carrier].pos
			var pts := PackedVector3Array()
			if mv[0] == "pass":
				var to: Vector3 = hm.attackers[mv[1]].pos
				pts = HeroSim.curve(from, to, mv[2], 16)
			else:
				var tgt := Vector3(HeroSim.GOAL_X, mv[2], mv[1])
				print("      intended shot ", mv, " from ", from)
				pts = HeroSim.curve(from, Vector3(HeroSim.GOAL_X - 0.6, 0, mv[1]), mv[3], 16)
				pts.append(tgt)
			var before: int = hm.moves
			if mv[0] == "pass":
				var cp := HeroSim.curve(from + Vector3(0.55, 0, 0), hm.attackers[mv[1]].pos, mv[2])
				var ln := HeroSim.path_length(cp)
				var lf := HeroSim.lift(HeroSim.resample(cp), "lob" if ln > HeroSim.LOB_LEN else "ground")
				var rr := HeroSim.run(lf, HeroSim.LOB_SPEED if ln > HeroSim.LOB_LEN else HeroSim.PASS_SPEED, hm.def_pos, float(lv.react), float(lv.def_speed), 0.8, 1.4, 0.22 if ln > HeroSim.LOB_LEN else 0.0)
				print("      SOLVER pass len=%.1f cut=%d bend=%s" % [ln, rr.cut, mv[2]])
			await _drag(hm.cam, pts, mv[0] == "shot")
			await get_tree().create_timer(0.1).timeout
			if hm.moves == before:
				print("      move not taken: ", mv, " phase=", hm.phase, " hint=", hm._hint.text, " carrier=", hm.carrier, " start_screen=", hm.cam.unproject_position(from + Vector3(0, 0.9, 0)))
		var t0 := Time.get_ticks_msec()
		while hm.phase != "done" and Time.get_ticks_msec() - t0 < 8000:
			await get_tree().process_frame
		var won: bool = hm._done_reason == "goal"
		if won:
			wins += 1
		print("    level %s: %s (moves=%d)" % [id, "GOAL" if won else "fail " + hm._done_reason, hm.moves])
		hm.queue_free()
		await get_tree().process_frame
	check(wins == ids.size(), "hero levels completed through touch input (%d/%d)" % [wins, ids.size()])


func _win(v: Vector2) -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var ws := Vector2(DisplayServer.window_get_size())
	return v * (ws / vp)


func _drag(cam: Camera3D, pts: PackedVector3Array, shot: bool) -> void:
	var first := _win(cam.unproject_position(pts[0] + Vector3(0, 0.9, 0)))
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = true
	ev.position = first
	Input.parse_input_event(ev)
	await get_tree().process_frame
	for i in range(1, pts.size()):
		var p: Vector3 = pts[i]
		var sp := _win(cam.unproject_position(p))
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = sp
		Input.parse_input_event(d)
		await get_tree().process_frame
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = _win(cam.unproject_position(pts[pts.size() - 1]))
	Input.parse_input_event(up)
	await get_tree().process_frame


func _tune1(id: String) -> void:
	var parts := id.split("-")
	var c := int(parts[0]) - 1
	var n := int(parts[1]) - 1
	for off in 120:
		var lv := HeroLevels._make(c, n, off)
		if HeroSolver.new().solvable(lv):
			if lv.kind in ["cross", "switch", "square"]:
				var ps := HeroSolver.new()
				ps.prefer_pass = true
				if not ps.solvable(lv) or ps.solution.is_empty() or ps.solution[0][0] != "pass":
					continue
			if lv.kind in ["one_two", "through", "counter"]:
				var l2: Dictionary = lv.duplicate()
				l2.par = 1
				if HeroSolver.new().solvable(l2):
					continue
			print("TUNE1 ", id, " ", off)
			return
	print("TUNE1 ", id, " none")


func _drillbot(a: Array) -> void:
	var list: Array = a.slice(1) if a.size() > 1 else ["freekick", "penalty", "shooting", "keeper", "corner", "dribble"]
	Engine.time_scale = 2.0
	for d in list:
		var dm = load("res://scripts/modes/drill_mode.gd").new()
		dm.params = {"drill": d}
		add_child(dm)
		await get_tree().process_frame
		var t0 := Time.get_ticks_msec()
		var acted_round := -1
		var gate := 0
		while dm.phase != "done" and Time.get_ticks_msec() - t0 < 120000:
			await get_tree().physics_frame
			match d:
				"dribble":
					var k: Footballer = dm.kicker
					var tgt := Vector3(40, 0, 0)
					if dm._gates_passed < dm.cones.size():
						var c: MeshInstance3D = dm.cones[dm._gates_passed]
						tgt = Vector3(c.position.x + 1.0, 0, -sign(c.position.z) * 1.6)
					var dv := tgt - k.pos
					var sp: Vector2 = dm.cam.unproject_position(k.pos + dv) - dm.cam.unproject_position(k.pos)
					dm.controls.move = sp.normalized() if dv.length() > 0.3 else Vector2.ZERO
					if dm._gates_passed >= dm.cones.size() and k.pos.x > 30.0:
						dm.controls._press("shoot")
						dm.controls._release("shoot")
				_:
					if dm.round != acted_round and (dm.phase == "aim" or (d == "keeper" and dm.phase == "flight")) and dm.phase_t > 0.4:
						if d == "shooting" and dm.kicker.pos.distance_to(dm.ball.pos) > 1.6:
							continue
						if d == "corner" and dm._corner.get("stage", "") == "header":
							pass
						elif d == "corner" and dm._corner.get("stage", "") != "cross":
							continue
						acted_round = dm.round
						var b: Vector2 = dm.cam.unproject_position(dm.ball.pos)
						var goal_c: Vector2 = dm.cam.unproject_position(Vector3(dm.stadium.L, 1.6, randf_range(-2.8, 2.8)))
						var pts := PackedVector2Array()
						if d == "corner" and dm._corner.stage == "cross":
							goal_c = dm.cam.unproject_position(Vector3(dm.stadium.L - 7.0, 0, randf_range(-3, 3)))
						for i in 8:
							var u := i / 7.0
							pts.append(b.lerp(goal_c, u * 0.6) + Vector2(sin(u * PI) * 25.0, 0))
						dm.controls.swiped.emit(pts, 0.18)
					if d == "corner" and dm._corner.get("stage", "") == "header":
						var b2: Vector2 = dm.cam.unproject_position(dm.ball.pos)
						var g2: Vector2 = dm.cam.unproject_position(Vector3(dm.stadium.L, 1.0, 1.5))
						dm.controls.swiped.emit(PackedVector2Array([b2, b2.lerp(g2, 0.5), g2]), 0.15)
		var info: Dictionary = dm.INFO[d]
		print("    drill %s: phase=%s score=%s timer=%.1f goals=%d saves=%d" % [d, dm.phase, dm.score, dm._timer, dm._goals, dm._saves])
		check(dm.phase == "done", "drill %s finishes" % d)
		Engine.time_scale = 1.0
		dm.queue_free()
		await get_tree().process_frame
		Engine.time_scale = 2.0
	Engine.time_scale = 1.0



## Tuning rule: solvable within par; cross/switch/square have a pass-first route;
## one-two/through/counter cannot be won with a single shot.
func _level_ok(lv: Dictionary) -> bool:
	if not HeroSolver.new().solvable(lv):
		return false
	if lv.kind in ["cross", "switch", "square"]:
		var ps := HeroSolver.new()
		ps.prefer_pass = true
		if not ps.solvable(lv) or ps.solution.is_empty() or ps.solution[0][0] != "pass":
			return false
	if lv.kind in ["one_two", "through", "counter"]:
		var l2: Dictionary = lv.duplicate()
		l2.par = 1
		if HeroSolver.new().solvable(l2):
			return false
	return true
