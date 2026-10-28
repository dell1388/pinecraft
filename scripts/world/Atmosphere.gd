extends RefCounted

## The sky with shaders on: a sky that follows the sun round the day instead
## of two flat colours - deep blue overhead fading to pale at the horizon by
## day; at sunrise and sunset a glowing orange band low down on the sun's side
## and purple-blue on the other, a bright disc and halo round the sun itself;
## drifting clouds lit by it (white by day, gold and pink edges at either end
## of the day, dark by night); and at night stars, gently twinkling, and the
## moon. World sets the uniforms from the sun's place (see `paint`).
##
## No class_name: World preloads it as `Atmosphere`, so it works before the
## editor has rescanned the project for new class names.

const SKY := """
shader_type sky;

uniform vec3 sun_dir = vec3(0.0, 0.6, -0.8);
uniform vec3 moon_dir = vec3(0.0, 0.6, 0.8);
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.9);
uniform float day : hint_range(0.0, 1.0) = 1.0;
uniform float dusk : hint_range(0.0, 1.0) = 0.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec3 haze_color : source_color = vec3(0.62, 0.78, 0.92);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.42;
uniform vec2 cloud_offset = vec2(0.0);

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * noise2(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return s;
}

// The sky's own colour in direction d, before sun, clouds and stars.
vec3 base_sky(vec3 d, vec3 s) {
	float up = max(d.y, 0.0);
	vec2 dh = normalize(d.xz + vec2(1e-5, 0.0));
	vec2 sh = normalize(s.xz + vec2(1e-5, 0.0));
	float toward = dot(dh, sh) * 0.5 + 0.5;

	vec3 zen_day = vec3(0.13, 0.36, 0.84);
	vec3 hor_day = vec3(0.60, 0.78, 0.95);
	vec3 zen_dusk = vec3(0.12, 0.20, 0.46);
	vec3 hor_sun = vec3(1.0, 0.48, 0.18);
	vec3 hor_away = vec3(0.46, 0.40, 0.62);
	vec3 zen_night = vec3(0.006, 0.010, 0.030);
	vec3 hor_night = vec3(0.025, 0.040, 0.085);

	vec3 hor_dusk = mix(hor_away, hor_sun, pow(toward, 3.0));
	vec3 zen = mix(zen_night, mix(zen_day, zen_dusk, dusk), day);
	vec3 hor = mix(hor_night, mix(hor_day, hor_dusk, dusk), day);
	// At either end of the day the colour stays low down, under a blue sky.
	vec3 col = mix(zen, hor, pow(1.0 - up, mix(4.0, 6.5, dusk)));
	// The glowing band low on the sun's side at either end of the day.
	col += vec3(1.0, 0.32, 0.06) * exp(-up * 12.0) * pow(toward, 6.0) * dusk * mix(0.3, 0.6, day);
	// Pink just above it, fading up into the blue.
	col += vec3(0.9, 0.35, 0.45) * exp(-up * 4.0) * (1.0 - exp(-up * 14.0)) * pow(toward, 2.0) * dusk * 0.25;
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 s = normalize(sun_dir);
	vec3 col = base_sky(d, s);

	// Below the horizon there is only haze (the land covers the rest).
	if (d.y < 0.0) {
		col = mix(col, haze_color, clamp(-d.y * 6.0, 0.0, 1.0));
	}

	float above = smoothstep(-0.02, 0.02, d.y);
	float cs = dot(d, s);
	float sun_up = smoothstep(-0.12, 0.02, s.y);
	// The halo round the sun, wider and warmer when it is low.
	float halo = pow(max(cs, 0.0), mix(18.0, 11.0, dusk)) * mix(0.18, 0.32, dusk) + pow(max(cs, 0.0), 300.0) * 0.9;
	col += sun_color * halo * sun_up;

	if (!AT_CUBEMAP_PASS) {
		// Stars, twinkling, only once it is dark.
		if (night > 0.01 && d.y > 0.0) {
			vec3 sp = d * 260.0;
			vec3 cell = floor(sp);
			float h = hash3(cell);
			if (h > 0.9968) {
				vec3 centre = cell + 0.5 + (vec3(hash3(cell + 1.3), hash3(cell + 2.7), hash3(cell + 4.1)) - 0.5) * 0.5;
				float star = smoothstep(0.32, 0.0, length(sp - centre));
				float bright = (h - 0.9968) / 0.0032;
				// Each star its own brightness (no TIME here: a sky that uses it is
				// redrawn into the reflections every frame).
				float twinkle = 0.55 + 0.45 * fract(h * 7919.0);
				col += vec3(1.0, 0.94, 0.86) * star * (0.4 + 1.6 * bright) * twinkle * night * smoothstep(0.0, 0.25, d.y);
			}
		}
		// The moon: a pale disc with darker seas on it.
		vec3 m = normalize(moon_dir);
		float cm = dot(d, m);
		float moon = smoothstep(0.99955, 0.99972, cm);
		if (moon > 0.0) {
			vec3 side = normalize(cross(m, vec3(0.0, 1.0, 0.0)));
			vec3 upv = cross(side, m);
			vec2 mp = vec2(dot(d - m, side), dot(d - m, upv)) * 400.0;
			float seas = smoothstep(0.45, 0.75, noise2(mp * 0.9 + 3.0)) * 0.35;
			col = mix(col, vec3(0.92, 0.94, 1.0) * (1.6 - seas), moon * night * above);
		}
		col += vec3(0.5, 0.6, 0.9) * pow(max(cm, 0.0), 80.0) * 0.12 * night;
		// The sun itself, far brighter than anything else in the sky.
		float disc = smoothstep(0.99986, 0.99993, cs);
		// Bright, but not so bright that the bloom blows it up into a ball.
		col += sun_color * disc * 6.0 * sun_up * above;
	}

	// Clouds on a dome overhead, drifting, lit from the sun's side.
	if (d.y > 0.0) {
		vec2 sh = normalize(s.xz + vec2(1e-5, 0.0));
		vec2 uv = d.xz / (d.y * 0.85 + 0.12) * 0.55 + cloud_offset;
		float n = fbm(uv * 1.3);
		float density = smoothstep(1.0 - cloud_cover - 0.12, 1.0 - cloud_cover + 0.28, n);
		if (density > 0.001) {
			float toward_sun = fbm(uv * 1.3 + sh * 0.09);
			float lit = clamp(0.55 + (n - toward_sun) * 4.0, 0.0, 1.0);
			vec3 shade = mix(vec3(0.03, 0.035, 0.06), mix(vec3(0.60, 0.66, 0.76), vec3(0.34, 0.25, 0.36), dusk), day);
			// At sunset the undersides catch the low sun: gold and pink, dimming
			// to ember as it goes down.
			vec3 sunset_lit = mix(sun_color * vec3(1.2, 0.95, 0.85), vec3(0.95, 0.58, 0.62), 0.35) * mix(0.45, 1.0, smoothstep(-0.10, 0.08, s.y));
			vec3 light = mix(vec3(0.10, 0.12, 0.17), mix(vec3(1.0, 0.99, 0.97), sunset_lit, dusk), day);
			vec3 cloud = mix(shade, light, lit);
			// Bright edges round the sun.
			cloud += sun_color * pow(max(cs, 0.0), 8.0) * (1.0 - density) * 1.2 * sun_up;
			float fade = smoothstep(0.0, 0.18, d.y);
			col = mix(col, cloud, density * fade * 0.96);
		}
	}
	// The reflections never see anything brighter than white: a hot spot
	// there flares off every shiny surface into a ball in the bloom.
	if (AT_CUBEMAP_PASS) {
		col = min(col, vec3(1.0));
	}
	COLOR = col;
}
"""

