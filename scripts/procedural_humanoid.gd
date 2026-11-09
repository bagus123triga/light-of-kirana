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

# Speeds are REAL human speeds (Bagus, 2026-11-09: walk and run felt
# too fast). Singer's panel says walk 1.75 / run 4.4, but Bagus's
# order overrides the panel: a real walk is ~1.4 m/s (5 km/h) and a
# real run ~3.2 m/s, not a sprint.
const WALK_SPEED := 1.4
const RUN_SPEED := 3.5
const SWING_TIME := 0.38
const HIP_STIFFNESS := 260.0
const HIP_DAMPING := 26.0
const LAND_BIAS := 0.47
const FOOT_CLEARANCE := 0.17
# Fisika lari manusia (Bagus, 2026-11-09 — langkah harus BESAR + dorongan
# kuat, bukan kaki cepat-cepat): pada 3,2 m/s manusia sungguhan punya
# stance ~0,25 dtk (kaki napak, badan lewat di atasnya, lalu toe-off),
# swing ~0,40 dtk (kaki di udara), flight ~0,1 dtk (kedua kaki lepas),
# cadence ~2,9 langkah/dtk, panjang langkah ~1,1 m. Kaki mendarat ~0,4 m
# DI DEPAN badan (bukan tepat di bawah), jadi stride target harus jauh
# (1,65 m dari posisi badan saat trigger) dan swing TIDAK diturunkan dari
# stride/speed — swing ditentukan siklus langkah, bukan kecepatan.
const RUN_SWING := 0.40
const RUN_STRIDE := 1.55
const RUN_GATE := 0.75  # kaki kedua baru boleh toe-off saat kaki pertama 75% ayunannya
const RUN_FOOT_CLEARANCE := 0.24  # lutut terangkat lebih tinggi saat lari
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
# Smoothed speed: a human does not jump from 1.4 to 3.2 m/s in one
# frame — the run-up takes ~0.3 s. Without it the stride jumped from
# 0.45 to 1.55 m the instant Shift was pressed and the planted foot
# was left ~0.8 m behind in a single step, collapsing the hip and
# clamping the ankle (the walk->run transition was most of the 21
# remaining run clamps).
var speed_smooth := 0.0
# Horizontal velocity is smoothed as a VECTOR, not only by speed.
# This prevents instant direction changes and hard stops while the
# feet are still completing their current swing.
var horizontal_motion := Vector3.ZERO

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
# Landing blend (Bagus, 2026-11-09): pendaratan lompat dulu men-TELEPORT
# kaki dari posisi tuck ke tanah dalam 1 frame — itu "nyedat"-nya.
# Sekarang kaki meluncur ke posisi napak selama 0,15 dtk (state 3).
var land_from: Array[Vector3] = []
var land_target: Array[Vector3] = []
var land_t := 0.0
# Procedural jump (Bagus, 2026-11-09): a jump is NOT an instant
# velocity — it presses into the ground first, then launches on
# physics, then absorbs the landing. States: 0 none, 1 crouch
# (pressing down), 2 airborne, 3 landing (absorbing).
var jump_state := 0
var jump_timer := 0.0
var jump_crouch := 0.0


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
	# BUG FIX 2026-11-09 (screenshot 21:19 WIB): capsule centre was
	# 0.85, so its bottom sat at 0.05 above the origin and the body
	# sank 0.05 into the floor to touch it. Hip then sat at 0.95
	# instead of 1.0, and the knees bent 0.16 m again IN THE REAL
	# SCENE even though the headless test (body at y=0) passed.
	# Centre 0.8 puts the bottom exactly at y=0, body stays at y=0.
	shape.position = Vector3(0, 0.8, 0)
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
	torso_mesh.radius = 0.13
	torso_mesh.height = 0.60
	torso.mesh = torso_mesh
	torso.material_override = mat
	torso.position = Vector3(0, 0.28, 0)
	body_root.add_child(torso)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.12
	head_mesh.height = 0.24
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
		shoulder.position = Vector3(side * 0.20, 0.5, 0)
		body_root.add_child(shoulder)
		var upper := _limb(0.043, ARM_UPPER, mat)
		upper.position = Vector3(0, -ARM_UPPER * 0.5, 0)
		shoulder.add_child(upper)
		var elbow := Node3D.new()
		elbow.position = Vector3(0, -ARM_UPPER, 0)
		shoulder.add_child(elbow)
		var forearm := _limb(0.04, ARM_LOWER, mat)
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
		foot_box.size = Vector3(0.09, 0.05, 0.18)
		foot.mesh = foot_box
		foot.material_override = mat
		add_child(foot)
		foot_mesh.append(foot)
		var start := global_position + Vector3(side * STEP_LATERAL, 0.05, 0)
		foot_planted_pos.append(start)
		foot_target_pos.append(start)
		foot_from_pos.append(start)
		land_from.append(start)
		land_target.append(start)


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

