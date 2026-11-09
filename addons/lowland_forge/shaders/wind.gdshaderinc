// Shared wind maths. Pure functions: everything (wind, wind_phase, ...) is passed in so this
// include declares no uniforms and can be pulled into any spatial shader.
//   wnd      = (dir.x, dir.z, strength, gustiness)
//   wphase = (x = gust travel distance along wnd (m), y = oscillation phase (rad))

// Gust factor 0..1 at a world position (waves rolling downwind).
float wind_gust(vec2 origin_xz, vec4 wnd, vec4 wphase) {
	vec2 wdir = wnd.xy;
	vec2 wperp = vec2(-wdir.y, wdir.x);
	float along = dot(origin_xz, wdir);
	float across = dot(origin_xz, wperp);
	float g1 = sin((along - wphase.x) * 0.16 + sin(across * 0.09) * 1.6);
	float g2 = sin((along - wphase.x * 1.3) * 0.37 + across * 0.13);
	float gust = clamp(g1 * 0.65 + g2 * 0.35, -1.0, 1.0) * 0.5 + 0.5;
	return gust * gust;
}

// Small plants / grass (world-space offset). Behaviour unchanged from the old foliage shader.
vec3 plant_wind(vec3 wp, vec3 origin, float href, float wresp, float max_offset,
		vec4 wnd, vec4 wphase) {
	float h = max(wp.y - origin.y, 0.0);
	float w = clamp(h / href, 0.0, 1.0);
	w *= w; // quadratic: bottoms stay put, tips move most
	float ws = wnd.z;
	vec2 wdir = wnd.xy;
	vec2 wperp = vec2(-wdir.y, wdir.x);
	float ph = origin.x * 0.31 + origin.z * 0.23;
	float gust = wind_gust(origin.xz, wnd, wphase);
	float lean = ws * 0.22 + gust * wnd.w * ws * 0.3;
	float osc_a = sin(wphase.y + ph + wp.y * 1.3) + 0.5 * sin(wphase.y * 2.3 + ph * 1.9);
	float osc_b = sin(wphase.y * 0.8 + ph * 1.4 + 1.7);
	float osc_amp = ws * (0.035 + 0.05 * gust * wnd.w);
	vec2 woff = (wdir * (lean + osc_a * osc_amp) + wperp * (osc_b * osc_amp * 0.4)) * wresp * w;
	float wl = length(woff);
	if (wl > max_offset) {
		woff *= max_offset / wl;
	}
	return vec3(woff.x, -wl * 0.25, woff.y);
}

// Whole-tree cantilever bend (world-space offset). Depends ONLY on the vertex height above the
// instance origin plus per-instance values, so trunk and canopy vertices at the same height move
// identically. tree_h = effective tree height in world metres (already includes instance scale).
// amp scales the bend, max_offset caps the displacement of the very top (m).
vec3 tree_bend(vec3 wp, vec3 origin, float tree_h, float amp, float max_offset,
		vec4 wnd, vec4 wphase) {
	float ws = wnd.z;
	float h = max(wp.y - origin.y, 0.0);
	float x = clamp(h / max(tree_h, 0.1), 0.0, 1.3);
	float w = x * x * (0.4 + 0.6 * x); // anchored base, top moves most
	vec2 wdir = wnd.xy;
	vec2 wperp = vec2(-wdir.y, wdir.x);
	float ph = origin.x * 0.17 + origin.z * 0.13;
	float gust = wind_gust(origin.xz, wnd, wphase);
	float lean = ws * 0.2 + gust * wnd.w * ws * 0.3;
	// Slow sway around the lean (no per-height term so the whole trunk swings coherently).
	float osc_a = sin(wphase.y * 0.55 + ph) + 0.4 * sin(wphase.y * 1.1 + ph * 1.7);
	float osc_b = sin(wphase.y * 0.45 + ph * 1.3 + 1.7);
	float osc_amp = ws * (0.03 + 0.06 * gust * wnd.w);
	vec2 woff = (wdir * (lean + osc_a * osc_amp) + wperp * (osc_b * osc_amp * 0.4)) * amp * w;
	float wl = length(woff);
	if (wl > max_offset) {
		woff *= max_offset / wl;
	}
	return vec3(woff.x, -wl * 0.15, woff.y);
}

// Extra leaf flutter for canopies (world-space offset), small and per-vertex.
vec3 leaf_flutter(vec3 wp, float amount, vec4 wnd, vec4 wphase) {
	float ws = wnd.z;
	float t = wphase.y;
	return vec3(
		sin(t * 2.7 + wp.x * 1.9 + wp.y * 1.3),
		sin(t * 3.3 + wp.z * 2.3 + wp.x * 0.7) * 0.5,
		sin(t * 2.3 + wp.z * 1.7 + wp.y * 1.1)) * (ws * amount);
}
