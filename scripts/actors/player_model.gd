class_name PlayerModel
extends RefCounted
## Builds the shared skinned athlete mesh and per-player skeletons.
## Model faces +Z, character's left is +X. Regions are baked into UV2.y (see player.gdshader).

enum { ROOT, HIPS, SPINE, CHEST, NECK, HEAD, ARM_L, FORE_L, ARM_R, FORE_R, THIGH_L, SHIN_L, FOOT_L, THIGH_R, SHIN_R, FOOT_R }

const BONES := [
	["root", -1, Vector3(0, 0, 0)],
	["hips", 0, Vector3(0, 0.96, 0)],
	["spine", 1, Vector3(0, 0.14, 0)],
	["chest", 2, Vector3(0, 0.20, 0)],
	["neck", 3, Vector3(0, 0.20, 0)],
	["head", 4, Vector3(0, 0.085, 0)],
	["arm_l", 3, Vector3(0.2, 0.155, 0)],
	["fore_l", 6, Vector3(0.005, -0.285, 0)],
	["arm_r", 3, Vector3(-0.2, 0.155, 0)],
	["fore_r", 8, Vector3(-0.005, -0.285, 0)],
	["thigh_l", 1, Vector3(0.095, -0.03, 0)],
	["shin_l", 10, Vector3(0, -0.44, 0)],
	["foot_l", 11, Vector3(0, -0.425, 0)],
	["thigh_r", 1, Vector3(-0.095, -0.03, 0)],
	["shin_r", 13, Vector3(0, -0.44, 0)],
	["foot_r", 14, Vector3(0, -0.425, 0)],
]

enum Region { SKIN, SHIRT, SHORTS, SOCKS, BOOTS, HAIR, HAND, FACE }

static var _mesh: ArrayMesh
static var _material: ShaderMaterial

var _st: SurfaceTool
var _count := 0


static func shared_mesh() -> ArrayMesh:
	if _mesh == null:
		_mesh = PlayerModel.new()._build()
	return _mesh


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/player.gdshader")
	return _material


static func make_skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	for b in BONES:
		var i = sk.add_bone(b[0])
		if b[1] >= 0:
			sk.set_bone_parent(i, b[1])
		sk.set_bone_rest(i, Transform3D(Basis(), b[2]))
	sk.reset_bone_poses()
	return sk


static func global_rest(i: int) -> Vector3:
	var p := Vector3.ZERO
	var k := i
	while k >= 0:
		p += BONES[k][2]
		k = BONES[k][1]
	return p


