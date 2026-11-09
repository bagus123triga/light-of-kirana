extends Node3D

## Light of Kirana — procedural walking experiment.
## World: flat grey map only, daylight, orange humanoid (Singer reference).
## Controls: WASD / arrows + Shift run + Space jump (desktop),
## virtual joystick + RUN / JUMP buttons (touch), drag anywhere else to orbit camera.

var humanoid: ProceduralHumanoid
var camera: Camera3D
var joystick: KiranaVirtualJoystick
var run_button: KiranaTouchButton
var jump_button: KiranaTouchButton

# cam_pitch = elevation angle of the camera above the humanoid (radians).
# Positive = camera above, looking down at the humanoid in the centre.
var cam_yaw := 0.0
var cam_pitch := 0.35
const CAMERA_MIN_PITCH := -0.35
const CAMERA_MAX_PITCH := 1.54
const CAM_DISTANCE := 4.2
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
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Midday sun.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_color = Color(1.0, 0.98, 0.94)
	sun.light_energy = 1.0
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

	# Temporary residential staircase prop for the next level-design stage.
	# Kept beside the spawn point so it is visible immediately in the test world.
	var staircase_scene: PackedScene = preload("res://scenes/props/modular_house_staircase.tscn")
	var staircase := staircase_scene.instantiate() as Node3D
	staircase.name = "HouseStaircase_Test"
	staircase.rotation.y = PI
	staircase.position = Vector3(1.8, 0.0, -3.2)
	add_child(staircase)


func _build_humanoid() -> void:
	humanoid = ProceduralHumanoid.new()
	humanoid.name = "Humanoid"
	humanoid.position = Vector3(0, 0, 0)
	add_child(humanoid)


func _build_camera() -> void:
	# No pivot rotation: the camera is placed on a sphere around the
	# humanoid every frame and look_at()s the humanoid, so the humanoid
	# is always in the centre of the screen, upright.
	# (The old pivot with rotation.x = -0.35 tilted the camera UP, which
	# pushed the humanoid to the bottom edge, half cut off — screenshot
	# 2026-11-09 20:55 WIB.)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 60.0
	add_child(camera)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var hint := Label.new()
	hint.text = "Light of Kirana — procedural walk (Singer)  |  WASD jalan, Shift lari, Space lompat"
	hint.position = Vector2(16, 12)
	hint.add_theme_color_override("font_color", Color(0.25, 0.25, 0.25))
	layer.add_child(hint)

	# Anchored to the screen corners (not fixed 1280x720 coordinates),
	# so on the tablet the joystick stays bottom-left and the buttons
	# stay bottom-right instead of floating mid-screen.
	joystick = KiranaVirtualJoystick.new()
	joystick.anchor_top = 1.0
	joystick.anchor_bottom = 1.0
	joystick.offset_left = 24
	joystick.offset_top = -244
	joystick.offset_right = 244
	joystick.offset_bottom = -24
	layer.add_child(joystick)

	run_button = KiranaTouchButton.new()
	run_button.label_text = "LARI"
	run_button.anchor_left = 1.0
	run_button.anchor_right = 1.0
	run_button.anchor_top = 1.0
	run_button.anchor_bottom = 1.0
	run_button.offset_left = -260
	run_button.offset_top = -260
	run_button.offset_right = -164
	run_button.offset_bottom = -164
	run_button.pressed_down.connect(func() -> void: run_held = true)
	run_button.released_up.connect(func() -> void: run_held = false)
	layer.add_child(run_button)

	jump_button = KiranaTouchButton.new()
	jump_button.label_text = "LOMPAT"
	jump_button.anchor_left = 1.0
	jump_button.anchor_right = 1.0
	jump_button.anchor_top = 1.0
	jump_button.anchor_bottom = 1.0
	jump_button.offset_left = -140
	jump_button.offset_top = -140
	jump_button.offset_right = -44
	jump_button.offset_bottom = -44
	jump_button.pressed_down.connect(func() -> void: humanoid.want_jump = true)
	layer.add_child(jump_button)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_orbit_mouse = event.pressed
	elif event is InputEventMouseMotion and _orbit_mouse:
		var motion := event as InputEventMouseMotion
		cam_yaw -= motion.relative.x * 0.005
		cam_pitch = clampf(cam_pitch - motion.relative.y * 0.005, CAMERA_MIN_PITCH, CAMERA_MAX_PITCH)
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
		cam_pitch = clampf(cam_pitch - d.y * 0.006, CAMERA_MIN_PITCH, CAMERA_MAX_PITCH)


func _process(delta: float) -> void:
	var kb := Vector2.ZERO
	kb.y -= 1.0 if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) else 0.0
	kb.y += 1.0 if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) else 0.0
	kb.x -= 1.0 if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT) else 0.0
	kb.x += 1.0 if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT) else 0.0
	# BUG FIX 2026-11-09: joystick output y down = +, and keyboard
	# forward is move2d.y = -1 (W). So stick.y = output.y directly:
	# pushing UP gives output.y = -1 = forward. The old code negated
	# it, so pushing up walked BACKWARDS.
	var stick := joystick.output if joystick != null else Vector2.ZERO
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

	# Third-person camera: orbit on a sphere around the humanoid and
	# look_at() its chest, so it stays centred and upright.
	# As the camera rises toward a top-down angle, lower its look target
	# toward the feet. This keeps the whole character framed like a standard
	# third-person game instead of aiming at the chest and cropping the legs.
	var overhead_blend := clampf(inverse_lerp(0.65, CAMERA_MAX_PITCH, cam_pitch), 0.0, 1.0)
	var target_height := lerpf(1.2, 0.22, overhead_blend)
	var target := humanoid.global_position + Vector3(0, target_height, 0)
	var offset := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch)) * CAM_DISTANCE
	camera.global_position = target + offset
	camera.look_at(target, Vector3.UP)
