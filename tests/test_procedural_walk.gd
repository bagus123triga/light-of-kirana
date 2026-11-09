extends SceneTree

## Headless check only (NOT proof it looks right on the tablet):
## run: godot --headless --path . --script res://tests/test_procedural_walk.gd
## Simulates the Singer pipeline in test_mode: step planner, spring body,
## two-bone IK. Prints WALK_TEST PASS / FAIL and exits 0 / 1.

func _init() -> void:
	var failures: Array[String] = []
	var humanoid := ProceduralHumanoid.new()
	humanoid.test_mode = true
	root.add_child(humanoid)
	# _ready runs on add_child; give the tree one idle frame worth of setup.
	await process_frame

	# 1. Idle 2 s: body must stay upright (powered ragdoll, not collapsed).
	humanoid.wish_dir = Vector3.ZERO
	humanoid.is_running = false
	for i in 120:
		humanoid._physics_process(1.0 / 60.0)
	if humanoid.hip_y < 0.7 or humanoid.hip_y > 1.05:
		failures.append("idle hip_y out of range: %s" % humanoid.hip_y)
	if humanoid.steps_taken != 0:
		failures.append("idle should not step, steps=%d" % humanoid.steps_taken)
	# Idle knees must be nearly straight (regression for the crouched /
	# sitting idle in the 2026-11-09 21:01 screenshot): knee forward
	# offset from the hip-ankle line must stay under 0.20 m.
	for i in 2:
		var hip_j: Vector3 = humanoid.body_root.global_position + Vector3(0, 0, 0)
		var mid := (hip_j + humanoid.foot_planted_pos[i]) * 0.5
		var knee_fwd := (humanoid.knee_pos[i] - mid).dot(Vector3(0, 0, 1))
		if knee_fwd > 0.12:
			failures.append("idle knee %d bent too far forward: %.2f m" % [i, knee_fwd])

	# 2. Walk forward 4 s: steps must happen, planted feet must stay on y=0.05,
	#    body must keep moving forward and stay upright.
	humanoid.wish_dir = Vector3(0, 0, -1)
	var start_pos := humanoid.position
	var min_foot_y := 10.0
	var max_planted_err := 0.0
	for i in 240:
		humanoid._physics_process(1.0 / 60.0)
		for f in 2:
			if not humanoid.foot_stepping[f]:
				max_planted_err = maxf(max_planted_err, absf(humanoid.foot_planted_pos[f].y - 0.05))
			min_foot_y = minf(min_foot_y, humanoid.foot_planted_pos[f].y)
	var moved := (humanoid.position - start_pos).length()
	if humanoid.steps_taken < 2:
		failures.append("walk produced too few steps: %d" % humanoid.steps_taken)
	if moved < 3.0:
		failures.append("walk moved too little: %.2f m in 4 s" % moved)
	if max_planted_err > 0.02:
		failures.append("planted foot lifted off ground, err=%.3f" % max_planted_err)
	if humanoid.hip_y < 0.7 or humanoid.hip_y > 1.05:
		failures.append("walk hip_y out of range: %s" % humanoid.hip_y)

	# 3. Two-bone IK: hip-ankle distance must stay within leg reach (0.48+0.48).
	for i in 2:
		var hip_joint: Vector3 = humanoid.body_root.global_position + Vector3(0, 0, 0)
		var ankle: Vector3 = humanoid.foot_planted_pos[i]
		var dist := (ankle - hip_joint).length()
		if dist > 0.97 or dist < 0.3:
			failures.append("leg %d hip-ankle distance impossible: %.2f" % [i, dist])

	# 3b. Arms have 3 joints (Bagus, 2026-11-09): shoulder, elbow,
	# wrist — the old single-capsule arm had no elbow at all.
	if humanoid.elbow_l == null or humanoid.elbow_r == null or humanoid.wrist_l == null or humanoid.wrist_r == null:
		failures.append("arm joints missing: elbow/wrist nodes not built")
	elif absf(humanoid.elbow_l.rotation.x + 0.4) > 0.15:
		failures.append("elbow not bent at idle: %.2f" % humanoid.elbow_l.rotation.x)

	# 4. Run 2 s: must be faster than walk, and feet must not drag
	# (ngesot): the IK clamp counter must stay low — a clamped ankle
	# means the planted foot was dragged along the ground.
	# Also (Bagus, 2026-11-09): the two feet must ALTERNATE, never
	# both start stepping together; and no foot may point more than
	# 45 degrees away from the body facing.
	var run_start := humanoid.position
	humanoid.is_running = true
	humanoid.foot_clamp_count = 0
	var bad_overlap := 0
	var max_yaw_err := 0.0
	var prev_stepping := [false, false]
	for i in 120:
		humanoid._physics_process(1.0 / 60.0)
		# A foot may only START stepping while the other is already
		# past 60% of its swing — starting together is the bug.
		for f in 2:
			if humanoid.foot_stepping[f] and not prev_stepping[f]:
				var o := 1 - f
				if humanoid.foot_stepping[o] and humanoid.foot_step_t[o] < 0.6:
					bad_overlap += 1
			prev_stepping[f] = humanoid.foot_stepping[f]
		for f in 2:
			max_yaw_err = maxf(max_yaw_err, absf(wrapf(humanoid.foot_yaw[f] - humanoid.facing_yaw, -PI, PI)))
	var run_moved := (humanoid.position - run_start).length()
	if run_moved < 5.0:
		failures.append("run moved too little: %.2f m in 2 s" % run_moved)
	if humanoid.foot_clamp_count > 20:
		failures.append("run dragged feet: ankle clamped %d times in 2 s" % humanoid.foot_clamp_count)
	if bad_overlap > 0:
		failures.append("run: both feet stepped together on %d frames" % bad_overlap)
	if max_yaw_err > deg_to_rad(46.0):
		failures.append("run: foot yaw %.1f deg off facing, max is 45" % rad_to_deg(max_yaw_err))
	print("RUN_CLAMP_TEST clamps=%d bad_overlap=%d max_yaw_err=%.1f deg" % [humanoid.foot_clamp_count, bad_overlap, rad_to_deg(max_yaw_err)])

	# Remove the test humanoid BEFORE the main scene: two
	# CharacterBody3Ds at the same origin overlap, and the physics
	# solver ejects the main one (measured: teleported to
	# (22, 0.89, -7) with velocity 1325 — a harness artifact, not a
	# game bug; the real game has one humanoid). The main scene must
	# spawn alone so its body starts clean at y=0.
	# Capture the summary numbers first — the node is freed below.
	var final_hip_y := humanoid.hip_y
	var final_steps := humanoid.steps_taken
	root.remove_child(humanoid)
	humanoid.queue_free()
	await physics_frame
	await physics_frame

	# 5. Camera framing (regression for screenshot 2026-11-09 20:55 WIB:
	#    humanoid was at the bottom edge, half cut off, because the old
	#    pivot rotation.x = -0.35 tilted the camera UP). The humanoid's
	#    chest must project near the centre of the 1280x720 viewport.
	var main_inst: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_inst)
	await process_frame
	await process_frame
	await process_frame
	var cam: Camera3D = main_inst.camera
	var hum2: Node3D = main_inst.humanoid
	var chest: Vector3 = hum2.global_position + Vector3(0, 1.0, 0)
	if cam.is_position_behind(chest):
		failures.append("camera framing: humanoid is behind the camera")
	else:
		# Headless viewport is tiny, so check relative to its centre,
		# not to 1280x720.
		var screen_pos := cam.unproject_position(chest)
		var vp_size := cam.get_viewport().get_visible_rect().size
		var centre := vp_size * 0.5
		if absf(screen_pos.x - centre.x) > vp_size.x * 0.2 or absf(screen_pos.y - centre.y) > vp_size.y * 0.2:
			failures.append("camera framing: chest at %s, not near centre %s (viewport %s)" % [screen_pos, centre, vp_size])
		print("CAM_TEST chest_screen=%s centre=%s viewport=%s" % [screen_pos, centre, vp_size])

	# 6. Real physics in the main scene (regression for 2026-11-09 21:01:
	#    the first build had no CollisionShape3D, so is_on_floor() was
	#    always false, the step planner never stepped and jump never
	#    fired). The humanoid must stand on the floor (body y=0, not
	#    sunk -0.05), then jump PROCEDURALLY: press down first
	#    (crouch: hip dips), then lift off on physics, then land.
	var hum3: ProceduralHumanoid = main_inst.humanoid
	for i in 30:
		await physics_frame
	if not hum3.is_on_floor():
		failures.append("main scene: humanoid is not on the floor after 30 physics frames")
	else:
		var y0 := hum3.position.y
		if absf(y0) > 0.02:
			failures.append("main scene: body sunk/floating at y=%.2f, should be 0.0" % y0)
		hum3.want_jump = true
		var peak_y := y0
		var min_hip := 10.0
		for i in 50:
			await physics_frame
			peak_y = maxf(peak_y, hum3.position.y)
			if i < 12:
				min_hip = minf(min_hip, hum3.hip_y)
		if min_hip > 0.92:
			failures.append("jump did not press down first (min hip_y in crouch=%.2f, want <0.92)" % min_hip)
		if peak_y <= y0 + 0.3:
			failures.append("main scene: jump did not lift the humanoid (peak y=%.2f, start y=%.2f)" % [peak_y, y0])
		print("JUMP_TEST start_y=%.2f peak_y=%.2f min_hip_crouch=%.2f" % [y0, peak_y, min_hip])

	# 6b. A LOMPAT press mid-air must be DROPPED, not queued
	# (regression for 2026-11-09 21:36: the jump kept re-firing on
	# landing and the humanoid flew and could not come back down).
	for i in 90:
		await physics_frame
		if hum3.jump_state == 0 and hum3.is_on_floor():
			break
	hum3.want_jump = true
	var mid_air_pressed := false
	var second_jump_started := false
	for i in 90:
		await physics_frame
		if hum3.jump_state == 2 and not mid_air_pressed:
			hum3.want_jump = true
			mid_air_pressed = true
		if hum3.jump_state == 1 and mid_air_pressed:
			second_jump_started = true
	for i in 30:
		await physics_frame
	if second_jump_started:
		failures.append("mid-air jump press queued a second jump")
	if hum3.position.y > 0.05:
		failures.append("humanoid still airborne after landing + 30 frames (y=%.2f)" % hum3.position.y)
	print("JUMP_QUEUE_TEST mid_air_pressed=%s second_jump=%s final_y=%.2f" % [mid_air_pressed, second_jump_started, hum3.position.y])

	print("WALK_TEST hip_y=%.2f steps=%d walked=%.2f m ran=%.2f m planted_err=%.3f" % [final_hip_y, final_steps, moved, run_moved, max_planted_err])
	if failures.is_empty():
		print("WALK_TEST PASS")
		quit(0)
	else:
		for f in failures:
			print("WALK_TEST FAIL: " + f)
		print("WALK_TEST FAIL")
		quit(1)
