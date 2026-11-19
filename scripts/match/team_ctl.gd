class_name TeamCtl
extends RefCounted
## One team: players, formation shape, and the AI that drives every non-user player.

const FORMATIONS := {
	"4-3-3": [[0.03, 0.0, "GK"], [0.22, 0.72, "DF"], [0.17, 0.25, "DF"], [0.17, -0.25, "DF"], [0.22, -0.72, "DF"],
		[0.36, 0.0, "MF"], [0.44, 0.42, "MF"], [0.44, -0.42, "MF"], [0.66, 0.7, "FW"], [0.72, 0.0, "FW"], [0.66, -0.7, "FW"]],
	"4-4-2": [[0.03, 0.0, "GK"], [0.22, 0.72, "DF"], [0.17, 0.25, "DF"], [0.17, -0.25, "DF"], [0.22, -0.72, "DF"],
		[0.42, 0.72, "MF"], [0.38, 0.22, "MF"], [0.38, -0.22, "MF"], [0.42, -0.72, "MF"], [0.68, 0.2, "FW"], [0.68, -0.2, "FW"]],
	"3-5-2": [[0.03, 0.0, "GK"], [0.18, 0.45, "DF"], [0.16, 0.0, "DF"], [0.18, -0.45, "DF"],
		[0.44, 0.8, "MF"], [0.36, 0.25, "MF"], [0.32, 0.0, "MF"], [0.36, -0.25, "MF"], [0.44, -0.8, "MF"], [0.68, 0.2, "FW"], [0.68, -0.2, "FW"]],
	"5s": [[0.04, 0.0, "GK"], [0.24, 0.0, "DF"], [0.48, 0.62, "MF"], [0.48, -0.62, "MF"], [0.72, 0.0, "FW"]],
}

# difficulty tables (index 0 Amateur .. 4 Legend)
const REACT := [0.5, 0.38, 0.28, 0.2, 0.14]
const DECIDE := [0.7, 0.5, 0.36, 0.26, 0.18]
const AIM_ERR := [0.11, 0.08, 0.055, 0.04, 0.028]
const PRESSERS := [1, 1, 1, 2, 2]
const TACKLE_RATE := [0.5, 0.8, 1.1, 1.4, 1.8]
const SHOOT_TH := [0.14, 0.11, 0.09, 0.075, 0.065]
const GK_REACH := [0.82, 0.9, 1.0, 1.06, 1.12]

var mt = null
var side := 0
var data: Dictionary
var kit: Dictionary
var players: Array = []
var dir := 1
var score := 0
var pen_score := 0
var is_user := false
var formation: Array = []
var opp: TeamCtl
var controlled: Footballer = null
var chaser: Footballer = null
var level := 2                 # difficulty index for this team's AI
var st := {"shots": 0, "on_target": 0, "xg": 0.0, "passes": 0, "passes_ok": 0, "corners": 0, "fouls": 0, "yellow": 0, "red": 0, "offsides": 0, "poss": 0.0}
var _decide_t := 0.0
var _runs := {}                # Footballer -> [target Vector3, time_left]
var _run_cool := 0.0
var _tackle_cool := {}
var expect = null              # {p: Footballer, target: Vector3, until: float}
var _gk_hold := 0.0
var _gk_threat_t := -1.0


func setup(m, s: int, d: Dictionary, user: bool, fmt: String) -> void:
	mt = m
	side = s
	data = d
	is_user = user
	kit = Game.kit_colors(d.kit)
	var fname: String = "5s" if fmt == "5" else ["4-3-3", "4-4-2", "3-5-2"][abs(hash(d.get("id", ""))) % 3]
	if user:
		fname = "5s" if fmt == "5" else "4-3-3"
	formation = FORMATIONS[fname]


func L() -> float:
	return mt.stadium.L


func W() -> float:
	return mt.stadium.W


func own_goal() -> Vector3:
	return Vector3(-dir * L(), 0, 0)


func opp_goal() -> Vector3:
	return Vector3(dir * L(), 0, 0)


func active() -> Array:
	var out: Array = []
	for p in players:
		if not p.sent_off:
			out.append(p)
	return out


func keeper() -> Footballer:
	for p in players:
		if p.keeper and not p.sent_off:
			return p
	return null


func has_ball() -> bool:
	var h = mt.ball.holder
	return h != null and h.team == self


