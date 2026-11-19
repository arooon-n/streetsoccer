extends Node
## Home: live stadium backdrop + main menu (approved mockup layout).

const DAILY := [
	{"drill": "freekick", "text": "Score 3 free kicks into the rings", "goal": 3, "reward": 250},
	{"drill": "penalty", "text": "Score 4 penalties in one round", "goal": 4, "reward": 200},
	{"drill": "shooting", "text": "Reach 900 points in the shooting gallery", "goal": 900, "reward": 250},
	{"drill": "dribble", "text": "Finish the dribble run in under 17 s", "goal": 1, "reward": 250},
	{"drill": "keeper", "text": "Make 8 saves in keeper reflexes", "goal": 8, "reward": 250},
	{"drill": "corner", "text": "Score 3 headers from corners", "goal": 3, "reward": 250},
]

var params := {}
var backdrop: MenuBackdrop
var root: Control
var coins_pill: PanelContainer


static func daily_today() -> Dictionary:
	var d := Time.get_date_dict_from_system()
	var idx: int = (d.year * 372 + d.month * 31 + d.day) % DAILY.size()
	var info: Dictionary = DAILY[idx].duplicate()
	var sv: Dictionary = Game.save.daily
	if sv.get("date", "") != Game.today():
		sv.date = Game.today()
		sv.progress = 0
		sv.done = false
		Game.write_save()
	info["progress"] = int(sv.get("progress", 0))
	info["done"] = bool(sv.get("done", false))
	return info


## Drill modes report results here; returns coins awarded (0 if not completed now).
static func daily_report(drill: String, value: int) -> int:
	var info := daily_today()
	if info.drill != drill or info.done:
		return 0
	var sv: Dictionary = Game.save.daily
	sv.progress = max(int(sv.progress), value)
	if int(sv.progress) >= int(info.goal):
		sv.done = true
		Game.add_coins(int(info.reward))
		Game.write_save()
		return int(info.reward)
	Game.write_save()
	return 0


func _ready() -> void:
	backdrop = MenuBackdrop.new()
	add_child(backdrop)
	var layer := CanvasLayer.new()
	add_child(layer)
	root = UI.screen_root()
	layer.add_child(root)
	_shade()
	var m := UI.safe_margin()
	root.add_child(m)
	var col := Control.new()
	m.add_child(col)
	# top bar
	var top := UI.hbox(10)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	col.add_child(top)
	var crest := Crest.new().setup(Color(Game.save.club.crest.c1), Color(Game.save.club.crest.c2), Game.save.club.short, int(Game.save.club.crest.get("shape", 0)), int(Game.save.club.crest.get("pattern", 1)))
	crest.custom_minimum_size = Vector2(30, 33)
	top.add_child(crest)
	var idv := UI.vbox(2)
	idv.add_child(UI.label(Game.save.club.name, 15, "disp", Game.C_CHALK, true))
	var lvrow := UI.hbox(6)
	lvrow.add_child(UI.label("Lv %d" % Game.level(), 11, "body_m", Game.C_DIM))
	var xp := ProgressBar.new()
	xp.custom_minimum_size = Vector2(90, 4)
	xp.show_percentage = false
	xp.value = Game.level_progress() * 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.93, 0.95, 0.92, 0.15)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Game.C_HOME
	xp.add_theme_stylebox_override("background", bg)
	xp.add_theme_stylebox_override("fill", fg)
	xp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lvrow.add_child(xp)
	idv.add_child(lvrow)
	top.add_child(idv)
	top.add_child(UI.spacer())
	coins_pill = UI.pill("{0}".format([_fmt(Game.save.coins)]), true)
	coins_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(coins_pill)
	var gear := UI.icon_button("gear", "Settings")
	gear.pressed.connect(func(): Game.goto("settings"))
	top.add_child(gear)
	Game.coins_changed.connect(_on_coins)
	# logo + menu
	var left := UI.vbox(14)
	left.position = Vector2(4, 50)
	col.add_child(left)
	left.add_child(_logo())
	var menu := UI.vbox(7)
	left.add_child(menu)
	var play := _menu_item("Play Match", "vs bots · 11v11 or 5-a-side", "play", Vector2(330, 62))
	play.pressed.connect(func(): Game.goto("setup"))
	menu.add_child(play)
	var stars := 0
	for k in Game.save.hero.stars.keys():
		stars += int(Game.save.hero.stars[k])
	var hero := _menu_item("Hero Challenges", "%s · ★ %d / 180" % [HeroLevels.chapter_name(HeroLevels.current_chapter()), stars], "menu", Vector2(330, 44))
	hero.pressed.connect(func(): Game.goto("hero_levels"))
	menu.add_child(hero)
	var golds := 0
	for k in Game.save.training.keys():
		if int(Game.save.training[k].get("medal", 0)) >= 3:
			golds += 1
	var tr := _menu_item("Training Ground", "6 drills · %d gold medal%s" % [golds, "" if golds == 1 else "s"], "menu", Vector2(330, 44))
	tr.pressed.connect(func(): Game.goto("training"))
	menu.add_child(tr)
	var cl := _menu_item("Cup & League", _comp_sub(), "menu", Vector2(330, 44))
	cl.pressed.connect(func(): Game.goto("cup_league"))
	menu.add_child(cl)
	# bottom-left pills
	var pills := UI.hbox(8)
	pills.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	pills.position = Vector2(4, 0)
	col.add_child(pills)
	for pr in [["Club", "club"], ["Kit room", "kit_room"], ["Records", "records"]]:
		var b := UI.button(pr[0], "ghost", Vector2(0, 30), 14)
		b.pressed.connect(Game.goto.bind(pr[1]))
		pills.add_child(b)
	# daily drill
	var daily := _daily_panel()
	col.add_child(daily)
	await get_tree().process_frame
	pills.position = Vector2(4, col.size.y - pills.size.y)
	daily.position = Vector2(col.size.x - daily.size.x, col.size.y - daily.size.y)


