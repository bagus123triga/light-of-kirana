// Baked map terrain (LFTileBaker): an indexed 2 m height grid that still looks flat-shaded and faceted.
//  * Each triangle's colour is one texel of `facets` (2 texels per 2 m cell, a row per cell row), found from
//    the block-local position: no per-triangle vertices needed.
//  * The flat normal comes from the screen-space derivatives of the position.
// The coarser LODs and the skirts read the same texels, so a far block keeps its colours.
shader_type spatial;

uniform sampler2D facets : source_color, filter_nearest, repeat_disable;
uniform float cell = 2.0;   // m per grid cell (LFTerrainGenerator.STEP)

varying vec3 local_pos;


void vertex() {
	local_pos = VERTEX;
}


void fragment() {
	vec2 c = local_pos.xz / cell;
	vec2 ci = floor(c);
	vec2 f = c - ci;
	// a cell is split p10-p01: the triangle at its (0, 0) corner, then the one at (1, 1)
	int t = f.x + f.y > 1.0 ? 1 : 0;
	ivec2 size = textureSize(facets, 0);
	ivec2 px = clamp(ivec2(int(ci.x) * 2 + t, int(ci.y)), ivec2(0), size - 1);
	ALBEDO = texelFetch(facets, px, 0).rgb;
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = dot(n, VERTEX) > 0.0 ? -n : n;   // facing the camera, whichever way the derivatives run
	ROUGHNESS = 1.0;
}
