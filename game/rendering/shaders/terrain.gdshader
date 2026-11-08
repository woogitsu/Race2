shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// Ground with biome vertex colours and a world-space micro-variation.
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n1 = texture(noise_tex, world_pos.xz * 0.03).r;
	float n2 = texture(noise_tex, world_pos.xz * 0.31 + vec2(0.5, 0.2)).r;
	ALBEDO = COLOR.rgb * (0.72 + 0.35 * n1 + 0.15 * n2);
	ROUGHNESS = 0.93;
	SPECULAR = 0.3;
}
