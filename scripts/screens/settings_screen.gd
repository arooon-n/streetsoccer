extends Control
## Settings: gameplay, controls, graphics (with presets), audio, save data.

var params := {}
var tab := 2
var _body: VBoxContainer
var _side: VBoxContainer
var _info: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	var c := ColorRect.new()
	c.color = Game.C_NIGHT
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var m := UI.safe_margin()
	add_child(m)
	var row := UI.hbox(18)
	m.add_child(row)
	var left := UI.vbox(14)
	left.add_child(UI.header("Settings", Game.back))
	_side = UI.vbox(4)
	left.add_child(_side)
	row.add_child(left)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(sc)
	_body = UI.vbox(10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_body)
	_build()


func _build() -> void:
	for ch in _side.get_children():
		ch.queue_free()
	for i in 5:
		var b := GDButton.new()
		b.style = "menu"
		b.text = ["Gameplay", "Controls", "Graphics", "Audio", "Save data"][i]
		b.font_size = 15
		b.custom_minimum_size = Vector2(140, 36)
		b.selected = i == tab
		b.pressed.connect(func(): tab = i; _build())
		_side.add_child(b)
	for ch in _body.get_children():
		ch.queue_free()
	match tab:
		0:
			_gameplay()
		1:
			_controls()
		2:
			_graphics()
		3:
			_audio()
		4:
			_data()


func _row(label: String, ctl: Control, note := "") -> void:
	var h := UI.hbox(14)
	var l := UI.label(label, 13, "body_sb")
	l.custom_minimum_size.x = 130
	h.add_child(l)
	h.add_child(ctl)
	if note != "":
		h.add_child(UI.label(note, 11, "body_m", Game.C_DIM))
	_body.add_child(h)


func _slider(key: String, lo: float, hi: float, step: float, fmt: String) -> Control:
	var h := UI.hbox(10)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Game.settings.get(key, lo))
	s.custom_minimum_size = Vector2(190, 24)
	var lab := UI.label(fmt % s.value, 13, "body_sb")
	s.value_changed.connect(func(v): Game.set_setting(key, v); lab.text = fmt % v; _update_info())
	h.add_child(s)
	h.add_child(lab)
	return h


func _toggle(key: String) -> Control:
	return UI.seg(["On", "Off"], 0 if Game.settings.get(key, true) else 1, func(i): Game.set_setting(key, i == 0))


func _gameplay() -> void:
	_row("Difficulty", UI.seg(["Amateur", "Semi-pro", "Pro", "World class", "Legend"], int(Game.settings.difficulty), func(i): Game.set_setting("difficulty", i)))
	_row("Half length", UI.seg(["3 min", "5 min", "8 min"], [3, 5, 8].find(int(Game.settings.half_minutes)), func(i): Game.set_setting("half_minutes", [3, 5, 8][i])))
	_row("Camera", UI.seg(["Broadcast", "Close"], 0 if Game.settings.camera == "broadcast" else 1, func(i): Game.set_setting("camera", ["broadcast", "close"][i])))
	_row("Offside", _toggle("offside"))
	_row("Auto switch", _toggle("auto_switch"), "Switch to the defender nearest the ball")
	_row("Shot assist", _toggle("aim_assist"), "Tighter shots for touch controls")


func _controls() -> void:
	_row("Button size", _slider("controls_scale", 0.8, 1.3, 0.05, "%.2f×"))
	_row("Opacity", _slider("controls_opacity", 0.4, 1.0, 0.05, "%.2f"))
	_row("Vibration", _toggle("haptics"))
	var help := UI.label("Left side: floating joystick. Right side: Shoot (hold for power), Pass (hold for a lofted ball), Through, Sprint. On defence: Slide, Switch, Tackle, Press. Free kicks and penalties: swipe from the ball, bend the swipe to curl.", 12, "body_m", Game.C_DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 470
	_body.add_child(help)


func _graphics() -> void:
	var presets := ["auto", "low", "medium", "high", "ultra"]
	var p: String = Game.settings.preset
	var idx := presets.find(p)
	_row("Preset", UI.seg(["Auto", "Low", "Medium", "High", "Ultra"], idx, func(i): Game.apply_preset(presets[i]); _build()), "" if p != "custom" else "Custom")
	_row("Frame rate", UI.seg(["30", "60", "90"], [30, 60, 90].find(int(Game.settings.fps)), func(i): Game.set_setting("fps", [30, 60, 90][i]); _update_info()))
	_row("Render scale", _slider("render_scale", 0.5, 1.0, 0.05, "%.2f"))
	_row("Shadows", UI.seg(["Off", "Low", "High"], int(Game.settings.shadows), func(i): Game.set_setting("shadows", i); _update_info()))
	_row("Grass", UI.seg(["Flat", "Detailed"], min(1, int(Game.settings.grass)), func(i): Game.set_setting("grass", i)))
	_row("Crowd", UI.seg(["Sparse", "Full", "Packed"], int(Game.settings.crowd), func(i): Game.set_setting("crowd", i); _update_info()))
	_row("Bloom + grading", _toggle("bloom"))
	_info = UI.label("", 12, "body_m", Game.C_CARD)
	_body.add_child(_info)
	_body.add_child(UI.label("Detected GPU: " + RenderingServer.get_video_adapter_name(), 11, "body_m", Game.C_DIM))
	_body.add_child(UI.label("Shadow, crowd and grass changes apply from the next match.", 11, "body_m", Game.C_DIM))
	_update_info()


func _update_info() -> void:
	if _info == null or not is_instance_valid(_info):
		return
	var cost := float(Game.settings.render_scale) * 1.5 + int(Game.settings.shadows) * 0.5 + int(Game.settings.crowd) * 0.3 + (0.3 if Game.settings.bloom else 0.0)
	var fps := int(Game.settings.fps)
	var battery := "Low" if cost < 1.8 and fps <= 30 else ("Medium" if cost < 2.8 else "High")
	_info.text = "Battery use: %s · Target %d fps" % [battery, fps]


func _audio() -> void:
	_row("Effects", _slider("sfx_vol", 0.0, 1.0, 0.05, "%.2f"))
	_row("Crowd", _slider("crowd_vol", 0.0, 1.0, 0.05, "%.2f"))
	_row("Menu sounds", _slider("ui_vol", 0.0, 1.0, 0.05, "%.2f"))


func _data() -> void:
	_body.add_child(UI.label("Everything is stored on this phone only. Nothing is sent anywhere.", 13))
	var b := UI.button("Reset all progress", "danger", Vector2(240, 42), 16)
	var note := UI.label("", 12, "body_m", Game.C_AWAY)
	b.pressed.connect(_reset_tap.bind(b, note))
	_body.add_child(b)
	_body.add_child(note)
	_body.add_child(UI.label("Goal Digger 1.0 · Fonts: Saira Condensed, Barlow (SIL OFL)", 11, "body_m", Game.C_DIM))


func _reset_tap(b: GDButton, note: Label) -> void:
	if b.text == "Tap again to erase":
		Game.reset_save()
		note.text = "Progress reset."
		b.text = "Reset all progress"
	else:
		b.text = "Tap again to erase"
		note.text = "This deletes coins, stars, records, club and unlocks."