## World position for a normalized formation slot (x 0 = own goal line .. 1 = opponent goal line).
func slot_world(xn: float, zn: float) -> Vector3:
	return Vector3(dir * (xn * 2.0 * L() - L()), 0, zn * W() * dir)


func kickoff_positions(kicking: bool) -> void:
	var i := 0
	for p in players:
		if p.sent_off:
			continue
		var f: Array = formation[p.idx]
		var xn: float = f[0] * 0.95
		xn = min(xn, 0.47)
		var t := slot_world(xn, f[1])
		if kicking and p.role == "FW" and abs(f[1]) < 0.3:
			t = Vector3(-dir * 0.4, 0, 0.1)
		elif kicking and p == _second_kicker():
			t = Vector3(-dir * 0.9, 0, 2.0 * dir)
		p.pos = t
		p.vel = Vector3.ZERO
		p.yaw = atan2(dir, 0.0)
		p.desired = Vector3.ZERO
		p.cancel_action()
		i += 1


func _second_kicker() -> Footballer:
	var best: Footballer = null
	var bd := INF
	for p in active():
		if p.keeper or (p.role == "FW" and abs(formation[p.idx][1]) < 0.3):
			continue
		var d: float = abs(formation[p.idx][1]) + (1.0 - formation[p.idx][0])
		if p.role in ["FW", "MF"] and d < bd:
			bd = d
			best = p
	return best


func kickoff_taker() -> Footballer:
	for p in active():
		if p.role == "FW" and abs(formation[p.idx][1]) < 0.3:
			return p
	var best: Footballer = null
	for p in active():
		if not p.keeper:
			best = p
	return best


# ====================================================================== AI tick
func tick(dt: float) -> void:
	var ball: Ball = mt.ball
	var holder = ball.holder
	var we_have: bool = holder != null and holder.team == self
	var they_have: bool = holder != null and holder.team == opp
	_run_cool -= dt
	if we_have:
		st.poss += dt
	elif holder == null and ball.last_touch != null and ball.last_touch.team == self:
		st.poss += dt
	chaser = null
	if holder == null and not ball.frozen:
		chaser = mt.best_interceptor(self)
	var press: Array = []
	if they_have:
		press = _pressers(holder)
	var marks := {}
	if they_have or (holder == null and not _ball_ours()):
		marks = _assign_marks(press)
	for p in players:
		if p.sent_off:
			continue
		if p.keeper:
			_keeper(p, dt)
			continue
		if is_user and p == controlled:
			continue
		if p.busy():
			p.desired = Vector3.ZERO if p.action in ["fall", "dejected"] else p.desired
			continue
		p.face_point = null
		p.sprint = false
		if p == holder:
			_holder(p, dt)
		elif p == chaser:
			_chase(p)
		elif expect != null and expect.p == p and mt.time_now < expect.until:
			# meet the ball where it is actually going, not where it was aimed
			var tgt: Vector3 = mt.intercept_point(p) if mt.ball.holder == null and mt._icpt.has(p) else expect.target
			_go(p, tgt, true)
			p.face_point = ball.pos
		elif we_have or (holder == null and _ball_ours()):
			_support(p, dt, holder)
		elif they_have:
			if p in press:
				_press(p, holder, dt)
			elif marks.has(p):
				_go(p, marks[p], false)
				p.face_point = ball.pos
			else:
				_go(p, shape_target(p, false), false)
				p.face_point = ball.pos
		else:
			_go(p, shape_target(p, false).lerp(Vector3(ball.pos.x, 0, ball.pos.z), 0.12), false)
			p.face_point = ball.pos


func _ball_ours() -> bool:
	var lt = mt.ball.last_touch
	return lt != null and lt.team == self


func _go(p: Footballer, target: Vector3, urgent: bool) -> void:
	if mt.cage_mode() and not p.keeper:
		for gx in [L(), -L()]:
			var v := Vector2(target.x - gx, target.z)
			if v.length() < 6.3:
				var o := v.normalized() * 6.3 if v.length() > 0.01 else Vector2(-sign(gx) * 6.3, 0)
				target = Vector3(gx + o.x, 0, o.y)
	var d := target - p.pos
	d.y = 0.0
	var dist := d.length()
	if dist < 0.35:
		p.desired = Vector3.ZERO
		return
	var spd := p.max_speed()
	p.sprint = urgent and dist > 3.0
	if p.sprint:
		spd = p.max_speed()
	elif dist < 4.0:
		spd = min(spd, dist * 1.4 + 0.6)
	p.desired = d / dist * spd


