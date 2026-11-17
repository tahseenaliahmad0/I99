// Post effects (GDD 16.4, 13.5): the one full-screen shader. It is drawn on
// the PostFX CanvasLayer, over the 3D view and under the pointer, the
// subtitles and the numeric HUD, and shows what the snapshot says of the
// glass and of his eyes (GDD 5.8, 16.3).
//
// What is of the glass (haze, rain, cracks) is drawn only where he looks
// through the windscreen, and what is of the world outside (the night, a
// light that dazzles) in full only where he looks out of a window: the
// cabin stays readable. A canvas shader cannot read the depth of the 3D
// view, so the glass is found by geometry: the ray through each pixel is
// taken into the cabin frame and met with the panes, which are rectangles
// there, and with what the cabin hangs before them.
//
// Everything here works in the Compatibility renderer as well as in
// Forward+ and Mobile: the screen texture and its mipmaps (the blur), and
// arithmetic. Every number comes from data/tuning.json through PostFxView.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// --- The nine uniforms of GDD 16.4, from the snapshot, every frame -----------
// How far the view has narrowed toward tunnel_min_view, 0 to 1.
uniform float tunnel : hint_range(0.0, 1.0) = 0.0;
// Share of the view each dark bar covers, from the top and from the bottom.
uniform float lids : hint_range(0.0, 0.5) = 0.0;
// 0 with his eyes open, 1 with his eyes shut.
uniform float blink : hint_range(0.0, 1.0) = 0.0;
// How clouded the windscreen is: the opacity of the veil.
uniform float haze : hint_range(0.0, 1.0) = 0.0;
// How blurred the rain has made the windscreen: 0 just wiped, 1 blurred.
uniform float rain_blur : hint_range(0.0, 1.0) = 0.0;
// Share of the windscreen the web of cracks covers.
uniform float cracks : hint_range(0.0, 1.0) = 0.0;
// How strong the wash of a dazzling light is at its middle, 0 to 1.
uniform float glare_amount : hint_range(0.0, 1.0) = 0.0;
// Where that light is in the picture (screen UV; it may lie outside it).
uniform vec2 glare_position = vec2(0.5, 0.5);
// Share of the light the night takes from what the headlights do not reach.
uniform float darkness : hint_range(0.0, 1.0) = 0.0;

// --- What goes with them, every frame ----------------------------------------
// 1 while it rains: streaks outside every window.
uniform float rain : hint_range(0.0, 1.0) = 0.0;
// Seconds of the simulation: moves the rain and the smoke.
uniform float fx_time = 0.0;
// How far the headlights reach, 1 at low beam: the size of their pool.
uniform float beam_reach = 1.0;
// Share of the light that sunglasses and tinted glass take at night, even
// where the headlights shine.
uniform float night_darker : hint_range(0.0, 1.0) = 0.0;
// The veil's colour now: smoke, or dust in a dust haze.
uniform vec3 haze_color : source_color;
// The camera in the cabin frame (origin at the wheel hub, +X toward the
// passenger, +Y up, +Z toward the driver): its axes, where the eye is, and
// the tangents of half its horizontal and vertical field of view.
uniform mat3 eye_basis = mat3(1.0);
uniform vec3 eye_origin = vec3(0.0);
uniform vec2 view_tan = vec2(1.0, 1.0);

// --- From data/tuning.json, through PostFxView -------------------------------
// These have no values of their own: a shader that was never set up shows
// nothing.

// The glass, in the cabin frame (m). The windscreen as the eye sees it:
// left, bottom, right, top; its plane's z.
uniform vec4 windscreen_rect;
uniform float windscreen_z;
// The side windows: front (z), bottom, back (z), top; their plane's x.
uniform vec4 window_left_rect;
uniform float window_left_x;
uniform vec4 window_right_rect;
uniform float window_right_x;
// Over this much glass an effect fades in at the window's frame.
uniform float glass_feather;
// How far above the dash the windscreen is still clear, and how far above it
// the windscreen's effects have their full strength.
uniform vec2 demist_strip;
// What of the cabin hangs before the glass (the mirror, the visor): each a
// rectangle (left, bottom, right, top) in a plane of its own z. Every frame.
const int MAX_BLINDS = 4;
uniform int blind_count = 0;
uniform vec4 blind_rect[MAX_BLINDS];
uniform float blind_z[MAX_BLINDS];

// Tunnel (GDD 5.8).
uniform vec3 tunnel_color : source_color;
uniform float tunnel_strength;
uniform float tunnel_feather;
uniform float tunnel_onset;
uniform float tunnel_min_view;

// Lids and Blink.
uniform vec3 lid_color : source_color;
uniform float lid_feather;
uniform float lid_curve;

