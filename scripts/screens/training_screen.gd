extends Control
## Training ground: six drill cards with best score and medal.

const DRILLS := [
	["freekick", "Free kicks", "Wall, wind and target rings"],
	["penalty", "Penalties", "Take five, then save five"],
	["corner", "Corners & crosses", "Whip it in, head it home"],
	["shooting", "Shooting gallery", "60 seconds, first-time strikes"],
	["dribble", "Dribble run", "Slalom the cones, then finish"],
	["keeper", "Keeper reflexes", "15 shots, swipe to dive"],
]

var params := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	var c := ColorRect.new()
	c.color = Game.C_NIGHT
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	UI.bg_gradient(self, Vector2(0.15, 0.0))
	var m := UI.safe_margin()
	add_child(m)
	var v := UI.vbox(10)
	m.add_child(v)
	var head := UI.header("Training ground", Game.back)
	head.add_child(UI.spacer())
	var counts := [0, 0, 0, 0]
	for d in DRILLS:
		counts[int(Game.save.training.get(d[0], {}).get("medal", 0))] += 1
	for i in [3, 2, 1]:
		var h := UI.hbox(4)
		var md := Control.new()
		md.custom_minimum_size = Vector2(14, 14)
		md.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		md.draw.connect(_medal.bind(md, i, 7.0))
		h.add_child(md)
		h.add_child(UI.label(str(counts[i]), 12, "body_sb"))
		head.add_child(h)
	v.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 9)
	grid.add_theme_constant_override("v_separation", 9)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grid)
	var daily: Dictionary = load("res://scripts/screens/home_screen.gd").daily_today()
	for d in DRILLS:
		grid.add_child(_card(d, daily))


func _card(d: Array, daily: Dictionary) -> Control:
	var rec: Dictionary = Game.save.training.get(d[0], {})
	var b := Control.new()
	b.custom_minimum_size = Vector2(240, 138)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.clip_contents = true
	b.draw.connect(_draw_card.bind(b, d, rec, daily.drill == d[0] and not daily.done))
	b.gui_input.connect(_card_input.bind(d[0]))
	return b


func _card_input(e: InputEvent, id: String) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		Sfx.ui()
		Game.goto("drill", {"drill": id})


func _medal(c: Control, m: int, r: float) -> void:
	var cols := [Color(0, 0, 0, 0), Color("b8723a"), Color("a9b4b7"), Color("e3b622")]
	var cc := Vector2(r, r)
	if m == 0:
		c.draw_arc(cc, r - 1.0, 0, TAU, 24, Game.C_LINE2, 1.5, true)
	else:
		c.draw_circle(cc, r, cols[m])
		c.draw_circle(cc - Vector2(r, r) * 0.25, r * 0.35, Color(1, 1, 1, 0.35))


