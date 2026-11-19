class_name PlayerRig
extends RefCounted
## Procedural animation: computes bone rotations from a small set of parameters.
## Positive X rotation tilts up-pointing bones forward and swings down-pointing limbs backward.

const N := 16
const B = preload("res://scripts/actors/player_model.gd")

var skel: Skeleton3D
var pose := PackedVector3Array()
var act_pose := PackedVector3Array()
var root_off := Vector3.ZERO
var act_root := Vector3.ZERO
var root_rot := Vector3.ZERO
var act_root_rot := Vector3.ZERO
var blend := 0.0


func _init(s: Skeleton3D) -> void:
	skel = s
	pose.resize(N)
	act_pose.resize(N)


static func _k(t: float, keys: Array) -> float:
	# keys: [[t, v], ...] smooth interpolation
	if t <= keys[0][0]:
		return keys[0][1]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t <= b[0]:
			var u: float = (t - a[0]) / max(0.0001, b[0] - a[0])
			u = u * u * (3.0 - 2.0 * u)
			return lerp(float(a[1]), float(b[1]), u)
	return keys[keys.size() - 1][1]


## state: {speed, fwd_speed, phase, action, t (0..1), side (+1 right foot / dive dir), height, time, keeper, ready}
func apply(st: Dictionary, delta: float) -> void:
	_locomotion(st)
	var action: String = st.get("action", "")
	var target_blend := 1.0 if action != "" else 0.0
	blend = move_toward(blend, target_blend, delta * (10.0 if target_blend > blend else 7.0))
	if action != "":
		_action(action, float(st.get("t", 0.0)), st)
	if blend > 0.001:
		for i in N:
			pose[i] = pose[i].lerp(act_pose[i], blend)
		root_off = root_off.lerp(act_root, blend)
		root_rot = root_rot.lerp(act_root_rot, blend)
	_write()


func _write() -> void:
	# whole-body rotations pivot at the hips; the root only translates
	skel.set_bone_pose_position(0, root_off)
	skel.set_bone_pose_rotation(1, Quaternion.from_euler(root_rot) * Quaternion.from_euler(pose[1]))
	for i in range(2, N):
		skel.set_bone_pose_rotation(i, Quaternion.from_euler(pose[i]))


func _clear(p: PackedVector3Array) -> void:
	for i in N:
		p[i] = Vector3.ZERO


