extends CharacterBody3D
class_name ProceduralHumanoid

## Procedural walking, no animation clips, no mocap.
## Reference: Procedural Humanoid Locomotion — Benjamin J Singer
## https://procedural-humanoid.benjaminjsinger.com/
## Singer publishes NO source repo (searched 2026-11-09, not found), so
## this is NOT a 1:1 copy of his code — it follows his PUBLISHED
## architecture and tuning-panel values, and every deviation from them
## is called out in comments instead of being invented silently.
## Architecture (his, followed):
##   1. Step planner — stance target projected from velocity (land bias 0.47)
##   2. Spring-damped body — hip stiffness 260 / damping 26
##   3. Two-bone IK — analytic, knee bends forward, feet stay planted
## Numbers copied from the reference tuning panel:
##   walk 1.75 m/s, run 4.4 m/s, swing 0.38 s, foot clearance 0.17 m.
## Idle is NOT a limp ragdoll: the spring holds the body upright and only
## breathing sway is added (powered ragdoll, like Zelda / Genshin idle).

const WALK_SPEED := 1.75
const RUN_SPEED := 4.4
const SWING_TIME := 0.38
const HIP_STIFFNESS := 260.0
const HIP_DAMPING := 26.0
const LAND_BIAS := 0.47
const FOOT_CLEARANCE := 0.17
# Proportions (Bagus, 2026-11-09): upper thigh LONGER than lower
# thigh — 0.52 vs 0.44, total still 0.96 so the idle-knee math and
# hip ceiling from the previous fix stay valid. Equal 0.48/0.48 made
# the figure look wrong and not upright.
const LEG_UPPER := 0.52
const LEG_LOWER := 0.44
const HIP_HEIGHT := 1.0
# Arms: 3 joints — shoulder, elbow, wrist (Bagus, 2026-11-09).
# The old single-capsule arm had no elbow at all.
const ARM_UPPER := 0.28
const ARM_LOWER := 0.26
const STEP_LATERAL := 0.11
const GRAVITY := 20.0

# Set by main.gd every frame (keyboard, joystick, or test).
var move_input := Vector2.ZERO
var wish_dir := Vector3.ZERO
var is_running := false
var want_jump := false
var test_mode := false

var hip_y := HIP_HEIGHT
var hip_vel_y := 0.0
var gait_phase := 0.0
var steps_taken := 0
var facing_yaw := 0.0
var time_alive := 0.0
var _was_airborne := false

var body_root: Node3D
var shoulder_l: Node3D
var shoulder_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var wrist_l: Node3D
var wrist_r: Node3D
var thigh_mesh: Array[MeshInstance3D] = []
var shin_mesh: Array[MeshInstance3D] = []
var foot_mesh: Array[MeshInstance3D] = []

var foot_planted_pos: Array[Vector3] = []
var foot_target_pos: Array[Vector3] = []
var foot_from_pos: Array[Vector3] = []
var foot_step_t: Array[float] = [0.0, 0.0]
var foot_stepping: Array[bool] = [false, false]
var foot_yaw: Array[float] = [0.0, 0.0]
var knee_pos: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var flight_timer := 0.0
var foot_clamp_count := 0


func _orange_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	# Deeper orange: the old (1.0, 0.45, 0.05) blew out to yellow under
	# the midday sun + filmic tonemap (screenshot 2026-11-09).
	mat.albedo_color = Color(0.95, 0.38, 0.02)
	mat.roughness = 0.7
	return mat