func _draw_card(b: Control, d: Array, rec: Dictionary, is_daily: bool) -> void:
	var r := Rect2(Vector2.ZERO, b.size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Game.C_TURF
	sb.border_color = Game.C_CARD if is_daily else Game.C_LINE
	sb.set_border_width_all(2 if is_daily else 1)
	sb.set_corner_radius_all(5)
	b.draw_style_box(sb, r)
	# pitch illustration
	var art := Rect2(Vector2(1, 1), Vector2(b.size.x - 2, b.size.y * 0.52))
	b.draw_rect(art, Color("2f6d34"))
	for i in 6:
		if i % 2 == 0:
			b.draw_rect(Rect2(art.position + Vector2(art.size.x * i / 6.0, 0), Vector2(art.size.x / 6.0, art.size.y)), Color("357a3a"))
	_art(b, d[0], art)
	var f := UI.font("disp")
	var fb := UI.font("body_m")
	b.draw_string(f, Vector2(12, art.end.y + 24), d[1].to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Game.C_CHALK)
	var best := "Not played yet"
	if rec.has("best") and float(rec.best) > 0.0:
		best = ("Best %.2f s" % float(rec.best)) if d[0] == "dribble" else ("Best %d" % int(rec.best))
	b.draw_string(fb, Vector2(12, art.end.y + 40), best, HORIZONTAL_ALIGNMENT_LEFT, b.size.x - 50, 12, Game.C_CHALK)
	b.draw_string(fb, Vector2(12, art.end.y + 56), d[2], HORIZONTAL_ALIGNMENT_LEFT, b.size.x - 50, 11, Game.C_DIM)
	b.draw_set_transform(Vector2(b.size.x - 34, art.end.y + 16))
	_medal(b, int(rec.get("medal", 0)), 11.0)
	b.draw_set_transform(Vector2.ZERO)
	if is_daily:
		var t := "TODAY'S DRILL"
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		b.draw_rect(Rect2(Vector2(b.size.x - tw - 18, 8), Vector2(tw + 12, 18)), Game.C_CARD)
		b.draw_string(f, Vector2(b.size.x - tw - 12, 21), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Game.C_INK)


func _art(b: Control, id: String, r: Rect2) -> void:
	var w := Game.C_CHALK
	var cx := r.get_center().x
	var gy := r.position.y + 36.0
	var goal := func(x: float, y: float, gw: float, gh: float) -> void:
		b.draw_rect(Rect2(Vector2(x - gw * 0.5, y - gh), Vector2(gw, gh)), Color(1, 1, 1, 0.08))
		b.draw_polyline(PackedVector2Array([Vector2(x - gw * 0.5, y), Vector2(x - gw * 0.5, y - gh), Vector2(x + gw * 0.5, y - gh), Vector2(x + gw * 0.5, y)]), w, 2.0)
	match id:
		"freekick":
			goal.call(cx, gy, 90, 30)
			for i in 3:
				b.draw_rect(Rect2(Vector2(cx - 22 + i * 14, gy + 14), Vector2(9, 18)), Game.C_AWAY)
			b.draw_circle(Vector2(cx + 30, r.end.y - 10), 4, Color.WHITE)
			b.draw_arc(Vector2(cx - 30, gy - 22), 6, 0, TAU, 16, Game.C_CARD, 2.0)
			b.draw_polyline(PackedVector2Array([Vector2(cx + 30, r.end.y - 14), Vector2(cx + 46, gy + 10), Vector2(cx - 26, gy - 20)]), Color(1, 0.95, 0.75, 0.7), 2.0, true)
		"penalty":
			goal.call(cx, gy + 4, 110, 34)
			b.draw_rect(Rect2(Vector2(cx - 6, gy - 26), Vector2(12, 26)), Color("8E6CF0"))
			b.draw_circle(Vector2(cx, r.end.y - 12), 4, Color.WHITE)
		"corner":
			b.draw_arc(Vector2(r.end.x - 4, r.end.y - 4), 10, PI, PI * 1.5, 12, w, 2.0)
			b.draw_polyline(PackedVector2Array([Vector2(r.end.x - 10, r.end.y - 8), Vector2(cx + 10, r.position.y + 6), Vector2(cx - 30, gy + 6)]), Color(1, 0.81, 0.2, 0.9), 2.0, true)
			for i in 3:
				b.draw_rect(Rect2(Vector2(cx - 50 + i * 26, gy + 2), Vector2(9, 18)), Game.C_HOME if i != 1 else Game.C_AWAY)
		"shooting":
			goal.call(cx, gy + 2, 110, 34)
			b.draw_arc(Vector2(cx + 34, gy - 18), 9, 0, TAU, 20, Game.C_CARD, 2.0)
			b.draw_arc(Vector2(cx - 30, gy - 8), 9, 0, TAU, 20, Game.C_CARD, 2.0)
			b.draw_circle(Vector2(cx - 10, r.end.y - 12), 4, Color.WHITE)
		"dribble":
			for i in 7:
				var x: float = r.position.x + 24 + i * (r.size.x - 48) / 6.0
				var y: float = r.get_center().y + (10 if i % 2 == 0 else -10)
				b.draw_colored_polygon(PackedVector2Array([Vector2(x - 5, y + 6), Vector2(x + 5, y + 6), Vector2(x, y - 8)]), Color("FF7A1A"))
			b.draw_circle(Vector2(r.position.x + 12, r.get_center().y), 4, Color.WHITE)
		"keeper":
			goal.call(cx, r.end.y - 4, r.size.x - 30, r.size.y - 14)
			b.draw_rect(Rect2(Vector2(cx - 7, r.end.y - 34), Vector2(14, 30)), Color("8E6CF0"))
			b.draw_circle(Vector2(cx + 40, r.position.y + 20), 5, Color.WHITE)
