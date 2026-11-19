extends Control
## Kit room: unlock and equip balls, boots, celebrations and venues with coins.

var params := {}
var tab := 0
var _grid: GridContainer
var _coins: PanelContainer


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
	var v := UI.vbox(10)
	m.add_child(v)
	var head := UI.header("Kit room", Game.back)
	head.add_child(UI.spacer())
	head.add_child(UI.seg(["Balls", "Boots", "Celebrations", "Venues"], tab, func(i): tab = i; _build()))
	_coins = UI.pill(str(Game.save.coins), true)
	head.add_child(_coins)
	v.add_child(head)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	v.add_child(_grid)
	_build()


func _kind() -> Array:
	return [["balls", Game.BALLS, "ball"], ["boots", Game.BOOTS, "boots"], ["celebrations", Game.CELEBRATIONS, "celebration"], ["venues", Game.VENUES, ""]][tab]


func _build() -> void:
	for ch in _grid.get_children():
		ch.queue_free()
	UI.pill_set(_coins, str(Game.save.coins))
	var k := _kind()
	var items: Dictionary = k[1]
	for id in items.keys():
		_grid.add_child(_item(k[0], k[2], id, items[id]))


func _item(kind: String, eq_key: String, id: String, info: Dictionary) -> Control:
	var p := UI.panel(false)
	p.custom_minimum_size = Vector2(178, 0)
	var v := UI.vbox(6)
	p.add_child(v)
	var art := Control.new()
	art.custom_minimum_size = Vector2(150, 58)
	art.draw.connect(_draw_art.bind(art, kind, id, info))
	v.add_child(art)
	v.add_child(UI.label(info.name, 16, "disp", Game.C_CHALK, true))
	var owned := Game.is_unlocked(kind, id)
	var equipped: bool = eq_key != "" and Game.save.equipped.get(eq_key, "") == id
	var b: GDButton
	if equipped:
		b = UI.button("Equipped", "ghost", Vector2(150, 34), 14)
		b.disabled = true
	elif owned:
		b = UI.button("Equip" if eq_key != "" else "Owned", "ghost", Vector2(150, 34), 14)
		if eq_key == "":
			b.disabled = true
		b.pressed.connect(func(): Game.save.equipped[eq_key] = id; Game.write_save(); _build())
	else:
		b = UI.button("%d coins" % info.cost, "primary", Vector2(150, 34), 14)
		b.pressed.connect(_buy.bind(kind, eq_key, id, int(info.cost)))
	v.add_child(b)
	return p


func _buy(kind: String, eq_key: String, id: String, cost: int) -> void:
	if not Game.spend(cost):
		UI.toast(self, "Not enough coins yet · play matches, levels and drills to earn more", Game.C_AWAY)
		return
	Sfx.ui("coin")
	Game.unlock(kind, id)
	if eq_key != "":
		Game.save.equipped[eq_key] = id
	Game.write_save()
	_build()


func _draw_art(c: Control, kind: String, id: String, info: Dictionary) -> void:
	var ctr := c.size * 0.5
	match kind:
		"balls":
			c.draw_circle(ctr, 24, Color(info.a))
			var pent := PackedVector2Array()
			for i in 5:
				var a := -PI / 2.0 + i * TAU / 5.0
				pent.append(ctr + Vector2(cos(a), sin(a)) * 9.0)
			c.draw_colored_polygon(pent, Color(info.b))
			for i in 5:
				var a := -PI / 2.0 + i * TAU / 5.0
				c.draw_line(ctr + Vector2(cos(a), sin(a)) * 9.0, ctr + Vector2(cos(a), sin(a)) * 22.0, Color(info.b), 2.0)
		"boots":
			var col := Color(info.c)
			c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(-40, 10), ctr + Vector2(-36, -12), ctr + Vector2(-10, -14), ctr + Vector2(20, -2), ctr + Vector2(40, 4), ctr + Vector2(40, 12)]), col)
			for i in 4:
				c.draw_circle(ctr + Vector2(-30 + i * 20, 15), 3, Color(0.6, 0.6, 0.6))
		"celebrations":
			Icon.draw_icon(c, "trophy", Rect2(ctr - Vector2(18, 18), Vector2(36, 36)), Game.C_CARD)
		"venues":
			var col = {"harbor": Color("43C6F0"), "oldground": Color("b05a3c"), "cage": Color("FF7A1A")}.get(id, Game.C_CHALK)
			c.draw_rect(Rect2(ctr - Vector2(60, 24), Vector2(120, 48)), Color("2f6d34"))
			c.draw_rect(Rect2(ctr - Vector2(60, 24), Vector2(120, 48)), Game.C_CHALK, false, 1.5)
			c.draw_line(ctr - Vector2(0, 24), ctr + Vector2(0, 24), Game.C_CHALK, 1.5)
			c.draw_rect(Rect2(ctr - Vector2(66, 30), Vector2(132, 6)), col)
