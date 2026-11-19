class_name Seg
extends HBoxContainer
## Segmented control (mockup ".seg"): one option highlighted in card yellow.

signal changed(index: int)

var font_size := 13
var options: Array = []
var index := 0
var _chips: Array[GDButton] = []


func _init() -> void:
	add_theme_constant_override("separation", 0)


func setup(opts: Array, sel: int) -> void:
	options = opts
	index = sel
	for c in get_children():
		c.queue_free()
	_chips.clear()
	for i in opts.size():
		var b := GDButton.new()
		b.style = "chip"
		b.text = str(opts[i])
		b.font_size = font_size
		var f := UI.font("disp_s")
		var w = f.get_string_size(str(opts[i]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		b.custom_minimum_size = Vector2(w + 16, 28)
		b.selected = i == sel
		b.pressed.connect(_on.bind(i))
		add_child(b)
		_chips.append(b)
	queue_redraw()


func set_index(i: int) -> void:
	index = i
	for k in _chips.size():
		_chips[k].selected = k == i


func _on(i: int) -> void:
	if i == index:
		return
	set_index(i)
	changed.emit(i)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Game.C_LINE2, false, 1.0)
	var x := 0.0
	for k in range(_chips.size() - 1):
		x += _chips[k].size.x
		draw_line(Vector2(x, 0), Vector2(x, size.y), Game.C_LINE, 1.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		queue_redraw()
