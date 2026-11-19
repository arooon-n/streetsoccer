extends Node
## Global game state: save data, settings, team database, screen routing.

signal coins_changed(value: int)
signal settings_changed

const SAVE_PATH := "user://save.json"
const SETTINGS_PATH := "user://settings.json"
const SAVE_VERSION := 1

# ---------- palette (from the approved mockups) ----------
const C_NIGHT := Color("07141A")
const C_TURF := Color("0E2622")
const C_TURF2 := Color("153730")
const C_CHALK := Color("EDF2EA")
const C_DIM := Color("9DB3AB")
const C_CARD := Color("FFCF33")
const C_INK := Color("1C1500")
const C_AWAY := Color("FF5B4A")
const C_HOME := Color("43C6F0")
const C_LINE := Color(0.93, 0.95, 0.92, 0.14)
const C_LINE2 := Color(0.93, 0.95, 0.92, 0.28)

var main: Node = null            # set by main.gd
var save: Dictionary = {}
var settings: Dictionary = {}
var match_request: Dictionary = {}   # parameters for the next match / mode
var last_result: Dictionary = {}

# ---------- fictional clubs ----------
# kit: [shirt, shirt2, pattern, shorts, socks]; pattern 0 plain 1 stripes 2 hoops 3 sash 4 halves
const TEAMS := [
	{"id": "hcf", "name": "Harbor City", "full": "Harbor City FC", "short": "HCF", "ovr": 78,
		"home": ["3FB8E6", "0E2238", 0, "0E2238", "3FB8E6"], "away": ["F4F1EA", "3FB8E6", 3, "F4F1EA", "0E2238"], "crest": ["0E2238", "3FB8E6"]},
	{"id": "rbr", "name": "Redbrick Rovers", "full": "Redbrick Rovers", "short": "RBR", "ovr": 81,
		"home": ["E5493C", "F4F1EA", 0, "F4F1EA", "E5493C"], "away": ["F2E6C8", "E5493C", 2, "2B2B2B", "F2E6C8"], "crest": ["7A1F18", "E5493C"]},
	{"id": "ngu", "name": "Northgate United", "full": "Northgate United", "short": "NGU", "ovr": 79,
		"home": ["F4F4F2", "1A1A1A", 1, "1A1A1A", "F4F4F2"], "away": ["2A2F45", "F2C230", 0, "2A2F45", "2A2F45"], "crest": ["1A1A1A", "F4F4F2"]},
	{"id": "val", "name": "Vale Athletic", "full": "Vale Athletic", "short": "VAL", "ovr": 76,
		"home": ["7B2242", "8FCBEA", 4, "F4F1EA", "7B2242"], "away": ["8FCBEA", "7B2242", 0, "7B2242", "8FCBEA"], "crest": ["7B2242", "8FCBEA"]},
	{"id": "irt", "name": "Ironbridge Town", "full": "Ironbridge Town", "short": "IRT", "ovr": 74,
		"home": ["F08A24", "151515", 2, "151515", "F08A24"], "away": ["151515", "F08A24", 0, "151515", "151515"], "crest": ["151515", "F08A24"]},
	{"id": "sol", "name": "Sol Dorado", "full": "Sol Dorado", "short": "SOL", "ovr": 83,
		"home": ["F6D23A", "1F7A4D", 0, "1F7A4D", "F6D23A"], "away": ["1F7A4D", "F6D23A", 3, "F4F1EA", "1F7A4D"], "crest": ["1F7A4D", "F6D23A"]},
	{"id": "kgm", "name": "Kingsmere", "full": "Kingsmere FC", "short": "KGM", "ovr": 80,
		"home": ["2346B8", "F4F1EA", 0, "F4F1EA", "2346B8"], "away": ["F4F1EA", "2346B8", 2, "2346B8", "F4F1EA"], "crest": ["14286B", "2346B8"]},
	{"id": "efa", "name": "Eastfield Albion", "full": "Eastfield Albion", "short": "EFA", "ovr": 77,
		"home": ["2E9E5B", "F4F1EA", 2, "F4F1EA", "2E9E5B"], "away": ["F4F1EA", "2E9E5B", 0, "2E9E5B", "F4F1EA"], "crest": ["17502E", "2E9E5B"]},
	{"id": "mar", "name": "Marisco", "full": "Marisco CF", "short": "MAR", "ovr": 82,
		"home": ["5B2C83", "E8B730", 1, "5B2C83", "5B2C83"], "away": ["E8B730", "5B2C83", 0, "5B2C83", "E8B730"], "crest": ["5B2C83", "E8B730"]},
	{"id": "ltw", "name": "Lowtide Wanderers", "full": "Lowtide Wanderers", "short": "LTW", "ovr": 72,
		"home": ["1C8C8C", "F4F1EA", 4, "0F3B3B", "1C8C8C"], "away": ["F4F1EA", "1C8C8C", 0, "F4F1EA", "1C8C8C"], "crest": ["0F3B3B", "1C8C8C"]},
]

