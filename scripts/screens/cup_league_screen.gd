extends Control
## Cup & League hub: league table + next fixture, cup bracket.

var params := {}
var tab := 0
var _body: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	var c := ColorRect.new()
	c.color = Game.C_NIGHT
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	UI.bg_gradient(self)
	if Competition.cup_active() and not Competition.league_active():
		tab = 1
	var m := UI.safe_margin()
	add_child(m)
	var v := UI.vbox(10)
	m.add_child(v)
	var head := UI.header("Cup & league", func(): Game.main.home())
	head.add_child(UI.spacer())
	head.add_child(UI.seg(["League", "Cup"], tab, func(i): tab = i; _build()))
	v.add_child(head)
	_body = UI.hbox(14)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_body)
	_build()


func _build() -> void:
	for ch in _body.get_children():
		ch.queue_free()
	if tab == 0:
		_league()
	else:
		_cup()


func _league() -> void:
	if not Competition.league_active():
		_empty("League", "Eight clubs, fourteen matchdays, home and away. Finish in the top three to earn a prize.", "Start a season", func(): Competition.new_league(); _build())
		return
	var lg: Dictionary = Game.save.league
	var tp := UI.panel(false)
	tp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tv := UI.vbox(2)
	tp.add_child(tv)
	tv.add_child(_table_row(["#", "Club", "P", "W", "D", "L", "GD", "Pts"], true, false))
	var rows := Competition.table()
	for i in rows.size():
		var r: Dictionary = rows[i]
		tv.add_child(_table_row([str(i + 1), Competition.team_name(r.id), str(r.p), str(r.w), str(r.d), str(r.l), "%+d" % (r.gf - r.ga), str(r.pts)], false, r.id == "user"))
	_body.add_child(tp)
	var side := UI.panel()
	side.custom_minimum_size = Vector2(250, 0)
	var sv := UI.vbox(9)
	side.add_child(sv)
	if lg.done:
		var pos := Competition.user_position()
		sv.add_child(UI.eyebrow("Season %d complete" % int(lg.season), Game.C_CARD))
		sv.add_child(UI.title("You finished " + _ord(pos), 22))
		if pos <= 3:
			sv.add_child(UI.pill("Prize +%d" % Competition.LEAGUE_PRIZE[pos - 1], true))
		var b := UI.button("New season", "primary", Vector2(200, 42), 17)
		b.pressed.connect(func(): Competition.new_league(); _build())
		sv.add_child(b)
	else:
		var fx = Competition.league_user_fixture()
		sv.add_child(UI.eyebrow("Matchday %d of 14" % (int(lg.md) + 1), Game.C_CARD))
		var opp: String = fx[1] if fx[0] == "user" else fx[0]
		sv.add_child(UI.title(("vs " if fx[0] == "user" else "at ") + Competition.team_name(opp), 20))
		sv.add_child(UI.label("Home" if fx[0] == "user" else "Away", 12, "body_m", Game.C_DIM))
		var b := UI.button("Play match", "primary", Vector2(200, 44), 18)
		b.pressed.connect(func(): var rq := Competition.make_request("league"); Game.match_request = rq; Game.goto("match", rq))
		sv.add_child(b)
	sv.add_child(UI.eyebrow("Top scorers"))
	var sc: Dictionary = lg.get("scorers", {})
	var keys := sc.keys()
	keys.sort_custom(func(a, b): return int(sc[a]) > int(sc[b]))
	for i in min(4, keys.size()):
		var parts: PackedStringArray = str(keys[i]).split("|")
		sv.add_child(UI.label("%s · %s  %d" % [parts[0], Competition.team_short(parts[1]), int(sc[keys[i]])], 12, "body_m"))
	_body.add_child(side)


func _table_row(cells: Array, header: bool, me: bool) -> Control:
	var h := UI.hbox(0)
	var widths := [26, 220, 34, 34, 34, 34, 44, 40]
	for i in cells.size():
		var l := UI.label(cells[i], 11 if header else 13, "disp_s" if header else ("body_b" if me else "body_m"), Game.C_DIM if header else (Game.C_CARD if me else Game.C_CHALK), header)
		l.custom_minimum_size = Vector2(widths[i], 20)
		if i >= 2:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(l)
	return h


