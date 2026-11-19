class_name Icon
extends Control
## Small vector icon set drawn with lines (no image assets).

@export var kind := "star":
	set(v):
		kind = v
		queue_redraw()
@export var color := Color("EDF2EA"):
	set(v):
		color = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_icon(self, kind, Rect2(Vector2.ZERO, size), color)


static func draw_icon(ci: CanvasItem, k: String, r: Rect2, c: Color) -> void:
	var s: float = min(r.size.x, r.size.y)
	var o = r.position + (r.size - Vector2(s, s)) * 0.5
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s / 24.0
	var w: float = max(1.4, s / 11.0)
	match k:
		"back":
			ci.draw_polyline(PackedVector2Array([P.call(15, 5), P.call(8, 12), P.call(15, 19)]), c, w, true)
		"next":
			ci.draw_polyline(PackedVector2Array([P.call(9, 5), P.call(16, 12), P.call(9, 19)]), c, w, true)
		"pause":
			ci.draw_line(P.call(9, 6), P.call(9, 18), c, w + 0.6, true)
			ci.draw_line(P.call(15, 6), P.call(15, 18), c, w + 0.6, true)
		"play":
			ci.draw_colored_polygon(PackedVector2Array([P.call(8, 5), P.call(19, 12), P.call(8, 19)]), c)
		"close":
			ci.draw_line(P.call(6, 6), P.call(18, 18), c, w, true)
			ci.draw_line(P.call(18, 6), P.call(6, 18), c, w, true)
		"check":
			ci.draw_polyline(PackedVector2Array([P.call(5, 12), P.call(10, 17), P.call(19, 7)]), c, w, true)
		"gear":
			var cc: Vector2 = P.call(12, 12)
			ci.draw_arc(cc, s * 0.17, 0, TAU, 20, c, w, true)
			for i in 8:
				var a := i * TAU / 8.0
				ci.draw_line(cc + Vector2(cos(a), sin(a)) * s * 0.27, cc + Vector2(cos(a), sin(a)) * s * 0.4, c, w + 0.8, true)
			ci.draw_arc(cc, s * 0.3, 0, TAU, 24, c, w, true)
		"coin":
			var cc: Vector2 = P.call(12, 12)
			ci.draw_circle(cc, s * 0.48, Color("a37500"))
			ci.draw_circle(cc, s * 0.40, Color("FFCF33"))
			ci.draw_circle(cc - Vector2(s, s) * 0.1, s * 0.14, Color("fff3b8"))
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI / 2.0 + i * PI / 5.0
				var rad := s * (0.48 if i % 2 == 0 else 0.2)
				pts.append(P.call(12, 12) + Vector2(cos(a), sin(a)) * rad)
			ci.draw_colored_polygon(pts, c)
		"lock":
			ci.draw_rect(Rect2(P.call(5, 11), Vector2(14, 10) * s / 24.0), c)
			ci.draw_arc(P.call(12, 11), s * 0.2, PI, TAU, 12, c, w, true)
		"trophy":
			ci.draw_colored_polygon(PackedVector2Array([P.call(6, 4), P.call(18, 4), P.call(17, 11), P.call(12, 15), P.call(7, 11)]), c)
			ci.draw_line(P.call(12, 15), P.call(12, 19), c, w + 1, true)
			ci.draw_line(P.call(8, 20), P.call(16, 20), c, w + 1, true)
			ci.draw_arc(P.call(5, 8), s * 0.12, PI * 0.5, PI * 1.5, 8, c, w, true)
			ci.draw_arc(P.call(19, 8), s * 0.12, -PI * 0.5, PI * 0.5, 8, c, w, true)
		"ball":
			var cc: Vector2 = P.call(12, 12)
			ci.draw_circle(cc, s * 0.44, c)
			var pent := PackedVector2Array()
			for i in 5:
				var a := -PI / 2.0 + i * TAU / 5.0
				pent.append(cc + Vector2(cos(a), sin(a)) * s * 0.16)
			ci.draw_colored_polygon(pent, Game.C_NIGHT)
		"shirt":
			ci.draw_colored_polygon(PackedVector2Array([P.call(8, 3), P.call(16, 3), P.call(22, 8), P.call(19, 11), P.call(17, 9), P.call(17, 21), P.call(7, 21), P.call(7, 9), P.call(5, 11), P.call(2, 8)]), c)
		"edit":
			ci.draw_line(P.call(5, 19), P.call(17, 7), c, w + 1, true)
			ci.draw_line(P.call(4, 20), P.call(7, 20), c, w, true)
		"wind":
			ci.draw_line(P.call(4, 9), P.call(17, 9), c, w, true)
			ci.draw_line(P.call(4, 15), P.call(20, 15), c, w, true)
			ci.draw_arc(P.call(17, 6.5), s * 0.1, PI * 0.5, PI * 2.0, 10, c, w, true)
		"rain":
			ci.draw_arc(P.call(12, 10), s * 0.25, PI, TAU, 12, c, w, true)
			ci.draw_line(P.call(6, 10), P.call(18, 10), c, w, true)
			for x in [8, 12, 16]:
				ci.draw_line(P.call(x, 14), P.call(x - 1, 18), c, w, true)
		"replay":
			ci.draw_arc(P.call(12, 12), s * 0.33, -PI * 0.3, PI * 1.5, 20, c, w, true)
			ci.draw_colored_polygon(PackedVector2Array([P.call(3, 7), P.call(9, 5), P.call(8, 11)]), c)
		"plus":
			ci.draw_line(P.call(12, 5), P.call(12, 19), c, w, true)
			ci.draw_line(P.call(5, 12), P.call(19, 12), c, w, true)
		"whistle":
			ci.draw_circle(P.call(10, 14), s * 0.25, c)
			ci.draw_rect(Rect2(P.call(10, 8), Vector2(11, 4) * s / 24.0), c)
		_:
			ci.draw_circle(P.call(12, 12), s * 0.2, c)
