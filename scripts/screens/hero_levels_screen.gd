extends Control
## Hero Challenges: chapter tabs, level grid with stars, selected-level details.

var params := {}
var chapter := 0
var selected: Dictionary = {}
var _grid: GridContainer
var _tabs: HBoxContainer
var _detail: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	_bg()
	chapter = HeroLevels.current_chapter()
	var m := UI.safe_margin()
	add_child(m)
	var v := UI.vbox(10)
	m.add_child(v)
	var head := UI.header("Hero challenges", Game.back)
	head.add_child(UI.spacer())
	head.add_child(UI.pill("★ %d / 180" % HeroLevels.total_stars()))
	v.add_child(head)
	_tabs = UI.hbox(6)
	v.add_child(_tabs)
	var body := UI.hbox(12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 7)
	_grid.add_theme_constant_override("v_separation", 7)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_grid)
	var dp := UI.panel()
	dp.custom_minimum_size = Vector2(262, 0)
	_detail = UI.vbox(10)
	dp.add_child(_detail)
	body.add_child(dp)
	_build()


func _bg() -> void:
	var c := ColorRect.new()
	c.color = Game.C_NIGHT
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	UI.bg_gradient(self)


func _build() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	for c in _grid.get_children():
		c.queue_free()
	for i in 4:
		var b := GDButton.new()
		b.style = "tab"
		b.text = HeroLevels.CHAPTERS[i]
		b.font_size = 14
		b.custom_minimum_size = Vector2(158, 42)
		var st := 0
		for l in HeroLevels.chapter_levels(i):
			st += int(Game.save.hero.stars.get(l.id, 0))
		var unlocked := HeroLevels.chapter_unlocked(i)
		b.subtitle = ("★ %d / 45" % st) if unlocked else ("Needs ★ %d" % HeroLevels.UNLOCK[i])
		b.selected = i == chapter
		b.locked = not unlocked
		b.disabled = not unlocked
		b.pressed.connect(func(): chapter = i; selected = {}; _build())
		_tabs.add_child(b)
	var levels := HeroLevels.chapter_levels(chapter)
	for l in levels:
		_grid.add_child(_tile(l))
	if selected.is_empty():
		for l in levels:
			if HeroLevels.level_unlocked(l):
				selected = l
				if int(Game.save.hero.stars.get(l.id, 0)) == 0:
					break
	_show_detail()


func _tile(l: Dictionary) -> Control:
	var b := Control.new()
	b.custom_minimum_size = Vector2(80, 58)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var unlocked := HeroLevels.level_unlocked(l)
	var stars := int(Game.save.hero.stars.get(l.id, 0))
	b.draw.connect(_draw_tile.bind(b, l, unlocked, stars))
	b.gui_input.connect(_on_tile_input.bind(l, unlocked))
	return b


func _on_tile_input(e: InputEvent, l: Dictionary, unlocked: bool) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and unlocked:
		Sfx.ui()
		selected = l
		_build()


func _draw_tile(b: Control, l: Dictionary, unlocked: bool, stars: int) -> void:
	var cur: bool = not selected.is_empty() and selected.id == l.id
	var r := Rect2(Vector2.ZERO, b.size)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.bg_color = Color(1.0, 0.81, 0.2, 0.12) if cur else Color(0.055, 0.15, 0.135, 0.75)
	sb.border_color = Game.C_CARD if cur else Game.C_LINE
	sb.set_border_width_all(2 if cur else 1)
	b.draw_style_box(sb, r)
	var a := 1.0 if unlocked else 0.4
	var f := UI.font("disp_x")
	b.draw_string(f, Vector2(8, 24), l.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, a))
	if unlocked:
		for i in 3:
			Icon.draw_icon(b, "star", Rect2(Vector2(8 + i * 14, 36), Vector2(12, 12)), Game.C_CARD if i < stars else Color(0.93, 0.95, 0.92, 0.22))
	else:
		Icon.draw_icon(b, "lock", Rect2(Vector2(8, 36), Vector2(12, 12)), Color(0.93, 0.95, 0.92, 0.5))


func _show_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	if selected.is_empty():
		_detail.add_child(UI.label("Earn more stars to unlock this chapter.", 14))
		return
	var l := selected
	_detail.add_child(UI.eyebrow("Level " + l.id))
	var t := UI.title(l.title, 22)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(t)
	var objs := ["Score", "Score in %d move%s or fewer" % [l.par, "" if l.par == 1 else "s"], "Bonus: " + HeroLevels.BONUS_TEXT.get(l.bonus, "")]
	for i in 3:
		var row := UI.hbox(8)
		var n := UI.label(str(i + 1), 11, "body_b", Game.C_CARD)
		n.custom_minimum_size = Vector2(14, 0)
		row.add_child(n)
		var lab := UI.label(objs[i], 13)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.custom_minimum_size.x = 210
		row.add_child(lab)
		_detail.add_child(row)
	_detail.add_child(UI.spacer())
	var row := UI.hbox(8)
	var best := int(Game.save.hero.stars.get(l.id, 0))
	row.add_child(UI.label(("Best: " + "★".repeat(best)) if best > 0 else "Not played yet", 12, "body_m", Game.C_DIM))
	row.add_child(UI.spacer())
	var play := UI.button("Play", "primary", Vector2(100, 40), 17)
	play.pressed.connect(func(): Game.goto("hero", {"level": l.id}))
	row.add_child(play)
	_detail.add_child(row)
	var how := UI.label("Drag from your player to draw. End on a teammate to pass, or carry the line into the goal to shoot. Bend it to curl.", 11, "body_m", Game.C_DIM)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size.x = 236
	_detail.add_child(how)