func _on_coins(v) -> void:
	if is_instance_valid(coins_pill):
		UI.pill_set(coins_pill, _fmt(v))


func _exit_tree() -> void:
	if Game.coins_changed.is_connected(_on_coins):
		Game.coins_changed.disconnect(_on_coins)


func _fmt(v) -> String:
	var s := str(int(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _comp_sub() -> String:
	if Competition.league_active() and not Game.save.league.done:
		return "Matchday %d of 14 · %s" % [int(Game.save.league.md) + 1, _ord(Competition.user_position())]
	if Competition.cup_active() and Game.save.cup.alive and not Game.save.cup.done:
		return "Cup · " + Competition.round_name(int(Game.save.cup.round))
	return "Season or cup run"


func _ord(n: int) -> String:
	var suf := "th"
	if n % 100 < 11 or n % 100 > 13:
		suf = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return str(n) + suf


func _shade() -> void:
	var tr := TextureRect.new()
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.4, 0.7, 1.0])
	grad.colors = PackedColorArray([Color(0.02, 0.055, 0.067, 0.96), Color(0.02, 0.055, 0.067, 0.8), Color(0.02, 0.055, 0.067, 0.15), Color(0.02, 0.055, 0.067, 0.0)])
	g.gradient = grad
	g.width = 256
	g.height = 4
	tr.texture = g
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(tr)


func _logo() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(330, 40)
	c.draw.connect(_draw_logo.bind(c))
	return c


func _draw_logo(c: Control) -> void:
	var f := UI.font("disp_x")
	c.draw_set_transform(Vector2(0, 0), 0.0, Vector2.ONE)
	var xf := Transform2D(Vector2(1, 0), Vector2(-0.176, 1), Vector2(8, 0))
	c.draw_set_transform_matrix(xf)
	c.draw_string(f, Vector2(0, 36), "GOAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Game.C_CHALK)
	var w := f.get_string_size("GOAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
	c.draw_string(f, Vector2(w + 10, 36), "DIGGER", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Game.C_HOME)


func _menu_item(title: String, sub: String, style: String, sz: Vector2) -> GDButton:
	var b := GDButton.new()
	b.style = style
	b.text = title
	b.subtitle = sub
	b.font_size = 28 if style == "play" else 19
	b.custom_minimum_size = sz
	return b


func _daily_panel() -> Control:
	var info := daily_today()
	var p := UI.panel()
	p.custom_minimum_size = Vector2(250, 0)
	var v := UI.vbox(6)
	p.add_child(v)
	var row := UI.hbox(6)
	row.add_child(UI.eyebrow("Today's drill", Game.C_CARD))
	row.add_child(UI.spacer())
	row.add_child(UI.pill("+%d" % info.reward if not info.done else "Done", not info.done))
	v.add_child(row)
	var t := UI.label(info.text, 14, "body_sb")
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 226
	v.add_child(t)
	var prog := UI.hbox(8)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(150, 4)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.value = 100.0 * clamp(float(info.progress) / float(info.goal), 0.0, 1.0) if not info.done else 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.93, 0.95, 0.92, 0.18)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Game.C_CARD
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	prog.add_child(bar)
	prog.add_child(UI.label("%d / %d" % [min(info.progress, info.goal), info.goal] if info.goal > 1 else ("Done" if info.done else "Not yet"), 11, "body_m", Game.C_DIM))
	v.add_child(prog)
	var go := UI.button("Play drill", "ghost", Vector2(0, 30), 14)
	go.pressed.connect(func(): Game.goto("drill", {"drill": info.drill}))
	v.add_child(go)
	return p
