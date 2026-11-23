shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 deep : source_color = vec4(0.02, 0.17, 0.27, 1.0);
uniform vec4 shallow : source_color = vec4(0.10, 0.50, 0.58, 1.0);

void fragment() {
	vec2 p = UV * 600.0;
	float w = sin(p.x * 0.9 + TIME * 0.8) * 0.5 + sin(p.y * 1.3 - TIME * 0.6) * 0.5;
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep.rgb, shallow.rgb, clamp(f * 0.9 + w * 0.06 + 0.1, 0.0, 1.0));
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.8;
}
