extends Node3D

## Light of Kirana — procedural walking experiment.
## World: flat grey map only, daylight, orange humanoid (Singer reference).
## Controls: WASD / arrows + Shift run + Space jump (desktop),
## virtual joystick + RUN / JUMP buttons (touch), drag anywhere else to orbit camera.

var humanoid: ProceduralHumanoid
var camera_pivot: Node3D
var camera: Camera3D
var joystick: KiranaVirtualJoystick
var run_button: KiranaTouchButton
var jump_button: KiranaTouchButton

var cam_yaw := 0.0
var cam_pitch := -0.35
var run_held := false
var _orbit_touch := -1
var _orbit_last := Vector2.ZERO
var _orbit_mouse := false


func _ready() -> void:
	_build_world()
	_build_humanoid()
	_build_camera()
	_build_ui()


func _grey_material(albedo: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = 1.0
	return mat


func _build_world() -> void:
	# Daylight sky: pale grey (the whole world is grey, humanoid is orange).
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.72, 0.74, 0.76)
	sky_mat.sky_horizon_color = Color(0.86, 0.86, 0.86)
	sky_mat.ground_bottom_color = Color(0.45, 0.45, 0.45)
	sky_mat.ground_horizon_color = Color(0.8, 0.8, 0.8)
	sky_mat.sun_angle_max = 30.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Midday sun.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_color = Color(1.0, 0.98, 0.94)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

	# Flat grey map only: one 100 x 100 m plane, y = 0.
	var ground_body := StaticBody3D.new()
	ground_body.name = "Ground"
	add_child(ground_body)
	var ground_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100, 100)
	ground_mesh.mesh = plane
	ground_mesh.material_override = _grey_material(Color(0.55, 0.55, 0.55))
	ground_body.add_child(ground_mesh)
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	ground_shape.shape = box
	ground_shape.position = Vector3(0, -0.5, 0)
	ground_body.add_child(ground_shape)


func _build_humanoid() -> void:
	humanoid = ProceduralHumanoid.new()
	humanoid.name = "Humanoid"
	humanoid.position = Vector3(0, 0, 0)
	add_child(humanoid)


func _build_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	add_child(camera_pivot)
	camera = Camera3D.new()
	camera.position = Vector3(0, 2.2, 4.5)
	camera.fov = 60.0
	camera_pivot.add_child(camera)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var hint := Label.new()
	hint.text = "Light of Kirana — procedural walk (Singer)  |  WASD jalan, Shift lari, Space lompat"
	hint.position = Vector2(16, 12)
	hint.add_theme_color_override("font_color", Color(0.25, 0.25, 0.25))
	layer.add_child(hint)

	joystick = KiranaVirtualJoystick.new()
	joystick.position = Vector2(24, 480)
	joystick.size = Vector2(220, 220)
	layer.add_child(joystick)

	run_button = KiranaTouchButton.new()
	run_button.label_text = "LARI"
	run_button.position = Vector2(1050, 500)
	run_button.size = Vector2(96, 96)
	run_button.pressed_down.connect(func() -> void: run_held = true)
	run_button.released_up.connect(func() -> void: run_held = false)
	layer.add_child(run_button)

	jump_button = KiranaTouchButton.new()
	jump_button.label_text = "LOMPAT"
	jump_button.position = Vector2(1160, 600)
	jump_button.size = Vector2(96, 96)
	jump_button.pressed_down.connect(func() -> void: humanoid.want_jump = true)
	layer.add_child(jump_button)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_orbit_mouse = event.pressed
	elif event is InputEventMouseMotion and _orbit_mouse:
		var motion := event as InputEventMouseMotion
		cam_yaw -= motion.relative.x * 0.005
		cam_pitch = clampf(cam_pitch - motion.relative.y * 0.005, -1.2, 0.4)
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _orbit_touch == -1:
			_orbit_touch = touch.index
			_orbit_last = touch.position
		elif not touch.pressed and touch.index == _orbit_touch:
			_orbit_touch = -1
	elif event is InputEventScreenDrag and event.index == _orbit_touch:
		var drag := event as InputEventScreenDrag
		var d: Vector2 = drag.position - _orbit_last
		_orbit_last = drag.position
		cam_yaw -= d.x * 0.006
		cam_pitch = clampf(cam_pitch - d.y * 0.006, -1.2, 0.4)


func _process(delta: float) -> void:
	var kb := Vector2.ZERO
	kb.y -= 1.0 if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) else 0.0
	kb.y += 1.0 if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) else 0.0
	kb.x -= 1.0 if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT) else 0.0
	kb.x += 1.0 if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT) else 0.0
	# Joystick output: y down = +, so forward is -output.y.
	var stick := Vector2(joystick.output.x, -joystick.output.y) if joystick != null else Vector2.ZERO
	var move2d := kb + stick
	if move2d.length() > 1.0:
		move2d = move2d.normalized()

	var running := run_held or Input.is_key_pressed(KEY_SHIFT)
	if Input.is_key_pressed(KEY_SPACE):
		humanoid.want_jump = true

	# Camera-relative wish direction. Camera looks -Z from behind the pivot.
	var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	humanoid.wish_dir = (right * move2d.x + fwd * -move2d.y).normalized() * move2d.length() if move2d.length() > 0.05 else Vector3.ZERO
	humanoid.is_running = running
	humanoid.move_input = move2d

	# Third-person camera follows the humanoid.
	camera_pivot.position = humanoid.global_position + Vector3(0, 1.4, 0)
	camera_pivot.rotation.y = cam_yaw
	camera_pivot.rotation.x = cam_pitch
