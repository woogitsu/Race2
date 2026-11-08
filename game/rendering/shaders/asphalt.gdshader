shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// Asphalt with procedural micro-texture and wetness response.
// wetness 0 = dry (matte, rough), 1 = soaked (darker, glossy reflections).
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float coarse = texture(noise_tex, world_pos.xz * 0.012).r;
	float fine = texture(noise_tex, world_pos.xz * 0.9 + vec2(0.37, 0.11)).r;
	float grain = 0.80 + 0.28 * coarse + 0.12 * fine;
	vec3 base = COLOR.rgb * grain;
	// Water darkens the surface and suppresses diffuse light.
	ALBEDO = mix(base, base * 0.5, wetness * 0.7);
	float rough = mix(0.88, 0.12, wetness) * (0.85 + 0.3 * fine);
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = mix(0.35, 0.65, wetness);
}
