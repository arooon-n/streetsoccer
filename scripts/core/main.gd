extends Node
## Root node: owns the current screen (menus, match, modes) and handles navigation + back button.

const SCREENS := {
	"home": "res://scripts/screens/home_screen.gd",
	"setup": "res://scripts/screens/match_setup_screen.gd",
	"match": "res://scripts/match/match.gd",
	"hero_levels": "res://scripts/screens/hero_levels_screen.gd",
	"hero": "res://scripts/modes/hero_mode.gd",
	"training": "res://scripts/screens/training_screen.gd",
	"drill": "res://scripts/modes/drill_mode.gd",
	"cup_league": "res://scripts/screens/cup_league_screen.gd",
	"club": "res://scripts/screens/club_screen.gd",
	"kit_room": "res://scripts/screens/kit_room_screen.gd",
	"records": "res://scripts/screens/records_screen.gd",
	"settings": "res://scripts/screens/settings_screen.gd",
}

var current: Node = null
var current_name := ""
var history: Array = []
var _fade: ColorRect
var _layer: CanvasLayer
var _back_time := -10000


func _ready() -> void:
	Game.main = self
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "--preview":
		var pv = load("res://scripts/dev/preview.gd").new()
		pv.args = args.slice(1)
		add_child(pv)
		return
	if args.size() > 0 and args[0] == "--test":
		var t = load("res://scripts/dev/tests.gd").new()
		t.args = args.slice(1)
		add_child(t)
		return
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Game.C_NIGHT
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_fade)
	Game.apply_viewport_settings()
	get_tree().root.theme = UI.theme()
	var shot_args := args
	if shot_args.size() > 0 and shot_args[0] == "--screen":
		var prm := {"shot": shot_args[2] if shot_args.size() > 2 else "", "shot_frames": int(shot_args[3]) if shot_args.size() > 3 else 50}
		if shot_args.size() > 4:
			var extra = JSON.parse_string(shot_args[4])
			if extra is Dictionary:
				prm.merge(extra, true)
		if shot_args[1] == "match":
			var fmt: String = prm.get("format", "11")
			var home := Game.make_team("user")
			var away := Game.make_team("rbr")
			Game.choose_kits(home, away)
			Game.match_request = {"mode": "quick", "home": home, "away": away, "user_side": int(prm.get("user_side", 0)), "format": fmt, "difficulty": 2,
				"half_minutes": 5, "venue": prm.get("venue", "cage" if fmt == "5" else "harbor"), "time": prm.get("time", "night"),
				"weather": prm.get("weather", "clear"), "offside": true, "return_to": "home"}
			prm.merge(Game.match_request, false)
		show_screen(shot_args[1], prm)
		var ua := OS.get_cmdline_user_args()
		var fi := ua.find("film")
		if fi >= 0:
			var fm = load("res://scripts/dev/film.gd").new()
			fm.prefix = ua[fi + 1]
			fm.count = int(ua[fi + 2])
			fm.every = int(ua[fi + 3])
			add_child(fm)
		if OS.get_cmdline_user_args().has("probe"):
			add_child(load("res://scripts/dev/size_probe.gd").new())
	else:
		show_screen("home")


func show_screen(name: String, params: Dictionary = {}, push := true) -> void:
	if not SCREENS.has(name):
		push_warning("Unknown screen " + name)
		return
	_fade.modulate.a = 1.0
	if current:
		if push and current_name != name and current_name not in ["match", "hero", "drill"]:
			history.append([current_name, current.get_meta("params", {})])
		current.queue_free()
		current = null
		await get_tree().process_frame
	if name == "home":
		history.clear()
	var scr = load(SCREENS[name]).new()
	scr.set_meta("params", params)
	if "params" in scr:
		scr.params = params
	current = scr
	current_name = name
	add_child(scr)
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 0.0, 0.22)
	if params.get("shot", "") != "":
		_screenshot(params.shot)


func go_back() -> void:
	if current and current.has_method("on_back") and current.on_back():
		return
	if history.is_empty():
		if current_name != "home":
			show_screen("home", {}, false)
		return
	var h: Array = history.pop_back()
	show_screen(h[0], h[1], false)


func home() -> void:
	history.clear()
	show_screen("home", {}, false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and current_name == "home":
		var now := Time.get_ticks_msec()
		if now - _back_time < 2000:
			Game.write_save()
			get_tree().quit()
		else:
			_back_time = now
			var holder := Control.new()
			holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.theme = UI.theme()
			_layer.add_child(holder)
			UI.toast(holder, "Press back again to exit", Game.C_CHALK, 1.4)
			get_tree().create_timer(2.2).timeout.connect(holder.queue_free)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		Sfx.ui("back")
		go_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		if current and current.has_method("on_app_paused"):
			current.on_app_paused()
		Game.write_save()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		go_back()


func _screenshot(path: String) -> void:
	var n: int = current.get_meta("params", {}).get("shot_frames", 50) if current else 50
	for i in n:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SAVED ", path)
	get_tree().quit()
