extends Control
## Club editor: name, short name, crest builder, home/away kits, player names.

const PALETTE := ["0E2238", "3FB8E6", "E5493C", "F4F1EA", "1A1A1A", "F6D23A", "1F7A4D", "7B2242", "8FCBEA", "F08A24", "5B2C83", "2346B8", "2E9E5B", "C7CBC4"]
const PATTERNS := ["Plain", "Stripes", "Hoops", "Sash", "Halves"]

var params := {}
var tab := 0
var _body: VBoxContainer
var _crest: Crest


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	var c := ColorRect.new()
	c.color = Game.C_NIGHT
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	UI.bg_gradient(self)
	var m := UI.safe_margin()
	add_child(m)
	var v := UI.vbox(10)
	m.add_child(v)
	var head := UI.header("Club", _save_back)
	head.add_child(UI.spacer())
	head.add_child(UI.seg(["Identity", "Home kit", "Away kit", "Squad"], tab, func(i): tab = i; _build()))
	v.add_child(head)
	var row := UI.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	var left := UI.vbox(8)
	left.custom_minimum_size = Vector2(170, 0)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	_crest = Crest.new()
	_crest.custom_minimum_size = Vector2(120, 132)
	_crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(_crest)
	var preview := Control.new()
	preview.custom_minimum_size = Vector2(170, 70)
	preview.draw.connect(_draw_kits.bind(preview))
	left.add_child(preview)
	row.add_child(left)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(sc)
	_body = UI.vbox(10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_body)
	_build()


func _club() -> Dictionary:
	return Game.save.club


func _refresh() -> void:
	var cl := _club()
	_crest.setup(Color(cl.crest.c1), Color(cl.crest.c2), cl.short, int(cl.crest.get("shape", 0)), int(cl.crest.get("pattern", 1)))
	queue_redraw()
	get_tree().call_group("kitprev", "queue_redraw")


func _draw_kits(c: Control) -> void:
	if not c.is_in_group("kitprev"):
		c.add_to_group("kitprev")
	var cl := _club()
	for i in 2:
		var k: Array = cl.home if i == 0 else cl.away
		_shirt(c, Vector2(20 + i * 80, 4), Color(k[0]), Color(k[1]), int(k[2]), Color(k[3]))


func _shirt(c: Control, o: Vector2, a: Color, b: Color, pat: int, shorts: Color) -> void:
	var pts := PackedVector2Array([o + Vector2(16, 0), o + Vector2(34, 0), o + Vector2(50, 10), o + Vector2(44, 20), o + Vector2(40, 16), o + Vector2(40, 46), o + Vector2(10, 46), o + Vector2(10, 16), o + Vector2(6, 20), o + Vector2(0, 10)])
	c.draw_colored_polygon(pts, a)
	var stripes: Array = []
	match pat:
		1:
			for i in 3:
				stripes.append(PackedVector2Array([o + Vector2(14 + i * 9, 0), o + Vector2(18 + i * 9, 0), o + Vector2(18 + i * 9, 46), o + Vector2(14 + i * 9, 46)]))
		2:
			for i in 3:
				stripes.append(PackedVector2Array([o + Vector2(0, 12 + i * 11), o + Vector2(50, 12 + i * 11), o + Vector2(50, 17 + i * 11), o + Vector2(0, 17 + i * 11)]))
		3:
			stripes.append(PackedVector2Array([o + Vector2(36, 0), o + Vector2(44, 6), o + Vector2(16, 46), o + Vector2(8, 40)]))
		4:
			stripes.append(PackedVector2Array([o + Vector2(25, 0), o + Vector2(50, 0), o + Vector2(50, 46), o + Vector2(25, 46)]))
	for s in stripes:
		for poly in Geometry2D.intersect_polygons(s, pts):
			c.draw_colored_polygon(poly, b)
	c.draw_rect(Rect2(o + Vector2(12, 48), Vector2(26, 14)), shorts)


func _build() -> void:
	for ch in _body.get_children():
		ch.queue_free()
	_refresh()
	match tab:
		0:
			_identity()
		1:
			_kit("home")
		2:
			_kit("away")
		3:
			_squad()


func _field(label: String, value: String, max_len: int, cb: Callable) -> void:
	var h := UI.hbox(10)
	var l := UI.label(label, 12, "disp_s", Game.C_DIM, true)
	l.custom_minimum_size.x = 110
	h.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.max_length = max_len
	e.custom_minimum_size = Vector2(240, 34)
	e.text_changed.connect(cb)
	h.add_child(e)
	_body.add_child(h)


