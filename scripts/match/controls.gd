class_name Controls
extends Control
## Multi-touch controls: floating joystick (left), four action buttons (right), swipe capture.
## Keyboard fallback: WASD/arrows move, J pass, K shoot, L through, Shift sprint.

signal swiped(points: PackedVector2Array, duration: float)
signal hud_tap(id: String)

const BTN := ["shoot", "pass", "through", "sprint"]

var labels := {"shoot": "Shoot", "pass": "Pass", "through": "Through", "sprint": "Sprint"}
var move := Vector2.ZERO
var held := {"shoot": false, "pass": false, "through": false, "sprint": false}
var hold_t := {"shoot": 0.0, "pass": 0.0, "through": 0.0, "sprint": 0.0}
var _pressed := {}          # one-frame flags
var _released := {}
var enabled := true
var swipe_mode := false
var show_buttons := true
var show_joystick := true
var power := 0.0            # shoot charge 0..1 shown on the button
var hint := ""
var hud_rects := {}          # id -> Rect2 (for multi-touch taps on HUD buttons)

var _joy_idx := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _btn_idx := {}           # touch index -> button name
var _swipe_idx := -1
var _swipe_pts := PackedVector2Array()
var _swipe_t0 := 0.0
var _keys := {}
var _time := 0.0

const JOY_R := 54.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE


func scale_k() -> float:
	return float(Game.settings.get("controls_scale", 1.0))


func button_rect(name: String) -> Array:
	# returns [center, radius] in local coords (mirrors the approved HUD mockup)
	var k := scale_k()
	var ins := UI.safe_insets()
	var r = size.x - max(26.0, ins.y + 10.0)
	var b := size.y
	match name:
		"shoot":
			return [Vector2(r - 8.0 - 42.0 * k, b - 30.0 - 42.0 * k), 42.0 * k]
		"pass":
			return [Vector2(r - 106.0 * k - 31.0 * k, b - 20.0 - 31.0 * k), 31.0 * k]
		"through":
			return [Vector2(r - 94.0 * k - 28.0 * k, b - 96.0 * k - 28.0 * k), 28.0 * k]
		"sprint":
			return [Vector2(r - 22.0 * k - 28.0 * k, b - 128.0 * k - 28.0 * k), 28.0 * k]
	return [Vector2.ZERO, 0.0]


func just_pressed(n: String) -> bool:
	return _pressed.get(n, false)


func just_released(n: String) -> bool:
	return _released.get(n, false)


func consume() -> void:
	_pressed.clear()
	_released.clear()


func reset() -> void:
	move = Vector2.ZERO
	for k in held.keys():
		held[k] = false
		hold_t[k] = 0.0
	_joy_idx = -1
	_btn_idx.clear()
	_swipe_idx = -1
	consume()
	queue_redraw()


func set_labels(l: Dictionary) -> void:
	for k in l.keys():
		labels[k] = l[k]
	queue_redraw()


## Joystick in world space for a camera (screen up = away from camera).
func move_world(cam: Camera3D) -> Vector3:
	if move.length() < 0.08:
		return Vector3.ZERO
	var b := cam.global_transform.basis
	var r := Vector3(b.x.x, 0, b.x.z).normalized()
	var f := Vector3(-b.z.x, 0, -b.z.z).normalized()
	var v := r * move.x + f * (-move.y)
	return v.limit_length(1.0)


func _process(delta: float) -> void:
	_time += delta
	for k in held.keys():
		if held[k]:
			hold_t[k] += delta
	_keyboard()
	queue_redraw()


func _keyboard() -> void:
	var kv := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if _joy_idx < 0:
		move = kv.normalized() if kv.length() > 0.0 else Vector2.ZERO
	for pair in [["pass", KEY_J], ["shoot", KEY_K], ["through", KEY_L], ["sprint", KEY_SHIFT]]:
		var down := Input.is_physical_key_pressed(pair[1])
		var was: bool = _keys.get(pair[0], false)
		if down and not was:
			_press(pair[0])
		elif not down and was:
			_release(pair[0])
		_keys[pair[0]] = down


func _press(n: String) -> void:
	if not enabled:
		return
	held[n] = true
	hold_t[n] = 0.0
	_pressed[n] = true
	if n != "sprint":
		Game.haptic(10)


func _release(n: String) -> void:
	if not held.get(n, false):
		return
	held[n] = false
	_released[n] = true


