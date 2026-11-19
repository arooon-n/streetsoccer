extends Node
func _ready():
	await get_tree().create_timer(4.0).timeout
	var m = get_parent().current
	print("hud size ", m.hud.size, " controls size ", m.controls.size, " root ", m.hud.get_parent().size, " root anchors ", m.hud.get_parent().anchor_right, " vis ", m.controls.visible, " layer vis ", m.layer.visible)
	get_tree().quit()
