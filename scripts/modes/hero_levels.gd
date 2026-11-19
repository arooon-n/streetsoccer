class_name HeroLevels
extends RefCounted
## 60 Hero Challenge levels in 4 chapters, built from hand-designed templates with fixed seeds.

const CHAPTERS := ["Sunday League", "Academy", "First Team", "Continental Nights"]
const UNLOCK := [0, 30, 80, 125]
const ORDER := ["clear", "square", "curl", "one_two", "cross", "switch", "through", "counter",
	"clear", "curl", "square", "cross", "through", "switch", "counter"]
const TITLES := {
	"clear": ["Pick your spot", "Edge of the box", "Keeper off his line", "Placed, not powered"],
	"square": ["Square it", "Pull-back", "Unselfish", "Across the face"],
	"curl": ["Bend it", "Over the wall?", "Round the wall", "Banana shot"],
	"one_two": ["Give and go", "Wall pass", "One-two", "Quick feet"],
	"cross": ["Whip it in", "Near-post run", "Header time", "Far-post header"],
	"switch": ["Switch play", "Overload on the left", "Find the space", "Long diagonal"],
	"through": ["Through the lines", "Split them", "In behind", "Thread the needle"],
	"counter": ["Counter attack", "Three on two", "Break at pace", "Everyone involved"],
}
const BONUS_TEXT := {
	"first_time": "Finish first time, no extra touch",
	"curl": "Curl the finish (bend your shot)",
	"top_corner": "Score in a top corner",
	"low": "Keep the finish low",
	"far_post": "Finish inside the far post",
	"header": "Score with a header",
	"one_two": "Play a one-two before scoring",
	"all_players": "Every attacker touches the ball",
}
const NAMES := ["Okafor", "Silva", "Mensah", "Duarte", "Takeda", "Byrne", "Haddad", "Novak", "Castillo", "Osei"]

## Seed offsets chosen by the level tuner (tests.gd "tune"): every level is solvable within par
## and multi-move levels cannot be won with a single shot.
const SEED_FIX := {"3-7": 1, "4-2": 1, "4-7": 1}

static var _cache: Array = []


static func all_levels() -> Array:
	if _cache.is_empty():
		for c in 4:
			for n in 15:
				_cache.append(_make(c, n, int(SEED_FIX.get("%d-%d" % [c + 1, n + 1], 0))))
	return _cache


static func level(id: String) -> Dictionary:
	for l in all_levels():
		if l.id == id:
			return l
	return {}


static func chapter_levels(c: int) -> Array:
	var out: Array = []
	for l in all_levels():
		if l.chapter == c:
			out.append(l)
	return out


static func chapter_name(c: int) -> String:
	return CHAPTERS[clamp(c, 0, 3)]


static func total_stars() -> int:
	var s := 0
	for k in Game.save.hero.stars.keys():
		s += int(Game.save.hero.stars[k])
	return s


static func chapter_unlocked(c: int) -> bool:
	return total_stars() >= UNLOCK[c]


static func current_chapter() -> int:
	var c := 0
	for i in 4:
		if chapter_unlocked(i):
			c = i
	return c


static func level_unlocked(l: Dictionary) -> bool:
	if not chapter_unlocked(l.chapter):
		return false
	if l.n == 0:
		return true
	var prev := "%d-%d" % [l.chapter + 1, l.n]
	return int(Game.save.hero.stars.get(prev, 0)) > 0


static func next_level(l: Dictionary) -> Dictionary:
	var all := all_levels()
	var i := all.find(l)
	if i >= 0 and i + 1 < all.size():
		return all[i + 1]
	return {}


