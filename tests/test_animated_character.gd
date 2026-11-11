extends SceneTree

## Run after Godot has imported the project:
## godot --headless --path . --script res://tests/test_animated_character.gd

func _initialize() -> void:
	var packed: PackedScene = load("res://assets/characters/light_of_kirana_animated.glb")
	if packed == null:
		push_error("Animated character GLB did not import.")
		quit(1)
		return

	var instance := packed.instantiate()
	root.add_child(instance)
	await process_frame

	var skeletons := instance.find_children("*", "Skeleton3D", true, false)
	var players := instance.find_children("*", "AnimationPlayer", true, false)
	var meshes := instance.find_children("*", "MeshInstance3D", true, false)
	if skeletons.is_empty() or players.is_empty() or meshes.is_empty():
		push_error("Character scene is missing Skeleton3D, AnimationPlayer, or mesh.")
		quit(1)
		return

	var player := players[0] as AnimationPlayer
	var required := [
		"Idle_relaxed", "Walk_forwards", "Run_jog_forwards", "Run_sprint",
		"Jump_take_off", "Jump_in_the_air", "Jump_landing"
	]
	var missing: Array[String] = []
	for animation_name in required:
		if not player.has_animation(animation_name):
			missing.append(animation_name)

	if not missing.is_empty():
		push_error("Missing imported animations: %s" % ", ".join(missing))
		quit(1)
		return

	print("ANIMATED_CHARACTER_TEST PASS — rig, mesh, AnimationPlayer, 7 clips")
	quit(0)