# ------------------------------------------------------------ building
func _build() -> ArrayMesh:
	_st = SurfaceTool.new()
	_st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# torso
	_tube(Vector3(0, 0.9, 0.0), Vector3(0, 1.535, 0.0), _torso_r, func(p, t): return Region.SHIRT,
		func(p, t): return _chain(p.y, [[0.96, HIPS], [1.12, SPINE], [1.3, CHEST]]), 16, 12)
	# pelvis / shorts
	_tube(Vector3(0, 0.8, 0), Vector3(0, 0.99, 0), func(t): return Vector2(0.162, 0.112),
		func(p, t): return Region.SHORTS, func(p, t): return [[HIPS, 1.0]], 16, 3)
	for s in [1.0, -1.0]:
		var left: bool = s > 0.0
		var thigh: int = THIGH_L if left else THIGH_R
		var shin: int = SHIN_L if left else SHIN_R
		var foot: int = FOOT_L if left else FOOT_R
		var arm: int = ARM_L if left else ARM_R
		var fore: int = FORE_L if left else FORE_R
		var x: float = 0.095 * s
		_tube(Vector3(x, 0.97, 0), Vector3(x, 0.49, 0), _thigh_r,
			func(p, t): return Region.SHORTS if p.y > 0.69 else Region.SKIN,
			func(p, t): return _blend(t, HIPS, thigh, shin, 0.12, 0.16), 12, 8)
		_tube(Vector3(x, 0.5, 0), Vector3(x, 0.07, 0), _shin_r,
			func(p, t): return Region.SOCKS if p.y < 0.455 else Region.SKIN,
			func(p, t): return _blend(t, thigh, shin, foot, 0.12, 0.14), 12, 7)
		_tube(Vector3(x, 0.05, -0.075), Vector3(x, 0.045, 0.175), _boot_r,
			func(p, t): return Region.BOOTS, func(p, t): return [[foot, 1.0]], 10, 7)
		_ellipsoid(Vector3(0.188 * s, 1.44, 0.0), Vector3(0.068, 0.06, 0.07), func(p): return Region.SHIRT, func(p): return [[CHEST, 0.5], [arm, 0.5]], 10, 6)
		_tube(Vector3(0.2 * s, 1.47, 0), Vector3(0.205 * s, 1.17, 0), func(t): return Vector2(lerp(0.054, 0.04, t), lerp(0.054, 0.04, t)),
			func(p, t): return Region.SHIRT if t < 0.42 else Region.SKIN,
			func(p, t): return _blend(t, CHEST, arm, fore, 0.1, 0.14), 10, 6)
		_tube(Vector3(0.205 * s, 1.18, 0), Vector3(0.21 * s, 0.92, 0), func(t): return Vector2(lerp(0.041, 0.03, t), lerp(0.041, 0.03, t)),
			func(p, t): return Region.SKIN, func(p, t): return _blend(t, arm, fore, fore, 0.14, 0.0), 10, 5)
		_ellipsoid(Vector3(0.212 * s, 0.87, 0.008), Vector3(0.03, 0.052, 0.042), func(p): return Region.HAND, func(p): return [[fore, 1.0]], 8, 6)
	# neck
	_tube(Vector3(0, 1.47, 0), Vector3(0, 1.64, 0.0), func(t): return Vector2(0.051, 0.054),
		func(p, t): return Region.SKIN, func(p, t): return _chain(p.y, [[1.5, CHEST], [1.56, NECK], [1.62, HEAD]]), 10, 3)
	# head
	_ellipsoid(Vector3(0, 1.705, 0.008), Vector3(0.096, 0.118, 0.106), _head_region, func(p): return [[HEAD, 1.0]], 14, 10)
	_ellipsoid(Vector3(0, 1.69, 0.108), Vector3(0.016, 0.026, 0.02), func(p): return Region.FACE, func(p): return [[HEAD, 1.0]], 6, 4)
	_st.generate_tangents()
	return _st.commit()


func _torso_r(t: float) -> Vector2:
	var y: float = lerp(0.9, 1.535, t)
	var rx := _prof(y, [[0.9, 0.152], [1.05, 0.156], [1.28, 0.178], [1.42, 0.198], [1.49, 0.16], [1.535, 0.055]])
	var rz := _prof(y, [[0.9, 0.104], [1.1, 0.104], [1.28, 0.118], [1.42, 0.104], [1.49, 0.085], [1.535, 0.045]])
	return Vector2(rx, rz)


func _thigh_r(t: float) -> Vector2:
	var y: float = lerp(0.97, 0.49, t)
	var r := 0.094 if y > 0.69 else _prof(y, [[0.49, 0.058], [0.6, 0.07], [0.69, 0.082]])
	return Vector2(r, r * 1.02)


func _shin_r(t: float) -> Vector2:
	var y: float = lerp(0.5, 0.07, t)
	var r := _prof(y, [[0.07, 0.04], [0.2, 0.045], [0.34, 0.062], [0.44, 0.06], [0.5, 0.057]])
	return Vector2(r, r * 1.08)


func _boot_r(t: float) -> Vector2:
	var e = sqrt(max(0.0, 1.0 - pow(abs(2.0 * t - 1.0), 4.0)))
	return Vector2(0.05 * e, 0.047 * e)


func _head_region(p: Vector3) -> int:
	var lp: Vector3 = p - Vector3(0, 1.705, 0.008)
	if lp.y > 0.045 or (lp.z < -0.015 and lp.y > -0.05) or (abs(lp.x) > 0.085 and lp.y > 0.0 and lp.z < 0.04):
		return Region.HAIR
	return Region.FACE


func _prof(y: float, pts: Array) -> float:
	if y <= pts[0][0]:
		return pts[0][1]
	for i in pts.size() - 1:
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		if y <= b[0]:
			var t: float = (y - a[0]) / (b[0] - a[0])
			t = t * t * (3.0 - 2.0 * t)
			return lerp(float(a[1]), float(b[1]), t)
	return pts[pts.size() - 1][1]