## Target position from the team shape.
func shape_target(p: Footballer, in_poss: bool) -> Vector3:
	var f: Array = formation[p.idx]
	var bx: float = mt.ball.pos.x * dir
	var bp: float = clamp((bx + L()) / (2.0 * L()), 0.0, 1.0)
	var line: float
	var span: float
	if in_poss:
		line = lerp(0.1, 0.5, bp)
		span = 0.95
	else:
		line = lerp(0.06, 0.36, bp)
		span = 0.62
	var xn: float = line + (f[0] - 0.17) * span
	if p.role == "DF":
		xn = min(xn, 0.58)
	xn = clamp(xn, 0.05, 0.93)
	var zw: float = 0.95 if in_poss else 0.66
	var t := slot_world(xn, f[1] * zw)
	t.z += mt.ball.pos.z * (0.15 if in_poss else 0.32)
	t.z = clamp(t.z, -W() + 1.5, W() - 1.5)
	if in_poss and p.role in ["FW", "MF"]:
		var ol := offside_line_x()
		if t.x * dir > ol - 1.0:
			t.x = (ol - 1.0) * dir
	return t


## Position (x * dir) of the opponents' second-last player; attackers beyond it are offside.
func offside_line_x() -> float:
	var xs: Array = []
	for q in opp.active():
		xs.append(q.pos.x * dir)
	xs.sort()
	var line: float = xs[xs.size() - 2] if xs.size() >= 2 else L()
	line = max(line, 0.0)
	line = max(line, mt.ball.pos.x * dir)
	return line


func _support(p: Footballer, dt: float, holder) -> void:
	var t := shape_target(p, true)
	var ball_pos: Vector3 = mt.ball.pos
	# forward runs in behind
	if _runs.has(p):
		var r: Array = _runs[p]
		r[1] -= dt
		if r[1] <= 0.0:
			_runs.erase(p)
		else:
			_go(p, r[0], true)
			p.face_point = null
			return
	if holder != null and p.role in ["FW", "MF"] and _run_cool <= 0.0 and not mt.cage_mode():
		var prog: float = (holder.pos.x * dir + L()) / (2.0 * L())
		if prog > 0.3 and randf() < dt * (1.3 if p.role == "FW" else 0.3):
			var line := offside_line_x()
			if p.pos.x * dir < line and p.pos.x * dir > line - 12.0:
				var tgt := Vector3((line + randf_range(7.0, 13.0)) * dir, 0, clamp(p.pos.z * 0.6 + randf_range(-5, 5), -W() + 3, W() - 3))
				tgt.x = clamp(tgt.x, -L() + 4, L() - 4)
				_runs[p] = [tgt, 1.6]
				_run_cool = 1.2
	# short support angle for the two nearest
	if holder != null:
		var near := _nearest_to(holder.pos, 2, [holder])
		if p in near:
			var away = (p.pos - holder.pos)
			away.y = 0.0
			if away.length() < 0.5:
				away = Vector3(0, 0, 1)
			var ang := atan2(away.z, away.x)
			var desired_d := 11.0 if not mt.cage_mode() else 6.5
			var sup = holder.pos + Vector3(cos(ang), 0, sin(ang)) * desired_d + Vector3(dir * 3.0, 0, 0)
			t = t.lerp(sup, 0.55)
	t.x = clamp(t.x, -L() + 1.0, L() - 1.0)
	t.z = clamp(t.z, -W() + 1.0, W() - 1.0)
	_go(p, t, false)
	p.face_point = ball_pos


func _nearest_to(pt: Vector3, n: int, exclude: Array) -> Array:
	var arr: Array = []
	for p in active():
		if p.keeper or p in exclude:
			continue
		arr.append([p.pos.distance_squared_to(pt), p])
	arr.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for i in min(n, arr.size()):
		out.append(arr[i][1])
	return out


func _pressers(holder: Footballer) -> Array:
	var n: int = PRESSERS[level]
	if is_user:
		n = 1
	var ex: Array = []
	if is_user and controlled != null:
		ex.append(controlled)
	return _nearest_to(holder.pos, n, ex)