func _locomotion(st: Dictionary) -> void:
	_clear(pose)
	root_rot = Vector3.ZERO
	var s: float = st.get("speed", 0.0)
	var ph: float = st.get("phase", 0.0)
	var tm: float = st.get("time", 0.0)
	var keeper: bool = st.get("keeper", false)
	var ready: float = st.get("ready", 0.0)
	if s < 0.35:
		# idle: breathing, slight athletic stance
		var br := sin(tm * 2.2) * 0.025
		pose[B.SPINE] = Vector3(0.05 + br, 0, 0)
		pose[B.CHEST] = Vector3(br, 0, 0)
		pose[B.ARM_L] = Vector3(0.05, 0, 0.12)
		pose[B.ARM_R] = Vector3(0.05, 0, -0.12)
		pose[B.FORE_L] = Vector3(-0.25, 0, 0)
		pose[B.FORE_R] = Vector3(-0.25, 0, 0)
		pose[B.THIGH_L] = Vector3(-0.08, 0, 0.04)
		pose[B.THIGH_R] = Vector3(-0.08, 0, -0.04)
		pose[B.SHIN_L] = Vector3(0.14, 0, 0)
		pose[B.SHIN_R] = Vector3(0.14, 0, 0)
		pose[B.FOOT_L] = Vector3(-0.06, 0, 0)
		pose[B.FOOT_R] = Vector3(-0.06, 0, 0)
		root_off = Vector3(0, -0.015, 0)
		if keeper and ready > 0.0:
			var r := ready
			pose[B.SPINE] = Vector3(0.32 * r, 0, 0)
			pose[B.THIGH_L] = Vector3(-0.5 * r, 0, 0.12 * r)
			pose[B.THIGH_R] = Vector3(-0.5 * r, 0, -0.12 * r)
			pose[B.SHIN_L] = Vector3(0.85 * r, 0, 0)
			pose[B.SHIN_R] = Vector3(0.85 * r, 0, 0)
			pose[B.FOOT_L] = Vector3(-0.3 * r, 0, 0)
			pose[B.FOOT_R] = Vector3(-0.3 * r, 0, 0)
			pose[B.ARM_L] = Vector3(-0.55 * r, 0, 0.55 * r)
			pose[B.ARM_R] = Vector3(-0.55 * r, 0, -0.55 * r)
			pose[B.FORE_L] = Vector3(-0.8 * r, 0, 0)
			pose[B.FORE_R] = Vector3(-0.8 * r, 0, 0)
			root_off = Vector3(0, -0.13 * r, 0)
		return
	var k: float = clamp(s / 8.5, 0.0, 1.0)
	var walk: float = clamp((2.6 - s) / 2.0, 0.0, 1.0)
	var amp: float = lerp(0.42, 0.98, k) * lerp(1.0, 0.65, walk)
	var sn := sin(ph)
	var cs := cos(ph)
	var knee_k: float = lerp(0.55, 1.75, k) * lerp(1.0, 0.45, walk)
	var kl: float = 0.12 + knee_k * pow(max(0.0, cos(ph + 0.75)), 1.5)
	var kr: float = 0.12 + knee_k * pow(max(0.0, cos(ph + PI + 0.75)), 1.5)
	pose[B.THIGH_L] = Vector3(-amp * sn, 0, 0.03)
	pose[B.THIGH_R] = Vector3(amp * sn, 0, -0.03)
	pose[B.SHIN_L] = Vector3(kl, 0, 0)
	pose[B.SHIN_R] = Vector3(kr, 0, 0)
	pose[B.FOOT_L] = Vector3(-0.25 * max(0.0, cs) + 0.15 * max(0.0, -cs), 0, 0)
	pose[B.FOOT_R] = Vector3(-0.25 * max(0.0, -cs) + 0.15 * max(0.0, cs), 0, 0)
	var arm_amp := amp * 0.75
	pose[B.ARM_L] = Vector3(arm_amp * sn, 0, 0.1 + 0.08 * k)
	pose[B.ARM_R] = Vector3(-arm_amp * sn, 0, -0.1 - 0.08 * k)
	var elbow: float = -(0.35 + 1.05 * k) * lerp(1.0, 0.5, walk)
	pose[B.FORE_L] = Vector3(elbow - 0.2 * max(0.0, -sn), 0, 0)
	pose[B.FORE_R] = Vector3(elbow - 0.2 * max(0.0, sn), 0, 0)
	pose[B.HIPS] = Vector3(0, 0.12 * k * sn, 0)
	pose[B.SPINE] = Vector3(0.06 + 0.2 * k, 0, 0)
	pose[B.CHEST] = Vector3(0.03, -0.18 * k * sn, 0)
	pose[B.NECK] = Vector3(-0.06 - 0.15 * k, 0, 0)
	var bob = -0.035 * k * abs(cs) - 0.01
	root_off = Vector3(0, bob, 0)
	# strafing / backpedalling lean
	var fwd: float = st.get("fwd_speed", s)
	if fwd < -0.5:
		pose[B.SPINE].x = -0.05