// Haze.
uniform float haze_mottle;
uniform float haze_patch;
uniform float haze_drift;

// Rain.
uniform float rain_blur_radius;
uniform vec3 rain_streak_color : source_color;
uniform float rain_streak_alpha;
uniform float rain_streak_speed;
uniform float rain_streak_slant;
uniform vec2 rain_streak_density;
uniform float rain_streak_width;

// Cracks.
uniform vec2 crack_center;
uniform vec3 crack_color : source_color;
uniform float crack_alpha;
uniform float crack_width;
uniform float crack_spokes;
uniform float crack_shift;
uniform float crack_frost;
uniform float crack_core;
uniform float crack_fray;

// Glare.
uniform vec3 glare_color : source_color;
uniform float glare_radius;
uniform float glare_core;
uniform float glare_cabin_share;

// Darkness. The headlights' pool, as tangents of angles from straight
// ahead: where its middle is (right, up) and half its width and height at
// low beam.
uniform vec3 darkness_color : source_color;
uniform float cabin_darkness_share;
uniform vec2 beam_aim;
uniform vec2 beam_size;
uniform float beam_feather;


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Smooth noise, 0 to 1, one lump per unit of `p`.
float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 w = f * f * (3.0 - 2.0 * f);
	float a = hash12(cell);
	float b = hash12(cell + vec2(1.0, 0.0));
	float c = hash12(cell + vec2(0.0, 1.0));
	float d = hash12(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

// 1 inside the rectangle (min.xy, max.xy) and 0 outside it, passing from
// the one to the other over `feather`: across its edge with `grown` 0,
// wholly outside its edge with `grown` 1.
float inside_rect(vec2 at, vec4 rect, float feather, float grown) {
	vec2 margin = min(at - rect.xy, rect.zw - at);
	float soft = max(feather, 0.0001);
	float from = -0.5 * soft * (1.0 + grown);
	return smoothstep(from, from + soft, min(margin.x, margin.y));
}

// Falling rain: thin slanted streaks in two sizes. `p` is in view heights.
float rain_streaks(vec2 p, float time) {
	float sum = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		float grow = 1.0 + 0.6 * float(layer);
		vec2 q = vec2(p.x - p.y * rain_streak_slant, p.y - time * rain_streak_speed * grow);
		q *= rain_streak_density / grow;
		vec2 id = floor(q) + 37.0 * float(layer);
		vec2 f = fract(q);
		// Two cells in five hold a streak, somewhere across the cell.
		float held = step(0.6, hash12(id));
		float across = abs(f.x - 0.25 - 0.5 * hash12(id + 11.0));
		float wide = max(rain_streak_width, 0.0001);
		float body = 1.0 - smoothstep(0.5 * wide, wide, across);
		float taper = smoothstep(0.0, 0.35, f.y) * (1.0 - smoothstep(0.65, 1.0, f.y));
		sum += held * body * taper / grow;
	}
	return min(sum, 1.0);
}

// Where the shard of glass of cell `id` has its middle, 0 to 1 each way.
// The web closes on itself around the impact: `around` cells make a turn.
vec2 shard_middle(vec2 id, float around) {
	return hash22(vec2(id.x, mod(id.y, around)));
}

// The web of a cracked windscreen around its point of impact. `d` is the way
// from that point (m on the glass), `radius` the web's reach. Returns how
// much of a crack this spot is, 0 to 1; `shard` is a number of the shard of
// glass the spot lies on (-0.5 to 0.5 each way), `core` how near the impact.
float crack_web(vec2 d, float radius, out vec2 shard, out float core) {
	shard = vec2(0.0);
	core = 0.0;
	float r = length(d) / radius;
	if (r >= 1.0 || r <= 0.0001) {
		return 0.0;
	}
	// Log-polar cells: equal steps are equal ratios of distance, so the
	// shards grow with their distance from the impact, as in broken glass.
	float around = max(floor(crack_spokes), 3.0);
	vec2 p = vec2(log(r) * around / TAU, (atan(d.y, d.x) / TAU + 0.5) * around);
	vec2 cell = floor(p);
	vec2 f = fract(p);
	// The shard this spot lies on: the one whose middle is nearest.
	vec2 own_cell = vec2(0.0);
	vec2 to_own = vec2(0.0);
	float nearest = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 to = g + shard_middle(cell + g, around) - f;
			float dist = dot(to, to);
			if (dist < nearest) {
				nearest = dist;
				to_own = to;
				own_cell = g;
			}
		}
	}
	// A crack runs where two shards meet: how far is the nearest such line?
	float border = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = own_cell + vec2(float(i), float(j));
			vec2 to = g + shard_middle(cell + g, around) - f;
			vec2 between = to - to_own;
			if (dot(between, between) > 0.00001) {
				border = min(border, dot(0.5 * (to_own + to), normalize(between)));
			}
		}
	}
	vec2 own_id = cell + own_cell;
	shard = hash22(vec2(own_id.x, mod(own_id.y, around)) + 17.0) - 0.5;
	core = 1.0 - smoothstep(0.0, max(crack_core, 0.001), r);
	// One cell is this wide here (m), so the crack is this far (m):
	float to_crack = border * r * radius * TAU / around;
	float wide = max(crack_width, 0.00001);
	float line = 1.0 - smoothstep(0.5 * wide, wide, to_crack);
	// The web ends raggedly: each shard a little nearer or further.
	float fray = max(crack_fray, 0.001);
	float rim = 1.0 - smoothstep(1.0 - fray, 1.0, r + fray * (shard.x + 0.5));
	return line * rim;
}


