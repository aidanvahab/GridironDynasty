shader_type spatial;
render_mode diffuse_burley, cull_back;
// Instanced spectators (MultiMesh). Instance COLOR = shirt color.
// INSTANCE_CUSTOM: x = phase, y = enthusiasm, z = skin tone (0..1), w = unused.
// Arms are identified by |x| > 0.21 and the head by y > 0.62 (mesh space).

uniform float excitement : hint_range(0.0, 1.0) = 0.25;
varying float is_skin;
varying float skin_tone;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	float enthusiasm = INSTANCE_CUSTOM.y;
	float e = clamp(excitement * (0.55 + enthusiasm * 0.9), 0.0, 1.0);
	float t = TIME * (2.2 + enthusiasm * 3.0) + phase;
	float arm = step(0.21, abs(VERTEX.x));
	float raise = arm * step(0.45, VERTEX.y) * e * step(0.35, enthusiasm + e * 0.4);
	VERTEX.y += raise * (0.38 + 0.12 * sin(t * 1.3));
	VERTEX.y += max(0.0, sin(t)) * 0.14 * e + sin(TIME * 0.6 + phase) * 0.012;
	is_skin = step(0.62, VERTEX.y - raise * 0.5) * (1.0 - arm);
	skin_tone = INSTANCE_CUSTOM.z;
}

void fragment() {
	vec3 skin = mix(vec3(0.95, 0.78, 0.62), vec3(0.32, 0.2, 0.13), skin_tone);
	ALBEDO = mix(COLOR.rgb, skin, is_skin);
	ROUGHNESS = 0.92;
}
