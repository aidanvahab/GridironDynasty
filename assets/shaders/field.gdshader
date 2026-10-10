shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Football field surface. World units are yards: x along the length
// (goal lines at +-50, end lines at +-60), z across (sidelines at +-26.667).

uniform vec3 grass_a : source_color = vec3(0.23, 0.50, 0.22);
uniform vec3 grass_b : source_color = vec3(0.19, 0.44, 0.19);
uniform vec3 line_color : source_color = vec3(0.97, 0.96, 0.93);
uniform vec3 endzone_a : source_color = vec3(0.10, 0.18, 0.30);
uniform vec3 endzone_b : source_color = vec3(0.60, 0.25, 0.10);
uniform vec3 apron_color : source_color = vec3(0.16, 0.34, 0.17);
uniform float wetness = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float band(float d, float w) {
	float fw = max(fwidth(d), 0.0005);
	return 1.0 - smoothstep(w * 0.5 - fw, w * 0.5 + fw, abs(d));
}

float rect(vec2 p, vec2 c, vec2 half_size) {
	vec2 d = abs(p - c) - half_size;
	float fw = max(fwidth(p.x), 0.0005);
	return 1.0 - smoothstep(-fw, fw, max(d.x, d.y));
}

void fragment() {
	float x = wpos.x;
	float z = wpos.z;
	float ax = abs(x);
	float az = abs(z);
	float n = vnoise(wpos.xz * 1.3) * 0.45 + vnoise(wpos.xz * 5.7) * 0.35 + vnoise(wpos.xz * 21.0) * 0.2;
	float stripe = mod(floor((x + 60.0) / 5.0), 2.0);
	vec3 col = mix(grass_a, grass_b, stripe);
	// Cross-mow pattern for depth.
	col *= 0.97 + 0.03 * mod(floor((z + 30.0) / 5.0), 2.0);
	col *= 0.86 + n * 0.26;
	bool in_field = az <= 26.667 && ax <= 60.0;
	if (!in_field) {
		col = apron_color * (0.85 + n * 0.25);
	}
	if (ax > 50.0 && ax < 60.0 && az < 26.667) {
		vec3 ez = x < 0.0 ? endzone_a : endzone_b;
		// Diagonal hatch for a classic painted end zone.
		float hatch = step(0.5, fract((x + z) / 3.0));
		col = mix(col, ez * (0.86 + n * 0.18) * (0.93 + 0.07 * hatch), 0.88);
	}
	float lines = 0.0;
	if (az <= 26.667) {
		// Yard lines every 5 yards.
		if (ax <= 50.1) {
			float d = mod(x + 52.5, 5.0) - 2.5;
			lines = max(lines, band(d, 0.12));
		}
		// Goal lines (8 inches).
		lines = max(lines, band(ax - 50.0, 0.24));
		// End lines.
		lines = max(lines, band(ax - 60.0, 0.24));
		// Hash marks every yard: center hashes and inbound marks near the sidelines.
		if (ax < 50.0) {
			float dy = mod(x + 50.5, 1.0) - 0.5;
			float tick = band(dy, 0.11);
			float h1 = 1.0 - step(0.333, abs(az - 3.083 - 0.333));
			float h2 = 1.0 - step(0.333, abs(az - 26.0));
			lines = max(lines, tick * max(h1, h2));
		}
		// Two-point try marks at the 2-yard line.
		lines = max(lines, rect(vec2(ax, z), vec2(48.0, 0.0), vec2(0.06, 0.5)));
	}
	// Sideline / end line border (6 ft wide white border outside the field).
	if (ax <= 60.67 && az <= 27.333) {
		float border = max(step(26.667, az), step(60.0, ax));
		lines = max(lines, border);
	}
	vec3 albedo = mix(col, line_color * (0.94 + n * 0.06), lines);
	ALBEDO = albedo;
	ROUGHNESS = mix(0.92 - wetness * 0.5, 0.75, lines);
	SPECULAR = 0.3 + wetness * 0.3;
}