## A sky material made from SKY.
static func sky_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SKY
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat

## Where the sun is, as a direction towards it, for an elevation and an
## azimuth in degrees (the same way round as the sun light is turned).
static func direction(elevation: float, azimuth: float) -> Vector3:
	return Basis.from_euler(Vector3(deg_to_rad(-elevation), deg_to_rad(azimuth), 0.0)).z

## The sunlight's colour for the sun's height (sin of its elevation): deep
## orange at the horizon, through gold, to near white from mid-morning.
static func sun_colour(h: float) -> Color:
	var low := Color(1.0, 0.42, 0.16)
	var gold := Color(1.0, 0.72, 0.46)
	var noon := Color(1.0, 0.96, 0.90)
	if h < 0.12:
		return low.lerp(gold, clampf(h / 0.12, 0.0, 1.0))
	return gold.lerp(noon, smoothstep(0.12, 0.45, h))

## How golden the hour is: strongest with the sun on the horizon, gone by
## mid-morning and once it is properly dark.
static func dusk_amount(h: float) -> float:
	return clampf(1.0 - smoothstep(0.0, 0.32, h), 0.0, 1.0) * smoothstep(-0.22, -0.04, h)

## The horizon's colour all round (what the haze takes), matching the sky.
static func horizon_colour(day: float, dusk: float) -> Color:
	var hor_day := Color(0.60, 0.78, 0.95)
	var hor_dusk := Color(0.78, 0.50, 0.46)
	var hor_night := Color(0.025, 0.040, 0.085)
	return hor_night.lerp(hor_day.lerp(hor_dusk, dusk), day)
