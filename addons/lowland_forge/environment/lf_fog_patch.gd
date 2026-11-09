@tool
class_name LFFogPatch
extends Node3D
## A local patch of denser fog at a place in the world (a misty hollow, a haunted ruin, a fog bank on a moor): a
## sphere or a flat disc of `radius` m with a soft edge. As the camera goes in, the fog of the scene's Environment
## thickens to `visibility` metres at the core and thins again on the way out, so a site can sit in its own
## fog whatever the weather. Works with every renderer (it drives the Environment's depth or exponential fog;
## it turns fog on while the camera is in a patch if it was off). With `volumetric` on it also adds a Godot
## FogVolume, so the patch shows from outside as a bank of mist: that needs Forward+ and
## Environment.volumetric_fog_enabled (the project's choice; the patch doesn't switch it on).
##
##   var fog := LFFogPatch.new()
##   fog.radius = 40.0
##   add_child(fog)
##   fog.global_position = site_center
##
## Several patches may overlap: the thickest one wins. Fog values the host sets itself (weather, time of day)
## are respected: the patch only ever adds fog, and when the camera leaves the host's values are back.
## `LFFogPatch.amount_at(pos)` tells game code how deep in fog a point is (0..1), e.g. for encounters.

enum Shape { SPHERE, DISC }

## A ball of fog, or a flat disc (a cylinder `height` m tall from the node's origin) lying on the land.
@export var shape: Shape = Shape.DISC
## Radius (m) of the patch, edge included.
@export_range(1.0, 2000.0, 1.0) var radius := 40.0
## Height (m) of a disc patch, up from the node's origin (the fog thins over its top `edge_softness` m too).
@export_range(1.0, 500.0, 1.0) var height := 12.0
## How far the fog fades in from the rim (m): 0 = a hard wall of fog, `radius` = thickest only at the middle.
@export_range(0.0, 2000.0, 1.0) var edge_softness := 15.0
## 0..1: how much of the full fog the core gets (1 = see only `visibility` m).
@export_range(0.0, 1.0, 0.01) var density := 1.0
## How far (m) the camera sees in the core at density 1.
@export_range(2.0, 2000.0, 1.0) var visibility := 35.0
## The fog's colour in the patch (blended into the Environment's fog colour as the camera goes in).
@export var color := Color(0.72, 0.76, 0.78)
## Also a FogVolume for volumetric fog (seen from outside; Forward+ with volumetric fog on in the Environment).
@export var volumetric := false:
	set(v):
		volumetric = v
		_sync_volume()
## The Environment to drive. Empty = the one the camera renders with (the viewport's world, else its
## WorldEnvironment).
@export var environment: Environment

## Emitted when the camera comes into the patch (its amount rises above 0) and when it leaves.
signal camera_entered
signal camera_exited

static var _patches: Array[LFFogPatch] = []
# Per Environment: what the host had set ("base"), and what the patches last wrote ("wrote"), so a change the
# host makes while the camera is in fog becomes the new base.
static var _state := {}

var _volume: FogVolume
var _inside := false


func _enter_tree() -> void:
	if not _patches.has(self):
		_patches.append(self)
	_sync_volume()


func _exit_tree() -> void:
	_patches.erase(self)
	if _patches.is_empty() and not Engine.is_editor_hint():
		_apply_all()   # the last patch left: put the host's fog back


## 0..1: how deep world point `pos` is in this patch (1 in the core, fading to 0 at the rim), times density.
func amount(pos: Vector3) -> float:
	var l := to_local(pos)
	if shape == Shape.SPHERE:
		return density * _fade(radius - l.length(), edge_softness)
	var vs := minf(edge_softness, height * 0.5)   # a short disc fades over at most half its height
	return density * _fade(radius - Vector2(l.x, l.z).length(), edge_softness) * _fade(height - l.y, vs) \
			* _fade(l.y + vs, vs)


## 0 at or past the rim (d <= 0), rising to 1 `soft` m inside it.
static func _fade(d: float, soft: float) -> float:
	if d <= 0.0:
		return 0.0
	return 1.0 if soft <= 0.0 else smoothstep(0.0, soft, d)


