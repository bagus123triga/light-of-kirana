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

	# 3. Two-bone IK: hip-ankle distance must stay within leg reach (0.52+0.52).
	for i in 2:
		var hip_joint: Vector3 = humanoid.body_root.global_position + Vector3(0, 0, 0)
		var ankle: Vector3 = humanoid.foot_planted_pos[i]
		var dist := (ankle - hip_joint).length()
		if dist > 1.05 or dist < 0.3:
			failures.append("leg %d hip-ankle distance impossible: %.2f" % [i, dist])

	# 4. Run 2 s: must be faster than walk.
	var run_start := humanoid.position
	humanoid.is_running = true
	for i in 120:
		humanoid._physics_process(1.0 / 60.0)
	var run_moved := (humanoid.position - run_start).length()
	if run_moved < 5.0:
		failures.append("run moved too little: %.2f m in 2 s" % run_moved)

	print("WALK_TEST hip_y=%.2f steps=%d walked=%.2f m ran=%.2f m planted_err=%.3f" % [humanoid.hip_y, humanoid.steps_taken, moved, run_moved, max_planted_err])
	if failures.is_empty():
		print("WALK_TEST PASS")
		quit(0)
	else:
		for f in failures:
			print("WALK_TEST FAIL: " + f)
		print("WALK_TEST FAIL")
		quit(1)