func _action(a: String, t: float, st: Dictionary) -> void:
	_clear(act_pose)
	act_root = Vector3.ZERO
	act_root_rot = Vector3.ZERO
	var side: float = st.get("side", 1.0)
	match a:
		"kick", "pass", "lob", "cross", "volley":
			_kick_pose(a, t)
			if side < 0.0:
				_mirror(act_pose)
				act_root_rot = Vector3(act_root_rot.x, -act_root_rot.y, -act_root_rot.z)
		"header":
			var j = sin(PI * clamp(t, 0.0, 1.0))
			act_root = Vector3(0, j * float(st.get("height", 0.35)), 0)
			act_pose[B.SPINE] = Vector3(_k(t, [[0, 0.0], [0.3, -0.35], [0.5, 0.45], [1, 0.1]]), 0, 0)
			act_pose[B.CHEST] = Vector3(_k(t, [[0, 0.0], [0.3, -0.2], [0.5, 0.3], [1, 0.05]]), 0, 0)
			act_pose[B.NECK] = Vector3(_k(t, [[0, 0.0], [0.35, -0.3], [0.5, 0.35], [1, 0.0]]), 0, 0)
			for s in [1.0, -1.0]:
				var arm := B.ARM_L if s > 0.0 else B.ARM_R
				var fore := B.FORE_L if s > 0.0 else B.FORE_R
				var th := B.THIGH_L if s > 0.0 else B.THIGH_R
				var sh := B.SHIN_L if s > 0.0 else B.SHIN_R
				act_pose[arm] = Vector3(-0.7, 0, 1.0 * s)
				act_pose[fore] = Vector3(-0.9, 0, 0)
				act_pose[th] = Vector3(-0.35 * j, 0, 0.05 * s)
				act_pose[sh] = Vector3(0.2 + 0.9 * j, 0, 0)
		"tackle":
			var l := _k(t, [[0, 0.0], [0.3, 1.0], [0.7, 1.0], [1, 0.0]])
			act_pose[B.THIGH_R] = Vector3(-1.1 * l, 0.2 * l, -0.1)
			act_pose[B.SHIN_R] = Vector3(0.15, 0, 0)
			act_pose[B.FOOT_R] = Vector3(-0.3 * l, 0.6 * l, 0)
			act_pose[B.THIGH_L] = Vector3(0.35 * l, 0, 0.05)
			act_pose[B.SHIN_L] = Vector3(0.9 * l, 0, 0)
			act_pose[B.SPINE] = Vector3(0.38 * l, 0, 0)
			act_pose[B.ARM_L] = Vector3(-0.3, 0, 0.7 * l)
			act_pose[B.ARM_R] = Vector3(0.5, 0, -0.6 * l)
			act_root = Vector3(0, -0.18 * l, 0)
			if side < 0.0:
				_mirror(act_pose)
		"slide":
			var down := _k(t, [[0, 0.0], [0.15, 1.0], [0.72, 1.0], [1, 0.0]])
			act_root = Vector3(0, -0.66 * down, -0.15 * down)
			act_root_rot = Vector3(-1.15 * down, 0, 0)
			act_pose[B.THIGH_R] = Vector3(-0.4 * down, 0, -0.05)
			act_pose[B.SHIN_R] = Vector3(0.05, 0, 0)
			act_pose[B.FOOT_R] = Vector3(-0.4, 0, 0)
			act_pose[B.THIGH_L] = Vector3(0.25 * down, 0, 0.1)
			act_pose[B.SHIN_L] = Vector3(1.5 * down, 0, 0)
			act_pose[B.ARM_L] = Vector3(0.9 * down, 0, 0.45)
			act_pose[B.ARM_R] = Vector3(0.9 * down, 0, -0.45)
			act_pose[B.SPINE] = Vector3(0.35 * down, 0, 0)
			act_pose[B.NECK] = Vector3(0.4 * down, 0, 0)
			if side < 0.0:
				_mirror(act_pose)
		"dive":
			# side: +1 to the keeper's left (+X), -1 to the right
			var h: float = st.get("height", 0.4)
			var air := _k(t, [[0, 0.0], [0.12, 0.4], [0.4, 1.0], [0.62, 1.0], [0.78, 0.0]])
			var lay := _k(t, [[0, 0.0], [0.15, 0.65], [0.38, 1.0], [1, 1.0]])
			act_root_rot = Vector3(0, 0, -side * 1.35 * lay)
			act_root = Vector3(0, -0.2 * lay + air * (0.25 + h * 0.6) - 0.55 * _k(t, [[0.6, 0.0], [0.8, 1.0]]), 0)
			var up := 2.75
			act_pose[B.ARM_L] = Vector3(-0.2, 0, up * lay if side > 0.0 else 2.2 * lay)
			act_pose[B.ARM_R] = Vector3(-0.2, 0, -up * lay if side < 0.0 else -2.2 * lay)
			act_pose[B.FORE_L] = Vector3(-0.2, 0, 0)
			act_pose[B.FORE_R] = Vector3(-0.2, 0, 0)
			act_pose[B.THIGH_L] = Vector3(-0.3 * lay, 0, 0.2 * lay)
			act_pose[B.THIGH_R] = Vector3(0.2 * lay, 0, -0.2 * lay)
			act_pose[B.SHIN_L] = Vector3(0.7 * lay, 0, 0)
			act_pose[B.SHIN_R] = Vector3(0.5 * lay, 0, 0)
			act_pose[B.NECK] = Vector3(0, 0, side * 0.3 * lay)
		"catch":
			var c := _k(t, [[0, 0.0], [0.3, 1.0], [1, 1.0]])
			act_pose[B.ARM_L] = Vector3(-1.25 * c, 0, 0.25)
			act_pose[B.ARM_R] = Vector3(-1.25 * c, 0, -0.25)
			act_pose[B.FORE_L] = Vector3(-0.9 * c, 0, 0)
			act_pose[B.FORE_R] = Vector3(-0.9 * c, 0, 0)
			act_pose[B.SPINE] = Vector3(0.25 * c, 0, 0)
			act_pose[B.THIGH_L] = Vector3(-0.3 * c, 0, 0.08)
			act_pose[B.THIGH_R] = Vector3(-0.3 * c, 0, -0.08)
			act_pose[B.SHIN_L] = Vector3(0.6 * c, 0, 0)
			act_pose[B.SHIN_R] = Vector3(0.6 * c, 0, 0)
			act_root = Vector3(0, -0.1 * c, 0)
		"hold":
			act_pose[B.ARM_L] = Vector3(-0.9, 0, 0.2)
			act_pose[B.ARM_R] = Vector3(-0.9, 0, -0.2)
			act_pose[B.FORE_L] = Vector3(-1.2, 0, 0)
			act_pose[B.FORE_R] = Vector3(-1.2, 0, 0)
			_legs_from_loco()
		"gk_throw":
			act_pose[B.ARM_R] = Vector3(_k(t, [[0, -0.9], [0.4, 0.9], [0.65, -2.6], [1, -1.0]]), 0, -0.3)
			act_pose[B.FORE_R] = Vector3(_k(t, [[0, -1.2], [0.4, -0.4], [1, -0.1]]), 0, 0)
			act_pose[B.ARM_L] = Vector3(-0.9, 0, 0.5)
			act_pose[B.SPINE] = Vector3(_k(t, [[0, 0.0], [0.4, -0.25], [0.7, 0.3], [1, 0.1]]), _k(t, [[0, 0.0], [0.4, -0.4], [0.7, 0.3]]), 0)
			act_pose[B.THIGH_L] = Vector3(-0.5, 0, 0)
			act_pose[B.SHIN_L] = Vector3(0.3, 0, 0)
			act_pose[B.THIGH_R] = Vector3(0.3, 0, 0)
		"throw":
			var raise := _k(t, [[0, 0.0], [0.45, 1.0], [0.62, 0.6], [1, 0.0]])
			act_pose[B.ARM_L] = Vector3(-2.95 * raise, 0, 0.15)
			act_pose[B.ARM_R] = Vector3(-2.95 * raise, 0, -0.15)
			act_pose[B.FORE_L] = Vector3(-1.0 * _k(t, [[0, 0.0], [0.45, 1.0], [0.6, 0.1]]), 0, 0)
			act_pose[B.FORE_R] = act_pose[B.FORE_L]
			act_pose[B.SPINE] = Vector3(_k(t, [[0, 0.0], [0.45, -0.3], [0.62, 0.25], [1, 0.0]]), 0, 0)
			act_pose[B.THIGH_L] = Vector3(-0.3, 0, 0)
			act_pose[B.SHIN_L] = Vector3(0.2, 0, 0)
			act_pose[B.THIGH_R] = Vector3(0.25, 0, 0)
			act_pose[B.SHIN_R] = Vector3(0.3, 0, 0)
		"fall":
			var f := _k(t, [[0, 0.0], [0.25, 1.0], [0.75, 1.0], [1, 0.0]])
			act_root_rot = Vector3(1.45 * f, 0, 0.2 * f)
			act_root = Vector3(0, -0.82 * f, 0.15 * f)
			act_pose[B.ARM_L] = Vector3(-1.2 * f, 0, 0.6)
			act_pose[B.ARM_R] = Vector3(-1.2 * f, 0, -0.6)
			act_pose[B.THIGH_L] = Vector3(0.1, 0, 0.1)
			act_pose[B.SHIN_L] = Vector3(0.4 * f, 0, 0)
			act_pose[B.SHIN_R] = Vector3(0.9 * f, 0, 0)
			act_pose[B.NECK] = Vector3(-0.5 * f, 0, 0)
		"stumble":
			var f := sin(PI * t)
			act_pose[B.SPINE] = Vector3(0.5 * f, 0, 0.15 * f)
			act_pose[B.ARM_L] = Vector3(-0.6 * f, 0, 0.9 * f)
			act_pose[B.ARM_R] = Vector3(0.4 * f, 0, -0.8 * f)
			act_pose[B.THIGH_L] = Vector3(-0.6 * f, 0, 0)
			act_pose[B.SHIN_L] = Vector3(0.5 * f, 0, 0)
			act_pose[B.THIGH_R] = Vector3(0.4 * f, 0, 0)
			act_pose[B.SHIN_R] = Vector3(0.6 * f, 0, 0)
		"cel_fist":
			var tm: float = st.get("time", 0.0)
			var pump = abs(sin(tm * 5.0))
			act_pose[B.ARM_R] = Vector3(-0.3, 0, -2.4 - 0.4 * pump)
			act_pose[B.FORE_R] = Vector3(-0.4 * pump, 0, 0)
			act_pose[B.ARM_L] = Vector3(0.2, 0, 0.5)
			act_pose[B.FORE_L] = Vector3(-1.4, 0, 0)
			act_pose[B.SPINE] = Vector3(-0.15, 0, 0)
			act_pose[B.NECK] = Vector3(-0.35, 0, 0)
			act_root = Vector3(0, 0.2 * pump, 0)
			act_pose[B.THIGH_L] = Vector3(-0.4 * pump, 0, 0)
			act_pose[B.SHIN_L] = Vector3(0.9 * pump, 0, 0)
		"cel_airplane":
			_loco_copy()
			var tm: float = st.get("time", 0.0)
			act_pose[B.ARM_L] = Vector3(0, 0, 1.5)
			act_pose[B.ARM_R] = Vector3(0, 0, -1.5)
			act_pose[B.FORE_L] = Vector3.ZERO
			act_pose[B.FORE_R] = Vector3.ZERO
			act_root_rot = Vector3(0, 0, sin(tm * 1.6) * 0.32)
			act_root = root_off
		"cel_kneeslide":
			act_root = Vector3(0, -0.47, 0)
			act_root_rot = Vector3(-0.3, 0, 0)
			act_pose[B.THIGH_L] = Vector3(0.25, 0, 0.12)
			act_pose[B.THIGH_R] = Vector3(0.25, 0, -0.12)
			act_pose[B.SHIN_L] = Vector3(1.6, 0, 0)
			act_pose[B.SHIN_R] = Vector3(1.6, 0, 0)
			act_pose[B.FOOT_L] = Vector3(0.6, 0, 0)
			act_pose[B.FOOT_R] = Vector3(0.6, 0, 0)
			act_pose[B.ARM_L] = Vector3(-0.3, 0, 2.5)
			act_pose[B.ARM_R] = Vector3(-0.3, 0, -2.5)
			act_pose[B.SPINE] = Vector3(-0.3, 0, 0)
			act_pose[B.NECK] = Vector3(-0.5, 0, 0)
		"cel_arms":
			var tm: float = st.get("time", 0.0)
			act_pose[B.ARM_L] = Vector3(-0.2, 0, 2.1 + 0.15 * sin(tm * 3.0))
			act_pose[B.ARM_R] = Vector3(-0.2, 0, -2.1 - 0.15 * sin(tm * 3.0))
			act_pose[B.CHEST] = Vector3(-0.25, 0, 0)
			act_pose[B.NECK] = Vector3(-0.4, 0, 0)
			act_pose[B.THIGH_L] = Vector3(0, 0, 0.12)
			act_pose[B.THIGH_R] = Vector3(0, 0, -0.12)
		"cheer":
			_loco_copy()
			act_pose[B.ARM_L] = Vector3(-0.4, 0, 2.3)
			act_pose[B.ARM_R] = Vector3(-0.4, 0, -2.3)
			act_root = root_off
		"dejected":
			act_pose[B.SPINE] = Vector3(0.35, 0, 0)
			act_pose[B.NECK] = Vector3(0.5, 0, 0)
			act_pose[B.ARM_L] = Vector3(-0.6, 0, 0.6)
			act_pose[B.ARM_R] = Vector3(-0.6, 0, -0.6)
			act_pose[B.FORE_L] = Vector3(-1.6, 0, 0)
			act_pose[B.FORE_R] = Vector3(-1.6, 0, 0)
		_:
			_loco_copy()
			act_root = root_off


