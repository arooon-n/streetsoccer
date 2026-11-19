extends Node
## Quick match setup: teams, kits, difficulty, length, venue, time, weather, offside.

var params := {}
var root: Control
var fmt := "11"
var opp_index := 1
var user_kit := "home"
var opp_kit := "home"
var difficulty := 2
var halves := 5
var venue := "harbor"
var tod := "night"
var weather := "clear"
var offside := true
var _opp_box: VBoxContainer
var _user_box: VBoxContainer
var _opts: GridContainer
var _venue_seg: Seg
var _venue_ids: Array = []


func _ready() -> void:
	difficulty = int(Game.settings.difficulty)
	halves = int(Game.settings.half_minutes)
	offside = bool(Game.settings.offside)
	var others := _opponents()
	opp_index = randi() % others.size()
	var bd := MenuBackdrop.new()
	add_child(bd)
	var layer := CanvasLayer.new()
	add_child(layer)
	root = UI.screen_root()
	layer.add_child(root)
	root.add_child(_blur())
	var m := UI.safe_margin()
	root.add_child(m)
	var v := UI.vbox(10)
	m.add_child(v)
	var head := UI.header("Quick match", Game.back)
	head.add_child(UI.spacer())
	head.add_child(UI.seg(["11 v 11", "5-a-side cage"], 0, _on_format))
	v.add_child(head)
	var vs := UI.hbox(10)
	vs.alignment = BoxContainer.ALIGNMENT_CENTER
	vs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_user_box = UI.vbox(4)
	_user_box.custom_minimum_size = Vector2(250, 0)
	_opp_box = UI.vbox(4)
	_opp_box.custom_minimum_size = Vector2(250, 0)
	vs.add_child(_user_box)
	vs.add_child(_vs_mark())
	vs.add_child(_opp_box)
	v.add_child(vs)
	var bottom := UI.hbox(10)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	var panel := UI.panel(false)
	panel.pad = 10
	_opts = GridContainer.new()
	_opts.columns = 4
	_opts.add_theme_constant_override("h_separation", 8)
	_opts.add_theme_constant_override("v_separation", 7)
	panel.add_child(_opts)
	bottom.add_child(panel)
	bottom.add_child(UI.spacer())
	var ko := UI.button("Kick off", "primary", Vector2(150, 54), 22)
	ko.icon_name = "next"
	ko.size_flags_vertical = Control.SIZE_SHRINK_END
	ko.pressed.connect(_kick_off)
	bottom.add_child(ko)
	v.add_child(bottom)
	_build_teams()
	_build_opts()


func _blur() -> ColorRect:
	var c := ColorRect.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	var s := Shader.new()
	s.code = "shader_type canvas_item; uniform sampler2D sc : hint_screen_texture, filter_linear_mipmap; void fragment(){ vec3 c = textureLod(sc, SCREEN_UV, 3.5).rgb; COLOR = vec4(c * 0.38, 1.0); }"
	m.shader = s
	c.material = m
	return c


func _opponents() -> Array:
	var out: Array = []
	for t in Game.TEAMS:
		if t.id != Game.save.club.base:
			out.append(t)
	return out


func _vs_mark() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(80, 80)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.draw.connect(_draw_vs.bind(c))
	return c


func _draw_vs(c: Control) -> void:
	c.draw_line(Vector2(40, -30), Vector2(40, 110), Game.C_LINE, 2.0)
	c.draw_circle(Vector2(40, 40), 36, Color(0.02, 0.055, 0.067, 1.0))
	c.draw_arc(Vector2(40, 40), 36, 0, TAU, 40, Game.C_LINE2, 2.0, true)
	var f := UI.font("disp_x")
	c.draw_string(f, Vector2(24, 50), "VS", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Game.C_CHALK)


func _build_teams() -> void:
	for c in _user_box.get_children():
		c.queue_free()
	for c in _opp_box.get_children():
		c.queue_free()
	var club: Dictionary = Game.save.club
	_team_card(_user_box, club.name, club.short, Color(club.crest.c1), Color(club.crest.c2), Competition.team_ovr("user"), "You",
		[club.home, club.away], user_kit, func(k): user_kit = k; _build_teams(), false)
	var o: Dictionary = _opponents()[opp_index]
	_team_card(_opp_box, o.name, o.short, Color(o.crest[0]), Color(o.crest[1]), int(o.ovr), "Bot",
		[o.home, o.away], opp_kit, func(k): opp_kit = k; _build_teams(), true)