func _press(p: Footballer, holder: Footballer, dt: float) -> void:
	var goal := own_goal()
	var to_goal := (goal - holder.pos)
	to_goal.y = 0.0
	var goalside := holder.pos + to_goal.normalized() * 1.1
	var d := p.pos.distance_to(holder.pos)
	p.face_point = holder.pos
	if d > 3.5:
		_go(p, goalside, true)
		return
	# jockey and tackle
	var spd: float = min(p.max_speed(), 3.6)
	var dd := goalside - p.pos
	dd.y = 0.0
	p.desired = dd.limit_length(spd)
	var cool: float = _tackle_cool.get(p, 0.0) - dt
	_tackle_cool[p] = cool
	if d < 1.55 and cool <= 0.0:
		var rate: float = TACKLE_RATE[level] * (0.8 if is_user else 1.0)
		if randf() < rate * dt:
			_tackle_cool[p] = 1.6 - level * 0.18
			var slide := randf() < 0.12 and d > 1.1
			mt.try_tackle(p, "slide" if slide else "stand")


func _assign_marks(press: Array) -> Dictionary:
	var out := {}
	var taken := {}
	var goal := own_goal()
	for p in active():
		if p.keeper or p in press or (is_user and p == controlled):
			continue
		if p.role == "FW" and not mt.cage_mode():
			continue
		var home := shape_target(p, false)
		var best = null
		var bd := 13.0 if not mt.cage_mode() else 7.0
		for q in opp.active():
			if q.keeper or taken.has(q) or q == mt.ball.holder:
				continue
			var d = q.pos.distance_to(home)
			if d < bd and q.pos.x * dir < home.x * dir + 14.0:
				bd = d
				best = q
		if best != null:
			taken[best] = true
			var g = (goal - best.pos)
			g.y = 0.0
			var mark: Vector3 = best.pos + g.normalized() * 1.7
			var tgt: Vector3 = home.lerp(mark, 0.65)
			if p.role == "DF" and tgt.x * dir > home.x * dir:
				tgt.x = home.x
			out[p] = tgt
	return out


func _chase(p: Footballer) -> void:
	var pt: Vector3 = mt.intercept_point(p)
	_go(p, pt, true)
	p.face_point = null


# ================================================================ ball holder
func _holder(p: Footballer, dt: float) -> void:
	_decide_t -= dt
	if _decide_t > 0.0 and p.desired.length() > 0.1:
		_dribble_step(p)
		return
	_decide_t = DECIDE[level] * randf_range(0.8, 1.25)
	var goal := opp_goal()
	var d_goal := p.pos.distance_to(goal)
	var pressure := _pressure(p)
	# 1. shoot?
	var xg: float = mt.shot_xg(p.pos, self)
	var max_range: float = 30.0 if not mt.cage_mode() else 15.0
	var th: float = SHOOT_TH[level] * (0.8 if pressure > 0.6 else 1.0)
	var far: float = 18.0 if not mt.cage_mode() else 9.0
	if d_goal > far:
		# from distance only with a clear sight of goal or when closed down
		th = max(th, 0.13) if pressure < 0.6 else th * 1.1
	if d_goal < max_range and xg > th:
		mt.ai_shoot(p)
		return
	# occasional long-range effort from good strikers with space
	if d_goal < 27.0 and d_goal > 17.0 and pressure < 0.45 and float(p.stats.shoot) > 70.0 and randf() < 0.12 and not mt.cage_mode():
		mt.ai_shoot(p)
		return
	# wide in the final third: cross into the box
	if not mt.cage_mode() and abs(p.pos.z) > W() * 0.55 and (p.pos.x * dir) > L() - 26.0 and randf() < 0.55:
		var box: Array = []
		for m in active():
			if m != p and not m.keeper and mt.in_penalty_area(m.pos, opp):
				box.append(m)
		if box.size() > 0:
			var m: Footballer = box[randi() % box.size()]
			mt.ai_cross(p, m)
			return
	# 2. carry the ball into space, pass forward, or pass out of pressure
	var best = _best_pass(p, pressure)
	var space_ahead := _space_ahead(p)
	if best != null:
		var fwd_gain: float = (best[2].x - p.pos.x) * dir
		var take_pass := false
		var held_for: float = mt.time_now - float(p.get_meta("got_ball", mt.time_now))
		if pressure > 0.7:
			take_pass = true
		elif held_for < 0.7:
			take_pass = false
		elif fwd_gain > 10.0 and best[0] > 0.7:
			take_pass = true
		elif space_ahead < 2.5 and best[0] > 0.3:
			take_pass = true
		elif pressure > 0.45 and best[0] > 0.45:
			take_pass = true
		elif randf() < 0.06 and best[0] > 0.8:
			take_pass = true
		if take_pass:
			mt.ai_pass(p, best[1], best[2], best[3])
			return
	# 3. clear when stuck in own third
	var prog: float = (p.pos.x * dir + L()) / (2.0 * L())
	if pressure > 0.85 and prog < 0.25 and best == null:
		mt.ai_clear(p)
		return
	_dribble_step(p)