const FIRST := ["D.", "M.", "J.", "T.", "A.", "L.", "K.", "R.", "S.", "E.", "N.", "O.", "P.", "C.", "B.", "F.", "G.", "H.", "I.", "V."]
const LAST := ["Okafor", "Silva", "Brandt", "Moreau", "Kowalski", "Haddad", "Lindqvist", "Mensah", "Ferreira", "Novak",
	"Takeda", "Osei", "Duarte", "Byrne", "Castillo", "Adeyemi", "Petrov", "Larsen", "Romano", "Achebe",
	"Varga", "Quinn", "Saito", "Ibarra", "Dlamini", "Keane", "Rossi", "Mbeki", "Navarro", "Holm",
	"Bakker", "Sousa", "Yilmaz", "Reyes", "Nakamura", "Eriksen", "Diallo", "Morales", "Fischer", "Abara",
	"Costa", "Lund", "Ward", "Kane", "Pires", "Dumas", "Koné", "Vidal", "Strand", "Oduya"]
const SKIN_TONES := ["8D5A3B", "C68B63", "E9C19D", "5B3A26", "B07850", "D9A47C", "F1CDB0", "6E452D"]
const HAIR := ["1A120C", "2B1B10", "3B2A1A", "0E0E0E", "6B4A2B", "A7834F", "1A120C", "4A2F1D"]

const VENUES := {
	"harbor": {"name": "Harbor Arena", "cost": 0, "format": "11"},
	"oldground": {"name": "Old Ground", "cost": 2500, "format": "11"},
	"cage": {"name": "Street Cage", "cost": 0, "format": "5"},
}
const BALLS := {
	"classic": {"name": "Classic", "cost": 0, "a": "F4F4F2", "b": "151A1A"},
	"nightglow": {"name": "Night Glow", "cost": 800, "a": "FFCF33", "b": "1C1500"},
	"ice": {"name": "Ice", "cost": 1200, "a": "E8F6FF", "b": "2B6CB0"},
	"ember": {"name": "Ember", "cost": 1500, "a": "FF5B4A", "b": "2A0E0A"},
	"street": {"name": "Street", "cost": 600, "a": "F08A24", "b": "1A1A1A"},
}
const BOOTS := {
	"black": {"name": "Classic Black", "cost": 0, "c": "151515"},
	"white": {"name": "Pure White", "cost": 400, "c": "F2F2F2"},
	"volt": {"name": "Volt", "cost": 700, "c": "D7F43A"},
	"coral": {"name": "Coral", "cost": 700, "c": "FF5B4A"},
	"gold": {"name": "Gold", "cost": 2000, "c": "E3B622"},
}
const CELEBRATIONS := {
	"fist": {"name": "Fist Pump", "cost": 0},
	"airplane": {"name": "Airplane", "cost": 900},
	"kneeslide": {"name": "Knee Slide", "cost": 1400},
	"arms": {"name": "Arms Wide", "cost": 600},
}

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	load_settings()
	load_save()
	get_tree().root.size_changed.connect(_on_resize)


func _on_resize() -> void:
	pass


# ================= routing =================
func goto(screen: String, params: Dictionary = {}) -> void:
	if main and main.has_method("show_screen"):
		main.show_screen(screen, params)


func back() -> void:
	if main and main.has_method("go_back"):
		main.go_back()


# ================= save data =================
func default_save() -> Dictionary:
	var t: Dictionary = TEAMS[0]
	return {
		"version": SAVE_VERSION,
		"coins": 1000,
		"xp": 0,
		"club": {
			"name": t.full, "short": t.short, "base": "hcf",
			"crest": {"shape": 0, "c1": t.crest[0], "c2": t.crest[1], "pattern": 1},
			"home": t.home.duplicate(), "away": t.away.duplicate(),
			"players": team_player_names("hcf", 16),
		},
		"unlocks": {"balls": ["classic"], "boots": ["black"], "celebrations": ["fist"], "venues": ["harbor", "cage"]},
		"equipped": {"ball": "classic", "boots": "black", "celebration": "fist"},
		"hero": {"stars": {}, "best": {}},
		"training": {},
		"daily": {"date": "", "progress": 0, "done": false},
		"league": {},
		"cup": {},
		"records": {"played": 0, "won": 0, "drawn": 0, "lost": 0, "gf": 0, "ga": 0, "best_win": "", "goals_scored_total": 0},
	}


