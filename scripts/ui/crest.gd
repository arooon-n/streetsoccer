class_name Crest
extends Control
## Vector club crest: shield with stripes, a ball emblem and initials.

var c1 := Color("0E2238")
var c2 := Color("3FB8E6")
var initials := "HCF"
var shape := 0       # 0 shield, 1 round, 2 diamond
var pattern := 1     # 0 plain, 1 stripes, 2 hoops, 3 half


func setup(a: Color, b: Color, txt: String, shp := 0, pat := 1) -> Crest:
	c1 = a
	c2 = b
	initials = txt
	shape = shp
	pattern = pat
	queue_redraw()
	return self


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _outline(w: float, h: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match shape:
		1:
			for i in 40:
				var a := TAU * i / 40.0
				pts.append(Vector2(w * 0.5 + cos(a) * w * 0.46, h * 0.5 + sin(a) * h * 0.46))
		2:
			pts = PackedVector2Array([Vector2(w * 0.5, h * 0.03), Vector2(w * 0.95, h * 0.5), Vector2(w * 0.5, h * 0.97), Vector2(w * 0.05, h * 0.5)])
		_:
			pts.append(Vector2(w * 0.5, h * 0.04))
			pts.append(Vector2(w * 0.92, h * 0.15))
			pts.append(Vector2(w * 0.92, h * 0.48))
			for i in 11:
				var t := i / 10.0
				var a := Vector2(w * 0.92, h * 0.48)
				var c := Vector2(w * 0.92, h * 0.78)
				var b := Vector2(w * 0.5, h * 0.96)
				pts.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
			for i in range(1, 11):
				var t := i / 10.0
				var a := Vector2(w * 0.5, h * 0.96)
				var c := Vector2(w * 0.08, h * 0.78)
				var b := Vector2(w * 0.08, h * 0.48)
				pts.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
			pts.append(Vector2(w * 0.08, h * 0.15))
	return pts


func _draw() -> void:
	var w := size.x
	var h := size.y
	var shield := _outline(w, h)
	draw_colored_polygon(shield, c1)
	var stripes: Array = []
	match pattern:
		1:
			for i in 3:
				var x0 := w * (0.14 + i * 0.28)
				stripes.append(PackedVector2Array([Vector2(x0, 0), Vector2(x0 + w * 0.14, 0), Vector2(x0 + w * 0.14, h), Vector2(x0, h)]))
		2:
			for i in 3:
				var y0 := h * (0.2 + i * 0.22)
				stripes.append(PackedVector2Array([Vector2(0, y0), Vector2(w, y0), Vector2(w, y0 + h * 0.1), Vector2(0, y0 + h * 0.1)]))
		3:
			stripes.append(PackedVector2Array([Vector2(w * 0.5, 0), Vector2(w, 0), Vector2(w, h), Vector2(w * 0.5, h)]))
	stripes.append(PackedVector2Array([Vector2(0, h * 0.6), Vector2(w, h * 0.6), Vector2(w, h), Vector2(0, h)]))
	for s in stripes:
		for poly in Geometry2D.intersect_polygons(s, shield):
			draw_colored_polygon(poly, c2)
	var loop := shield.duplicate()
	loop.append(shield[0])
	draw_polyline(loop, Game.C_CHALK, max(1.5, w * 0.04), true)
	# ball emblem
	var bc := Vector2(w * 0.5, h * 0.39)
	var br := w * 0.15
	draw_circle(bc, br, Game.C_CHALK)
	var pent := PackedVector2Array()
	for i in 5:
		var a := -PI / 2.0 + i * TAU / 5.0
		pent.append(bc + Vector2(cos(a), sin(a)) * br * 0.42)
	draw_colored_polygon(pent, Color("0b1714"))
	# initials
	var f := UI.font("disp_x")
	var fs := int(max(7.0, h * 0.2))
	var tw := f.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(w * 0.5 - tw * 0.5, h * 0.85), initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Game.C_CHALK)