func _loco_copy() -> void:
	for i in N:
		act_pose[i] = pose[i]


func _legs_from_loco() -> void:
	for i in [B.HIPS, B.THIGH_L, B.SHIN_L, B.FOOT_L, B.THIGH_R, B.SHIN_R, B.FOOT_R]:
		act_pose[i] = pose[i]
	act_root = root_off


## Right-foot kick family; t in 0..1, contact at ~0.5.
func _kick_pose(a: String, t: float) -> void:
	var power := 1.0
	var side_foot := 0.0
	var lean := 0.12
	match a:
		"pass":
			power = 0.55
			side_foot = 0.55
		"lob", "cross":
			power = 0.95
			lean = -0.18
		"volley":
			power = 1.0
			lean = -0.1
	var thigh := _k(t, [[0, 0.0], [0.35, 0.75 * power], [0.5, -0.85 * power], [0.72, -1.3 * power], [1, -0.15]])
	var shin := _k(t, [[0, 0.2], [0.35, 1.55 * power + 0.2], [0.5, 0.35], [0.72, 0.15], [1, 0.2]])
	act_pose[B.THIGH_R] = Vector3(thigh, -side_foot * 0.9, -0.08)
	act_pose[B.SHIN_R] = Vector3(shin, 0, 0)
	act_pose[B.FOOT_R] = Vector3(_k(t, [[0, 0.0], [0.4, 0.5], [0.5, -0.2], [1, 0.0]]), -side_foot * 0.6, 0)
	act_pose[B.THIGH_L] = Vector3(-0.22, 0, 0.12)
	act_pose[B.SHIN_L] = Vector3(0.45, 0, 0)
	act_pose[B.FOOT_L] = Vector3(-0.2, 0, 0)
	var arms := _k(t, [[0, 0.3], [0.4, 1.0], [0.75, 0.9], [1, 0.3]]) * power
	act_pose[B.ARM_L] = Vector3(-0.5 * arms, 0, 1.0 * arms + 0.15)
	act_pose[B.ARM_R] = Vector3(0.55 * arms, 0, -0.55 * arms - 0.1)
	act_pose[B.FORE_L] = Vector3(-0.5, 0, 0)
	act_pose[B.FORE_R] = Vector3(-0.6, 0, 0)
	act_pose[B.SPINE] = Vector3(lean + _k(t, [[0, 0.0], [0.5, 0.12], [1, 0.0]]), _k(t, [[0, 0.0], [0.35, 0.28 * power], [0.6, -0.2 * power], [1, 0.0]]), 0)
	act_pose[B.CHEST] = Vector3(0.05, _k(t, [[0, 0.0], [0.35, 0.15], [0.6, -0.15], [1, 0.0]]), 0)
	act_pose[B.NECK] = Vector3(0.2, 0, 0)
	act_root = Vector3(0, -0.05 * power, 0)


func _mirror(p: PackedVector3Array) -> void:
	var pairs := [[B.ARM_L, B.ARM_R], [B.FORE_L, B.FORE_R], [B.THIGH_L, B.THIGH_R], [B.SHIN_L, B.SHIN_R], [B.FOOT_L, B.FOOT_R]]
	for pr in pairs:
		var a: Vector3 = p[pr[0]]
		var b: Vector3 = p[pr[1]]
		p[pr[0]] = Vector3(b.x, -b.y, -b.z)
		p[pr[1]] = Vector3(a.x, -a.y, -a.z)
	for i in [B.HIPS, B.SPINE, B.CHEST, B.NECK, B.HEAD]:
		p[i] = Vector3(p[i].x, -p[i].y, -p[i].z)
