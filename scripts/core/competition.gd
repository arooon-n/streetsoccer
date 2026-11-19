class_name Competition
extends RefCounted
## League (8 teams, 14 matchdays) and Cup (8-team knockout) stored in Game.save.

const LEAGUE_PRIZE := [3000, 1500, 800]
const CUP_PRIZE := 2000


static func team_ovr(id: String) -> int:
	if id == "user":
		return int(Game.team_by_id(Game.save.club.base).ovr)
	return int(Game.team_by_id(id).ovr)


static func team_name(id: String) -> String:
	if id == "user":
		return Game.save.club.name
	return Game.team_by_id(id).name


static func team_short(id: String) -> String:
	if id == "user":
		return Game.save.club.short
	return Game.team_by_id(id).short


static func _pick_opponents(n: int) -> Array:
	var ids: Array = []
	for t in Game.TEAMS:
		if t.id != Game.save.club.base:
			ids.append(t.id)
	ids.shuffle()
	return ids.slice(0, n)


# ------------------------------------------------------------------ league
static func new_league() -> void:
	var teams: Array = ["user"] + _pick_opponents(7)
	var rounds: Array = []
	var arr := teams.duplicate()
	var n := arr.size()
	for r in n - 1:
		var md: Array = []
		for i in n / 2:
			var a: String = arr[i]
			var b: String = arr[n - 1 - i]
			md.append([a, b] if (r + i) % 2 == 0 else [b, a])
		rounds.append(md)
		var last: String = arr.pop_back()
		arr.insert(1, last)
	var second: Array = []
	for md in rounds:
		var m2: Array = []
		for f in md:
			m2.append([f[1], f[0]])
		second.append(m2)
	Game.save.league = {"season": int(Game.save.league.get("season", 0)) + 1, "teams": teams, "fixtures": rounds + second, "results": [], "md": 0, "scorers": {}, "done": false}
	Game.write_save()


static func league_active() -> bool:
	return not Game.save.league.is_empty() and Game.save.league.has("fixtures")


static func league_user_fixture() -> Variant:
	var lg: Dictionary = Game.save.league
	if not league_active() or lg.done:
		return null
	for f in lg.fixtures[lg.md]:
		if f[0] == "user" or f[1] == "user":
			return f
	return null


static func table() -> Array:
	var lg: Dictionary = Game.save.league
	var rows := {}
	for id in lg.get("teams", []):
		rows[id] = {"id": id, "p": 0, "w": 0, "d": 0, "l": 0, "gf": 0, "ga": 0, "pts": 0}
	for md in lg.get("results", []):
		for r in md:
			var h: Dictionary = rows[r[0]]
			var a: Dictionary = rows[r[1]]
			var hg := int(r[2])
			var ag := int(r[3])
			h.p += 1
			a.p += 1
			h.gf += hg
			h.ga += ag
			a.gf += ag
			a.ga += hg
			if hg > ag:
				h.w += 1
				h.pts += 3
				a.l += 1
			elif hg < ag:
				a.w += 1
				a.pts += 3
				h.l += 1
			else:
				h.d += 1
				a.d += 1
				h.pts += 1
				a.pts += 1
	var out: Array = rows.values()
	out.sort_custom(Competition._cmp_rows)
	return out


static func _cmp_rows(x: Dictionary, y: Dictionary) -> bool:
	if x.pts != y.pts:
		return x.pts > y.pts
	if x.gf - x.ga != y.gf - y.ga:
		return x.gf - x.ga > y.gf - y.ga
	return x.gf > y.gf


static func user_position() -> int:
	var t := table()
	for i in t.size():
		if t[i].id == "user":
			return i + 1
	return 0


static func sim_score(home: String, away: String) -> Array:
	var oh := float(team_ovr(home))
	var oa := float(team_ovr(away))
	var lh := 1.35 * pow(oh / oa, 3.0) + 0.15
	var la := 1.15 * pow(oa / oh, 3.0)
	return [_poisson(lh), _poisson(la)]


static func _poisson(l: float) -> int:
	var L := exp(-l)
	var k := 0
	var p := 1.0
	while true:
		p *= randf()
		if p <= L:
			break
		k += 1
	return min(k, 7)


static func _add_scorers(id: String, goals: int, scorers: Dictionary, names = null) -> void:
	if goals <= 0:
		return
	var pool: Array = names if names != null else Game.team_player_names(id, 11).slice(5, 11)
	for g in goals:
		var n: String = pool[randi() % pool.size()] if names == null else pool[g % pool.size()]
		var key := n + "|" + id
		scorers[key] = int(scorers.get(key, 0)) + 1


# ------------------------------------------------------------------ cup
static func new_cup() -> void:
	var teams: Array = ["user"] + _pick_opponents(7)
	teams.shuffle()
	var ties: Array = []
	for i in 4:
		ties.append([teams[i * 2], teams[i * 2 + 1]])
	Game.save.cup = {"round": 0, "rounds": [ties], "results": [[]], "alive": true, "winner": "", "done": false}
	Game.write_save()


