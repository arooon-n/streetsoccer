shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// One material for every footballer. Regions are baked into UV2.y; rest-pose position in UV/UV2.x.
// Regions: 0 skin, 1 shirt, 2 shorts, 3 socks, 4 boots, 5 hair, 6 hand, 7 face
instance uniform vec4 c_shirt : source_color = vec4(0.25, 0.72, 0.9, 1.0);
instance uniform vec4 c_shirt2 : source_color = vec4(0.05, 0.13, 0.22, 1.0);
instance uniform vec4 c_shorts : source_color = vec4(0.05, 0.13, 0.22, 1.0);
instance uniform vec4 c_socks : source_color = vec4(0.25, 0.72, 0.9, 1.0);
instance uniform vec4 c_skin : source_color = vec4(0.78, 0.55, 0.39, 1.0);
instance uniform vec4 c_hair : source_color = vec4(0.1, 0.07, 0.05, 1.0);
instance uniform vec4 c_boots : source_color = vec4(0.08, 0.08, 0.08, 1.0);
instance uniform vec4 c_gloves : source_color = vec4(0.0, 0.0, 0.0, 0.0);
instance uniform float pattern = 0.0;
instance uniform float number = 9.0;

varying vec3 rest;
varying float region;

void vertex() {
	rest = vec3(UV.x, UV.y, UV2.x);
	region = UV2.y;
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

int digit_mask(int d) {
	if (d == 0) return 63;
	if (d == 1) return 6;
	if (d == 2) return 91;
	if (d == 3) return 79;
	if (d == 4) return 102;
	if (d == 5) return 109;
	if (d == 6) return 125;
	if (d == 7) return 7;
	if (d == 8) return 127;
	return 111;
}

// p in digit space: x 0..0.5, y 0..1
float digit_dist(vec2 p, int d) {
	int m = digit_mask(d);
	float r = 10.0;
	if ((m & 1) != 0) r = min(r, seg(p, vec2(0.0, 1.0), vec2(0.5, 1.0)));
	if ((m & 2) != 0) r = min(r, seg(p, vec2(0.5, 1.0), vec2(0.5, 0.5)));
	if ((m & 4) != 0) r = min(r, seg(p, vec2(0.5, 0.5), vec2(0.5, 0.0)));
	if ((m & 8) != 0) r = min(r, seg(p, vec2(0.0, 0.0), vec2(0.5, 0.0)));
	if ((m & 16) != 0) r = min(r, seg(p, vec2(0.0, 0.0), vec2(0.0, 0.5)));
	if ((m & 32) != 0) r = min(r, seg(p, vec2(0.0, 0.5), vec2(0.0, 1.0)));
	if ((m & 64) != 0) r = min(r, seg(p, vec2(0.0, 0.5), vec2(0.5, 0.5)));
	return r;
}

float number_mask(vec2 p, float n, float scale) {
	// p: centred coordinates in metres on the back; digits are `scale` tall
	int num = int(n + 0.5);
	int tens = num / 10;
	int ones = num - tens * 10;
	vec2 q = p / scale + vec2(0.0, 0.5);
	float d;
	if (tens > 0) {
		d = min(digit_dist(q - vec2(-0.62, 0.0), tens), digit_dist(q - vec2(0.12, 0.0), ones));
	} else {
		d = digit_dist(q - vec2(-0.25, 0.0), ones);
	}
	float w = fwidth(d);
	return 1.0 - smoothstep(0.085 - w, 0.085 + w, d);
}

void fragment() {
	int r = int(region + 0.5);
	vec3 col = c_skin.rgb;
	float rough = 0.6;
	if (r == 1) {
		col = c_shirt.rgb;
		int pat = int(pattern + 0.5);
		if (pat == 1) {
			float s = step(0.5, fract(rest.x * 7.5 + 0.25));
			col = mix(c_shirt.rgb, c_shirt2.rgb, s);
		} else if (pat == 2) {
			float s = step(0.5, fract(rest.y * 7.0));
			col = mix(c_shirt.rgb, c_shirt2.rgb, s);
		} else if (pat == 3) {
			float s = step(abs(rest.x * 0.9 + (rest.y - 1.2) * 0.8), 0.045);
			col = mix(c_shirt.rgb, c_shirt2.rgb, s);
		} else if (pat == 4) {
			col = mix(c_shirt.rgb, c_shirt2.rgb, step(0.0, rest.x));
		}
		// collar trim
		col = mix(col, c_shirt2.rgb, step(1.455, rest.y) * 0.85);
		// number on the back, small number on the chest
		if (rest.z < -0.05 && rest.y > 1.08 && rest.y < 1.42) {
			float nm = number_mask(vec2(-rest.x, rest.y - 1.25), number, 0.2);
			vec3 numc = dot(col, vec3(0.33)) > 0.55 ? vec3(0.06) : vec3(0.97);
			if (pat == 1 || pat == 4) numc = dot(c_shirt2.rgb, vec3(0.33)) > 0.5 ? vec3(0.06) : vec3(0.97);
			col = mix(col, numc, nm);
		}
		if (rest.z > 0.05 && rest.y > 1.28 && rest.y < 1.4 && rest.x > 0.03 && rest.x < 0.13) {
			float cm = 1.0 - smoothstep(0.03, 0.036, length(vec2(rest.x - 0.08, rest.y - 1.34)));
			col = mix(col, c_shirt2.rgb, cm);
		}
		rough = 0.75;
	} else if (r == 2) {
		col = c_shorts.rgb;
		rough = 0.7;
	} else if (r == 3) {
		col = c_socks.rgb;
		col = mix(col, c_shirt2.rgb, step(0.40, rest.y) * step(rest.y, 0.43) * 0.8);
		rough = 0.8;
	} else if (r == 4) {
		col = c_boots.rgb;
		rough = 0.35;
	} else if (r == 5) {
		col = c_hair.rgb;
		rough = 0.85;
	} else if (r == 6) {
		col = c_gloves.a > 0.5 ? c_gloves.rgb : c_skin.rgb;
	} else if (r == 7) {
		col = c_skin.rgb;
		// eyes and brows for close-ups
		vec2 e = vec2(abs(rest.x) - 0.036, rest.y - 1.717);
		float eye = 1.0 - smoothstep(0.009, 0.013, length(e * vec2(1.0, 1.4)));
		float brow = (1.0 - smoothstep(0.004, 0.007, abs(rest.y - 1.738 + rest.x * rest.x * 2.0))) * step(abs(rest.x), 0.058) * step(0.014, abs(rest.x));
		float mouth = (1.0 - smoothstep(0.003, 0.006, abs(rest.y - 1.66))) * step(abs(rest.x), 0.022);
		col = mix(col, vec3(0.05), max(eye, brow * 0.8) * step(0.06, rest.z));
		col = mix(col, col * 0.55, mouth * step(0.06, rest.z));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	RIM = 0.25;
	RIM_TINT = 0.4;
}
