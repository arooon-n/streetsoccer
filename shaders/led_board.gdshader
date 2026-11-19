shader_type spatial;
render_mode unshaded, cull_disabled;

// Scrolling LED advertising board. UV.x is metres along the board run.
uniform sampler2D board_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float has_tex = 0.0;
uniform float tex_len = 24.0;      // metres covered by one texture repeat
uniform float scroll = 0.6;
uniform float energy = 1.6;
uniform vec3 col_a : source_color = vec3(1.0, 0.81, 0.2);
uniform vec3 col_b : source_color = vec3(0.26, 0.78, 0.94);

void fragment() {
	float x = UV.x / tex_len - TIME * scroll / tex_len;
	vec3 c;
	if (has_tex > 0.5) {
		c = texture(board_tex, vec2(x, UV.y)).rgb;
	} else {
		float band = step(0.5, fract(x * 3.0));
		c = mix(col_a, col_b, band);
	}
	// LED pixel grid
	vec2 px = fract(vec2(UV.x * 40.0, UV.y * 18.0));
	float dot_m = smoothstep(0.5, 0.25, length(px - 0.5));
	float far = clamp(fwidth(UV.x * 40.0) * 2.0, 0.0, 1.0);
	c *= mix(0.65 + 0.45 * dot_m, 0.85, far);
	ALBEDO = c * energy;
}