func _pressure(p: Footballer) -> float:
	var nd := INF
	for q in opp.active():
		nd = min(nd, q.pos.distance_to(p.pos))
	return clamp(1.0 - (nd - 1.0) / 5.0, 0.0, 1.0)


func _space_ahead(p: Footballer) -> float:
	var ahead := Vector3(dir, 0, 0)
	var space := 14.0
	for q in opp.active():
		var rel = q.pos - p.pos
		if rel.dot(ahead) > -0.5 and abs(rel.z) < 5.0:
			space = min(space, rel.length())
	return space


func _dribble_score(p: Footballer, pressure: float) -> float:
	var ahead := Vector3(dir, 0, 0)
	var space := 12.0
	for q in opp.active():
		var rel = q.pos - p.pos
		if rel.dot(ahead) > 0.0 and abs(rel.z) < 4.0:
			space = min(space, rel.length())
	var prog: float = (p.pos.x * dir + L()) / (2.0 * L())
	return 0.25 + space * 0.06 - pressure * 0.55 + (0.12 if p.role == "FW" else 0.0) - prog * 0.1


func _dribble_step(p: Footballer) -> void:
	var goal := opp_goal()
	var to_goal := (goal - p.pos)
	to_goal.y = 0.0
	var dv := to_goal.normalized()
	# avoid defenders in front
	for q in opp.active():
		var rel = q.pos - p.pos
		rel.y = 0.0
		var dist = rel.length()
		if dist < 6.0 and rel.dot(dv) > 0.0:
			var side := Vector3(-dv.z, 0, dv.x)
			var s: float = -sign(rel.dot(side)) if abs(rel.dot(side)) > 0.05 else (1.0 if p.pos.z < 0.0 else -1.0)
			dv += side * s * (6.0 - dist) / 6.0 * 1.3
	# stay inside the pitch
	if abs(p.pos.z) > W() - 4.0:
		dv.z -= sign(p.pos.z) * 0.8
	dv = dv.normalized()
	var space := _dribble_score(p, _pressure(p))
	p.sprint = space > 0.6 and p.stamina > 0.3
	p.desired = dv * p.max_speed()
	p.face_point = null


## Returns [score, receiver, target, kind] or null.
func _best_pass(p: Footballer, pressure: float):
	var best = null
	var best_s := -INF
	var cage: bool = mt.cage_mode()
	for m in active():
		if m == p:
			continue
		if m.keeper and pressure < 0.7:
			continue
		var lead: Vector3 = m.vel * 0.45
		var target: Vector3 = m.pos + lead
		target.x = clamp(target.x, -L() + 1.5, L() - 1.5)
		target.z = clamp(target.z, -W() + 1.0, W() - 1.0)
		var dist := p.pos.distance_to(target)
		if dist < 4.0 or dist > (45.0 if not cage else 22.0):
			continue
		var kind := "ground"
		var lane := _lane_safety(p.pos, target)
		if lane < 1.4 and dist > 22.0 and not cage and _receiver_space(m) > 5.0:
			kind = "lob"
			lane = _receiver_space(m) * 0.5
		var space := _receiver_space(m)
		var prog: float = (target.x - p.pos.x) * dir
		# offside check: avoid passing to offside players
		if not cage and prog > 0.0 and m.pos.x * dir > offside_line_x() + 0.2:
			continue
		var s: float = prog * 0.06 + min(space, 8.0) * 0.05 + min(lane, 4.0) * 0.18 - dist * 0.01
		if lane < 1.2:
			s -= 1.0
		if space < 2.0:
			s -= 0.4
		if prog < -5.0 and pressure < 0.5:
			s -= 0.35
		if (target.x * dir) > L() - 30.0:
			s += 0.25
		if m.role == "FW":
			s += 0.06
		if _runs.has(m):
			# through ball into the run
			var run_t: Vector3 = _runs[m][0]
			var tb: Vector3 = m.pos + (run_t - m.pos).normalized() * 7.0
			var lane2 := _lane_safety(p.pos, tb)
			if lane2 > 1.6:
				var s2: float = (tb.x - p.pos.x) * dir * 0.05 + lane2 * 0.2 + 0.25
				if s2 > s:
					s = s2
					target = tb
					kind = "through"
		s += randf_range(-0.15, 0.15) * (1.0 - level * 0.18)
		if s > best_s:
			best_s = s
			best = [s, m, target, kind]
	if best != null and best[0] < 0.1 - pressure * 0.4:
		return null
	return best


