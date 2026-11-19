class_name GDButton
extends Control
## Slanted broadcast-style button drawn entirely in code.
## Styles: primary, ghost, menu, play, round, chip, danger.

signal pressed

const SKEW := 0.176 # tan(10 deg)

@export var text := "":
	set(v):
		text = v
		queue_redraw()
@export var subtitle := "":
	set(v):
		subtitle = v
		queue_redraw()
@export var style := "primary":
	set(v):
		style = v
		queue_redraw()
@export var font_size := 18
@export var icon_name := "":
	set(v):
		icon_name = v
		queue_redraw()
@export var disabled := false:
	set(v):
		disabled = v
		modulate.a = 0.42 if v else 1.0
		queue_redraw()
@export var selected := false:
	set(v):
		selected = v
		queue_redraw()
var badge := ""
var locked := false:
	set(v):
		locked = v
		queue_redraw()
var align_left := false
var sound := "tap"

var _down := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	resized.connect(func(): pivot_offset = size * 0.5)
	pivot_offset = size * 0.5
	if custom_minimum_size.x <= 0.0 and style != "round":
		var f := UI.font("disp_x")
		var w = f.get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		custom_minimum_size.x = w + 44 + (22 if icon_name != "" else 0)


func _gui_input(e: InputEvent) -> void:
	if disabled:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_down = true
			_anim(0.95)
		elif _down:
			_down = false
			_anim(1.0)
			if Rect2(Vector2.ZERO, size).has_point(e.position):
				if sound != "":
					Sfx.ui(sound)
				Game.haptic(12)
				pressed.emit()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _down:
		_down = false
		_anim(1.0)


func _anim(s: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(s, s), 0.08 if s < 1.0 else 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _para(r: Rect2) -> PackedVector2Array:
	var o = r.size.y * SKEW * 0.5
	return PackedVector2Array([
		Vector2(r.position.x + o * 2.0, r.position.y), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x - o * 2.0, r.end.y), Vector2(r.position.x, r.end.y)])


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	match style:
		"custom":
			return
		"tab":
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(4)
			sb.bg_color = Color(1.0, 0.81, 0.2, 0.1) if selected else Color(0.055, 0.15, 0.135, 0.6)
			sb.border_color = Game.C_CARD if selected else Game.C_LINE
			sb.set_border_width_all(1)
			draw_style_box(sb, r)
			var f := UI.font("disp")
			draw_string(f, Vector2(12, 19), text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 14, Game.C_CHALK)
			draw_string(UI.font("body_m"), Vector2(12, 34), subtitle, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 11, Game.C_DIM)
			if locked:
				Icon.draw_icon(self, "lock", Rect2(Vector2(size.x - 22, 8), Vector2(12, 12)), Game.C_DIM)
			return
		"round":
			var c := size * 0.5
			var rad: float = min(size.x, size.y) * 0.5 - 1.0
			draw_circle(c, rad, Color(0.02, 0.055, 0.063, 0.6))
			draw_arc(c, rad, 0, TAU, 40, Game.C_LINE2, 1.2, true)
			Icon.draw_icon(self, icon_name, Rect2(c - Vector2(9, 9), Vector2(18, 18)), Game.C_CHALK)
			return
		"chip":
			var bg := Game.C_CARD if selected else Color(0, 0, 0, 0)
			draw_rect(r, bg)
			_text_center(r, Game.C_INK if selected else Game.C_DIM, "disp_s")
			return
	var pts := _para(r)
	var fill := Game.C_CARD
	var txt := Game.C_INK
	var border := Color(0, 0, 0, 0)
	match style:
		"ghost":
			fill = Color(0.93, 0.95, 0.92, 0.08)
			txt = Game.C_CHALK
			border = Game.C_LINE2
		"menu":
			fill = Color(0.055, 0.15, 0.135, 0.88)
			txt = Game.C_CHALK
			border = Game.C_LINE
			if selected:
				border = Game.C_CARD
		"danger":
			fill = Game.C_AWAY
			txt = Color.WHITE
		"play", "primary":
			pass
	if style in ["primary", "play"]:
		var sh := pts.duplicate()
		for i in sh.size():
			sh[i] += Vector2(0, 5)
		draw_colored_polygon(sh, Color(1.0, 0.81, 0.2, 0.18))
	draw_colored_polygon(pts, fill)
	if border.a > 0.0:
		var loop := pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, border, 1.0, true)
	if style in ["menu", "play"] or align_left:
		var f := UI.font("disp_x" if style == "play" else "disp")
		var fs := font_size
		var x := 16.0 + size.y * SKEW
		var base = (size.y + f.get_ascent(fs) - f.get_descent(fs)) * 0.5 - 1.0
		draw_string(f, Vector2(x, base), text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, txt)
		if subtitle != "":
			var tw = f.get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var sf := UI.font("body_sb" if style == "play" else "body_m")
			var sx: float = max(x + tw + 14.0, x + 150.0) if style == "menu" else x + tw + 14.0
			var sc := Color("4b3d00") if style == "play" else Game.C_DIM
			draw_string(sf, Vector2(sx, base - 1), subtitle, HORIZONTAL_ALIGNMENT_LEFT, size.x - sx - 20, 12, sc)
		if locked:
			Icon.draw_icon(self, "lock", Rect2(Vector2(size.x - 34, size.y * 0.5 - 8), Vector2(16, 16)), Game.C_DIM)
		elif badge != "":
			var bf := UI.font("disp")
			draw_string(bf, Vector2(size.x - 22 - bf.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x, base), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Game.C_CARD)
		return
	_text_center(r, txt, "disp_x")


func _text_center(r: Rect2, col: Color, kind: String) -> void:
	var f := UI.font(kind)
	var t := text.to_upper()
	var tw = f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var iw := 0.0
	if icon_name != "":
		iw = 22.0
	var x = (r.size.x - tw - iw) * 0.5
	var base = (r.size.y + f.get_ascent(font_size) - f.get_descent(font_size)) * 0.5 - 1.0
	draw_string(f, Vector2(x, base), t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
	if icon_name != "":
		Icon.draw_icon(self, icon_name, Rect2(Vector2(x + tw + 6, r.size.y * 0.5 - 8), Vector2(16, 16)), col)