func _colors(label: String, current: String, cb: Callable) -> void:
	var h := UI.hbox(6)
	var l := UI.label(label, 12, "disp_s", Game.C_DIM, true)
	l.custom_minimum_size.x = 110
	h.add_child(l)
	for hex in PALETTE:
		var b := GDButton.new()
		b.style = "custom"
		b.custom_minimum_size = Vector2(24, 24)
		b.draw.connect(_swatch.bind(b, Color(hex), hex == current))
		b.pressed.connect(cb.bind(hex))
		h.add_child(b)
	_body.add_child(h)


func _swatch(b: Control, col: Color, on: bool) -> void:
	b.draw_rect(Rect2(Vector2(3, 3), b.size - Vector2(6, 6)), col)
	b.draw_rect(Rect2(Vector2(1, 1), b.size - Vector2(2, 2)), Game.C_CARD if on else Game.C_LINE2, false, 2.0 if on else 1.0)


func _identity() -> void:
	var cl := _club()
	_field("Club name", cl.name, 22, func(t): cl.name = t.strip_edges() if t.strip_edges() != "" else "My Club"; _refresh())
	_field("Short name", cl.short, 3, func(t): cl.short = t.to_upper().strip_edges() if t.strip_edges() != "" else "MYC"; _refresh())
	var h := UI.hbox(10)
	var l := UI.label("Crest shape", 12, "disp_s", Game.C_DIM, true)
	l.custom_minimum_size.x = 110
	h.add_child(l)
	h.add_child(UI.seg(["Shield", "Round", "Diamond"], int(cl.crest.get("shape", 0)), func(i): cl.crest.shape = i; _refresh()))
	_body.add_child(h)
	var h2 := UI.hbox(10)
	var l2 := UI.label("Crest pattern", 12, "disp_s", Game.C_DIM, true)
	l2.custom_minimum_size.x = 110
	h2.add_child(l2)
	h2.add_child(UI.seg(["Plain", "Stripes", "Hoops", "Halves"], int(cl.crest.get("pattern", 1)), func(i): cl.crest.pattern = i; _refresh()))
	_body.add_child(h2)
	_colors("Main colour", cl.crest.c1, func(hex): cl.crest.c1 = hex; _build())
	_colors("Trim colour", cl.crest.c2, func(hex): cl.crest.c2 = hex; _build())
	var h3 := UI.hbox(10)
	var l3 := UI.label("Base squad", 12, "disp_s", Game.C_DIM, true)
	l3.custom_minimum_size.x = 110
	h3.add_child(l3)
	h3.add_child(UI.label("Rating %d · stronger squads unlock as you level up" % Competition.team_ovr("user"), 12, "body_m", Game.C_DIM))
	_body.add_child(h3)


func _kit(which: String) -> void:
	var cl := _club()
	var k: Array = cl[which]
	_colors("Shirt", k[0], func(hex): k[0] = hex; _build())
	_colors("Trim", k[1], func(hex): k[1] = hex; _build())
	var h := UI.hbox(10)
	var l := UI.label("Pattern", 12, "disp_s", Game.C_DIM, true)
	l.custom_minimum_size.x = 110
	h.add_child(l)
	h.add_child(UI.seg(PATTERNS, int(k[2]), func(i): k[2] = i; _refresh()))
	_body.add_child(h)
	_colors("Shorts", k[3], func(hex): k[3] = hex; _build())
	_colors("Socks", k[4], func(hex): k[4] = hex; _build())


func _squad() -> void:
	var cl := _club()
	var roles := ["GK", "RB", "CB", "CB", "LB", "CM", "CM", "CM", "RW", "ST", "LW"]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	for i in 11:
		var h := UI.hbox(8)
		var r := UI.label(roles[i], 12, "disp", Game.C_CARD, true)
		r.custom_minimum_size.x = 28
		h.add_child(r)
		var e := LineEdit.new()
		e.text = cl.players[i]
		e.max_length = 18
		e.custom_minimum_size = Vector2(190, 32)
		e.text_changed.connect(func(t): cl.players[i] = t if t.strip_edges() != "" else "Player %d" % (i + 1))
		h.add_child(e)
		grid.add_child(h)
	_body.add_child(grid)


func _save_back() -> void:
	Game.write_save()
	Game.back()


func on_back() -> bool:
	Game.write_save()
	return false
