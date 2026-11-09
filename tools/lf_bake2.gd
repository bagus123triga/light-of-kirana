extends SceneTree

## Bake ulang map LowLand Forge ala gambar referensi Bagus.
## Highland Island: 2 gunung bersalju + ridge curam (gunung salju di gambar).
## cliffs=0.9: tebing bertingkat dramatis (kayak tebing gua di gambar).
## Seed baru 2026: bentuk pulau beda dari Classic Island 1234.

func _init() -> void:
	var baker := LFMapBaker.new()
	baker.auto_preview = false
	baker.map_seed = 2026
	baker.params = LFMapPresets.make("Highland Island")
	baker.params.cliffs = 0.9
	baker.params.lake_count = 2
	baker.params.river_count = 2
	baker.tile_size = 512
	baker.tiles_x = 1
	baker.tiles_z = 1
	baker.props = LFTileBaker.Props.ALL
	baker.output_dir = "res://maps/lf_map"
	var err := baker.settings_error()
	if err != "":
		print("LF_BAKE2 SETTINGS ERROR: " + err)
		quit(1)
		return
	print("LF_BAKE2: mulai...")
	var info: Dictionary = baker.bake()
	print("LF_BAKE2: info=" + str(info))
	if int(info.get("error", 1)) != OK:
		print("LF_BAKE2 FAILED")
		baker.free()
		quit(1)
		return
	baker.free()
	# Map image (minimap, buat verifikasi tampilan dari atas).
	var baker2 := LFMapBaker.new()
	baker2.auto_preview = false
	baker2.map_seed = 2026
	baker2.params = LFMapPresets.make("Highland Island")
	baker2.params.cliffs = 0.9
	baker2.params.lake_count = 2
	baker2.params.river_count = 2
	baker2.tile_size = 512
	baker2.tiles_x = 1
	baker2.tiles_z = 1
	baker2.output_dir = "res://maps/lf_map"
	baker2.map_image_px = 512
	var img_err: int = baker2.export_map_image()
	print("LF_BAKE2: map_image err=" + str(img_err))
	baker2.free()
	print("LF_BAKE2 DONE")
	quit(0)
