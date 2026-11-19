extends Control
## Records: career totals, training bests, hero stars.

var params := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	var c := ColorRect.new()
	c.color = Game.C_NIGHT
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	UI.bg_gradient(self)
	var m := UI.safe_margin()
	add_child(m)
	var v := UI.vbox(12)
	m.add_child(v)
	v.add_child(UI.header("Records", Game.back))
	var row := UI.hbox(12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	var r: Dictionary = Game.save.records
	row.add_child(_card("Matches", [["Played", str(r.played)], ["Won", str(r.won)], ["Drawn", str(r.drawn)], ["Lost", str(r.lost)],
		["Goals for", str(r.gf)], ["Goals against", str(r.ga)], ["Best win", r.best_win if r.best_win != "" else "-"]]))
	var tr: Array = []
	for d in ["freekick", "penalty", "corner", "shooting", "dribble", "keeper"]:
		var rec: Dictionary = Game.save.training.get(d, {})
		var name: String = load("res://scripts/modes/drill_mode.gd").INFO[d].name
		var best := "-"
		if rec.has("best") and float(rec.best) > 0.0:
			best = ("%.2f s" % float(rec.best)) if d == "dribble" else str(int(rec.best))
		best += "  " + ["", "· Bronze", "· Silver", "· Gold"][int(rec.get("medal", 0))]
		tr.append([name, best])
	row.add_child(_card("Training bests", tr))
	var hs: Array = [["Total stars", "%d / 180" % HeroLevels.total_stars()]]
	for ci in 4:
		var s := 0
		for l in HeroLevels.chapter_levels(ci):
			s += int(Game.save.hero.stars.get(l.id, 0))
		hs.append([HeroLevels.CHAPTERS[ci], "%d / 45" % s])
	hs.append(["Level", str(Game.level())])
	hs.append(["Coins", str(Game.save.coins)])
	row.add_child(_card("Hero & career", hs))


func _card(title: String, rows: Array) -> Control:
	var p := UI.panel()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(7)
	p.add_child(v)
	v.add_child(UI.eyebrow(title, Game.C_CARD))
	for r in rows:
		var h := UI.hbox(8)
		var a := UI.label(r[0], 13, "body_m", Game.C_DIM)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		h.add_child(UI.label(r[1], 13, "body_b"))
		v.add_child(h)
	return p
