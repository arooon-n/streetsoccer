shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Pitch surface: mowing stripes, wear, and analytically drawn chalk markings.
uniform float half_len = 52.5;
uniform float half_wid = 34.0;
uniform int layout = 0;          // 0 = full size, 1 = 5-a-side cage
uniform float stripe_w = 5.25;
uniform vec3 grass_a : source_color = vec3(0.2, 0.43, 0.17);
uniform vec3 grass_b : source_color = vec3(0.16, 0.355, 0.145);
uniform vec3 surround : source_color = vec3(0.14, 0.32, 0.13);
uniform float pool = 0.0;
uniform float surround_dist = 4.0;
uniform vec3 track_col : source_color = vec3(0.11, 0.14, 0.15);
uniform float wet = 0.0;
uniform float detail = 1.0;
uniform float wear_amt = 1.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_nrm : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

float line_dist(vec2 p) {
	float L = half_len;
	float W = half_wid;
	vec2 q = abs(p);
	float d = abs(sd_box(p, vec2(L, W)));
	if (q.y <= W) { d = min(d, abs(p.x)); }
	vec2 m = vec2(q.x, p.y);
	if (layout == 0) {
		d = min(d, abs(length(p) - 9.15));
		d = min(d, abs(sd_box(m - vec2(L - 8.25, 0.0), vec2(8.25, 20.16))));
		d = min(d, abs(sd_box(m - vec2(L - 2.75, 0.0), vec2(2.75, 9.16))));
		if (q.x < L - 16.5) { d = min(d, abs(length(m - vec2(L - 11.0, 0.0)) - 9.15)); }
		if (q.x <= L && q.y <= W) { d = min(d, abs(length(q - vec2(L, W)) - 1.0)); }
	} else {
		d = min(d, abs(length(p) - 3.0));
		if (q.x <= L) { d = min(d, abs(length(m - vec2(L, 0.0)) - 6.0)); }
	}
	return d;
}

float spot_dist(vec2 p) {
	vec2 q = abs(p);
	float d = length(p);
	float s = layout == 0 ? half_len - 11.0 : half_len - 6.0;
	d = min(d, length(vec2(q.x - s, p.y)));
	return d;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 q = abs(p);
	float n1 = texture(noise_tex, p * 0.031).r;
	float n2 = texture(noise_tex, p * 0.19 + vec2(0.37, 0.11)).r;
	float dn = texture(detail_tex, p * 1.3).r;
	float stripe = mod(floor((p.x + half_len) / stripe_w), 2.0);
	vec3 g = mix(grass_a, grass_b, stripe);
	float outside = step(0.0, max(q.x - half_len, q.y - half_wid));
	g = mix(g, surround, outside * 0.8);
	g *= 0.84 + 0.26 * n1;
	g *= mix(1.0, 0.86 + 0.28 * dn, detail);
	float wear = 0.0;
	if (layout == 0) {
		wear = smoothstep(8.0, 1.5, length(vec2((q.x - (half_len - 4.5)) * 1.2, p.y * 0.75))) * 0.6;
		wear += smoothstep(3.5, 0.4, length(vec2(q.x - (half_len - 11.0), p.y))) * 0.4;
		wear += smoothstep(2.5, 0.3, length(p)) * 0.25;
	} else {
		wear = smoothstep(5.0, 1.0, length(vec2(q.x - (half_len - 2.0), p.y))) * 0.35;
	}
	wear *= smoothstep(0.3, 0.75, n2 + 0.15) * wear_amt;
	g = mix(g, vec3(0.3, 0.32, 0.17), clamp(wear * 0.55, 0.0, 0.4));
	float beyond = step(0.0, max(q.x - half_len - surround_dist, q.y - half_wid - surround_dist));
	g = mix(g, track_col * (0.9 + 0.2 * n2), beyond);
	float d = line_dist(p);
	float aa = fwidth(d) + 0.002;
	float lw = 0.065;
	float lm = 1.0 - smoothstep(lw - aa, lw + aa, d);
	float sp = 1.0 - smoothstep(0.16 - aa, 0.16 + aa, spot_dist(p));
	lm = max(lm, sp) * (1.0 - beyond);
	vec3 chalk = vec3(0.88, 0.9, 0.86) * (0.93 + 0.07 * dn);
	vec3 col = mix(g, chalk, lm * 0.96);
	col *= 1.0 - pool * 0.22 * smoothstep(0.45, 1.25, length(p / vec2(half_len, half_wid)));
	col *= mix(1.0, 0.7, wet * (1.0 - lm * 0.5));
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.93, 0.7, lm), 0.2 + 0.25 * n2, wet);
	SPECULAR = mix(0.22, 0.8, wet);
	NORMAL_MAP = texture(detail_nrm, p * 1.3).rgb;
	NORMAL_MAP_DEPTH = 0.55 * detail * (1.0 - beyond);
}