# Recovery step (Bagus, 2026-11-09 — feet must never cross): a planted
# foot that ended up on the other side of the body's midline (the body
# turned over it) takes a short step back to its own side.
func _is_crossed(i: int, right: Vector3) -> bool:
	var lateral := (foot_planted_pos[i] - global_position).dot(right)
	return (i == 0 and lateral > -0.03) or (i == 1 and lateral < 0.03)

func _start_recovery_step(i: int, right: Vector3, forward: Vector3) -> void:
	var side := -1.0 if i == 0 else 1.0
	foot_from_pos[i] = foot_planted_pos[i]
	foot_target_pos[i] = global_position + right * side * STEP_LATERAL + forward * 0.05
	foot_target_pos[i].y = 0.05
	foot_step_t[i] = 0.0
	foot_stepping[i] = true

func _resolve_foot_collision(right: Vector3, forward: Vector3) -> void:
	# Only intervene when the actual foot volumes overlap. Normal gait spacing
	# is left untouched; this is a collision response, not a permanent wide stance.
	var left_foot := foot_planted_pos[0]
	var right_foot := foot_planted_pos[1]
	var separation := Vector2(left_foot.x - right_foot.x, left_foot.z - right_foot.z).length()
	if separation >= 0.15 or absf(left_foot.y - right_foot.y) >= 0.12:
		return

	# Move the foot that is already swinging. If both are planted, or both
	# are airborne, move the one that has drifted furthest across the midline.
	var mover := 0
	if foot_stepping[1] and not foot_stepping[0]:
		mover = 1
	elif foot_stepping[0] and foot_stepping[1]:
		var left_lateral := (left_foot - global_position).dot(right)
		var right_lateral := (right_foot - global_position).dot(right)
		mover = 0 if absf(left_lateral + STEP_LATERAL) < absf(right_lateral - STEP_LATERAL) else 1
	elif not foot_stepping[0] and not foot_stepping[1]:
		var left_lateral := (left_foot - global_position).dot(right)
		var right_lateral := (right_foot - global_position).dot(right)
		mover = 0 if left_lateral > -STEP_LATERAL else 1

	var side := -1.0 if mover == 0 else 1.0
	if not foot_stepping[mover]:
		_start_recovery_step(mover, right, forward)
	else:
		# Nudge the swinging foot away smoothly and keep its swing trajectory
		# attached to the corrected position, preventing repeated interpenetration.
		var push := maxf(0.04, 0.15 - separation) * 0.65
		var correction := right * side * push
		foot_planted_pos[mover] += correction
		foot_from_pos[mover] += correction
		foot_target_pos[mover] += right * side * 0.08