## How safe a pass lane is: (defender arrival time - ball arrival time) for the most dangerous
## opponent, scaled to metres-ish (x5). Positive = the ball gets there first.
func _lane_safety(a: Vector3, b: Vector3) -> float:
	var ab := b - a
	ab.y = 0.0
	var len := ab.length()
	if len < 0.1:
		return 9.0
	var dirv := ab / len
	var v_ball := 12.0
	var m := 9.0
	for q in opp.active():
		var rel: Vector3 = q.pos - a
		rel.y = 0.0
		var along: float = clamp(rel.dot(dirv), 0.0, len)
		var perp: float = (rel - dirv * along).length()
		var t_ball: float = along / v_ball
		var t_def: float = 0.25 + max(0.0, perp - 0.8) / 6.5
		m = min(m, (t_def - t_ball) * 5.0 + 0.6)
	return m


func _receiver_space(m: Footballer) -> float:
	var nd := 20.0
	for q in opp.active():
		nd = min(nd, q.pos.distance_to(m.pos))
	return nd


# ===================================================================== keeper
func _keeper(p: Footballer, dt: float) -> void:
	var ball: Ball = mt.ball
	var goal := own_goal()
	var bd := ball.pos.distance_to(goal)
	p.ready_amt = clamp(1.0 - (bd - 12.0) / 20.0, 0.0, 1.0)
	if is_user and p == controlled and mt.user_has_control():
		return
	if p.busy():
		return
	p.sprint = false
	# holding the ball
	if ball.holder == p:
		p.desired = Vector3.ZERO
		_gk_hold += dt
		if _gk_hold > randf_range(1.4, 2.2) and mt.state == "play":
			_gk_hold = 0.0
			mt.keeper_distribute(p)
		return
	_gk_hold = 0.0
	# shot / dangerous ball coming
	var threat: Dictionary = mt.goal_threat(self)
	if not threat.is_empty():
		if _gk_threat_t < 0.0:
			_gk_threat_t = mt.time_now
		var react: float = REACT[level] * (0.7 if not mt.cage_mode() else 0.45)
		if mt.time_now - _gk_threat_t >= react:
			mt.keeper_react(p, threat, GK_REACH[level] if not is_user else 1.04)
			return
		p.ready_amt = 1.0
		p.desired = Vector3.ZERO
		return
	else:
		_gk_threat_t = -1.0
	# claim loose balls in the box / 1v1
	var in_box: bool = mt.in_penalty_area(ball.pos, self)
	var cage: bool = mt.cage_mode()
	if ball.holder == null and in_box and (cage or mt.best_interceptor(self) == p):
		_go(p, mt.intercept_point(p), true)
		return
	var h = ball.holder
	if h != null and h.team == opp and in_box and h.pos.distance_to(goal) < (13.0 if not cage else 3.5):
		_go(p, h.pos + (goal - h.pos).normalized() * 1.0, true)
		if p.pos.distance_to(h.pos) < 1.6:
			mt.try_tackle(p, "smother")
		return
	# positioning on the arc between ball and goal centre
	var to_ball := ball.pos - goal
	to_ball.y = 0.0
	var depth: float = clamp(0.6 + bd * 0.07, 0.6, 4.0 if not mt.cage_mode() else 1.8)
	if bd > 40.0:
		depth = 7.0 if not mt.cage_mode() else 2.0
	var t := goal + to_ball.normalized() * depth
	t.z = clamp(t.z, -mt.stadium.goal_hw - 0.4, mt.stadium.goal_hw + 0.4)
	if t.x * dir < -L() + 0.4:
		t.x = (-L() + 0.4) * dir
	_go(p, t, bd < 20.0)
	p.face_point = ball.pos
