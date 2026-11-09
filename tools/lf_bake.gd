extends SceneTree

## Bake LowLand Forge map headless buat Light of Kirana.
## Preset Classic Island (pulau + pantai/laut, gunung, hutan, danau, sungai —
## paling Zelda), 1 tile 512 m, seed 1234 (reproducible).
## Output: res://maps/lf_map (map.tscn + tile_0_0.tscn + tiles.json + map_image.png).
## Jalankan: godot --headless --path . --script res://tools/lf_bake.gd

func _init() -> void:
	var baker := LFMapBaker.new()
	baker.auto_preview = false
	baker.map_seed = 1234
	baker.params = LFMapPresets.make("Classic Island")
	baker.params.lake_count = 2
	baker.params.river_count = 2
	baker.tile_size = 512
	baker.tiles_x = 1
	baker.tiles_z = 1
	baker.props = LFTileBaker.Props.ALL
	baker.output_dir = "res://maps/lf_map"
	var err := baker.settings_error()
	if err != "":
		print("LF_BAKE SETTINGS ERROR: " + err)
		quit(1)
		return
	print("LF_BAKE: mulai...")
	var info: Dictionary = baker.bake()
	print("LF_BAKE: info=" + str(info))
	if int(info.get("error", 1)) != OK:
		print("LF_BAKE FAILED")
		baker.free()
		quit(1)
		return
	baker.free()
	# Map image (minimap, buat verifikasi tampilan dari atas).
	var baker2 := LFMapBaker.new()
	baker2.auto_preview = false
	baker2.map_seed = 1234
	baker2.params = LFMapPresets.make("Classic Island")
	baker2.params.lake_count = 2
	baker2.params.river_count = 2
	baker2.tile_size = 512
	baker2.tiles_x = 1
	baker2.tiles_z = 1
	baker2.output_dir = "res://maps/lf_map"
	baker2.map_image_px = 512
	var img_err: int = baker2.export_map_image()
	print("LF_BAKE: map_image err=" + str(img_err))
	baker2.free()
	print("LF_BAKE DONE")
	quit(0)
