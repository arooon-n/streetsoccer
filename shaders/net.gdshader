shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, shadows_disabled;

// Goal / cage net. UV is in metres. Bulges along NORMAL around the last ball impact.
uniform vec3 hit_pos = vec3(0.0, -100.0, 0.0);
uniform float hit_amp = 0.0;
uniform float hit_phase = 0.0;
uniform float cell = 0.13;
uniform int pattern = 0;            // 0 diamond (goal), 1 square chain-link (cage)
uniform vec3 net_col : source_color = vec3(0.93, 0.94, 0.92);
uniform float thickness = 0.06;
uniform float opacity = 0.95;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = distance(w, hit_pos);
	float b = hit_amp * exp(-d * d / 0.55) * (0.65 + 0.35 * cos(hit_phase));
	VERTEX += NORMAL * b;
}

void fragment() {
	vec2 g = UV / cell;
	vec2 f;
	if (pattern == 0) {
		f = abs(fract(vec2(g.x + g.y, g.x - g.y) * 0.5) - 0.5);
	} else {
		f = abs(fract(g) - 0.5);
	}
	float l = 0.5 - max(f.x, f.y);
	float w = fwidth(l);
	float cov = clamp((thickness - l) / max(w, 1e-4) + 0.5, 0.0, 1.0);
	// at distance the mesh averages into a faint haze
	float haze = clamp(w * 6.0, 0.0, 1.0);
	float a = mix(cov, thickness * 2.4, haze);
	ALBEDO = net_col;
	ROUGHNESS = 0.9;
	ALPHA = clamp(a, 0.0, 1.0) * opacity;
}