static func cup_active() -> bool:
	return not Game.save.cup.is_empty() and Game.save.cup.has("rounds")


static func cup_user_tie() -> Variant:
	var c: Dictionary = Game.save.cup
	if not cup_active() or c.done or not c.alive:
		return null
	for t in c.rounds[c.round]:
		if t[0] == "user" or t[1] == "user":
			return t
	return null


static func round_name(r: int) -> String:
	return ["Quarter-final", "Semi-final", "Final"][clamp(r, 0, 2)]


static func _sim_knockout(a: String, b: String) -> Array:
	var s := sim_score(a, b)
	var pa := 0
	var pb := 0
	if s[0] == s[1]:
		pa = 3 + randi() % 3
		pb = 3 + randi() % 3
		if pa == pb:
			pa += 1
	return [a, b, s[0], s[1], pa, pb]


static func _winner(r: Array) -> String:
	if r[2] != r[3]:
		return r[0] if r[2] > r[3] else r[1]
	return r[0] if r[4] > r[5] else r[1]


static func _advance_cup(c: Dictionary) -> void:
	var res: Array = c.results[c.round]
	if c.round == 2:
		c.winner = _winner(res[0])
		c.done = true
		if c.winner == "user":
			Game.add_coins(CUP_PRIZE)
		return
	var winners: Array = []
	for r in res:
		winners.append(_winner(r))
	var ties: Array = []
	for i in winners.size() / 2:
		ties.append([winners[i * 2], winners[i * 2 + 1]])
	c.round += 1
	c.rounds.append(ties)
	c.results.append([])
	if not c.alive:
		for t in ties:
			c.results[c.round].append(_sim_knockout(t[0], t[1]))
		_advance_cup(c)


# ------------------------------------------------------------------ results
static func record_user_result(params: Dictionary, home_g: int, away_g: int, home_p: int, away_p: int, scorer_names: Array) -> void:
	var mode: String = params.get("mode", "")
	var home_id: String = params.get("home_id", "")
	var away_id: String = params.get("away_id", "")
	if mode == "league" and league_active():
		var lg: Dictionary = Game.save.league
		var md_res: Array = []
		for f in lg.fixtures[lg.md]:
			if f[0] == home_id and f[1] == away_id:
				md_res.append([f[0], f[1], home_g, away_g])
				var user_is_home: bool = f[0] == "user"
				_add_scorers("user", home_g if user_is_home else away_g, lg.scorers, scorer_names if scorer_names.size() > 0 else null)
				var opp: String = f[1] if user_is_home else f[0]
				_add_scorers(opp, away_g if user_is_home else home_g, lg.scorers)
			else:
				var s := sim_score(f[0], f[1])
				md_res.append([f[0], f[1], s[0], s[1]])
				_add_scorers(f[0], s[0], lg.scorers)
				_add_scorers(f[1], s[1], lg.scorers)
		lg.results.append(md_res)
		lg.md += 1
		if lg.md >= lg.fixtures.size():
			lg.done = true
			var pos := user_position()
			if pos >= 1 and pos <= 3:
				Game.add_coins(LEAGUE_PRIZE[pos - 1])
		Game.write_save()
	elif mode == "cup" and cup_active():
		var c: Dictionary = Game.save.cup
		for t in c.rounds[c.round]:
			if t[0] == home_id and t[1] == away_id:
				c.results[c.round].append([t[0], t[1], home_g, away_g, home_p, away_p])
				if _winner(c.results[c.round][c.results[c.round].size() - 1]) != "user":
					c.alive = false
			else:
				c.results[c.round].append(_sim_knockout(t[0], t[1]))
		_advance_cup(c)
		Game.write_save()


## Builds the match request for the user's next league / cup game.
static func make_request(mode: String) -> Dictionary:
	var fx: Variant = league_user_fixture() if mode == "league" else cup_user_tie()
	if fx == null:
		return {}
	var home := Game.make_team(fx[0])
	var away := Game.make_team(fx[1])
	Game.choose_kits(home, away)
	var user_side := 0 if fx[0] == "user" else 1
	var c: Dictionary = Game.save.cup
	return {"mode": mode, "home": home, "away": away, "home_id": fx[0], "away_id": fx[1], "user_side": user_side,
		"format": "11", "difficulty": int(Game.settings.difficulty), "half_minutes": int(Game.settings.half_minutes),
		"venue": "harbor" if fx[0] == "user" else ("oldground" if Game.is_unlocked("venues", "oldground") and randf() < 0.5 else "harbor"),
		"time": ["night", "dusk", "day"][randi() % 3], "weather": "rain" if randf() < 0.2 else "clear",
		"offside": bool(Game.settings.offside), "knockout": mode == "cup", "extra_time": mode == "cup" and int(c.get("round", 0)) == 2,
		"return_to": "cup_league"}
