shader_type spatial;
render_mode unshaded, cull_back;

// Each instance is a 1.6 m wide card with three fans drawn procedurally.
// INSTANCE_CUSTOM: x = phase, y = seed A, z = seed B, w = team bias (0 home, 1 away, 0.5 neutral)
uniform float excite = 0.0;       // 0 calm .. 1 goal celebration
uniform float home_cheer = 0.0;   // which side celebrates (0 = everyone, 1 home, -1 away)
uniform float bright = 1.0;
uniform vec3 home_col : source_color = vec3(0.26, 0.72, 0.9);
uniform vec3 away_col : source_color = vec3(0.9, 0.29, 0.24);
uniform vec3 back_col : source_color = vec3(0.05, 0.07, 0.08);

varying vec4 cust;
varying float wy;
varying float lift;

float h1(float n) { return fract(sin(n * 127.1) * 43758.5453); }

void vertex() {
	cust = INSTANCE_CUSTOM;
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	float team = cust.w;
	float side = home_cheer == 0.0 ? 1.0 : (home_cheer > 0.0 ? (1.0 - team) : team);
	float e = excite * mix(0.15, 1.0, side);
	float idle = sin(TIME * 1.3 + cust.x * 6.28) * 0.015;
	float jump = abs(sin(TIME * (7.0 + cust.y * 3.0) + cust.x * 6.28)) * 0.22 * e;
	lift = e;
	VERTEX.y += idle + jump;
}

void fragment() {
	float slots = 3.0;
	float sx = UV.x * slots;
	float slot = floor(sx);
	vec2 u = vec2(fract(sx), 1.0 - UV.y);   // u.y: 0 bottom .. 1 top
	float s1 = h1(cust.y * 31.0 + slot * 7.13);
	float s2 = h1(cust.z * 17.0 + slot * 3.71);
	float present = step(0.12, s1);
	float height = 0.78 + 0.14 * s2;
	float aspect = 1.6 / 3.0 / 0.95;
	vec2 hp = vec2(0.5 + (s2 - 0.5) * 0.12, height - 0.12);
	vec2 dh = (u - hp) * vec2(aspect, 1.0);
	float head = step(length(dh), 0.105);
	float bw = 0.36 + 0.08 * s1;
	float body = step(abs(u.x - 0.5 - (s2 - 0.5) * 0.06), bw) * step(u.y, height - 0.24) ;
	body *= step(0.0, (height - 0.24) - u.y + 0.0);
	float arms = 0.0;
	if (lift > 0.4 && s2 > 0.35) {
		float ax = abs(u.x - 0.5);
		arms = step(abs(ax - 0.3), 0.07) * step(height - 0.3, u.y) * step(u.y, height + 0.12);
	}
	float person = clamp(max(max(head, body), arms) * present, 0.0, 1.0);
	float pick = h1(cust.z * 91.0 + slot * 1.7);
	vec3 team_c = mix(home_col, away_col, cust.w > 0.5 ? 1.0 : 0.0);
	vec3 shirt;
	if (pick < 0.55) { shirt = team_c * (0.75 + 0.35 * s1); }
	else if (pick < 0.7) { shirt = vec3(0.92, 0.92, 0.9) * (0.7 + 0.3 * s2); }
	else if (pick < 0.85) { shirt = vec3(0.12, 0.14, 0.17); }
	else { shirt = vec3(s1, s2, h1(pick)) * 0.7; }
	vec3 skin = mix(vec3(0.36, 0.22, 0.14), vec3(0.93, 0.76, 0.62), s2);
	vec3 c = mix(shirt, skin, max(head, arms * 0.0));
	c *= 0.75 + 0.25 * u.y;
	vec3 col = mix(back_col, c, person);
	ALBEDO = col * bright * mix(1.0, 0.55, smoothstep(6.0, 22.0, wy));
}
