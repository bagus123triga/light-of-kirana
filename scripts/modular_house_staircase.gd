@tool
extends Node3D

## Reusable residential staircase. Place/rotate this scene anywhere in a level.
## The stairs are built from solid step blocks with matching collision shapes.

@export_range(3, 24, 1) var step_count: int = 12:
	set(value):
		step_count = value
		if is_inside_tree():
			_rebuild()

@export_range(0.8, 3.0, 0.05) var stair_width: float = 1.4:
	set(value):
		stair_width = value
		if is_inside_tree():
			_rebuild()

@export_range(0.18, 0.4, 0.01) var tread_depth: float = 0.28:
	set(value):
		tread_depth = value
		if is_inside_tree():
			_rebuild()

@export_range(0.12, 0.24, 0.01) var riser_height: float = 0.18:
	set(value):
		riser_height = value
		if is_inside_tree():
			_rebuild()

@export var add_handrails: bool = true:
	set(value):
		add_handrails = value
		if is_inside_tree():
			_rebuild()

@export var stair_material: Material

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var material := stair_material
	if material == null:
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.48, 0.29, 0.16)
		wood.roughness = 0.82
		material = wood

	for i in range(step_count):
		var height := float(i + 1) * riser_height
		# Each tread is a real solid step: its visual block and collision
		# share the same dimensions. The block fills from floor level to
		# this riser's top, creating a true staircase profile.
		var step_body := StaticBody3D.new()
		step_body.name = "Step_%02d" % (i + 1)
		# Step blocks are visual/foot-placement surfaces only. The player
		# rides the continuous ramp collision built below, so the capsule
		# never catches on vertical risers. Layer 2 remains raycast-visible.
		step_body.collision_layer = 2
		step_body.collision_mask = 0
		step_body.position = Vector3(0.0, height * 0.5, -(float(i) + 0.5) * tread_depth)
		add_child(step_body)

		var step_mesh := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(stair_width, height, tread_depth)
		step_mesh.mesh = box_mesh
		step_mesh.material_override = material
		step_body.add_child(step_mesh)

		var step_collision := CollisionShape3D.new()
		var step_shape := BoxShape3D.new()
		step_shape.size = box_mesh.size
		step_collision.shape = step_shape
		step_body.add_child(step_collision)

	if add_handrails and step_count >= 3:
		_build_handrail(-1.0, material)
		_build_handrail(1.0, material)

	_build_walkable_ramp()
	_setup_stair_trigger()


func _build_walkable_ramp() -> void:
	# A continuous collision surface follows the centre of every tread.
	# This preserves the visible stepped geometry while giving CharacterBody3D
	# a walkable slope (both up and down) instead of a wall at every riser.
	# The slope is below floor_max_angle for both configured stair variants.
	var total_height := float(step_count) * riser_height
	var total_depth := float(step_count) * tread_depth
	var profile: Array[Vector3] = [Vector3(0.0, 0.0, tread_depth * 0.5)]
	for i in range(step_count):
		profile.append(Vector3(0.0, float(i + 1) * riser_height, -(float(i) + 0.5) * tread_depth))
	profile.append(Vector3(0.0, total_height, -total_depth))

	var faces := PackedVector3Array()
	var half_width := stair_width * 0.5
	for i in range(profile.size() - 1):
		var a := profile[i]
		var b := profile[i + 1]
		var a_left := a + Vector3(-half_width, 0.0, 0.0)
		var a_right := a + Vector3(half_width, 0.0, 0.0)
		var b_left := b + Vector3(-half_width, 0.0, 0.0)
		var b_right := b + Vector3(half_width, 0.0, 0.0)
		faces.append(a_left)
		faces.append(a_right)
		faces.append(b_right)
		faces.append(a_left)
		faces.append(b_right)
		faces.append(b_left)

	var ramp_shape := ConcavePolygonShape3D.new()
	ramp_shape.set_faces(faces)
	var ramp_body := StaticBody3D.new()
	ramp_body.name = "WalkableRamp"
	ramp_body.collision_layer = 1
	ramp_body.collision_mask = 1
	var ramp_collision := CollisionShape3D.new()
	ramp_collision.shape = ramp_shape
	ramp_body.add_child(ramp_collision)
	add_child(ramp_body)


func _setup_stair_trigger() -> void:
	var total_height := float(step_count) * riser_height
	var total_depth := float(step_count) * tread_depth
	var trigger := Area3D.new()
	trigger.name = "StairTraversalArea"
	trigger.collision_layer = 0
	trigger.collision_mask = 1
	var trigger_shape := CollisionShape3D.new()
	var area_box := BoxShape3D.new()
	area_box.size = Vector3(stair_width + 0.8, total_height + 2.0, total_depth + 1.0)
	trigger_shape.shape = area_box
	trigger_shape.position = Vector3(0.0, total_height * 0.5, -total_depth * 0.5)
	trigger.add_child(trigger_shape)
	trigger.body_entered.connect(_on_stair_body_entered)
	trigger.body_exited.connect(_on_stair_body_exited)
	add_child(trigger)


func _stair_up_direction() -> Vector3:
	var slope_ratio := riser_height / tread_depth
	return (global_basis * Vector3(0.0, 1.0, -slope_ratio).normalized()).normalized()


func _on_stair_body_entered(body: Node3D) -> void:
	if body.has_method("set_stair_state"):
		body.set_stair_state(true, _stair_up_direction(), tread_depth)


func _on_stair_body_exited(body: Node3D) -> void:
	if body.has_method("set_stair_state"):
		body.set_stair_state(false)


func _build_handrail(side: float, material: Material) -> void:
	var rail_x := side * (stair_width * 0.5 - 0.06)
	var post_material := StandardMaterial3D.new()
	post_material.albedo_color = Color(0.28, 0.17, 0.10)
	post_material.roughness = 0.72

	var post_indices: Array[int] = [0, int(step_count / 2), step_count - 1]
	var first_point := Vector3.ZERO
	var last_point := Vector3.ZERO

	for index in post_indices:
		var tread_y := float(index + 1) * riser_height
		var point := Vector3(rail_x, tread_y + 0.82, -(float(index) + 0.5) * tread_depth)
		if index == post_indices[0]:
			first_point = point
		if index == post_indices[post_indices.size() - 1]:
			last_point = point

		var post_bottom := Vector3(rail_x, tread_y, point.z)
		_add_cylinder_beam("RailPost_%s_%d" % [str(side), index], post_bottom, point, 0.035, post_material)

	_add_cylinder_beam("Handrail_%s" % str(side), first_point, last_point, 0.045, post_material)

func _add_cylinder_beam(node_name: String, start: Vector3, finish: Vector3, radius: float, material: Material) -> void:
	var direction := finish - start
	var beam := MeshInstance3D.new()
	beam.name = node_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = direction.length()
	beam.mesh = cylinder
	beam.material_override = material
	beam.position = (start + finish) * 0.5
	beam.quaternion = Quaternion(Vector3.UP, direction.normalized())
	add_child(beam)