func _input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if e is InputEventScreenTouch:
		var p: Vector2 = get_global_transform_with_canvas().affine_inverse() * e.position
		if e.pressed:
			# HUD buttons (pause etc.) work with any finger
			for id in hud_rects.keys():
				if (hud_rects[id] as Rect2).has_point(p):
					hud_tap.emit(id)
					get_viewport().set_input_as_handled()
					return
			if not enabled:
				return
			if show_buttons:
				for n in BTN:
					var br: Array = button_rect(n)
					if p.distance_to(br[0]) < br[1] * 1.25:
						_btn_idx[e.index] = n
						_press(n)
						get_viewport().set_input_as_handled()
						return
			if swipe_mode and p.x > size.x * 0.25:
				_swipe_idx = e.index
				_swipe_pts = PackedVector2Array([p])
				_swipe_t0 = _time
				return
			if show_joystick and p.x < size.x * 0.5 and p.y > size.y * 0.22:
				_joy_idx = e.index
				_joy_origin = p
				_joy_pos = p
				move = Vector2.ZERO
		else:
			if e.index == _joy_idx:
				_joy_idx = -1
				move = Vector2.ZERO
			if _btn_idx.has(e.index):
				_release(_btn_idx[e.index])
				_btn_idx.erase(e.index)
			if e.index == _swipe_idx:
				_swipe_idx = -1
				_swipe_pts.append(p)
				if _swipe_pts.size() >= 2 and _swipe_pts[0].distance_to(p) > 30.0:
					swiped.emit(_swipe_pts, max(0.05, _time - _swipe_t0))
				_swipe_pts = PackedVector2Array()
	elif e is InputEventScreenDrag:
		var p: Vector2 = get_global_transform_with_canvas().affine_inverse() * e.position
		if e.index == _joy_idx:
			_joy_pos = p
			var d := p - _joy_origin
			if d.length() > JOY_R:
				# floating joystick follows the thumb
				_joy_origin = p - d.normalized() * JOY_R
				d = p - _joy_origin
			move = d / JOY_R
		elif e.index == _swipe_idx:
			if _swipe_pts.size() == 0 or _swipe_pts[_swipe_pts.size() - 1].distance_to(p) > 4.0:
				_swipe_pts.append(p)


func _draw() -> void:
	var op := float(Game.settings.get("controls_opacity", 0.85))
	var f := UI.font("disp_x")
	if show_joystick and enabled:
		var c := _joy_origin if _joy_idx >= 0 else Vector2(max(62.0, UI.safe_insets().x + 30.0) + 64.0, size.y - 22.0 - 64.0)
		draw_circle(c, 64.0, Color(0.93, 0.95, 0.92, 0.05 * op))
		draw_arc(c, 64.0, 0, TAU, 48, Color(0.93, 0.95, 0.92, 0.3 * op), 2.0, true)
		var kp := c + move * JOY_R
		draw_circle(kp, 25.0, Color(0.93, 0.95, 0.92, (0.45 if _joy_idx >= 0 else 0.3) * op))
		draw_arc(kp, 25.0, 0, TAU, 32, Color(0.93, 0.95, 0.92, 0.6 * op), 2.0, true)
	if show_buttons and enabled:
		for n in BTN:
			var br: Array = button_rect(n)
			var c: Vector2 = br[0]
			var r: float = br[1]
			var is_shoot = n == "shoot"
			var col := Game.C_CARD if is_shoot else Game.C_CHALK
			var on: bool = held[n]
			draw_circle(c, r, Color(0.16, 0.12, 0.0, 0.45 * op) if is_shoot else Color(0.02, 0.055, 0.063, (0.62 if on else 0.42) * op))
			if on:
				draw_circle(c, r, Color(col.r, col.g, col.b, 0.22 * op))
			draw_arc(c, r, 0, TAU, 48, Color(col.r, col.g, col.b, (0.95 if is_shoot else 0.45) * op), 2.0, true)
			if is_shoot and power > 0.01:
				draw_arc(c, r + 6.0, -PI / 2.0, -PI / 2.0 + TAU * power, 48, Game.C_CARD if power < 0.9 else Game.C_AWAY, 5.0, true)
			var t: String = labels[n].to_upper()
			var fs := 17 if is_shoot else (13 if t.length() <= 6 else 11)
			var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, c + Vector2(-tw * 0.5, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, op))
	if swipe_mode and _swipe_pts.size() > 1:
		draw_polyline(_swipe_pts, Color(1.0, 0.95, 0.75, 0.85), 7.0, true)
		draw_circle(_swipe_pts[_swipe_pts.size() - 1], 12.0, Color(1.0, 0.81, 0.2, 0.5))