func load_save() -> void:
	save = default_save()
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			var data = JSON.parse_string(f.get_as_text())
			if data is Dictionary:
				_merge(save, data)
	_normalize()
	write_save()


## JSON stores every number as a float; restore integers where the game expects them.
func _normalize() -> void:
	save.coins = int(save.coins)
	save.xp = int(save.xp)
	for k in save.records.keys():
		if k != "best_win":
			save.records[k] = int(save.records[k])
	for k in save.hero.stars.keys():
		save.hero.stars[k] = int(save.hero.stars[k])
	for k in save.training.keys():
		var t: Dictionary = save.training[k]
		t.medal = int(t.get("medal", 0))
		if k != "dribble":
			t.best = int(t.get("best", 0))
	save.daily.progress = int(save.daily.get("progress", 0))
	if save.league.has("md"):
		save.league.md = int(save.league.md)
		save.league.season = int(save.league.season)
		for md in save.league.get("results", []):
			for r in md:
				r[2] = int(r[2])
				r[3] = int(r[3])
		for k in save.league.get("scorers", {}).keys():
			save.league.scorers[k] = int(save.league.scorers[k])
	if save.cup.has("round"):
		save.cup.round = int(save.cup.round)
		for rr in save.cup.get("results", []):
			for r in rr:
				for i in range(2, 6):
					r[i] = int(r[i])


func _merge(dst: Dictionary, src: Dictionary) -> void:
	for k in src.keys():
		if dst.has(k) and dst[k] is Dictionary and src[k] is Dictionary:
			_merge(dst[k], src[k])
		else:
			dst[k] = src[k]


func write_save() -> void:
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write save")
		return
	f.store_string(JSON.stringify(save))
	f.close()
	var d := DirAccess.open("user://")
	if d:
		if d.file_exists("save.json"):
			d.remove("save.json")
		d.rename("save.json.tmp", "save.json")


func reset_save() -> void:
	save = default_save()
	write_save()
	coins_changed.emit(save.coins)


func add_coins(n: int) -> void:
	save.coins = max(0, int(save.coins) + n)
	write_save()
	coins_changed.emit(save.coins)


func spend(n: int) -> bool:
	if int(save.coins) < n:
		return false
	add_coins(-n)
	return true


func add_xp(n: int) -> void:
	save.xp = int(save.xp) + n
	write_save()


func level() -> int:
	return 1 + int(floor(sqrt(float(save.xp) / 120.0)))


func level_progress() -> float:
	var l := level()
	var a = 120.0 * pow(l - 1, 2)
	var b = 120.0 * pow(l, 2)
	return clamp((float(save.xp) - a) / (b - a), 0.0, 1.0)


func is_unlocked(kind: String, id: String) -> bool:
	return id in save.unlocks.get(kind, [])


func unlock(kind: String, id: String) -> void:
	if not save.unlocks.has(kind):
		save.unlocks[kind] = []
	if not id in save.unlocks[kind]:
		save.unlocks[kind].append(id)
	write_save()


# ================= settings =================
func default_settings() -> Dictionary:
	return {
		"preset": "auto", "fps": 60, "render_scale": 0.8, "shadows": 2, "grass": 1, "crowd": 2, "bloom": true,
		"camera": "broadcast", "difficulty": 2, "half_minutes": 5, "offside": true,
		"sfx_vol": 0.9, "crowd_vol": 0.8, "ui_vol": 0.7, "haptics": true,
		"controls_scale": 1.0, "controls_opacity": 0.85, "auto_switch": true, "aim_assist": true,
		"preset_resolved": "",
	}


func load_settings() -> void:
	settings = default_settings()
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if f:
			var data = JSON.parse_string(f.get_as_text())
			if data is Dictionary:
				for k in data.keys():
					settings[k] = data[k]
				for k in ["fps", "shadows", "grass", "crowd", "difficulty", "half_minutes"]:
					settings[k] = int(settings[k])
	if settings.preset == "auto":
		apply_preset(detect_preset(), false)
	write_settings()


func write_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))


