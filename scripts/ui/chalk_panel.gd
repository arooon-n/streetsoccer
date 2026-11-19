class_name ChalkPanel
extends PanelContainer
## Translucent turf panel with chalk corner-arcs (the mockups' signature element).

var chalk := true
var bg_alpha := 0.82
var pad := 12
var border_color := Color(0.93, 0.95, 0.92, 0.14)


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.039, 0.118, 0.11, bg_alpha)
	sb.border_color = border_color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	add_theme_stylebox_override("panel", sb)


func _draw() -> void:
	if not chalk:
		return
	var c := Game.C_LINE2
	draw_arc(Vector2(3, 3), 12, 0.0, PI * 0.5, 10, c, 1.5, true)
	draw_arc(size - Vector2(3, 3), 12, PI, PI * 1.5, 10, c, 1.5, true)