func _team_card(box: VBoxContainer, name: String, short: String, c1: Color, c2: Color, ovr: int, who: String, kits: Array, sel: String, on_kit: Callable, cycle: bool) -> void:
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var top := UI.hbox(8)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	if cycle:
		var prev := UI.icon_button("back", "Previous opponent")
		prev.pressed.connect(func(): opp_index = (opp_index - 1 + _opponents().size()) % _opponents().size(); opp_kit = "home"; _build_teams())
		top.add_child(prev)
	var cr := Crest.new().setup(c1, c2, short)
	cr.custom_minimum_size = Vector2(80, 88)
	top.add_child(cr)
	if cycle:
		var nxt := UI.icon_button("next", "Next opponent")
		nxt.pressed.connect(func(): opp_index = (opp_index + 1) % _opponents().size(); opp_kit = "home"; _build_teams())
		top.add_child(nxt)
	box.add_child(top)
	var n := UI.label(name, 22, "disp_x", Game.C_CHALK, true)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(n)
	var o := UI.label("OVR %d · %s" % [ovr, who], 13, "disp", Game.C_DIM, true)
	o.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(o)
	var kr := UI.hbox(6)
	kr.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 2:
		var k: Array = kits[i]
		var kid := "home" if i == 0 else "away"
		var sw := GDButton.new()
		sw.style = "custom"
		sw.custom_minimum_size = Vector2(36, 24)
		sw.selected = sel == kid
		sw.draw.connect(_draw_swatch.bind(sw, Color(k[0]), Color(k[1]), sel == kid))
		sw.pressed.connect(on_kit.bind(kid))
		kr.add_child(sw)
	box.add_child(kr)


func _draw_swatch(sw: Control, a: Color, b: Color, on: bool) -> void:
	var r := Rect2(Vector2(4, 4), sw.size - Vector2(8, 8))
	sw.draw_rect(r, a)
	sw.draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.7), Vector2(r.size.x, r.size.y * 0.3)), b)
	sw.draw_rect(r, Game.C_CARD if on else Game.C_LINE2, false, 2.0 if on else 1.0)


func _row(label: String, ctl: Control) -> void:
	var l := UI.label(label, 12, "disp_s", Game.C_DIM, true)
	_opts.add_child(l)
	_opts.add_child(ctl)


func _build_opts() -> void:
	for c in _opts.get_children():
		c.queue_free()
	_row("Difficulty", UI.seg(["Amateur", "Semi-pro", "Pro", "World class", "Legend"], difficulty, func(i): difficulty = i))
	_row("Halves", UI.seg(["3 min", "5 min", "8 min"], [3, 5, 8].find(halves) if [3, 5, 8].has(halves) else 1, func(i): halves = [3, 5, 8][i]))
	_venue_ids = ["cage"] if fmt == "5" else ["harbor", "oldground"]
	var names: Array = []
	for vid in _venue_ids:
		var info: Dictionary = Game.VENUES[vid]
		names.append(info.name if Game.is_unlocked("venues", vid) else info.name + " · locked")
	if not venue in _venue_ids:
		venue = _venue_ids[0]
	_venue_seg = UI.seg(names, _venue_ids.find(venue), _on_venue)
	_row("Venue", _venue_seg)
	_row("Kick-off", UI.seg(["Day", "Dusk", "Night"], ["day", "dusk", "night"].find(tod), func(i): tod = ["day", "dusk", "night"][i]))
	_row("Weather", UI.seg(["Clear", "Rain"], 1 if weather == "rain" else 0, func(i): weather = ["clear", "rain"][i]))
	if fmt == "11":
		_row("Offside", UI.seg(["On", "Off"], 0 if offside else 1, func(i): offside = i == 0))
	else:
		_row("Rules", UI.label("Ball off the walls · no offside", 12, "body_m", Game.C_DIM))


func _on_format(i: int) -> void:
	fmt = ["11", "5"][i]
	venue = "cage" if fmt == "5" else "harbor"
	_build_opts()


func _on_venue(i: int) -> void:
	var vid: String = _venue_ids[i]
	if not Game.is_unlocked("venues", vid):
		var cost: int = Game.VENUES[vid].cost
		UI.toast(root, "%s unlocks in the Kit room for %d coins" % [Game.VENUES[vid].name, cost], Game.C_CARD, 2.2)
		_venue_seg.set_index(_venue_ids.find(venue))
		return
	venue = vid


func _kick_off() -> void:
	var o: Dictionary = _opponents()[opp_index]
	var home := Game.make_team("user", user_kit)
	var away := Game.make_team(o.id, opp_kit)
	# avoid kit clashes automatically
	var hc := Color(home.kit[0])
	var ac := Color(away.kit[0])
	if Vector3(hc.r - ac.r, hc.g - ac.g, hc.b - ac.b).length() < 0.3:
		away.kit_name = "away" if opp_kit == "home" else "home"
		away.kit = away[away.kit_name]
	Game.settings.difficulty = difficulty
	Game.settings.half_minutes = halves
	Game.settings.offside = offside
	Game.write_settings()
	Game.match_request = {"mode": "quick", "home": home, "away": away, "user_side": 0, "format": fmt, "difficulty": difficulty,
		"half_minutes": halves, "venue": venue, "time": tod, "weather": weather, "offside": offside, "return_to": "home"}
	Game.goto("match", Game.match_request)