func _limb(radius: float, length: float, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = length
	mesh.mesh = cap
	mesh.material_override = mat
	return mesh


func _ready() -> void:
	# BUG FIX 2026-11-09: the first build had NO CollisionShape3D, so
	# is_on_floor() was ALWAYS false. That one missing shape broke two
	# things at once: the step planner (gated on on-floor) never stepped
	# — legs frozen while arms swung — and jump (gated on on-floor)
	# never fired. A CharacterBody3D without a shape cannot stand.
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.6
	shape.shape = capsule
	shape.position = Vector3(0, 0.85, 0)
	add_child(shape)
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(45.0)

	var mat := _orange_material()
	body_root = Node3D.new()
	body_root.name = "BodyRoot"
	body_root.position = Vector3(0, HIP_HEIGHT, 0)
	add_child(body_root)

	var torso := MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.17
	torso_mesh.height = 0.62
	torso.mesh = torso_mesh
	torso.material_override = mat
	torso.position = Vector3(0, 0.28, 0)
	body_root.add_child(torso)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.13
	head_mesh.height = 0.26
	head.mesh = head_mesh
	head.material_override = mat
	head.position = Vector3(0, 0.72, 0)
	body_root.add_child(head)

	# Arms, 3 joints each: shoulder -> elbow -> wrist -> hand.
	# Hierarchy does the posing: shoulder swings, elbow bends,
	# wrist adds a small flick. Upper arm 0.28, forearm 0.26.
	var shoulders: Array[Node3D] = []
	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.21, 0.5, 0)
		body_root.add_child(shoulder)
		var upper := _limb(0.05, ARM_UPPER, mat)
		upper.position = Vector3(0, -ARM_UPPER * 0.5, 0)
		shoulder.add_child(upper)
		var elbow := Node3D.new()
		elbow.position = Vector3(0, -ARM_UPPER, 0)
		shoulder.add_child(elbow)
		var forearm := _limb(0.045, ARM_LOWER, mat)
		forearm.position = Vector3(0, -ARM_LOWER * 0.5, 0)
		elbow.add_child(forearm)
		var wrist := Node3D.new()
		wrist.position = Vector3(0, -ARM_LOWER, 0)
		elbow.add_child(wrist)
		var hand := MeshInstance3D.new()
		var hand_mesh := SphereMesh.new()
		hand_mesh.radius = 0.06
		hand_mesh.height = 0.12
		hand.mesh = hand_mesh
		hand.material_override = mat
		hand.position = Vector3(0, -0.05, 0)
		wrist.add_child(hand)
		shoulders.append(shoulder)
		if side < 0.0:
			elbow_l = elbow
			wrist_l = wrist
		else:
			elbow_r = elbow
			wrist_r = wrist
	shoulder_l = shoulders[0]
	shoulder_r = shoulders[1]

	for side in [-1.0, 1.0]:
		var thigh := _limb(0.06, LEG_UPPER, mat)
		var shin := _limb(0.05, LEG_LOWER, mat)
		add_child(thigh)
		add_child(shin)
		thigh_mesh.append(thigh)
		shin_mesh.append(shin)
		var foot := MeshInstance3D.new()
		var foot_box := BoxMesh.new()
		foot_box.size = Vector3(0.09, 0.05, 0.24)
		foot.mesh = foot_box
		foot.material_override = mat
		add_child(foot)
		foot_mesh.append(foot)
		var start := global_position + Vector3(side * STEP_LATERAL, 0.05, 0)
		foot_planted_pos.append(start)
		foot_target_pos.append(start)
		foot_from_pos.append(start)


func _solve_two_bone(hip: Vector3, target: Vector3, bend_dir: Vector3) -> Vector3:
	var to_target := target - hip
	var d := clampf(to_target.length(), 0.05, LEG_UPPER + LEG_LOWER - 0.01)
	var dir := to_target / to_target.length()
	var cos_a := clampf((LEG_UPPER * LEG_UPPER + d * d - LEG_LOWER * LEG_LOWER) / (2.0 * LEG_UPPER * d), -1.0, 1.0)
	var a := LEG_UPPER * cos_a
	var h := sqrt(maxf(LEG_UPPER * LEG_UPPER - a * a, 0.0))
	var perp := bend_dir - dir * bend_dir.dot(dir)
	if perp.length() < 0.001:
		perp = Vector3.UP
	perp = perp.normalized()
	return hip + dir * a + perp * h


