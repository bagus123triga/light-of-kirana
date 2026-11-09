@tool
class_name LFBiomeRegions
extends Resource
## Splits the land into wedges round the map's centre (LFTerrainGenerator.region_center), like a game's regions,
## each with its own allowed biomes, plus an optional central disc. Set it as LFMapParams.biome_regions.
## Region 0 starts at `start_angle` and the wedges run clockwise seen from above. The borders blend over `blend`
## metres, so a meadow region meets a forest region through a soft band, not a seam. A game reads which region a
## point is in with LFTerrainGenerator.region_at (-1 = the central disc, or no regions).
## A subclass's LFTerrainGenerator.biome_allowed combines with this (the two factors multiply). Read-only once
## the map is set up, so it is safe to ask from worker threads.

## How many wedges the land is split into.
@export_range(1, 16, 1) var count := 4
## Where region 0 starts, in degrees clockwise from north (-Z).
@export_range(-360.0, 360.0, 1.0, "suffix:deg") var start_angle := 0.0
## Radius of a central disc that has its own rules (Center), in metres. 0 = no disc.
@export_range(0.0, 5000.0, 10.0, "or_greater", "suffix:m") var inner_radius := 0.0
## How wide (m) the soft border between two regions, and round the disc, is. 0 = a hard edge.
@export_range(0.0, 1000.0, 5.0, "or_greater", "suffix:m") var blend := 80.0
## The rules of the central disc. Empty biomes = all biomes.
@export var center: LFBiomeRegion = null
## The rules of each wedge, in order from Start Angle. A wedge without an entry (the list is shorter than Count)
## allows every biome.
@export var regions: Array[LFBiomeRegion] = []


## Which region (x, z) is in: 0 .. count - 1, or -1 in the central disc. `origin` is the map's centre
## (LFTerrainGenerator.region_center; LFTerrainGenerator.region_at passes it for you).
func region_at(x: float, z: float, origin := Vector2.ZERO) -> int:
	var loc := locate(x, z, origin)
	if loc.w >= 0.5:
		return -1
	return int(loc.x) if loc.z >= 0.5 else int(loc.y)


## Where (x, z) sits as Vector4(region, neighbour region, share of the region, share of the central disc): the
## point blends the `region` wedge (share z) with the `neighbour` (1 - z), and the disc (w) over both.
## Cheap and allocation free: the generator asks it for every height and colour sample.
func locate(x: float, z: float, origin := Vector2.ZERO) -> Vector4:
	var dx := x - origin.x
	var dz := z - origin.y
	var r := sqrt(dx * dx + dz * dz)
	var disc := 0.0
	if inner_radius > 0.0:
		disc = 1.0 - smoothstep(inner_radius - blend * 0.5, inner_radius + blend * 0.5, r) if blend > 0.0 \
				else (1.0 if r < inner_radius else 0.0)
	var n := maxi(count, 1)
	if n == 1:
		return Vector4(0.0, 0.0, 1.0, disc)
	var sector := TAU / float(n)
	var u := fposmod(atan2(dx, -dz) - deg_to_rad(start_angle), TAU) / sector
	var a := mini(floori(u), n - 1)
	var f := u - float(a)
	var nb := (a + n - 1) % n if f < 0.5 else (a + 1) % n
	var share := 1.0
	if blend > 0.0:
		var edge_m := minf(f, 1.0 - f) * sector * r   # metres to the nearer border
		share = 0.5 + 0.5 * smoothstep(0.0, blend, edge_m)
	return Vector4(float(a), float(nb), share, disc)


## Per-biome factors for `biome_names` (the map's biomes in order): count + 1 arrays, wedge 0 .. count - 1 and the
## central disc last. Names that match no biome are warned about once.
func compile(biome_names: PackedStringArray) -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	var n := maxi(count, 1)
	for k in n + 1:
		var src: LFBiomeRegion = null
		if k == n:
			src = center
		elif k < regions.size():
			src = regions[k]
		var f := PackedFloat32Array()
		f.resize(biome_names.size())
		f.fill(1.0)
		if src != null and not src.biomes.is_empty():
			var hit := false
			for i in biome_names.size():
				var listed := src.biomes.has(biome_names[i])
				f[i] = src.favour if listed else src.others
				hit = hit or listed
			for nm in src.biomes:
				if not biome_names.has(nm):
					push_warning("LFBiomeRegions: region %d lists the biome \"%s\", which the map does not have" % [k, nm])
			if not hit:   # nothing it lists exists: leave the region unrestricted rather than empty
				f.fill(1.0)
		out.append(f)
	return out