# ------------------------------------------------------------------ templates
static func _make(c: int, n: int, seed_off := 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + c * 97 + n * 13 + seed_off * 7919
	var kind: String = ORDER[n]
	var d := c
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var lv := {"id": "%d-%d" % [c + 1, n + 1], "chapter": c, "n": n, "kind": kind,
		"title": TITLES[kind][(c + n) % 4], "attackers": [], "defenders": [], "carrier": 0,
		"keeper_skill": 0.15 + 0.18 * c, "react": 0.36 - 0.045 * c, "def_speed": 4.6 + 0.55 * c,
		"time": ["day", "dusk", "night", "night"][c], "par": 2, "bonus": "first_time"}
	if kind in ["cross", "switch"]:
		# aerial balls: cap marker speed / keeper so the landing ball stays winnable
		var dc: int = min(c, 2)
		lv.react = 0.36 - 0.045 * dc
		lv.def_speed = 4.6 + 0.55 * dc
		lv.keeper_skill = 0.15 + 0.18 * dc
	var A: Array = lv.attackers
	var D: Array = lv.defenders
	var nm := func(i: int) -> String: return NAMES[(i + n + c * 3) % NAMES.size()]
	match kind:
		"clear":
			A.append([rng.randf_range(34, 37) + d * 1.2, rng.randf_range(-6, 6), nm.call(0)])
			var bonus_opts := ["low", "top_corner", "far_post", "curl"]
			lv.bonus = bonus_opts[(n + c) % 4]
			lv.par = 1
			for k in min(d, 2):
				D.append([rng.randf_range(40, 44), A[0][1] + (k * 2 - 1) * rng.randf_range(3.5, 5.5)])
		"square":
			A.append([rng.randf_range(39, 42), side * rng.randf_range(12, 15), nm.call(0)])
			A.append([rng.randf_range(42, 45), -side * rng.randf_range(0, 2), nm.call(1)])
			D.append([47.0, side * 5.0])
			_lane_blocker(D, Vector2(A[0][0], A[0][1]), Vector2(52.5, -side * 3.0), 0.55)
			for k in d:
				D.append([rng.randf_range(44, 47), -side * rng.randf_range(4.5, 7.5) * (1 if k % 2 == 0 else -1) - side * 2.0])
			lv.par = 2
			lv.bonus = "first_time"
		"curl":
			var cz := rng.randf_range(-4, 4)
			A.append([rng.randf_range(33, 35.5), cz, nm.call(0)])
			var to_goal := (Vector2(52.5, 0) - Vector2(A[0][0], cz)).normalized()
			var wc := Vector2(A[0][0], cz) + to_goal * 9.15
			var w: int = 2 + min(d, 2)
			for k in w:
				var off: float = (k - (w - 1) * 0.5) * 0.65
				D.append([wc.x - to_goal.y * off * 0.0, wc.y + off])
			lv.par = 1
			lv.bonus = "curl"
		"one_two":
			A.append([rng.randf_range(28, 31), side * rng.randf_range(4, 7), nm.call(0)])
			A.append([rng.randf_range(35, 38), -side * rng.randf_range(1, 3), nm.call(1)])
			D.append([A[0][0] + 3.5, A[0][1] - side * 1.5])
			D.append([A[0][0] + 9.0, A[0][1] + side * 1.0])
			for k in d:
				D.append([rng.randf_range(42, 46), -side * rng.randf_range(6, 9)])
			lv.par = 3
			lv.bonus = "one_two"
		"cross":
			A.append([rng.randf_range(44, 47), side * rng.randf_range(21, 24), nm.call(0)])
			A.append([rng.randf_range(44, 46), -side * rng.randf_range(0.5, 2.5), nm.call(1)])
			D.append([A[1][0] + 2.4, A[1][1] + side * 2.3])
			D.append([A[0][0] - 3.0, A[0][1] - side * 3.0])
			for k in d:
				D.append([rng.randf_range(46, 49), side * rng.randf_range(3, 6)])
			lv.par = 2
			lv.bonus = "header"
		"switch":
			A.append([rng.randf_range(28, 32), side * rng.randf_range(16, 20), nm.call(0)])
			A.append([rng.randf_range(42, 45), -side * rng.randf_range(9, 12), nm.call(1)])
			for k in 2 + d:
				D.append([A[0][0] + rng.randf_range(4, 9), side * rng.randf_range(9, 17)])
			_lane_blocker(D, Vector2(A[0][0], A[0][1]), Vector2(52.5, -side * 3.0), 0.5)
			D.append([47.0, -side * 4.0])
			lv.par = 2
			lv.bonus = "first_time" if c % 2 == 0 else "far_post"
		"through":
			A.append([rng.randf_range(26, 28), rng.randf_range(-3, 3), nm.call(0)])
			A.append([rng.randf_range(39, 41), side * rng.randf_range(4, 7), nm.call(1)])
			A.append([rng.randf_range(33, 35), -side * rng.randf_range(8, 11), nm.call(2)])
			var nd: int = 2 + min(d, 1)
			for k in nd:
				D.append([rng.randf_range(35, 37.5), (k - (nd - 1) * 0.5) * 9.0 + rng.randf_range(-1, 1)])
			lv.par = 3
			lv.bonus = "low" if c < 2 else "first_time"
		"counter":
			A.append([rng.randf_range(30, 32), rng.randf_range(-2, 2), nm.call(0)])
			A.append([rng.randf_range(37, 39), side * rng.randf_range(10, 13), nm.call(1)])
			A.append([rng.randf_range(37, 39), -side * rng.randf_range(10, 13), nm.call(2)])
			for k in 2 + min(d, 1):
				D.append([rng.randf_range(40, 43), (k - 0.5) * 8.0 + rng.randf_range(-1, 1)])
			lv.par = 3
			lv.bonus = "all_players"
	return lv


## Puts a defender on the shooting lane from a to b at fraction t (forces a pass).
static func _lane_blocker(D: Array, a: Vector2, b: Vector2, t: float) -> void:
	var p := a.lerp(b, t)
	D.append([p.x, p.y])