void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	// The ray through this pixel, in the cabin frame; -Z is ahead.
	vec3 ray = eye_basis * vec3(vec2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0) * view_tan, -1.0);

	// --- Where the glass is -------------------------------------------------
	// windscreen: 1 where he looks through the windscreen's glass, less over
	// the strip above the dash. outside: 1 where he looks out of any window;
	// it reaches a feather onto the window's frame, so that no rim of the
	// world is left out of the night.
	float windscreen = 0.0;
	float outside = 0.0;
	vec2 glass_at = vec2(0.0);
	if (ray.z < -0.0001) {
		glass_at = eye_origin.xy + ray.xy * (windscreen_z - eye_origin.z) / ray.z;
		outside = inside_rect(glass_at, windscreen_rect, glass_feather, 1.0);
		windscreen = inside_rect(glass_at, windscreen_rect, glass_feather, 0.0)
				* smoothstep(demist_strip.x, max(demist_strip.y, demist_strip.x + 0.0001), glass_at.y - windscreen_rect.y);
	}
	if (ray.x < -0.0001) {
		vec2 at = eye_origin.zy + ray.zy * (window_left_x - eye_origin.x) / ray.x;
		outside = max(outside, inside_rect(at, window_left_rect, glass_feather, 1.0));
	}
	if (ray.x > 0.0001) {
		vec2 at = eye_origin.zy + ray.zy * (window_right_x - eye_origin.x) / ray.x;
		outside = max(outside, inside_rect(at, window_right_rect, glass_feather, 1.0));
	}
	// What hangs before the glass is of the cabin, not of the glass.
	if (ray.z < -0.0001 && outside > 0.0) {
		float covered = 0.0;
		for (int i = 0; i < MAX_BLINDS; i++) {
			if (i < blind_count) {
				vec2 at = eye_origin.xy + ray.xy * (blind_z[i] - eye_origin.z) / ray.z;
				covered = max(covered, inside_rect(at, blind_rect[i], glass_feather, 0.0));
			}
		}
		windscreen *= 1.0 - covered;
		outside *= 1.0 - covered;
	}

	// --- Cracks (GDD 5.8, 6.3): a web over a share of the windscreen ---------
	vec2 look_uv = uv;
	float crack_line = 0.0;
	float crack_dust = 0.0;
	if (cracks > 0.0005 && windscreen > 0.0) {
		// The web is a disc as large as that share of the windscreen.
		vec2 size = windscreen_rect.zw - windscreen_rect.xy;
		float radius = max(sqrt(cracks * size.x * size.y / PI), 0.0001);
		vec2 from_impact = glass_at - (windscreen_rect.xy + crack_center * size);
		vec2 shard;
		crack_line = crack_web(from_impact, radius, shard, crack_dust) * windscreen;
		crack_dust *= windscreen;
		// Each shard shows what is behind it a little out of place.
		float in_web = 1.0 - smoothstep(1.0 - max(crack_fray, 0.001), 1.0, length(from_impact) / radius);
		look_uv += shard * crack_shift * in_web * windscreen * vec2(1.0 / aspect, 1.0);
	}

	// --- Rain on the glass: the view blurs between wiper sweeps (GDD 9.1) ----
	vec3 col;
	float blur = rain_blur * windscreen;
	if (blur > 0.001) {
		// The radius in shares of the view's height, and the mipmap level
		// whose texels are about half of it wide.
		float radius = blur * rain_blur_radius;
		float level = max(log2(max(radius / SCREEN_PIXEL_SIZE.y, 1.0)) - 1.0, 0.0);
		vec2 reach = vec2(radius / aspect, radius) * 0.5;
		col = textureLod(screen_texture, look_uv, level).rgb * 0.36;
		col += textureLod(screen_texture, look_uv + reach * vec2(1.0, 0.4), level).rgb * 0.16;
		col += textureLod(screen_texture, look_uv + reach * vec2(-0.4, 1.0), level).rgb * 0.16;
		col += textureLod(screen_texture, look_uv + reach * vec2(-1.0, -0.4), level).rgb * 0.16;
		col += textureLod(screen_texture, look_uv + reach * vec2(0.4, -1.0), level).rgb * 0.16;
	} else {
		col = textureLod(screen_texture, look_uv, 0.0).rgb;
	}

	// --- Rain in the air: streaks outside every window ------------------------
	if (rain > 0.001 && outside > 0.0) {
		float streak = rain_streaks(vec2(uv.x * aspect, uv.y), fx_time);
		col = mix(col, rain_streak_color, streak * rain * outside * rain_streak_alpha);
	}

	// --- Haze (GDD 5.8): the windscreen clouds --------------------------------
	if (haze > 0.0005 && windscreen > 0.0) {
		// Patches where it is thinner; never thicker than the snapshot says.
		vec2 patch_at = glass_at / max(haze_patch, 0.001) + vec2(fx_time * haze_drift, 0.0);
		float thin = 0.65 * value_noise(patch_at) + 0.35 * value_noise(patch_at * 2.7 + 13.0);
		col = mix(col, haze_color, haze * windscreen * (1.0 - haze_mottle * thin));
	}

	// The cracks themselves, and the crushed glass at the impact.
	if (crack_line > 0.0 || crack_dust > 0.0) {
		col = mix(col, crack_color, max(crack_line * crack_alpha, crack_dust * crack_frost));
	}

	// --- Darkness (GDD 9.1): the night outside the headlights' pool ----------
	if (darkness > 0.0005) {
		float lit = 0.0;
		if (ray.z < -0.0001) {
			vec2 off = (ray.xy / -ray.z - beam_aim) / max(beam_size * beam_reach, vec2(0.0001));
			float soft = clamp(beam_feather, 0.001, 1.0);
			lit = 1.0 - smoothstep(1.0 - soft, 1.0 + soft, length(off));
		}
		// Where the headlights shine, only what he wears and what the glass
		// is tinted with takes light. The cabin has its dashboard's glow:
		// it takes a share of the dark.
		float taken = mix(darkness, night_darker, lit);
		col = mix(col, darkness_color, mix(darkness * cabin_darkness_share, taken, outside));
	}

	// --- Glare (GDD 5.8): a bright wash around the light ----------------------
	if (glare_amount > 0.0005) {
		// The wash is strongest at the light and falls away from it; the
		// light itself is a small blaze in its middle.
		vec2 away = (uv - glare_position) * vec2(aspect, 1.0);
		float apart = dot(away, away);
		float wash = glare_amount * exp(-apart / max(glare_radius * glare_radius, 0.0001));
		float blaze = glare_amount * exp(-apart / max(glare_core * glare_core, 0.0001));
		float dazzle = 1.0 - (1.0 - wash) * (1.0 - blaze);
		col = mix(col, glare_color, clamp(dazzle * mix(glare_cabin_share, 1.0, outside), 0.0, 1.0));
	}

	// --- His eyes: over everything --------------------------------------------
	vec2 centred = uv * 2.0 - 1.0;
	// Tunnel (GDD 5.8): dark edges close in. What is left of the view is an
	// ellipse, the whole view when Tunnel begins and tunnel_min_view of it
	// at its worst; the dark comes up over the first part of the way, so
	// that nothing jumps as his Nerves pass the threshold.
	if (tunnel > 0.0005) {
		float open = mix(1.0, tunnel_min_view, tunnel);
		float edge = smoothstep(open, open + max(tunnel_feather, 0.001), length(centred));
		col = mix(col, tunnel_color, edge * tunnel_strength * smoothstep(0.0, max(tunnel_onset, 0.001), tunnel));
	}
	// Lids and Blink (GDD 5.8): dark bars from the top and the bottom, which
	// meet when his eyes are shut.
	float lid_soft = max(lid_feather, 0.001);
	float cover = mix(lids, 0.5 + lid_soft, blink);
	if (cover > 0.0005) {
		// A lid reaches further at the sides of the view than in its middle.
		cover *= 1.0 + lid_curve * centred.x * centred.x;
		float lid = 1.0 - smoothstep(cover - lid_soft, cover, min(uv.y, 1.0 - uv.y));
		col = mix(col, lid_color, lid);
	}

	COLOR = vec4(col, 1.0);
}
