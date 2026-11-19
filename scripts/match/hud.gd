class_name MatchHUD
extends Control
## In-match overlay: scoreboard, radar, banners, name tag, pause / half-time / full-time panels.

signal resume_pressed
signal quit_pressed
signal restart_pressed
signal continue_pressed
signal highlights_pressed
signal skip_pressed

var mt = null
var home_short := "HCF"
var away_short := "RBR"
var home_col := Game.C_HOME
var away_col := Game.C_AWAY
var score := [0, 0]
var clock_text := "00:00"
var added_text := ""
var show_radar := true
var replay := false
var tag_text := ""
var tag_pos := Vector2(-100, -100)
var tag_stamina := 1.0
var pill_text := ""

var _banner_title := ""
var _banner_sub := ""
var _banner_col := Game.C_CARD
var _banner_t := 0.0
var _banner_dur := 0.0
var _msg := ""
var _msg_t := 0.0
var _flash: ColorRect
var _pause_btn: GDButton
var _overlay: Control = null
var _skip: GDButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_btn = UI.icon_button("pause", "Pause")
	_pause_btn.size = Vector2(40, 40)
	add_child(_pause_btn)
	_pause_btn.pressed.connect(func(): resume_pressed.emit() if get_tree().paused else _on_pause())
	_skip = UI.button("Skip", "ghost", Vector2(90, 36), 15)
	_skip.visible = false
	add_child(_skip)
	_skip.pressed.connect(func(): skip_pressed.emit())
	_flash = ColorRect.new()
	_flash.color = Color(0.02, 0.05, 0.06, 1.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	add_child(_flash)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var ins := UI.safe_insets()
	_pause_btn.position = Vector2(size.x - max(26.0, ins.y + 12.0) - 40.0, 14)
	_skip.position = Vector2(size.x - max(26.0, ins.y + 12.0) - 90.0, size.y - 52)


func pause_rect() -> Rect2:
	return Rect2(_pause_btn.position - Vector2(6, 6), _pause_btn.size + Vector2(12, 12))


func _on_pause() -> void:
	if mt and mt.has_method("pause_game"):
		mt.pause_game()


func set_teams(h: Dictionary, a: Dictionary, hc: Color, ac: Color) -> void:
	home_short = h.short
	away_short = a.short
	home_col = hc
	away_col = ac


func banner(title: String, sub := "", col := Game.C_CARD, dur := 2.4) -> void:
	_banner_title = title
	_banner_sub = sub
	_banner_col = col
	_banner_t = 0.0
	_banner_dur = dur


func message(t: String, dur := 2.0) -> void:
	_msg = t
	_msg_t = dur


func flash(dur := 0.45) -> void:
	_flash.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(dur * 0.35)
	tw.tween_property(_flash, "modulate:a", 0.0, dur * 0.65)


func set_replay(on: bool) -> void:
	replay = on
	_skip.visible = on


func _process(delta: float) -> void:
	if _banner_dur > 0.0:
		_banner_t += delta
		if _banner_t > _banner_dur:
			_banner_dur = 0.0
	if _msg_t > 0.0:
		_msg_t -= delta
	queue_redraw()


func _draw() -> void:
	var ins := UI.safe_insets()
	var left: float = max(46.0, ins.x + 14.0)
	_draw_scoreboard(Vector2(left, 14))
	if show_radar and not replay and mt != null:
		_draw_radar()
	if tag_text != "" and not replay:
		_draw_tag()
	if pill_text != "":
		var f := UI.font("body_sb")
		var tw := f.get_string_size(pill_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var r := Rect2(Vector2(_pause_btn.position.x - tw - 34, 20), Vector2(tw + 24, 26))
		draw_style_box(_pill_box(), r)
		draw_string(f, r.position + Vector2(12, 17), pill_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Game.C_CHALK)
	if replay:
		var f := UI.font("disp_x")
		var r := Rect2(Vector2(size.x * 0.5 - 60, 18), Vector2(120, 30))
		_slant_rect(r, Game.C_AWAY)
		Icon.draw_icon(self, "replay", Rect2(r.position + Vector2(14, 7), Vector2(16, 16)), Color.WHITE)
		draw_string(f, r.position + Vector2(36, 22), "REPLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	if _msg_t > 0.0 and _msg != "":
		var f := UI.font("disp")
		var tw := f.get_string_size(_msg.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var r := Rect2(Vector2(size.x * 0.5 - tw * 0.5 - 16, 58), Vector2(tw + 32, 30))
		var a: float = clamp(_msg_t / 0.3, 0.0, 1.0)
		draw_style_box(_pill_box(a), r)
		draw_string(f, r.position + Vector2(16, 21), _msg.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, a))
	if _banner_dur > 0.0:
		_draw_banner()


func _pill_box(a := 1.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.055, 0.063, 0.78 * a)
	sb.border_color = Color(0.93, 0.95, 0.92, 0.14 * a)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(14)
	return sb


func _slant_rect(r: Rect2, c: Color) -> void:
	var o := r.size.y * 0.176
	draw_colored_polygon(PackedVector2Array([r.position + Vector2(o, 0), Vector2(r.end.x, r.position.y), r.end - Vector2(o, 0), Vector2(r.position.x, r.end.y)]), c)


func _draw_scoreboard(at: Vector2) -> void:
	var fd := UI.font("disp")
	var fx := UI.font("disp_x")
	_sx = at.x
	_sy = at.y
	# shadow
	_slant_rect(Rect2(at + Vector2(2, 5), Vector2(330, 34.0)), Color(0, 0, 0, 0.3))
	var r1: Rect2 = _seg(78.0, Color(0.02, 0.055, 0.063, 0.9))
	draw_rect(Rect2(r1.position + Vector2(14, 8), Vector2(5, 18)), home_col)
	draw_string(fd, r1.position + Vector2(25, 24), home_short, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Game.C_CHALK)
	var r2: Rect2 = _seg(36.0, Game.C_CHALK)
	_centered(fx, str(score[0]), r2, 21, Color("0b1714"))
	var r3: Rect2 = _seg(36.0, Color("cfd6cc"))
	_centered(fx, str(score[1]), r3, 21, Color("0b1714"))
	var r4: Rect2 = _seg(78.0, Color(0.02, 0.055, 0.063, 0.9))
	draw_string(fd, r4.position + Vector2(14, 24), away_short, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Game.C_CHALK)
	draw_rect(Rect2(r4.position + Vector2(58, 8), Vector2(5, 18)), away_col)
	var cw := 74.0 if added_text == "" else 104.0
	var r5: Rect2 = _seg(cw, Game.C_CARD)
	_centered(fd, clock_text + ("" if added_text == "" else "  " + added_text), r5, 17, Game.C_INK)


var _sx := 0.0
var _sy := 0.0


func _seg(w: float, c: Color) -> Rect2:
	var r := Rect2(Vector2(_sx, _sy), Vector2(w, 34.0))
	_slant_rect(r, c)
	_sx += w - 34.0 * 0.176
	return r


func _centered(f: Font, t: String, r: Rect2, fs: int, c: Color) -> void:
	var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(r.position.x + (r.size.x - tw) * 0.5, r.position.y + r.size.y * 0.5 + fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)


func _draw_radar() -> void:
	var L: float = mt.stadium.L
	var W: float = mt.stadium.W
	var rw := 132.0
	var rh := rw * W / L
	rh = min(rh, 64.0)
	var r := Rect2(Vector2(size.x * 0.5 - rw * 0.5, size.y - rh - 12), Vector2(rw, rh))
	draw_rect(r, Color(0.02, 0.055, 0.063, 0.6))
	draw_rect(r, Color(0.93, 0.95, 0.92, 0.32), false, 1.0)
	draw_line(Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y), Color(0.93, 0.95, 0.92, 0.32), 1.0)
	draw_arc(r.get_center(), rh * 0.13, 0, TAU, 20, Color(0.93, 0.95, 0.92, 0.32), 1.0)
	var mp := func(p: Vector3) -> Vector2:
		return r.position + Vector2((p.x + L) / (2.0 * L) * rw, (p.z + W) / (2.0 * W) * rh)
	for t in mt.teams:
		var col: Color = home_col if t.side == 0 else away_col
		for p in t.players:
			if p.sent_off:
				continue
			var q: Vector2 = mp.call(p.pos)
			if t.is_user and p == t.controlled:
				draw_circle(q, 4.2, Game.C_CARD)
			draw_circle(q, 2.8, col)
	draw_circle(mp.call(mt.ball.pos), 2.3, Color.WHITE)


func _draw_tag() -> void:
	var f := UI.font("disp")
	var tw := f.get_string_size(tag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0
	var r := Rect2(tag_pos - Vector2(tw * 0.5, 22), Vector2(tw, 17))
	draw_rect(r, Color(0.02, 0.055, 0.063, 0.82))
	draw_string(f, r.position + Vector2(7, 13), tag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Game.C_CHALK)
	draw_rect(Rect2(r.position + Vector2(0, 17), Vector2(tw, 3)), Color(0.93, 0.95, 0.92, 0.2))
	draw_rect(Rect2(r.position + Vector2(0, 17), Vector2(tw * tag_stamina, 3)), Game.C_CARD)


func _draw_banner() -> void:
	var t := _banner_t
	var inn: float = clamp(t / 0.25, 0.0, 1.0)
	var out: float = clamp((_banner_dur - t) / 0.3, 0.0, 1.0)
	var a: float = min(inn, out)
	var ease_in := 1.0 - pow(1.0 - inn, 3.0)
	var fx := UI.font("disp_x")
	var fs := 64
	var tw := fx.get_string_size(_banner_title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w := tw + 90.0
	var cy := size.y * 0.42
	var x := size.x * 0.5 - w * 0.5 + (1.0 - ease_in) * -120.0
	var r := Rect2(Vector2(x, cy - 44), Vector2(w, 74))
	_slant_rect(Rect2(r.position + Vector2(6, 8), r.size), Color(0, 0, 0, 0.35 * a))
	_slant_rect(r, Color(_banner_col.r, _banner_col.g, _banner_col.b, a))
	var tc := Game.C_INK if _banner_col.get_luminance() > 0.5 else Color.WHITE
	draw_string(fx, Vector2(r.position.x + 45, cy + 13), _banner_title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(tc.r, tc.g, tc.b, a))
	if _banner_sub != "":
		var fs2 := 16
		var f2 := UI.font("disp")
		var sw := f2.get_string_size(_banner_sub.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		var r2 := Rect2(Vector2(size.x * 0.5 - sw * 0.5 - 16, cy + 36), Vector2(sw + 32, 28))
		_slant_rect(r2, Color(0.02, 0.055, 0.063, 0.88 * a))
		draw_string(f2, Vector2(r2.position.x + 16, r2.position.y + 20), _banner_sub.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(1, 1, 1, a))


# ------------------------------------------------------------------ overlays
func clear_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func _make_overlay(dim := 0.55) -> Control:
	clear_overlay()
	var o := Control.new()
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.03, 0.04, dim)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.add_child(bg)
	add_child(o)
	move_child(o, get_child_count() - 2)
	_overlay = o
	return o


func show_pause(home_name: String, away_name: String) -> void:
	var o := _make_overlay(0.6)
	var p := UI.panel()
	p.custom_minimum_size = Vector2(300, 0)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	o.add_child(p)
	var v := UI.vbox(10)
	p.add_child(v)
	v.add_child(UI.eyebrow("Paused"))
	v.add_child(UI.title("%s %d – %d %s" % [home_name, score[0], score[1], away_name], 20))
	var resume := UI.button("Resume", "primary", Vector2(260, 44), 18)
	resume.pressed.connect(func(): resume_pressed.emit())
	v.add_child(resume)
	var cam_seg := UI.seg(["Broadcast", "Close"], 0 if Game.settings.camera == "broadcast" else 1, func(i): Game.set_setting("camera", ["broadcast", "close"][i]))
	var hb := UI.hbox(10)
	hb.add_child(UI.label("Camera", 13, "body_sb"))
	hb.add_child(cam_seg)
	v.add_child(hb)
	var restart := UI.button("Restart match", "ghost", Vector2(260, 40), 16)
	restart.pressed.connect(func(): restart_pressed.emit())
	v.add_child(restart)
	var quit := UI.button("Quit match", "ghost", Vector2(260, 40), 16)
	var confirm := UI.label("", 12, "body_m", Game.C_AWAY)
	quit.pressed.connect(_on_quit.bind(quit, confirm))
	v.add_child(quit)
	v.add_child(confirm)
	await get_tree().process_frame
	p.position = (size - p.size) * 0.5


func _on_quit(quit: GDButton, confirm: Label) -> void:
	if quit.text == "Tap again to quit":
		quit_pressed.emit()
	else:
		quit.text = "Tap again to quit"
		confirm.text = "Quitting counts as a loss in cup and league."


func show_halftime(title: String, home_name: String, away_name: String, lines: Array, btn_text := "Second half") -> void:
	var o := _make_overlay(0.5)
	var p := UI.panel()
	o.add_child(p)
	var v := UI.vbox(10)
	p.add_child(v)
	v.add_child(UI.eyebrow(title, Game.C_CARD))
	v.add_child(UI.title("%s  %d – %d  %s" % [home_name, score[0], score[1], away_name], 26))
	for l in lines:
		v.add_child(UI.label(l, 13, "body_m", Game.C_DIM))
	var b := UI.button(btn_text, "primary", Vector2(220, 44), 18)
	b.pressed.connect(func(): continue_pressed.emit())
	v.add_child(b)
	await get_tree().process_frame
	p.position = (size - p.size) * 0.5


## data: {venue, home, away (team dicts), score [a,b], scorers_home, scorers_away, stats [[label,a,b,unit]], potm, coins, pens}
func show_fulltime(data: Dictionary) -> void:
	var o := _make_overlay(0.62)
	var p := UI.panel()
	p.custom_minimum_size = Vector2(600, 0)
	o.add_child(p)
	var v := UI.vbox(8)
	p.add_child(v)
	var e := UI.eyebrow(data.get("title", "Full time") + " · " + data.venue, Game.C_CARD)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(e)
	var row := UI.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var hn := UI.label(data.home.name, 20, "disp_x", Game.C_CHALK, true)
	hn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hn.custom_minimum_size.x = 200
	row.add_child(hn)
	var hc = Crest.new().setup(Color(data.home.crest[0]), Color(data.home.crest[1]), data.home.short)
	hc.custom_minimum_size = Vector2(34, 37)
	row.add_child(hc)
	row.add_child(UI.label("%d – %d" % [data.score[0], data.score[1]], 44, "disp_x"))
	var ac = Crest.new().setup(Color(data.away.crest[0]), Color(data.away.crest[1]), data.away.short)
	ac.custom_minimum_size = Vector2(34, 37)
	row.add_child(ac)
	var an := UI.label(data.away.name, 20, "disp_x", Game.C_CHALK, true)
	an.custom_minimum_size.x = 200
	row.add_child(an)
	v.add_child(row)
	if data.get("pens", "") != "":
		var pl := UI.label(data.pens, 13, "body_sb", Game.C_CARD)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(pl)
	var sc := UI.hbox(40)
	sc.alignment = BoxContainer.ALIGNMENT_CENTER
	var sh := UI.label(data.scorers_home, 12, "body_m", Game.C_DIM)
	sh.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sh.custom_minimum_size.x = 250
	sh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sa := UI.label(data.scorers_away, 12, "body_m", Game.C_DIM)
	sa.custom_minimum_size.x = 250
	sa.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sc.add_child(sh)
	sc.add_child(sa)
	v.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	for s in data.stats:
		grid.add_child(_stat_row(s[0], s[1], s[2], s[3]))
	v.add_child(grid)
	var bottom := UI.hbox(10)
	var pv := UI.vbox(0)
	pv.add_child(UI.eyebrow("Player of the match"))
	pv.add_child(UI.label(data.potm, 14, "body_b"))
	bottom.add_child(pv)
	bottom.add_child(UI.gap(10))
	var coins := UI.pill("+%d" % data.coins, true)
	coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(coins)
	bottom.add_child(UI.spacer())
	if data.get("can_highlights", false):
		var hl := UI.button("Highlights", "ghost", Vector2(130, 40), 16)
		hl.pressed.connect(func(): highlights_pressed.emit())
		bottom.add_child(hl)
	var cont := UI.button("Continue", "primary", Vector2(130, 40), 16)
	cont.pressed.connect(func(): continue_pressed.emit())
	bottom.add_child(cont)
	v.add_child(bottom)
	await get_tree().process_frame
	p.position = (size - p.size) * 0.5


func _stat_row(label: String, a: float, b: float, unit: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(270, 30)
	c.draw.connect(_draw_stat.bind(c, label, a, b, unit))
	return c


func _draw_stat(c: Control, label: String, a: float, b: float, unit: String) -> void:
	var f := UI.font("body_sb")
	var fl := UI.font("disp_s")
	var lw := fl.get_string_size(label.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	c.draw_string(fl, Vector2(135 - lw * 0.5, 10), label.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Game.C_DIM)
	var at := _fmt(a) + unit
	var bt := _fmt(b) + unit
	c.draw_string(f, Vector2(0, 26), at, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Game.C_CHALK)
	var bw := f.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	c.draw_string(f, Vector2(270 - bw, 26), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Game.C_CHALK)
	var tot: float = max(0.0001, a + b)
	var x0 := 50.0
	var x1 := 220.0
	var mid: float = x0 + (x1 - x0) * (a / tot if a + b > 0.0 else 0.5)
	c.draw_rect(Rect2(Vector2(x0, 19), Vector2(max(0.0, mid - x0 - 2.0), 6)), home_col)
	c.draw_rect(Rect2(Vector2(mid + 2.0, 19), Vector2(max(0.0, x1 - mid - 2.0), 6)), away_col)


func _fmt(x: float) -> String:
	if abs(x - round(x)) < 0.001:
		return str(int(round(x)))
	return "%.1f" % x