func set_setting(key: String, value) -> void:
	settings[key] = value
	if key in ["render_scale", "shadows", "grass", "crowd", "bloom", "fps"]:
		settings.preset = "custom"
	write_settings()
	apply_viewport_settings()
	settings_changed.emit()


func detect_preset() -> String:
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	var os := OS.get_name()
	if os != "Android" and os != "iOS":
		return "high"
	var re := RegEx.new()
	re.compile("adreno[^0-9]*([0-9]{3})")
	var m := re.search(gpu)
	if m:
		var n := int(m.get_string(1))
		if n >= 730:
			return "ultra"
		if n >= 650:
			return "high"
		if n >= 610:
			return "medium"
		return "low"
	if gpu.contains("mali-g7") or gpu.contains("immortalis"):
		return "high"
	if gpu.contains("mali-g6") or gpu.contains("mali-g5"):
		return "medium"
	if gpu.contains("xclipse"):
		return "high"
	return "medium"


func apply_preset(p: String, emit := true) -> void:
	var resolved := p
	if p == "auto":
		resolved = detect_preset()
	match resolved:
		"low":
			settings.merge({"render_scale": 0.62, "shadows": 0, "grass": 0, "crowd": 0, "bloom": false, "fps": 30}, true)
		"medium":
			settings.merge({"render_scale": 0.72, "shadows": 1, "grass": 1, "crowd": 1, "bloom": true, "fps": 60}, true)
		"high":
			settings.merge({"render_scale": 0.85, "shadows": 2, "grass": 1, "crowd": 2, "bloom": true, "fps": 60}, true)
		"ultra":
			settings.merge({"render_scale": 1.0, "shadows": 2, "grass": 2, "crowd": 2, "bloom": true, "fps": 60}, true)
	settings.preset = p
	settings.preset_resolved = resolved
	write_settings()
	apply_viewport_settings()
	if emit:
		settings_changed.emit()


func apply_viewport_settings() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	# FSR is Forward+ only; the Mobile renderer upscales bilinearly.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = float(settings.render_scale)
	vp.msaa_3d = Viewport.MSAA_2X if int(settings.shadows) >= 2 and float(settings.render_scale) >= 0.84 else Viewport.MSAA_DISABLED
	Engine.max_fps = int(settings.fps)


func crowd_count() -> int:
	return [2200, 4200, 7000][clamp(int(settings.crowd), 0, 2)]


# ================= team helpers =================
func team_by_id(id: String) -> Dictionary:
	for t in TEAMS:
		if t.id == id:
			return t
	return TEAMS[0]


func team_player_names(id: String, n: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash(id) & 0x7fffffff
	var out: Array = []
	var used := {}
	while out.size() < n:
		var ln: String = LAST[r.randi() % LAST.size()]
		if used.has(ln):
			continue
		used[ln] = true
		out.append(FIRST[r.randi() % FIRST.size()] + " " + ln)
	return out


## Builds a runtime team description used by the match engine.
func make_team(id: String, kit: String = "home") -> Dictionary:
	var t: Dictionary
	if id == "user":
		var c: Dictionary = save.club
		var base = team_by_id(c.base)
		t = {"id": "user", "name": _short_name(c.name), "full": c.name, "short": c.short, "ovr": base.ovr,
			"home": c.home, "away": c.away, "crest": [c.crest.c1, c.crest.c2], "names": c.players.duplicate(), "user": true}
	else:
		var b := team_by_id(id)
		t = b.duplicate(true)
		t["names"] = team_player_names(id, 16)
		t["user"] = false
	t["kit_name"] = kit
	t["kit"] = t[kit]
	return t


func _short_name(full: String) -> String:
	var s := full.replace(" FC", "").replace(" CF", "")
	return s


func kit_colors(kit: Array) -> Dictionary:
	return {"shirt": Color(kit[0]), "shirt2": Color(kit[1]), "pattern": int(kit[2]), "shorts": Color(kit[3]), "socks": Color(kit[4])}


## Picks the opponent kit that contrasts best with the home kit.
func choose_kits(home: Dictionary, away: Dictionary) -> void:
	var h = Color(home.home[0])
	var a = Color(away.home[0])
	if _kit_distance(h, a) < 0.35:
		away.kit_name = "away"
		away.kit = away.away
	else:
		away.kit_name = "home"
		away.kit = away.home
	home.kit_name = "home"
	home.kit = home.home


func _kit_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() + abs(a.get_luminance() - b.get_luminance())


func today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


func haptic(ms: int = 20) -> void:
	if settings.get("haptics", true) and OS.get_name() == "Android":
		Input.vibrate_handheld(ms)
