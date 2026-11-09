@tool
class_name LFPropSwap
extends Resource
## Replaces the look of one built-in prop kind with your own meshes (LFMapParams.prop_swaps). Where and how many
## are placed stays the same, and so do the batching, collision groups, preview and felling.

## The built-in kind to replace.
@export var kind := LFPropMeshes.Kind.PINE
## Your meshes, used in turn across the kind's variants: an imported .obj, or a mesh saved from a .glb. Origin at
## the foot, +Y up. They keep their own materials (no wind unless your material has it).
@export var meshes: Array[Mesh] = []
## Multiplies your meshes' size. A built-in tree is about 10 m tall, a rock 0.5 to 3 m across.
@export_range(0.01, 100.0, 0.01, "or_greater") var mesh_scale := 1.0
## Radius (m) of the collider of trees, rocks, cacti and crystals; below 0 keeps the built-in one.
@export_range(-1.0, 10.0, 0.05, "or_greater", "suffix:m") var collide_radius := -1.0


static func make(k: LFPropMeshes.Kind, list: Array[Mesh], radius := -1.0, size := 1.0) -> LFPropSwap:
	var s := LFPropSwap.new()
	s.kind = k
	s.meshes = list
	s.collide_radius = radius
	s.mesh_scale = size
	return s
