shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Classic 32-panel football: dark pentagons at the 12 icosahedron vertices.
uniform vec3 col_a : source_color = vec3(0.96, 0.96, 0.95);
uniform vec3 col_b : source_color = vec3(0.08, 0.1, 0.1);

varying vec3 lp;

void vertex() {
	lp = normalize(VERTEX);
}

void fragment() {
	float phi = 1.618034;
	vec3 v[12] = vec3[](
		vec3(-1.0, phi, 0.0), vec3(1.0, phi, 0.0), vec3(-1.0, -phi, 0.0), vec3(1.0, -phi, 0.0),
		vec3(0.0, -1.0, phi), vec3(0.0, 1.0, phi), vec3(0.0, -1.0, -phi), vec3(0.0, 1.0, -phi),
		vec3(phi, 0.0, -1.0), vec3(phi, 0.0, 1.0), vec3(-phi, 0.0, -1.0), vec3(-phi, 0.0, 1.0));
	float best = -1.0;
	float second = -1.0;
	for (int i = 0; i < 12; i++) {
		float d = dot(lp, normalize(v[i]));
		if (d > best) { second = best; best = d; } else if (d > second) { second = d; }
	}
	float pent = smoothstep(0.935, 0.945, best);
	float seam = 1.0 - smoothstep(0.0, 0.012, best - second);
	vec3 c = mix(col_a, col_b, pent);
	c *= 1.0 - seam * 0.35;
	ALBEDO = c;
	ROUGHNESS = 0.38;
	SPECULAR = 0.6;
}
