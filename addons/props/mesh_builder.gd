class_name LFMeshBuilder
extends RefCounted
## Tiny helper for building low-poly meshes triangle by triangle.
## Every triangle gets its own normal (never shared), which is what makes the
## model look "flat shaded" / faceted. Colours are stored per vertex.
## Winding: Godot treats clockwise triangles as front-facing.

static var _ico_cache: Dictionary = {}

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()


static func tint(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, 1.0)


## Raw triangle. Normal is derived from the winding.
func tri(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	_verts.append(a)
	_verts.append(b)
	_verts.append(c)
	_normals.append(n)
	_normals.append(n)
	_normals.append(n)
	_colors.append(ca)
	_colors.append(cb)
	_colors.append(cc)


## Triangle that is automatically wound so it faces away from `inside`
## (a point inside the solid). Saves us from getting winding right by hand.
func tri_out(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, inside: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		tri(a, c, b, ca, cc, cb)
	else:
		tri(a, b, c, ca, cb, cc)


func quad_out(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color, inside: Vector3) -> void:
	tri_out(a, b, c, ca, cb, cc, inside)
	tri_out(a, c, d, ca, cc, cd, inside)


## Tapered tube / cone along `dir`. r1 ~ 0 makes a cone.
func frustum(base: Vector3, dir: Vector3, length: float, r0: float, r1: float, sides: int,
		c0: Color, c1: Color, rng: RandomNumberGenerator, jitter: float = 0.0,
		cap_bottom: bool = false, twist: float = 0.0) -> void:
	var axis := dir.normalized()
	var ref := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var v := axis.cross(u)
	var top := base + axis * length
	var inside := base + axis * (length * 0.5)
	var ring0: Array[Vector3] = []
	var ring1: Array[Vector3] = []
	for i in sides:
		var ang := TAU * float(i) / float(sides) + twist
		var d := u * cos(ang) + v * sin(ang)
		var j0 := 1.0 + rng.randf_range(-jitter, jitter)
		var j1 := 1.0 + rng.randf_range(-jitter, jitter)
		ring0.append(base + d * (r0 * j0))
		ring1.append(top + d * (r1 * j1))
	for i in sides:
		var k := (i + 1) % sides
		var f := 1.0 + rng.randf_range(-0.06, 0.06)  # per-face shade jitter
		var cb := tint(c0, f)
		var ct := tint(c1, f)
		if r1 < 0.001:
			tri_out(ring0[i], ring0[k], top, cb, cb, ct, inside)
		else:
			quad_out(ring0[i], ring0[k], ring1[k], ring1[i], cb, cb, ct, ct, inside)
		if cap_bottom:
			tri_out(base, ring0[i], ring0[k], cb, cb, cb, inside)


## Lumpy ellipsoid made from a perturbed icosphere: canopies, rocks, bushes.
## `moss.a` is how strongly upward-facing faces are tinted with `moss`.
func blob(center: Vector3, radii: Vector3, subdiv: int, perturb: float, rng: RandomNumberGenerator,
		c_low: Color, c_high: Color, moss: Color = Color(0, 0, 0, 0)) -> void:
	var ico := _icosphere(subdiv)
	var uv: PackedVector3Array = ico[0]
	var idx: PackedInt32Array = ico[1]
	var pv := PackedVector3Array()
	for p in uv:
		pv.append(center + (p * (1.0 + rng.randf_range(-perturb, perturb))) * radii)
	for f in range(0, idx.size(), 3):
		var n := (uv[idx[f]] + uv[idx[f + 1]] + uv[idx[f + 2]]).normalized()
		var col := c_low.lerp(c_high, clampf(n.y * 0.5 + 0.5, 0.0, 1.0))
		col = tint(col, 1.0 + rng.randf_range(-0.08, 0.08))
		if moss.a > 0.0 and n.y > 0.4:
			col = col.lerp(Color(moss.r, moss.g, moss.b), moss.a)
		tri_out(pv[idx[f]], pv[idx[f + 1]], pv[idx[f + 2]], col, col, col, center)


## Thin bent blade (grass / flower stem). Use with a double-sided material.
func blade(base: Vector3, height: float, width: float, lean: Vector3, c_base: Color, c_tip: Color) -> void:
	var side := Vector3(-lean.z, 0, lean.x).normalized() if lean.length() > 0.001 else Vector3.RIGHT
	var l := side * width * 0.5
	var mid := base + Vector3(0, height * 0.55, 0) + lean * 0.3
	var tip := base + Vector3(0, height, 0) + lean
	var cm := c_base.lerp(c_tip, 0.55)
	tri(base - l, base + l, mid + l * 0.6, c_base, c_base, cm)
	tri(base - l, mid + l * 0.6, mid - l * 0.6, c_base, cm, cm)
	tri(mid - l * 0.6, mid + l * 0.6, tip, cm, cm, c_tip)


## Axis-aligned box (optionally turned by `yaw` around its centre), each face shaded a little
## differently. Used for anything boxy: walls, crates, furniture.
func box(c: Vector3, size: Vector3, col: Color, yaw: float = 0.0, jitter: float = 0.06) -> void:
	var h := size * 0.5
	var b := Basis(Vector3.UP, yaw)
	var p: Array[Vector3] = []
	for i in 8:
		p.append(c + b * Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	var faces := [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]
	var k := 0
	for f: Array in faces:
		var t := 1.0 + jitter * sin(c.x * 12.9 + c.y * 78.2 + c.z * 37.7 + float(k) * 4.1)
		var shade := 1.08 if k == 3 else (0.82 if k == 2 else 1.0)   # top lighter, bottom darker
		var fc := tint(col, t * shade)
		quad_out(p[f[0]], p[f[1]], p[f[2]], p[f[3]], fc, fc, fc, fc, c)
		k += 1


## Like box(), but turned by a full transform (a wall course on a slope, a crack rolled on a wall face).
func box_xf(xf: Transform3D, size: Vector3, col: Color, jitter: float = 0.06) -> void:
	var h := size * 0.5
	var p: Array[Vector3] = []
	for i in 8:
		p.append(xf * Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	var faces := [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]
	var k := 0
	for f: Array in faces:
		var t := 1.0 + jitter * sin(xf.origin.x * 12.9 + xf.origin.y * 78.2 + xf.origin.z * 37.7 + float(k) * 4.1)
		var shade := 1.08 if k == 3 else (0.82 if k == 2 else 1.0)
		var fc := tint(col, t * shade)
		quad_out(p[f[0]], p[f[1]], p[f[2]], p[f[3]], fc, fc, fc, fc, xf.origin)
		k += 1


## A plain material that colours by the vertex colours. `srgb` true reads them as sRGB, as the terrain, trees,
## rocks and buildings do (use it outdoors); false (the default, what dungeons use) reads them linear: paler.
static func vertex_material(rough: float = 0.92, srgb := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = srgb
	m.roughness = rough
	return m


func commit(material: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	add_surface_to(mesh, material)
	return mesh


## Appends this builder's triangles to `mesh` as a new surface (lets one prop have
## e.g. a rigid trunk surface and a separate, shader-animated canopy surface).
func add_surface_to(mesh: ArrayMesh, material: Material) -> void:
	if _verts.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


static func _icosphere(subdiv: int) -> Array:
	if _ico_cache.has(subdiv):
		return _ico_cache[subdiv]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in verts.size():
		verts[i] = verts[i].normalized()
	var faces: Array[int] = [
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	for s in subdiv:
		var mid: Dictionary = {}
		var nf: Array[int] = []
		for f in range(0, faces.size(), 3):
			var m: Array[int] = []
			for e in 3:
				var a := faces[f + e]
				var b := faces[f + (e + 1) % 3]
				var key := mini(a, b) * 10000 + maxi(a, b)
				if not mid.has(key):
					verts.append(((verts[a] + verts[b]) * 0.5).normalized())
					mid[key] = verts.size() - 1
				m.append(mid[key])
			var a0 := faces[f]
			var b0 := faces[f + 1]
			var c0 := faces[f + 2]
			nf.append_array([a0, m[0], m[2], b0, m[1], m[0], c0, m[2], m[1], m[0], m[1], m[2]])
		faces = nf
	var result := [PackedVector3Array(verts), PackedInt32Array(faces)]
	_ico_cache[subdiv] = result
	return result
