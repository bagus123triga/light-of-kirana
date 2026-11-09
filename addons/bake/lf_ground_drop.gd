class_name LFGroundDrop
extends RefCounted
## Puts nodes on the ground: the editor's Ground menu (3D toolbar) uses it on the selection. The ground is
## the LFMapBaker map under the node if there is one (no collision needed: works on the preview), otherwise
## the first collider straight below (a baked map, your own floors). The node's origin goes on the ground.


## The node's new global transform on the ground under it (tilted so its up follows the slope if `align`),
## or null if there is no ground below. `root`: the scene searched for LFMapBakers.
static func dropped(node: Node3D, root: Node, align := false) -> Variant:
	var xf := node.global_transform
	var hit := ground_under(node, root)
	if hit.is_empty():
		return null
	xf.origin = hit["position"]
	if align:
		var up := xf.basis.y.normalized()
		var n: Vector3 = hit["normal"]
		if up.dot(n) < 0.9999:
			xf.basis = Basis(Quaternion(up, n)) * xf.basis
	return xf


## {"position", "normal"} (global) of the ground straight below or above the node, or {} if none.
static func ground_under(node: Node3D, root: Node) -> Dictionary:
	var p := node.global_position
	for b in _bakers(root):
		if b == node:
			continue
		var lp := b.global_transform.affine_inverse() * p
		if not b.covers(lp):
			continue
		var g := b.ground_at(lp)
		return {"position": b.global_transform * Vector3(lp.x, g.w, lp.z),
				"normal": (b.global_basis * Vector3(g.x, g.y, g.z)).normalized()}
	if not node.is_inside_tree():
		return {}
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1000.0, p + Vector3.DOWN * 2000.0)
	var skip: Array[RID] = []
	for c in [node] + node.find_children("*", "CollisionObject3D", true, false):
		if c is CollisionObject3D:
			skip.append((c as CollisionObject3D).get_rid())   # not onto itself
	q.exclude = skip
	var hit := node.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {}
	return {"position": hit["position"], "normal": hit["normal"]}


static func _bakers(root: Node) -> Array[LFMapBaker]:
	var out: Array[LFMapBaker] = []
	if root is LFMapBaker:
		out.append(root)
	for n in root.find_children("*", "Node3D", true, false):
		if n is LFMapBaker:
			out.append(n)
	return out
