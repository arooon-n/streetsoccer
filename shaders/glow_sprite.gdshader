shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Camera-facing floodlight flare. Used on a MultiMesh of quads.
uniform vec3 tint : source_color = vec3(1.0, 0.96, 0.88);
uniform float intensity = 1.0;

void vertex() {
	// billboard: keep instance origin, orient quad to camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float core = exp(-r * r * 18.0);
	float halo = exp(-r * 3.2) * 0.35;
	float streak = exp(-abs(p.y) * 40.0) * exp(-abs(p.x) * 2.5) * 0.35;
	float a = (core + halo + streak) * (1.0 - smoothstep(0.85, 1.0, r));
	ALBEDO = tint * a * intensity;
}
