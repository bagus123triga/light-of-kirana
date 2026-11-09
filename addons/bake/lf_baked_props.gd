class_name LFBakedProps
extends RefCounted
## Finds and removes single props of a baked map at run time: a tree to fell, a rock to mine, a log to pick
## up. A bake draws trees, rocks and logs as MultiMeshes and gives each kind one collision body per batch
## (TreeBody, RockBody, LogBody, in groups tree / rock / log); each body knows where its props stand (metas
## lf_anchors and lf_ends), so a ray hit names one prop:
##
##   var hit := get_world_3d().direct_space_state.intersect_ray(query)
##   var prop := LFBakedProps.find(hit.collider, hit.position)
##   if not prop.is_empty():
##       LFBakedProps.remove(prop)   # gone from view and from collision
##
## Removing changes only the loaded tile, not the files: a tile loaded again (LFTileStreamer) has the prop
## back. Keep what was removed (its "position") and remove it again when the tile loads (find_near).

## How far (m) from a prop's anchor its drawn instance may stand (a boulder's centre is above its foot).
const MATCH_RADIUS := 6.0


## The prop of a baked TreeBody / RockBody / LogBody nearest `point` (world space: a ray hit on it), as
## {"body", "part": its index in the body, "position": where it stands (world), "group": tree / rock / log,
## "mesh": the MultiMeshInstance3D drawing it (null if none is near), "instance": its index there}.
## Empty if `body` is not a baked prop body, or its props are all removed.
static func find(body: Object, point: Vector3) -> Dictionary:
	if not body is StaticBody3D or not (body as Node).has_meta(&"lf_anchors"):
		return {}
	var b := body as StaticBody3D
	var anchors: PackedVector3Array = b.get_meta(&"lf_anchors")
	var ends: PackedInt32Array = b.get_meta(&"lf_ends")
	var local := b.global_transform.affine_inverse() * point
	var flat := b.is_in_group(LFTileBaker.GROUP_TREE)   # a trunk is hit anywhere up it: match its foot by x, z
	var best := -1
	var best_d := INF
	for i in anchors.size():
		if ends[i] == (ends[i - 1] if i > 0 else 0):
			continue   # removed
		var d := anchors[i] - local
		if flat:
			d.y = 0.0
		if d.length_squared() < best_d:
			best_d = d.length_squared()
			best = i
	if best < 0:
		return {}
	var out := {"body": b, "part": best, "position": b.global_transform * anchors[best],
			"group": _group_of(b), "mesh": null, "instance": -1}
	_match_instance(out, anchors[best])
	return out


## The prop of `group` (tree, rock, log; empty: any) standing nearest `position` (world) under `root` (a tile, a
## map), within `radius` m: find's result, or empty. For removing again what was removed before a tile reloaded.
static func find_near(root: Node, position: Vector3, group := &"", radius := 1.0) -> Dictionary:
	var best := {}
	var best_d := radius
	for n in root.find_children("*Body", "StaticBody3D", true, false):
		if not n.has_meta(&"lf_anchors") or group != &"" and not n.is_in_group(group):
			continue
		var p := find(n, position)
		if not p.is_empty() and (p["position"] as Vector3).distance_to(position) <= best_d:
			best_d = (p["position"] as Vector3).distance_to(position)
			best = p
	return best


## Removes a prop find() returned: its instance stops drawing and its collision goes. The body's shape and the
## MultiMesh are made this node's own first, so the scene file and other copies of it keep the prop.
static func remove(prop: Dictionary) -> void:
	var b: StaticBody3D = prop.get("body")
	if b == null or not is_instance_valid(b):
		return
	var part: int = prop["part"]
	var ends: PackedInt32Array = b.get_meta(&"lf_ends")
	var start := ends[part - 1] if part > 0 else 0
	var count := ends[part] - start
	if count > 0:
		var cs: CollisionShape3D = null
		for c in b.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is ConcavePolygonShape3D:
				cs = c
				break
		if cs != null:
			if not b.has_meta(&"lf_own"):
				cs.shape = cs.shape.duplicate()
				b.set_meta(&"lf_own", true)
			var shape := cs.shape as ConcavePolygonShape3D
			var faces := shape.get_faces()
			var kept := faces.slice(0, start)
			kept.append_array(faces.slice(start + count))
			shape.set_faces(kept)
		for i in range(part, ends.size()):
			ends[i] -= count
		b.set_meta(&"lf_ends", ends)
	var mmi: MultiMeshInstance3D = prop.get("mesh")
	var k: int = prop.get("instance", -1)
	if mmi != null and is_instance_valid(mmi) and k >= 0:
		if not mmi.has_meta(&"lf_own"):
			mmi.multimesh = mmi.multimesh.duplicate()
			mmi.set_meta(&"lf_own", true)
		var buf := mmi.multimesh.buffer   # (get_instance_transform reads the renderer: identity when headless)
		for c: int in [0, 1, 2, 4, 5, 6, 8, 9, 10]:   # the basis: scaled to nothing, the origin kept
			buf[k * 12 + c] = 0.0
		mmi.multimesh.buffer = buf


## tree, rock or log: the group of a prop body.
static func _group_of(b: Node) -> StringName:
	for g: StringName in [LFTileBaker.GROUP_TREE, LFTileBaker.GROUP_ROCK, LFTileBaker.GROUP_LOG]:
		if b.is_in_group(g):
			return g
	return &""


## Fills prop's "mesh" and "instance": the drawn instance of its group nearest `anchor` (body space, which is
## the batch's: bodies and MultiMeshes sit at its origin) among the body's sibling MultiMeshes.
static func _match_instance(prop: Dictionary, anchor: Vector3) -> void:
	var b: StaticBody3D = prop["body"]
	var parent := b.get_parent()
	if parent == null:
		return
	var best_d := MATCH_RADIUS * MATCH_RADIUS
	for c in parent.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or _kind_group(String(mmi.name)) != prop["group"]:
			continue
		var buf := mmi.multimesh.buffer   # 12 floats an instance: basis rows, the origin at 3, 7, 11
		for k in mmi.multimesh.instance_count:
			var i := k * 12
			if buf[i] == 0.0 and buf[i + 1] == 0.0 and buf[i + 2] == 0.0:
				continue   # removed
			var d := (b.transform * anchor).distance_squared_to(mmi.transform * Vector3(buf[i + 3], buf[i + 7], buf[i + 11]))
			if d < best_d:
				best_d = d
				prop["mesh"] = mmi
				prop["instance"] = k


## The group of the props a baked MultiMeshInstance3D named `name` ("Pine_0", "Snow Pine_2") draws.
static func _kind_group(mmi_name: String) -> StringName:
	var label := mmi_name.substr(0, mmi_name.rfind("_"))
	var names: Array = LFPropMeshes.Kind.keys()
	for kind in names.size():
		if String(names[kind]).capitalize() != label:
			continue
		if LFPropMeshes.is_small(kind):
			return &""
		if kind in [LFPropMeshes.Kind.ROCK, LFPropMeshes.Kind.CLIFF]:
			return LFTileBaker.GROUP_ROCK
		return LFTileBaker.GROUP_LOG if kind == LFPropMeshes.Kind.LOG else LFTileBaker.GROUP_TREE
	return &""
