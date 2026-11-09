@tool
extends EditorPlugin
## Enabling the plugin writes the global shader uniforms the addon's materials read (wind, weather, water
## waves...) into Project Settings > Shader Globals, so baked maps (plain scenes, no scripts) render the
## same in the editor and in the game. Values the project already set are kept.
## It also adds a Ground menu to the 3D toolbar: drop the selected nodes onto the land (LFGroundDrop), and a
## progress bar there while an LFMapBaker bakes or builds its preview. A preview that takes long brings up a
## tip, once per editor session, on how to make it quicker. While a map preview is shown, a note in the 3D
## view's corner says it is low detail. Project > Tools > "New Lowland Forge map" saves a new scene with an
## LFMapBaker, a sun and a sky (LFMapBaker.new_map_scene) and opens it.

const SLOW_PREVIEW_S := 6.0
const HIDE_TIP_SETTING := "lowland_forge/hide_slow_preview_tip"
const NEW_MAP_ITEM := "New Lowland Forge map"

var _ground_menu: MenuButton
var _bake_box: HBoxContainer
var _bake_label: Label
var _bake_bar: ProgressBar
var _cancel: Button
var _tip_shown := false
var _note: PanelContainer


func _enter_tree() -> void:
	_ground_menu = MenuButton.new()
	_ground_menu.text = "Ground"
	_ground_menu.tooltip_text = "Put the selected nodes on the ground below them: the Lowland Forge map " \
			+ "(works on the preview) or any collider."
	_ground_menu.get_popup().add_item("Drop selection to ground", 0)
	_ground_menu.get_popup().add_item("Drop and align to slope", 1)
	_ground_menu.get_popup().id_pressed.connect(func(id: int) -> void: _drop_selection(id == 1))
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _ground_menu)
	add_tool_menu_item(NEW_MAP_ITEM, _new_map)
	_add_bake_bar()
	_note = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	bg.set_corner_radius_all(4)
	bg.set_content_margin_all(6)
	_note.add_theme_stylebox_override("panel", bg)
	var text := Label.new()
	text.text = "Preview: low detail (thin rivers can look broken).\nBake, then open a tile scene to see full detail."
	text.add_theme_font_size_override("font_size", 13)
	text.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	_note.add_child(text)
	_note.position = Vector2(10, 44)   # under the view's Perspective menu, clear of the gizmo top right
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note.visible = false
	EditorInterface.get_editor_viewport_3d(0).add_child(_note)
	var added := false
	for g: Array in LFEnvironment.globals():
		var key := "shader_globals/" + String(g[0])
		if ProjectSettings.has_setting(key):
			continue
		ProjectSettings.set_setting(key, {"type": g[2], "value": g[3]})
		RenderingServer.global_shader_parameter_add(g[0], g[1], g[3])
		added = true
	if added:
		ProjectSettings.save()


func _exit_tree() -> void:
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _ground_menu)
	_ground_menu.queue_free()
	remove_tool_menu_item(NEW_MAP_ITEM)
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _bake_box)
	_bake_box.queue_free()
	_note.queue_free()


func _add_bake_bar() -> void:
	_bake_box = HBoxContainer.new()
	_bake_label = Label.new()
	_bake_box.add_child(_bake_label)
	_bake_bar = ProgressBar.new()
	_bake_bar.custom_minimum_size = Vector2(160, 0)
	_bake_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bake_bar.max_value = 1.0
	_bake_bar.step = 0.001
	_bake_box.add_child(_bake_bar)
	_cancel = Button.new()
	_cancel.text = "Cancel"
	_cancel.flat = true
	_cancel.pressed.connect(func() -> void:
		if LFMapBaker.baking != null and is_instance_valid(LFMapBaker.baking):
			LFMapBaker.baking.cancel_bake()
		elif LFMapBaker.loading != null and is_instance_valid(LFMapBaker.loading):
			LFMapBaker.loading.cancel_preview())
	_bake_box.add_child(_cancel)
	_bake_box.visible = false
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _bake_box)


