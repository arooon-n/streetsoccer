extends Node
## Captures frames from the running screen: --screen match "" 99999 '{json}' film <prefix> <count> <every_frames>
var prefix := ""
var count := 12
var every := 30
var n := 0
var f := 0
func _process(_d):
	f += 1
	if f % every == 0 and f > 200:
		var img := get_viewport().get_texture().get_image()
		img.resize(844, 390)
		img.save_png("%s_%02d.png" % [prefix, n])
		n += 1
		if n >= count:
			get_tree().quit()