func _physics_process(delta: float) -> void:
	time_alive += delta
	var speed_max := RUN_SPEED if is_running else WALK_SPEED
	var speed_factor := clampf(wish_dir.length(), 0.0, 1.0)
	var speed := speed_max * speed_factor
	# Smooth the speed toward its target (accelerate 6 m/s^2, brake
	# 8 m/s^2): movement, stride and swing all use the smoothed
	# value, so walk->run is a run-up, not a teleport.
	speed_smooth = move_toward(speed_smooth, speed, (6.0 if speed > speed_smooth else 8.0) * delta)
	speed = speed_smooth
	var moving := speed > 0.05
	# Preserve the last heading on release; atan2(0, 0) resets to world +Z.
	# Limit yaw speed so a sharp reversal is a grounded pivot, not a spin.
	if wish_dir.length() > 0.05:
		var target_yaw := atan2(wish_dir.x, wish_dir.z)
		facing_yaw = rotate_toward(facing_yaw, target_yaw, delta * 3.5)
	rotation.y = facing_yaw

	# --- Procedural jump: crouch -> launch -> land (Bagus, 2026-11-09) ---
	# The old jump set velocity.y = 6.0 instantly, feet snapped up —
	# it looked like a canned animation, not a jump. A real jump
	# PRESSES into the ground first (crouch: hip drops, knees bend
	# because the feet stay planted), then launches on physics
	# (gravity + velocity, no scripted height), then absorbs the
	# landing (hip dips again). All three are driven by the same
	# spring body + IK as walking, nothing is keyframed.
	# Edge-triggered: a press that arrives mid-jump is DROPPED, not
	# queued. The old code only cleared want_jump when a jump started,
	# so a press (or a held Space / a second tap) during the air stayed
	# true and re-fired the instant the feet touched down — the
	# humanoid kept jumping and could never stay on the ground
	# ("terbang gabisa balik", screenshot 2026-11-09 21:36).
	if want_jump:
		if jump_state == 0 and (test_mode or is_on_floor()):
			jump_state = 1
			jump_timer = 0.16
			# Cancel any step in progress: a foot mid-swing to a
			# far-ahead (1.1 m run) target would land way in front
			# while the body is airborne, and the body would come
			# down sitting with both legs stretched forward — the
			# exact pose in that screenshot. Feet stay planted
			# through the crouch, then tuck in the air.
			for i in 2:
				foot_stepping[i] = false
				foot_step_t[i] = 0.0
		want_jump = false
	if jump_state == 1:
		jump_timer -= delta
		if jump_timer <= 0.0:
			jump_state = 2
			if not test_mode:
				velocity.y = 6.5
	elif jump_state == 2:
		# ROOT CAUSE (screenshot 2026-11-09 21:43, reproduced headless):
		# the old check also required velocity.y < 0.0 — but
		# move_and_slide() ZEROES the downward velocity the moment
		# the body touches the floor, so by the next frame velocity.y
		# is 0 and the landing was NEVER detected. jump_state stayed
		# 2 forever: steps stayed gated, feet froze where the tuck
		# left them, the body ran away from its own feet (10 m in
		# the repro), the hip ceiling collapsed to 0.60 — the sitting
		# pose with legs stretched forward. is_on_floor() alone is
		# the landing signal; the launch frame is safe because the
		# if/elif chain skips this branch on the frame state becomes 2.
		if not test_mode and is_on_floor():
			jump_state = 3
			jump_timer = 0.18
			# Plant both feet on the ground under the body, LEADING
			# slightly in the direction of travel (wish_dir * 0.25):
			# the body keeps moving through the 0.18 s landing
			# absorption, so feet planted exactly under it are
			# already trailing by the time the next step starts.
			# LANDING BLEND (Bagus, 2026-11-09 — "nyedat dikit"): the
			# feet do NOT teleport from the tuck to the ground in
			# one frame; they glide down over 0.15 s during state 3.
			var fwd0 := Vector3(sin(facing_yaw), 0, cos(facing_yaw))
			var rgt0 := Vector3(cos(facing_yaw), 0, -sin(facing_yaw))
			for i in 2:
				var side0 := -1.0 if i == 0 else 1.0
				foot_stepping[i] = false
				foot_step_t[i] = 0.0
				land_from[i] = foot_planted_pos[i]
				land_target[i] = global_position + wish_dir * 0.25 + rgt0 * side0 * STEP_LATERAL + fwd0 * 0.05
				land_target[i].y = 0.05
			land_t = 0.0
	elif jump_state == 3:
		jump_timer -= delta
		if jump_timer <= 0.0:
			jump_state = 0
	var crouch_target := 0.22 if jump_state == 1 else (0.18 if jump_state == 3 else 0.0)
	jump_crouch = move_toward(jump_crouch, crouch_target, delta * (2.0 if jump_state == 1 else 0.9))

	# Brake while pressing down and while absorbing the landing: the
	# feet are planted (crouch) or just re-planted (landing), so the
	# body must not run away from them at full speed — that is what
	# left the feet metres behind and collapsed the hip after a
	# running jump. Half speed for those 0.34 s, full speed otherwise.
	var speed_mult := 0.5 if jump_state == 1 or jump_state == 3 else 1.0

	# Gravity (CharacterBody3D). Smooth horizontal velocity in both
	# directions. A scalar speed_smooth alone is insufficient: multiplying
	# it by wish_dir still makes turning and releasing input instantaneous.
	var target_horizontal := wish_dir * speed * speed_mult
	var horizontal_accel := 12.0 if target_horizontal.length() > horizontal_motion.length() else 16.0
	horizontal_motion = horizontal_motion.move_toward(target_horizontal, horizontal_accel * delta)
	if test_mode:
		position += horizontal_motion * delta
	else:
		if is_on_floor():
			# Launch frame: keep the impulse, don't overwrite it with
			# the -0.5 floor snap.
			if jump_state != 2:
				velocity.y = -0.5
		else:
			velocity.y -= GRAVITY * delta
		velocity.x = horizontal_motion.x
		velocity.z = horizontal_motion.z
		move_and_slide()

	# Drive gait timing from actual smoothed horizontal movement, not
	# raw joystick magnitude. This also makes stop/start transitions agree.
	speed = horizontal_motion.length()
	speed_factor = clampf(speed / maxf(speed_max, 0.01), 0.0, 1.0)
	moving = speed > 0.05
	var on_floor_now := test_mode or is_on_floor()
	var forward := Vector3(sin(facing_yaw), 0, cos(facing_yaw))
	var right := Vector3(cos(facing_yaw), 0, -sin(facing_yaw))
	var hip_global := body_root.global_position

	# --- Step planner (Singer) ---
	# WALK: stride = speed * 0.32 (1.4 m/s -> 0.45 m), swing derived
	# from stride/speed, cap 0.38 s. Walk is rated 9/10 — do not touch.
	# RUN: stride 1.65 m and swing 0.40 s FIXED (human running physics,
	# Bagus 2026-11-09). The old derivation (swing = stride/speed)
	# gave a 0.31 s swing and landings in quick pairs — that is why
	# the feet looked too fast even though the speed was right.
	# The foot lands ~0.4 m AHEAD of the body, so the stride target
	# must be far (body travel during the swing + 0.4 m ahead).
	var stride_max := 0.45 if not is_running else RUN_STRIDE
	var stride := clampf(speed * (0.32 if not is_running else 0.52), 0.18, stride_max)
	var swing := RUN_SWING if is_running else (clampf(stride / maxf(speed, 0.5), 0.16, SWING_TIME) if moving else SWING_TIME)

	# Push-off lift (run): flight_timer is now set when a foot TOES OFF
	# (starts its swing) while the other foot is also in the air — the
	# brief moment both feet are off the ground, when the hip rises
	# on the push. The old version tucked BOTH feet the instant one
	# landed, so the new stance foot never got a stance phase and
	# there was no push-off to feel. Now the landed foot stays
	# planted while the body passes over it (stance), and only toes
	# off when it starts its own swing.
	if flight_timer > 0.0:
		flight_timer -= delta
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		# Shared direction/prediction values for every branch in this loop.
		# Declaring these once avoids duplicate local declarations in GDScript.
		var step_forward := horizontal_motion.normalized() if speed > 0.05 else forward
		var step_right := Vector3(step_forward.z, 0.0, -step_forward.x)
		var landing_lead := clampf(stride - speed * swing, 0.08, 0.45)
		# Feet must NEVER cross the midline (Bagus, 2026-11-09): when
		# the body turns, a planted foot can end up on the other side
		# of the body. The foot then takes a short recovery step back
		# to its own side instead of staying crossed.
		# Keep the opposite foot planted while recovering a crossed foot.
		# Do not lift both feet during a pivot or reversal.
		if not foot_stepping[i] and not foot_stepping[1 - i] and on_floor_now and jump_state == 0 and _is_crossed(i, right):
			_start_recovery_step(i, right, forward)
		if foot_stepping[i]:
			foot_step_t[i] += delta / swing
			# Predict where the body will actually be when this swing ends.
			# Recompute the landing point EVERY physics frame: a one-time
			# target goes stale during turns and while accelerating/braking,
			# making the body run past the foot before it can land.
			var swing_remaining := swing * (1.0 - clampf(foot_step_t[i], 0.0, 1.0))
			var swing_side := -1.0 if i == 0 else 1.0
			foot_target_pos[i] = global_position + horizontal_motion * swing_remaining + step_forward * (landing_lead + 0.05) + step_right * swing_side * STEP_LATERAL
			foot_target_pos[i].y = 0.05
			var t := _smoothstep(foot_step_t[i])
			var pos := foot_from_pos[i].lerp(foot_target_pos[i], t)
			var clearance := FOOT_CLEARANCE if not is_running else RUN_FOOT_CLEARANCE
			# ROOT CAUSE of the landing "nyedat" (Bagus, 2026-11-09):
			# the old formula forced pos.y onto the ground arc
			# (0.05 + sin*clearance), which assumes the foot starts
			# on the ground. After a jump the foot starts TUCKED at
			# y≈0.82, so the first step frame teleported it straight
			# down 0.75 m (measured: frame 51, state 3, y 0.824→0.073).
			# Now the height lerps from the from-height to the
			# target-height and the arc is added ON TOP — a tucked
			# foot descends smoothly during its step instead.
			pos.y = lerpf(foot_from_pos[i].y, foot_target_pos[i].y, t) + sin(PI * clampf(foot_step_t[i], 0.0, 1.0)) * clearance
			foot_planted_pos[i] = pos
			if foot_step_t[i] >= 1.0:
				foot_stepping[i] = false
				foot_step_t[i] = 0.0
				foot_planted_pos[i] = foot_target_pos[i]
				foot_planted_pos[i].y = 0.05
				steps_taken += 1
		elif on_floor_now and flight_timer <= 0.0 and (jump_state == 0 or jump_state == 3):
			var ideal := global_position + step_forward * stride * LAND_BIAS + step_right * side * STEP_LATERAL + step_forward * 0.05
			ideal.y = 0.05
			var lag := (ideal - foot_planted_pos[i]).dot(forward) if moving else (ideal - foot_planted_pos[i]).length()
			var other_stepping := foot_stepping[1 - i]
			# Alternation, always. Walk: one foot at a time. Run: the
			# second foot may only toe off once the first is past 75%
			# of its swing. The old 60% gate let landings come in
			# quick pairs (0.22 s apart, then a gap) — even at the
			# right average cadence it LOOKED like shuffling fast feet.
			# 75% + the longer 0.40 s swing evens the rhythm to
			# ~2.9 steps/s with a real ~0.3 s stance per foot.
			# During a sharp turn keep a support foot down even at run speed.
			var turning_sharply := wish_dir.length() > 0.05 and forward.dot(wish_dir.normalized()) < 0.7
			var gate := (not other_stepping) or (is_running and not turning_sharply and foot_step_t[1 - i] > RUN_GATE)
			if (moving and lag > 0.15 and gate) or (not moving and lag > 0.25 and not other_stepping):
				# Predict the body position at touchdown and place the foot a
				# small distance ahead of it. RUN_STRIDE is total step reach,
				# not a fixed world-space point the body can run past.
				var target := global_position + horizontal_motion * swing + step_forward * (landing_lead + 0.05) + step_right * side * STEP_LATERAL
				target.y = 0.05
				foot_from_pos[i] = foot_planted_pos[i]
				foot_target_pos[i] = target
				foot_step_t[i] = 0.0
				foot_stepping[i] = true
				# Toe-off: if the other foot is already in the air,
				# this is the flight moment — the hip rises on the push.
				if is_running and foot_stepping[1 - i]:
					flight_timer = 0.10

	# Second recovery pass: a foot that JUST landed (in the loop above)
	# can land crossed if the body turned during its swing — its
	# recovery check already ran before it landed. Catch it here, in
	# the same frame, so a planted foot is never left crossed.
	# (No flight_timer block on recovery: a crossed foot must move
	# even right after a toe-off — the run test's leftover flight
	# timer was blocking the first turn frames.)
	for i in 2:
		if not foot_stepping[i] and not foot_stepping[1 - i] and on_floor_now and jump_state == 0 and _is_crossed(i, right):
			_start_recovery_step(i, right, forward)

	# Resolve real foot-to-foot contact only; ordinary close steps are untouched.
	if on_floor_now and jump_state == 0:
		_resolve_foot_collision(right, forward)

	# Return to the neutral idle stance after locomotion or a jump.
	# The airborne tuck / landing target can leave both feet offset from
	# the original standing pose; the hip ceiling then keeps the pelvis
	# low and the character appears permanently hunched after stopping.
	var fully_idle := not moving and wish_dir.length() <= 0.05 and jump_state == 0 and not foot_stepping[0] and not foot_stepping[1] and flight_timer <= 0.0
	if fully_idle and on_floor_now:
		for i in 2:
			var idle_side := -1.0 if i == 0 else 1.0
			var idle_foot := global_position + right * idle_side * STEP_LATERAL + forward * 0.05
			idle_foot.y = 0.05
			foot_planted_pos[i] = foot_planted_pos[i].move_toward(idle_foot, delta * 2.5)
			foot_target_pos[i] = idle_foot
			foot_from_pos[i] = idle_foot

	# Landing blend (state 3): feet glide from the tuck to their plant
	# positions over 0.15 s instead of snapping — the "nyedat" fix.
	# A foot that starts a step mid-blend is left alone (the step's
	# from-position picks up wherever the foot currently is).
	if jump_state == 3:
		land_t += delta / 0.15
		var lt := _smoothstep(land_t)
		for i in 2:
			if not foot_stepping[i]:
				foot_planted_pos[i] = land_from[i].lerp(land_target[i], lt)
				foot_target_pos[i] = land_target[i]
				foot_from_pos[i] = land_target[i]

	# Airborne: feet tuck under the body GRADUALLY (lerp), not snapped
	# — the old snap is what made the jump look like an animation.
	if not on_floor_now:
		for i in 2:
			var tuck := hip_global + Vector3(0, -0.65, 0) + right * (-1.0 if i == 0 else 1.0) * 0.08
			foot_planted_pos[i] = foot_planted_pos[i].lerp(tuck, clampf(delta * 8.0, 0.0, 1.0))
		_was_airborne = true
	elif _was_airborne:
		# No hip-velocity kick here anymore (Bagus, 2026-11-09): the
		# old -1.5 kick was a second landing dip on top of the
		# jump_crouch absorption — two dips in a row is the "nyedat".
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
	# Arm swing / bob phase is tied to the ACTUAL step cycle (PI per
	# step: swing time, + flight time when running), NOT to speed.
	# The old rate (speed/0.55 * PI) hit ~8 steps/s at run speed —
	# that is why the arms flailed like a cartoon (Bagus, 2026-11-09).
	if moving and (foot_stepping[0] or foot_stepping[1] or flight_timer > 0.0):
		var cycle := swing if not is_running else swing * 0.8
		gait_phase += delta * PI / maxf(cycle, 0.2)
	var horiz_max := 0.0
	for i in 2:
		# ANTICIPATORY ceiling (Bagus, 2026-11-09 — run dragged the
		# feet, 92 clamps): a stepping foot counts by where it WILL
		# land relative to the body at landing (target minus the body
		# travel left in the swing), not where it is now. The old
		# ceiling only saw planted feet, so it dropped suddenly the
		# frame a foot landed 0.27 m ahead and the spring lagged
		# behind it, clamping the ankle on nearly every run frame.
		# The hip now pre-dips during the swing and is already low
		# enough when the foot touches down.
		var p: Vector3
		if foot_stepping[i]:
			var remain := swing * (1.0 - foot_step_t[i])
			var body_at_land := global_position + horizontal_motion * remain
			p = foot_target_pos[i] - body_at_land
		else:
			p = foot_planted_pos[i] - global_position
		p.y = 0.0
		horiz_max = maxf(horiz_max, p.length())
	var leg_len := LEG_UPPER + LEG_LOWER
	# Ceiling is ankle height (0.05) + the vertical reach left over
	# after the horizontal offset. The old formula forgot the +0.05,
	# capping the hip 5 cm too low — that 5 cm was exactly the idle
	# knee bend (0.16 m) that would not go away.
	var hip_ceiling := 0.05 + sqrt(maxf(leg_len * leg_len - horiz_max * horiz_max, 0.55 * 0.55))
	var bob := sin(gait_phase * 2.0) * 0.02 * speed_factor if moving else sin(time_alive * 1.6) * 0.012
	var flight_lift := 0.05 if flight_timer > 0.0 else 0.0
	# Run slack: the hip sits below the ceiling while running, so the
	# leg is never at its absolute limit at landing/toe-off and the
	# spring lag cannot push the ankle past the clamp. The walk keeps
	# the exact ceiling (rated 9/10, do not touch).
	var ceiling_margin := 0.05 if is_running else 0.0
	var hip_target := minf(HIP_HEIGHT + bob - 0.04 * speed_factor + flight_lift - jump_crouch, hip_ceiling + flight_lift - ceiling_margin)
	hip_vel_y += (HIP_STIFFNESS * (hip_target - hip_y) - HIP_DAMPING * hip_vel_y) * delta
	hip_y = clampf(hip_y + hip_vel_y * delta, 0.55, 1.02)
	# Crouch overshoot guard: the spring must not dip the hip deeper
	# than the crouch itself (headless measured 0.60, a full squat,
	# for a 0.22 crouch — explicit-Euler overshoot at large dt).
	if jump_state == 1 or jump_state == 3:
		hip_y = maxf(hip_y, HIP_HEIGHT - jump_crouch - 0.05)
	body_root.position.y = hip_y
	# Tegap (Bagus, 2026-11-09): torso stays near-vertical. The old
	# 0.08 forward lean + sway made the figure slouch; lean is now
	# 0.03 walk / a touch more only when running.
	# A small forward pitch gives running a clear sense of momentum.
	# Positive X rotation leans the torso toward the character's +Z forward.
	var forward_lean := 0.025 if not is_running else 0.13
	body_root.rotation.x = speed_factor * forward_lean
	body_root.rotation.z = sin(gait_phase) * 0.02 * speed_factor
	hip_global = body_root.global_position

	# Heel lift / push-off (Bagus, 2026-11-09 — "tekanan lebih gede"):
	# as the body passes over a planted foot, the heel lifts and the
	# foot pushes off on its toe. The ankle rises (up to 0.12 m),
	# which is also what keeps the leg within reach at toe-off:
	# without it the ankle was clamped on 80 of 120 run frames,
	# because a flat foot 0.69 m behind the body is further from the
	# hip than the leg is long. A toe-off is on the toe, not flat.
	# RUNNING ONLY: the walk is rated 9/10 and its planted feet must
	# stay exactly on the ground (the walk test checks y=0.05).
	for i in 2:
		if is_running and not foot_stepping[i] and on_floor_now and jump_state == 0:
			var behind := (global_position - foot_planted_pos[i]).dot(forward)
			foot_planted_pos[i].y = 0.05 + minf(maxf(behind - 0.15, 0.0) * 0.35, 0.12)

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
		if to_ankle.length() > LEG_UPPER + LEG_LOWER - 0.01:
			ankle = hip_joint + to_ankle.normalized() * (LEG_UPPER + LEG_LOWER - 0.01)
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
		# Foot yaw is CLAMPED to +-45 degrees from the body facing
		# (Bagus, 2026-11-09). A human foot cannot spin all the way
		# round — the old code let it follow the step direction
		# without limit, so on sharp turns the sole rotated fully.
		var yaw_diff := clampf(wrapf(want_yaw - facing_yaw, -PI, PI), deg_to_rad(-45.0), deg_to_rad(45.0))
		foot_yaw[i] = lerp_angle(foot_yaw[i], facing_yaw + yaw_diff, clampf(delta * 10.0, 0.0, 1.0))
		var foot_pitch := 0.0
		if foot_stepping[i]:
			foot_pitch = sin(PI * clampf(foot_step_t[i], 0.0, 1.0)) * 0.35
		var foot_fwd := Vector3(sin(foot_yaw[i]), 0, cos(foot_yaw[i]))
		var foot_pos := ankle + foot_fwd * 0.07
		foot_pos.y = ankle.y
		foot_mesh[i].global_transform = Transform3D(Basis.from_euler(Vector3(foot_pitch, foot_yaw[i], 0.0)), foot_pos)

	# --- Arms, 3 joints: shoulder swings, elbow bends, wrist flicks ---
	# Arms swing opposite to the same-side leg (Singer's counter-swing).
	# Walking uses a restrained arm swing; running gets a stronger counter-swing.
	var arm_swing := 0.30 if not is_running else 0.48
	var swing_amount := sin(gait_phase) * arm_swing * speed_factor
	shoulder_l.rotation.x = swing_amount
	shoulder_r.rotation.x = -swing_amount
	# Keep both arms hanging vertically with a small natural gap from the torso.
	# No outward shoulder roll: it made the hands look detached and slanted.
	shoulder_l.rotation.z = 0.0
	shoulder_r.rotation.z = 0.0
	# Elbow: bent ~0.4 rad at rest, flexes a bit more on the forward
	# swing; wrist keeps the hand roughly level with a small flick.
	# During the jump crouch the arms pull back with the press.
	var elbow_bend := 0.4 + absf(swing_amount) * 0.3 + jump_crouch * 1.5
	elbow_l.rotation.x = -elbow_bend
	elbow_r.rotation.x = -elbow_bend
	wrist_l.rotation.x = elbow_bend * 0.5
	wrist_r.rotation.x = elbow_bend * 0.5