## Weights along a vertical chain of bones by height.
func _chain(y: float, pts: Array) -> Array:
	if y <= pts[0][0]:
		return [[pts[0][1], 1.0]]
	for i in pts.size() - 1:
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		if y <= b[0]:
			var t: float = (y - a[0]) / (b[0] - a[0])
			return [[a[1], 1.0 - t], [b[1], t]]
	return [[pts[pts.size() - 1][1], 1.0]]


func _blend(t: float, start_b: int, main_b: int, end_b: int, e0: float, e1: float) -> Array:
	if e0 > 0.0 and t < e0:
		var w := 0.5 + 0.5 * (t / e0)
		return [[main_b, w], [start_b, 1.0 - w]]
	if e1 > 0.0 and t > 1.0 - e1:
		var w := 0.5 + 0.5 * ((1.0 - t) / e1)
		return [[main_b, w], [end_b, 1.0 - w]]
	return [[main_b, 1.0]]


func _vert(p: Vector3, n: Vector3, region: int, weights: Array) -> int:
	var bones := PackedInt32Array([0, 0, 0, 0])
	var ws := PackedFloat32Array([0, 0, 0, 0])
	var total := 0.0
	for k in min(4, weights.size()):
		bones[k] = weights[k][0]
		ws[k] = weights[k][1]
		total += weights[k][1]
	for k in 4:
		ws[k] /= max(total, 0.0001)
	_st.set_normal(n)
	_st.set_uv(Vector2(p.x, p.y))
	_st.set_uv2(Vector2(p.z, float(region)))
	_st.set_bones(bones)
	_st.set_weights(ws)
	_st.add_vertex(p)
	_count += 1
	return _count - 1


func _tube(a: Vector3, b: Vector3, radius: Callable, region: Callable, weights: Callable, segs: int, rings: int) -> void:
	var axis := (b - a).normalized()
	var ref = Vector3(1, 0, 0) if abs(axis.y) > 0.7 else Vector3(0, 1, 0)
	var u := (ref - axis * ref.dot(axis)).normalized()
	var v := axis.cross(u).normalized()
	var base := _count
	for j in rings + 1:
		var t := float(j) / rings
		var c = a.lerp(b, t)
		var r: Vector2 = radius.call(t)
		for i in segs:
			var th := TAU * float(i) / segs
			var off = u * cos(th) * r.x + v * sin(th) * r.y
			var n = (u * cos(th) / max(r.x, 0.001) + v * sin(th) / max(r.y, 0.001)).normalized()
			var p = c + off
			_vert(p, n, region.call(p, t), weights.call(p, t))
	for j in rings:
		for i in segs:
			var i2 := (i + 1) % segs
			var a0 := base + j * segs + i
			var a1 := base + j * segs + i2
			var b0 := base + (j + 1) * segs + i
			var b1 := base + (j + 1) * segs + i2
			_tri_out(a0, b0, a1)
			_tri_out(a1, b0, b1)


var _positions: Dictionary = {}

func _tri_out(i0: int, i1: int, i2: int) -> void:
	# Godot front faces are clockwise; this ring winding produces outward faces.
	_st.add_index(i0)
	_st.add_index(i1)
	_st.add_index(i2)


func _ellipsoid(c: Vector3, r: Vector3, region: Callable, weights: Callable, segs: int, rings: int) -> void:
	var base := _count
	for j in rings + 1:
		var phi := PI * float(j) / rings
		for i in segs:
			var th := TAU * float(i) / segs
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var p := c + d * r
			var n := Vector3(d.x / r.x, d.y / r.y, d.z / r.z).normalized()
			_vert(p, n, region.call(p), weights.call(p))
	for j in rings:
		for i in segs:
			var i2 := (i + 1) % segs
			var a0 := base + j * segs + i
			var a1 := base + j * segs + i2
			var b0 := base + (j + 1) * segs + i
			var b1 := base + (j + 1) * segs + i2
			_st.add_index(a0)
			_st.add_index(b0)
			_st.add_index(a1)
			_st.add_index(a1)
			_st.add_index(b0)
			_st.add_index(b1)
