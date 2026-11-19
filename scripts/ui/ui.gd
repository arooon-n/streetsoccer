class_name UI
extends RefCounted
## Static UI helpers: fonts, theme, and factory functions for common widgets.

static var _fonts := {}
static var _theme: Theme

const FONT_FILES := {
	"disp_s": "res://assets/fonts/SairaCondensed-SemiBold.ttf",
	"disp": "res://assets/fonts/SairaCondensed-Bold.ttf",
	"disp_x": "res://assets/fonts/SairaCondensed-ExtraBold.ttf",
	"body": "res://assets/fonts/Barlow-Regular.ttf",
	"body_m": "res://assets/fonts/Barlow-Medium.ttf",
	"body_sb": "res://assets/fonts/Barlow-SemiBold.ttf",
	"body_b": "res://assets/fonts/Barlow-Bold.ttf",
}


static func font(kind: String = "body") -> Font:
	if not _fonts.has(kind):
		var f: FontFile = load(FONT_FILES.get(kind, FONT_FILES.body))
		_fonts[kind] = f
	return _fonts[kind]


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("body_m")
	t.default_font_size = 13
	t.set_color("font_color", "Label", Game.C_CHALK)
	# LineEdit
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0.03, 0.09, 0.1, 0.9)
	le.border_color = Game.C_LINE2
	le.set_border_width_all(1)
	le.set_corner_radius_all(4)
	le.content_margin_left = 10
	le.content_margin_right = 10
	le.content_margin_top = 6
	le.content_margin_bottom = 6
	t.set_stylebox("normal", "LineEdit", le)
	var lef := le.duplicate()
	lef.border_color = Game.C_CARD
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_color("font_color", "LineEdit", Game.C_CHALK)
	t.set_color("caret_color", "LineEdit", Game.C_CARD)
	t.set_font("font", "LineEdit", font("body_sb"))
	t.set_font_size("font_size", "LineEdit", 14)
	# Slider
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.93, 0.95, 0.92, 0.18)
	track.set_corner_radius_all(2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Game.C_CARD
	fill.set_corner_radius_all(2)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _circle_tex(16, Game.C_CHALK))
	t.set_icon("grabber_highlight", "HSlider", _circle_tex(16, Color.WHITE))
	# Scroll
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.95, 0.92, 0.25)
	sb.set_corner_radius_all(3)
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb)
	var empty := StyleBoxEmpty.new()
	t.set_stylebox("scroll", "VScrollBar", empty)
	t.set_stylebox("scroll", "HScrollBar", empty)
	t.set_stylebox("panel", "PanelContainer", empty)
	_theme = t
	return t


static func _circle_tex(s: int, c: Color) -> ImageTexture:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var r := s * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a: float = clamp(r - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)


# ---------------- factories ----------------
static func label(text: String, size := 13, kind := "body_m", color := Game.C_CHALK, upper := false) -> Label:
	var l := Label.new()
	l.text = text.to_upper() if upper else text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func title(text: String, size := 22) -> Label:
	return label(text, size, "disp_x", Game.C_CHALK, true)


static func eyebrow(text: String, color := Game.C_DIM) -> Label:
	var l := label(text, 11, "disp_s", color, true)
	return l


static func hbox(sep := 8) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func vbox(sep := 8) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func spacer(expand := true) -> Control:
	var c := Control.new()
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func gap(w := 0, h := 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	return c


static func panel(chalk := true, alpha := 0.82) -> ChalkPanel:
	var p := ChalkPanel.new()
	p.chalk = chalk
	p.bg_alpha = alpha
	return p


static func button(text: String, style := "primary", size := Vector2(0, 44), font_size := 18) -> GDButton:
	var b := GDButton.new()
	b.text = text
	b.style = style
	b.font_size = font_size
	b.custom_minimum_size = size
	return b


static func icon_button(icon: String, tip := "") -> GDButton:
	var b := GDButton.new()
	b.style = "round"
	b.icon_name = icon
	b.custom_minimum_size = Vector2(40, 40)
	b.tooltip_text = tip
	return b


static func pill(text: String, coin := false) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.055, 0.063, 0.72)
	sb.border_color = Game.C_LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	var h := hbox(6)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	if coin:
		var ic := Icon.new()
		ic.kind = "coin"
		ic.custom_minimum_size = Vector2(14, 14)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	var l := label(text, 13, "body_sb")
	l.name = "Text"
	h.add_child(l)
	p.add_child(h)
	return p


static func pill_set(p: PanelContainer, text: String) -> void:
	var l := p.find_child("Text", true, false) as Label
	if l:
		l.text = text


static func seg(options: Array, selected: int, on_change: Callable, font_size := 13) -> Seg:
	var s := Seg.new()
	s.font_size = font_size
	s.setup(options, selected)
	s.changed.connect(on_change)
	return s


static func screen_root() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.theme = theme()
	return c


## Margin container that respects the phone's cutout / safe area.
static func safe_margin(top := 14, bottom := 14, side := 26, cut_side := 46) -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ins := safe_insets()
	m.add_theme_constant_override("margin_left", int(max(cut_side if ins.x > 0.0 or OS.get_name() != "Android" else side, ins.x + 14)))
	m.add_theme_constant_override("margin_right", int(max(side, ins.y + 14)))
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_bottom", bottom)
	return m


## Left/right safe insets in base (844-wide) units.
static func safe_insets() -> Vector2:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return Vector2.ZERO
	var win_size := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	var vp_size := tree.root.get_visible_rect().size
	if win_size.x <= 0 or safe.size.x <= 0:
		return Vector2.ZERO
	var k := vp_size.x / float(win_size.x)
	var left: float = max(0.0, safe.position.x) * k
	var right: float = max(0.0, win_size.x - safe.end.x) * k
	return Vector2(left, right)


static func header(title_text: String, on_back: Callable) -> HBoxContainer:
	var h := hbox(10)
	var b := icon_button("back", "Back")
	b.pressed.connect(on_back)
	h.add_child(b)
	var t := title(title_text, 22)
	h.add_child(t)
	return h


static func stars_text(n: int) -> String:
	return "★".repeat(n) + "☆".repeat(3 - n)


static func bg_gradient(c: Control, focus := Vector2(0.85, 0.0)) -> void:
	var tr := TextureRect.new()
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var g := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color("14342d"))
	grad.set_color(1, Game.C_NIGHT)
	grad.add_point(0.6, Game.C_NIGHT)
	g.gradient = grad
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = focus
	g.fill_to = focus + Vector2(0.9, 0.9)
	g.width = 256
	g.height = 128
	tr.texture = g
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(tr)


static func toast(parent: Control, text: String, color := Game.C_CARD, secs := 1.8) -> void:
	var p := pill(text)
	p.modulate = Color(1, 1, 1, 0)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	parent.add_child(p)
	await parent.get_tree().process_frame
	p.position = Vector2((parent.size.x - p.size.x) * 0.5, parent.size.y - p.size.y - 24)
	(p.find_child("Text", true, false) as Label).add_theme_color_override("font_color", color)
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(secs)
	tw.tween_property(p, "modulate:a", 0.0, 0.25)
	tw.tween_callback(p.queue_free)