## The thickest fog over every patch in the tree at world point `pos` (0..1).
static func amount_at(pos: Vector3) -> float:
	var best := 0.0
	for p in _patches:
		if p.is_inside_tree() and p.visible:
			best = maxf(best, p.amount(pos))
	return best


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	var a := 0.0 if cam == null or not visible else amount(cam.global_position)
	if (a > 0.0) != _inside:
		_inside = a > 0.0
		if _inside:
			camera_entered.emit()
		else:
			camera_exited.emit()
	if not _patches.is_empty() and _patches[0] == self:   # one patch drives the fog for all
		_apply_all()


## Sets every driven Environment's fog from the thickest patch the camera is in.
static func _apply_all() -> void:
	var by_env := {}   # Environment -> [amount, patch]
	for p in _patches:
		if not p.is_inside_tree():
			continue
		var env := p._env()
		if env == null:
			continue
		var cam := p.get_viewport().get_camera_3d()
		var a := 0.0 if cam == null or not p.visible else p.amount(cam.global_position)
		var cur: Array = by_env.get(env, [0.0, p])
		if a > float(cur[0]):
			cur = [a, p]
		by_env[env] = cur
	for env: Environment in _state.keys():   # environments no patch drives any more go back to the host's fog
		if not by_env.has(env):
			_drive(env, 0.0, null)
	for env: Environment in by_env:
		_drive(env, float(by_env[env][0]), by_env[env][1])


static func _drive(env: Environment, a: float, p: LFFogPatch) -> void:
	var st: Dictionary = _state.get(env, {})
	var now := [env.fog_enabled, env.fog_depth_begin, env.fog_depth_end, env.fog_density, env.fog_light_color]
	if st.is_empty():
		st = {"base": now, "wrote": now}
	var base: Array = st["base"]
	for i in now.size():   # a value the host changed since the patches wrote it is its new base
		if now[i] != st["wrote"][i]:
			base[i] = now[i]
	if a <= 0.0:
		if now != base:
			_write(env, base)
		_state.erase(env)
		return
	var out := base.duplicate()
	out[0] = true
	if env.fog_mode == Environment.FOG_MODE_DEPTH:
		var begin0: float = base[1] if base[0] else 4000.0
		var end0: float = base[2] if base[0] else 4000.0
		out[1] = lerpf(begin0, 0.0, a) if begin0 > 0.0 else begin0
		out[2] = lerpf(end0, minf(end0, p.visibility), a)
		if not base[0]:
			out[3] = 1.0
	else:
		var d0: float = base[3] if base[0] else 0.0
		out[3] = lerpf(d0, maxf(d0, 3.0 / p.visibility), a)   # about 95% fogged at `visibility`
	out[4] = (base[4] as Color).lerp(p.color, a)
	_write(env, out)
	st["wrote"] = out
	_state[env] = st


static func _write(env: Environment, v: Array) -> void:
	env.fog_enabled = v[0]
	env.fog_depth_begin = v[1]
	env.fog_depth_end = v[2]
	env.fog_density = v[3]
	env.fog_light_color = v[4]


func _env() -> Environment:
	if environment != null:
		return environment
	var vp := get_viewport()
	if vp == null:
		return null
	var w := vp.find_world_3d()
	if w != null and w.environment != null:
		return w.environment
	var cam := vp.get_camera_3d()
	return cam.environment if cam != null else null


func _sync_volume() -> void:
	if not is_inside_tree():
		return
	if not volumetric:
		if _volume != null:
			_volume.queue_free()
			_volume = null
		return
	if _volume == null:
		_volume = FogVolume.new()
		_volume.name = "FogVolume"
		var mat := FogMaterial.new()
		_volume.material = mat
		add_child(_volume, false, Node.INTERNAL_MODE_BACK)
	var fm := _volume.material as FogMaterial
	fm.density = density * 0.4
	fm.albedo = color
	fm.edge_fade = clampf(edge_softness / maxf(radius, 1.0), 0.05, 1.0)
	if shape == Shape.SPHERE:
		_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		_volume.size = Vector3.ONE * radius * 2.0
		_volume.position = Vector3.ZERO
	else:
		_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_CYLINDER
		_volume.size = Vector3(radius * 2.0, height, radius * 2.0)
		_volume.position = Vector3(0, height * 0.5, 0)
