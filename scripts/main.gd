extends Node3D

# LIGHT OF KIRANA — starter scene.
# Builds the whole starter world in code: sky, sun, ground, a few
# obstacles, a camera, and a HUD label. No player yet, no animation
# files — gameplay is added one behaviour at a time, from a proven
# reference approved by Bagus (see Agent.md).

const WORLD_SIZE := 32.0


func _ready() -> void:
	_create_environment()
	_create_ground()
	_create_obstacles()
	_create_camera()
	_create_hud()


func _create_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.80, 0.92)
	environment.ambient_light_energy = 0.7
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)


func _create_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	add_child(ground)
	var mesh_instance := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(WORLD_SIZE, WORLD_SIZE)
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.42, 0.25)
	material.roughness = 1.0
	mesh_instance.material_override = material
	ground.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(WORLD_SIZE, 0.2, WORLD_SIZE)
	collision.shape = shape
	collision.position.y = -0.1
	ground.add_child(collision)


func _create_obstacles() -> void:
	for pos in [Vector3(4.0, 0.5, -4.0), Vector3(-5.0, 0.5, -2.0), Vector3(0.0, 0.5, -8.0)]:
		var body := StaticBody3D.new()
		body.position = pos
		add_child(body)
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		mesh_instance.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.6, 0.45, 0.3)
		mesh_instance.material_override = material
		body.add_child(mesh_instance)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3.ONE
		collision.shape = shape
		body.add_child(collision)


func _create_camera() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 4.0, 9.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.5, 0.0), Vector3.UP)


func _create_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = "LIGHT OF KIRANA — starter"
	label.position = Vector2(16, 16)
	layer.add_child(label)