func _place_limb(mesh: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var dir := b - a
	if dir.length() < 0.001:
		return
	var mid := (a + b) * 0.5
	var q := Quaternion(Vector3.UP, dir.normalized())
	mesh.global_transform = Transform3D(Basis(q), mid)


func _smoothstep(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _physics_process(delta: float) -> void:
	time_alive += delta
	var speed_max := RUN_SPEED if is_running else WALK_SPEED
	var speed_factor := clampf(wish_dir.length(), 0.0, 1.0)
	var speed := speed_max * speed_factor
	var moving := speed > 0.05

	if moving:
		var target_yaw := atan2(wish_dir.x, wish_dir.z)
		facing_yaw = lerp_angle(facing_yaw, target_yaw, clampf(delta * 10.0, 0.0, 1.0))
	rotation.y = facing_yaw

	# Gravity + jump (CharacterBody3D). In test_mode, integrate by hand.
	if test_mode:
		if want_jump:
			want_jump = false
		position += wish_dir * speed * delta
	else:
		if is_on_floor():
			if want_jump:
				velocity.y = 6.0
				want_jump = false
			else:
				velocity.y = -0.5
		else:
			velocity.y -= GRAVITY * delta
		velocity.x = wish_dir.x * speed
		velocity.z = wish_dir.z * speed
		move_and_slide()

	var on_floor_now := test_mode or is_on_floor()
	var forward := Vector3(sin(facing_yaw), 0, cos(facing_yaw))
	var right := Vector3(cos(facing_yaw), 0, -sin(facing_yaw))
	var hip_global := body_root.global_position

	# --- Step planner (Singer) ---
	# Swing time is DERIVED from stride / speed (reference swing 0.38 s
	# is the cap, not a fixed timer): the foot must land as the body
	# arrives, otherwise the body outruns its feet and they drag.
	# Stride is capped at 0.45 m (walk) so a planted foot never ends up
	# further from the hip than the legs can reach.
	var stride_max := 0.45 if not is_running else 0.85
	var stride := clampf(speed * 0.26, 0.18, stride_max)
	var swing := clampf(stride / maxf(speed, 0.5), 0.16, SWING_TIME) if moving else SWING_TIME
	# Run flight phase (Singer): after a step lands while running, the
	# body is briefly airborne with BOTH feet tucked — that is what
	# makes running look like running instead of sliding (ngesot).
	# Without it the support foot stays planted while the body moves
	# ~1 m, and the IK clamp drags it along the ground.
	if flight_timer > 0.0:
		flight_timer -= delta
		for i in 2:
			foot_planted_pos[i] = hip_global + Vector3(0, -0.5, 0) + right * (-1.0 if i == 0 else 1.0) * 0.08
			foot_planted_pos[i].y = hip_global.y - 0.5
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		if foot_stepping[i]:
			foot_step_t[i] += delta / swing
			var t := _smoothstep(foot_step_t[i])
			var pos := foot_from_pos[i].lerp(foot_target_pos[i], t)
			pos.y = 0.05 + sin(PI * clampf(foot_step_t[i], 0.0, 1.0)) * FOOT_CLEARANCE
			foot_planted_pos[i] = pos
			if foot_step_t[i] >= 1.0:
				foot_stepping[i] = false
				foot_step_t[i] = 0.0
				foot_planted_pos[i] = foot_target_pos[i]
				foot_planted_pos[i].y = 0.05
				steps_taken += 1
				if is_running and speed_factor > 0.6:
					flight_timer = 0.12
		elif on_floor_now and flight_timer <= 0.0:
			var ideal := global_position + wish_dir * stride * LAND_BIAS + right * side * STEP_LATERAL + forward * 0.05
			ideal.y = 0.05
			var lag := (ideal - foot_planted_pos[i]).dot(forward) if moving else (ideal - foot_planted_pos[i]).length()
			var other_stepping := foot_stepping[1 - i]
			# Walk: one foot at a time (stable). Run: overlap allowed —
			# the support foot must lift as soon as the body passes it,
			# otherwise it gets dragged (ngesot).
			var gate := (not other_stepping) or is_running
			if (moving and lag > 0.15 and gate) or (not moving and lag > 0.25 and not other_stepping):
				var target := global_position + wish_dir * stride + right * side * STEP_LATERAL + forward * 0.05
				target.y = 0.05
				foot_from_pos[i] = foot_planted_pos[i]
				foot_target_pos[i] = target
				foot_step_t[i] = 0.0
				foot_stepping[i] = true

	# Airborne: tuck both feet under the body.
	if not on_floor_now:
		for i in 2:
			foot_planted_pos[i] = hip_global + Vector3(0, -0.55, 0) + right * (-1.0 if i == 0 else 1.0) * 0.08
			foot_planted_pos[i].y = hip_global.y - 0.55
		_was_airborne = true
	elif _was_airborne:
		hip_vel_y -= 1.5
		_was_airborne = false

	# --- Spring-damped pendulum body (Singer: stiffness 260, damping 26) ---
	# The hip is a pendulum over the support foot: its height ceiling is
	# set by how far the furthest planted foot is from the body, so the
	# legs are never asked to reach further than they are long. The hip
	# dips as the body moves away from the support foot and rises again
	# as the next foot plants — that dip/rise IS the walk bob, not a
	# fixed timer. (The old fixed hip target + 1.04 m legs is what made
	# the idle crouch: the spring held the hip low while the legs were
	# long, so both knees had to bend 0.31 m just to stand still.)
	if moving:
		gait_phase += delta * (speed / 0.55) * PI
	var horiz_max := 0.0
	for i in 2:
		if not foot_stepping[i]:
			var dx := foot_planted_pos[i].x - global_position.x
			var dz := foot_planted_pos[i].z - global_position.z
			horiz_max = maxf(horiz_max, sqrt(dx * dx + dz * dz))
	var leg_len := LEG_UPPER + LEG_LOWER
	# Ceiling is ankle height (0.05) + the vertical reach left over
	# after the horizontal offset. The old formula forgot the +0.05,
	# capping the hip 5 cm too low — that 5 cm was exactly the idle
	# knee bend (0.16 m) that would not go away.
	var hip_ceiling := 0.05 + sqrt(maxf(leg_len * leg_len - horiz_max * horiz_max, 0.55 * 0.55))
	var bob := sin(gait_phase * 2.0) * 0.02 * speed_factor if moving else sin(time_alive * 1.6) * 0.012
	var flight_lift := 0.06 if flight_timer > 0.0 else 0.0
	var hip_target := minf(HIP_HEIGHT + bob - 0.04 * speed_factor + flight_lift, hip_ceiling + flight_lift)
	hip_vel_y += (HIP_STIFFNESS * (hip_target - hip_y) - HIP_DAMPING * hip_vel_y) * delta
	hip_y = clampf(hip_y + hip_vel_y * delta, 0.55, 1.02)
	body_root.position.y = hip_y
	# Tegap (Bagus, 2026-11-09): torso stays near-vertical. The old
	# 0.08 forward lean + sway made the figure slouch; lean is now
	# 0.03 walk / a touch more only when running.
	body_root.rotation.x = speed_factor * (0.03 if not is_running else 0.06)
	body_root.rotation.z = sin(gait_phase) * 0.02 * speed_factor
	hip_global = body_root.global_position

	# --- Two-bone IK + foot placement ---
	# Visual ankle is clamped to leg reach so the shin can never detach
	# from the foot, even at the far end of a stride (Singer's pendulum
	# body does this by dipping the hip; the clamp is the safety net).
	# The clamp counter is a test signal: if it fires often while
	# running, the feet are being dragged (ngesot).
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hip_joint := hip_global + right * side * 0.09
		var ankle := foot_planted_pos[i]
		var to_ankle := ankle - hip_joint
		if to_ankle.length() > LEG_UPPER + LEG_LOWER - 0.02:
			ankle = hip_joint + to_ankle.normalized() * (LEG_UPPER + LEG_LOWER - 0.02)
			foot_clamp_count += 1
		var knee := _solve_two_bone(hip_joint, ankle, forward)
		knee_pos[i] = knee
		_place_limb(thigh_mesh[i], hip_joint, knee)
		_place_limb(shin_mesh[i], knee, ankle)
		# Foot orientation (Bagus, 2026-11-09): the sole must FOLLOW
		# the movement direction. The old code set the foot's LOCAL
		# rotation.y = facing_yaw on top of the body's own facing_yaw
		# — the yaw was doubled, so when turning left/right the feet
		# pointed backwards / tilted. Now the foot is placed by its
		# GLOBAL transform: yaw tracks the step direction while
		# stepping, the facing while planted; pitch lets the toe drop
		# mid-swing (foot dangles) and is flat (0) when planted.
		var step_dir := foot_target_pos[i] - foot_from_pos[i]
		var want_yaw := facing_yaw
		if foot_stepping[i] and step_dir.length() > 0.01:
			want_yaw = atan2(step_dir.x, step_dir.z)
		foot_yaw[i] = lerp_angle(foot_yaw[i], want_yaw, clampf(delta * 10.0, 0.0, 1.0))
		var foot_pitch := 0.0
		if foot_stepping[i]:
			foot_pitch = sin(PI * clampf(foot_step_t[i], 0.0, 1.0)) * 0.35
		var foot_fwd := Vector3(sin(foot_yaw[i]), 0, cos(foot_yaw[i]))
		var foot_pos := ankle + foot_fwd * 0.05
		foot_pos.y = ankle.y
		foot_mesh[i].global_transform = Transform3D(Basis.from_euler(Vector3(foot_pitch, foot_yaw[i], 0.0)), foot_pos)

	# --- Arms, 3 joints: shoulder swings, elbow bends, wrist flicks ---
	# Arms swing opposite to the same-side leg (Singer's counter-swing).
	var swing_amount := sin(gait_phase) * 0.55 * speed_factor
	shoulder_l.rotation.x = swing_amount
	shoulder_r.rotation.x = -swing_amount
	shoulder_l.rotation.z = 0.06
	shoulder_r.rotation.z = -0.06
	# Elbow: bent ~0.4 rad at rest, flexes a bit more on the forward
	# swing; wrist keeps the hand roughly level with a small flick.
	var elbow_bend := 0.4 + absf(swing_amount) * 0.3
	elbow_l.rotation.x = -elbow_bend
	elbow_r.rotation.x = -elbow_bend
	wrist_l.rotation.x = elbow_bend * 0.5
	wrist_r.rotation.x = elbow_bend * 0.5