func _cup() -> void:
	if not Competition.cup_active():
		_empty("Cup", "Eight clubs, straight knockout. Quarter-final, semi-final, final. Draws go to penalties, with extra time in the final.", "Enter the cup", func(): Competition.new_cup(); _build())
		return
	var c: Dictionary = Game.save.cup
	var bp := UI.panel(false)
	bp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := UI.hbox(18)
	bp.add_child(hb)
	for r in 3:
		var col := UI.vbox(8)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(UI.eyebrow(Competition.round_name(r)))
		if r < c.rounds.size():
			var ties: Array = c.rounds[r]
			for k in ties.size():
				var t: Array = ties[k]
				var res = null
				for x in c.results[r]:
					if x[0] == t[0] and x[1] == t[1]:
						res = x
				col.add_child(_tie(t, res))
		else:
			for k in [4, 2, 1][r]:
				col.add_child(UI.label("TBD", 12, "body_m", Game.C_DIM))
		hb.add_child(col)
	_body.add_child(bp)
	var side := UI.panel()
	side.custom_minimum_size = Vector2(240, 0)
	var sv := UI.vbox(9)
	side.add_child(sv)
	if c.done:
		sv.add_child(UI.eyebrow("Cup complete", Game.C_CARD))
		sv.add_child(UI.title(("You won the cup!" if c.winner == "user" else Competition.team_name(c.winner) + " won"), 20))
		if c.winner == "user":
			sv.add_child(UI.pill("Prize +%d" % Competition.CUP_PRIZE, true))
		var b := UI.button("New cup", "primary", Vector2(180, 42), 17)
		b.pressed.connect(func(): Competition.new_cup(); _build())
		sv.add_child(b)
	elif not c.alive:
		sv.add_child(UI.eyebrow("Knocked out", Game.C_AWAY))
		sv.add_child(UI.label("The rest of the cup has been played out.", 13))
		var b := UI.button("New cup", "primary", Vector2(180, 42), 17)
		b.pressed.connect(func(): Competition.new_cup(); _build())
		sv.add_child(b)
	else:
		var t = Competition.cup_user_tie()
		var opp: String = t[1] if t[0] == "user" else t[0]
		sv.add_child(UI.eyebrow(Competition.round_name(int(c.round)), Game.C_CARD))
		sv.add_child(UI.title("vs " + Competition.team_name(opp), 20))
		sv.add_child(UI.label("Win or you're out. Level after 90 minutes goes to penalties%s." % (" after extra time" if int(c.round) == 2 else ""), 12, "body_m", Game.C_DIM))
		var b := UI.button("Play tie", "primary", Vector2(180, 44), 18)
		b.pressed.connect(func(): var rq := Competition.make_request("cup"); Game.match_request = rq; Game.goto("match", rq))
		sv.add_child(b)
	_body.add_child(side)


func _tie(t: Array, res) -> Control:
	var v := UI.vbox(1)
	for i in 2:
		var id: String = t[i]
		var h := UI.hbox(6)
		var me := id == "user"
		var l := UI.label(Competition.team_short(id), 14, "disp", Game.C_CARD if me else Game.C_CHALK, true)
		l.custom_minimum_size.x = 50
		h.add_child(l)
		if res != null:
			var g := str(res[2 + i])
			if res[2] == res[3]:
				g += " (%d)" % res[4 + i]
			h.add_child(UI.label(g, 13, "body_b"))
		v.add_child(h)
	return v


func _empty(title: String, text: String, btn: String, cb: Callable) -> void:
	var p := UI.panel()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(12)
	p.add_child(v)
	v.add_child(UI.title(title, 26))
	var l := UI.label(text, 14)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 420
	v.add_child(l)
	var b := UI.button(btn, "primary", Vector2(220, 44), 18)
	b.pressed.connect(cb)
	v.add_child(b)
	_body.add_child(p)


func _ord(n: int) -> String:
	var suf := "th"
	if n % 100 < 11 or n % 100 > 13:
		suf = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return str(n) + suf