func _process(_delta: float) -> void:
	if Engine.get_process_frames() % 20 == 0:
		_note.visible = _showing_preview()
	var b := LFMapBaker.baking
	var p := LFMapBaker.loading
	var e := LFMapBaker.exporting
	if b != null and is_instance_valid(b):
		b.drive_bake()   # its own _process stops while its scene is in another tab
	if e != null and is_instance_valid(e) and e.export_progress() >= 0.0:
		_bake_label.text = "Exporting"
		_bake_bar.value = e.export_progress()
		_bake_box.visible = true
	elif b != null and is_instance_valid(b):
		_bake_label.text = "Baking"
		_bake_bar.value = b.bake_progress()
		_bake_box.visible = true
	elif p != null and is_instance_valid(p) and p.preview_progress() >= 0.0:
		_bake_label.text = "Preview"
		_bake_bar.value = p.preview_progress()
		_bake_box.visible = true
		if not _tip_shown and p.preview_seconds() > SLOW_PREVIEW_S:
			_tip_shown = true
			_slow_preview_tip()
	else:
		_bake_box.visible = false


## True if the edited scene has an LFMapBaker showing its preview.
func _showing_preview() -> bool:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return false
	if root is LFMapBaker and (root as LFMapBaker).has_preview():
		return true
	for n in root.find_children("*", "Node3D", true, false):
		if n is LFMapBaker and (n as LFMapBaker).has_preview() and (n as LFMapBaker).is_visible_in_tree():
			return true
	return false


## Once per session, unless turned off: how to make a slow preview quicker.
func _slow_preview_tip() -> void:
	var es := EditorInterface.get_editor_settings()
	if es.has_setting(HIDE_TIP_SETTING) and es.get_setting(HIDE_TIP_SETTING):
		return
	var dlg := AcceptDialog.new()
	dlg.title = "Lowland Forge: slow preview"
	var box := VBoxContainer.new()
	var text := Label.new()
	text.text = "This preview is taking a while: a big map with all its trees, rocks and logs.\n" \
			+ "To make it quicker (LFMapBaker in the Inspector):\n\n" \
			+ "  - Work on One Tile: one tile in detail, with its props, the rest of the map coarse.\n" \
			+ "  - Preview > Preview Props off: the land alone is quick.\n" \
			+ "  - Preview > Preview Props Limit: leave props out of previews bigger than that (km²).\n" \
			+ "  - Preview > Auto Preview off: redraw only when you press Refresh preview.\n\n" \
			+ "The bake is the same whatever you choose here."
	box.add_child(text)
	var hide := CheckBox.new()
	hide.text = "Don't show this again"
	box.add_child(hide)
	dlg.add_child(box)
	dlg.visibility_changed.connect(func() -> void:   # OK or the close button
		if not dlg.visible:
			if hide.button_pressed:
				es.set_setting(HIDE_TIP_SETTING, true)
			dlg.queue_free())
	EditorInterface.get_base_control().add_child(dlg)
	dlg.popup_centered()


## Moves every selected Node3D onto the ground under it, as one undoable action.
func _drop_selection(align: bool) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var moves: Array = []   # [node, new global transform]
	for n in EditorInterface.get_selection().get_top_selected_nodes():
		if n is Node3D and not n is LFMapBaker:
			var xf: Variant = LFGroundDrop.dropped(n, root, align)
			if xf != null:
				moves.append([n, xf])
	if moves.is_empty():
		push_warning("Lowland Forge: no ground below the selection (select Node3Ds over a map or a collider).")
		return
	var ur := get_undo_redo()
	ur.create_action("Drop to ground")
	for m: Array in moves:
		ur.add_do_property(m[0], "global_transform", m[1])
		ur.add_undo_property(m[0], "global_transform", (m[0] as Node3D).global_transform)
	ur.commit_action()


## Saves a new map scene (res://maps/map.tscn, or map_2, map_3... if taken; it bakes to the folder of the
## same name) and opens it.
func _new_map() -> void:
	var file := "map"
	var n := 1
	while FileAccess.file_exists("res://maps/%s.tscn" % file) or DirAccess.dir_exists_absolute("res://maps/" + file):
		n += 1
		file = "map_%d" % n
	var path := "res://maps/%s.tscn" % file
	var root := LFMapBaker.new_map_scene("res://maps/" + file)
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	DirAccess.make_dir_recursive_absolute("res://maps")
	var err := ResourceSaver.save(ps, path)
	if err != OK:
		push_error("Lowland Forge: couldn't save %s (%s)" % [path, error_string(err)])
		return
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.open_scene_from_path(path)
	print("Lowland Forge: new map scene %s (select LFMapBaker to set it up, then Bake)." % path)
