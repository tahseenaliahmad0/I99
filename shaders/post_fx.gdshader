// Post effects (GDD 16.4, 13.5): the one full-screen shader. It is drawn on
// the PostFX CanvasLayer, over the 3D view and under the pointer, the
// subtitles and the numeric HUD, and shows what the snapshot says of the
// glass and of his eyes (GDD 5.8, 16.3).
//
// What is of the glass (haze, rain, cracks) is drawn only where he looks
// through the windscreen, and what is of the world outside (the night, a
// light that dazzles, the falling rain) in full only where he sees the
// world: the cabin stays readable. A canvas shader cannot read the depth of
// the 3D view, so it is told the two apart. `cabin_mask` is a picture of the
// cabin alone, drawn once more from his eye (PostFxView): where it is solid
// the pixel is of the cabin, whatever stands there (his arm, the clock, what
// stands on the dash, a passenger, the vendor's tray). Everything else is
// the world. Which of it he sees through the windscreen is found by
// geometry: the ray through the pixel is taken into the cabin frame and met
// with the windscreen, which is a rectangle there. `cabin_smear` is the
// cabin's picture again, read from the mipmap the rain's blur reads the view
// from (post_fx_cabin.gdshader), so that the blur can leave the cabin out.
//
// Everything here works in the Compatibility renderer as well as in
// Forward+ and Mobile: the screen texture and its mipmaps (the blur), two
// more textures, and arithmetic.
//
// Every number that shapes what is seen comes from data/tuning.json through
// PostFxView. The numbers left here are the shader's own arithmetic: the
// hashes, the halves and doubles of geometry, the thresholds below which
// nothing is drawn or divided by, the offsets that keep two patterns apart
// (rain_streaks, the haze's finer patches, crack_web), and where the five
// taps of the blur lie (its middle and the four ends of a slightly turned
// cross, about half the radius out, on the mipmap whose texels are about
// half the radius wide).
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
// 1 while it rains: streaks over the world outside.
uniform float rain : hint_range(0.0, 1.0) = 0.0;
// Seconds of the simulation: moves the rain and the smoke.
uniform float fx_time = 0.0;
// How far the headlights reach, 1 at low beam: the size of their pool.
uniform float beam_reach = 1.0;
// Share of the light that sunglasses and tinted glass take at night, even
// where the headlights shine.
uniform float night_darker : hint_range(0.0, 1.0) = 0.0;
// The veil's colour now: smoke, or dust where dust is in the air (a dust
// haze, the Storm).
uniform vec3 haze_color : source_color;
// The camera in the cabin frame (origin at the wheel hub, +X toward the
// passenger, +Y up, +Z toward the driver): its axes, where the eye is, and
// the tangents of half its horizontal and vertical field of view.
uniform mat3 eye_basis = mat3(1.0);
uniform vec3 eye_origin = vec3(0.0);
uniform vec2 view_tan = vec2(1.0, 1.0);

// --- The cabin ----------------------------------------------------------------
// The cabin alone as his eye sees it, over nothing: its alpha says how much
// of the pixel is the cabin's. With no such picture nothing is of the cabin.
uniform sampler2D cabin_mask : hint_default_transparent, repeat_disable, filter_linear;
// The same picture from the mipmap the rain's blur reads the view from
// (post_fx_cabin.gdshader): the cabin's part of a blurred texel.
uniform sampler2D cabin_smear : hint_default_transparent, repeat_disable, filter_linear;

// --- From data/tuning.json, through PostFxView -------------------------------
// These have no values of their own: a shader that was never set up shows
// nothing.

// How solid what the cabin draws must be to count as the cabin: none of it
// below the first, all of it from the second (glass he sees through is not).
uniform vec2 cabin_solid;
// The windscreen's glass in the cabin frame (m), as the eye sees it: left,
// bottom, right, top; and its plane's z.
uniform vec4 windscreen_rect;
uniform float windscreen_z;
// Where the cabin's own frame does not end the windscreen, its effects fade
// out over this much glass (m).
uniform float glass_feather;

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

// Haze. haze_fine: the weight of the finer patches among all of them, and
// how many of them lie across a coarse one.
uniform float haze_mottle;
uniform float haze_patch;
uniform float haze_drift;
uniform vec2 haze_fine;

// Rain. rain_blur_center: the weight of the middle one of the blur's taps.
// rain_streak_far: how many times larger and faster the second layer of
// streaks is than the first.
uniform float rain_blur_radius;
uniform float rain_blur_center;
uniform vec3 rain_streak_color : source_color;
uniform float rain_streak_alpha;
uniform float rain_streak_speed;
uniform float rain_streak_slant;
uniform vec2 rain_streak_density;
uniform float rain_streak_width;
uniform float rain_streak_share;
uniform float rain_streak_taper;
uniform float rain_streak_far;

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

// The four taps of the blur around its middle: the ends of a turned cross.
const vec2 BLUR_TAPS[4] = { vec2(1.0, 0.4), vec2(-0.4, 1.0), vec2(-1.0, -0.4), vec2(0.4, -1.0) };
// The world's share of a smear below which eight-bit pictures leave too
// little of it to divide by: there the smear gives way to the sharp view.
const float SMEAR_FLOOR = 0.1;


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

// How much of the pixel at `at` (screen UV) is the cabin's, 0 to 1.
float cabin_at(vec2 at) {
	return smoothstep(cabin_solid.x, max(cabin_solid.y, cabin_solid.x + 0.0001), texture(cabin_mask, at).a);
}

// 1 inside the rectangle (min.xy, max.xy), passing to 0 over `feather`
// outside its edge.
float inside_rect(vec2 at, vec4 rect, float feather) {
	vec2 margin = min(at - rect.xy, rect.zw - at);
	return smoothstep(-max(feather, 0.0001), 0.0, min(margin.x, margin.y));
}

// Falling rain: thin slanted streaks in two sizes. `p` is in view heights.
float rain_streaks(vec2 p, float time) {
	float sum = 0.0;
	float wide = clamp(rain_streak_width, 0.0001, 0.5);
	float taper = clamp(rain_streak_taper, 0.0001, 0.5);
	for (int layer = 0; layer < 2; layer++) {
		float grow = mix(1.0, max(rain_streak_far, 0.0001), float(layer));
		vec2 q = vec2(p.x - p.y * rain_streak_slant, p.y - time * rain_streak_speed * grow);
		q *= rain_streak_density / grow;
		vec2 id = floor(q) + 37.0 * float(layer);
		vec2 f = fract(q);
		// That share of the cells hold a streak, somewhere across the cell
		// where the whole of it is inside.
		float held = step(1.0 - rain_streak_share, hash12(id));
		float across = abs(f.x - mix(wide, 1.0 - wide, hash12(id + 11.0)));
		float body = 1.0 - smoothstep(0.5 * wide, wide, across);
		float ends = smoothstep(0.0, taper, f.y) * (1.0 - smoothstep(1.0 - taper, 1.0, f.y));
		sum += held * body * ends / grow;
	}
	return min(sum, 1.0);
}

// Where the shard of glass of cell `id` has its middle, 0 to 1 each way.
// The web closes on itself around the impact: `around` cells make a turn.
vec2 shard_middle(vec2 id, float around) {
	return hash22(vec2(id.x, mod(id.y, around)));
}

// The web of a cracked windscreen around its point of impact. `d` is the way
// from that point (m on the glass), `radius` the reach of a web that covers
// its share. Returns how much of a crack this spot is, 0 to 1; `shard` is a
// number of the shard of glass the spot lies on (-0.5 to 0.5 each way; 0
// where the glass is whole), `core` how near the impact.
float crack_web(vec2 d, float radius, out vec2 shard, out float core) {
	shard = vec2(0.0);
	core = 0.0;
	float r = length(d) / radius;
	float fray = max(crack_fray, 0.001);
	float wide = max(crack_width, 0.00001);
	if (r >= 1.0 + 0.5 * fray + wide / radius || r <= 0.0001) {
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
	// The web ends raggedly: each shard a little short of the web's reach or
	// a little past it, so that on the whole the web covers its share. The
	// glass is cracked along the shard's end too, and whole beyond it.
	float to_end = (1.0 - fray * shard.x - r) * radius;
	if (to_end < 0.0) {
		shard = vec2(0.0);
		return 1.0 - smoothstep(0.5 * wide, wide, -to_end);
	}
	return 1.0 - smoothstep(0.5 * wide, wide, min(to_crack, to_end));
}


void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	// The ray through this pixel, in the cabin frame; -Z is ahead.
	vec3 ray = eye_basis * vec3(vec2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0) * view_tan, -1.0);

	// --- What is the cabin, what the world, and where the windscreen is ------
	// outside: how much of this pixel is the world, seen through a window or
	// past the cabin's edge. windscreen: how much of it he sees through the
	// windscreen's glass.
	float outside = 1.0 - cabin_at(uv);
	float windscreen = 0.0;
	vec2 glass_at = vec2(0.0);
	if (ray.z < -0.0001 && outside > 0.0) {
		glass_at = eye_origin.xy + ray.xy * (windscreen_z - eye_origin.z) / ray.z;
		windscreen = outside * inside_rect(glass_at, windscreen_rect, glass_feather);
	}

	// --- Cracks (GDD 5.8, 6.3): a web over a share of the windscreen ---------
	vec2 look_uv = uv;
	float crack_line = 0.0;
	float crack_dust = 0.0;
	if (cracks > 0.0005 && windscreen > 0.0) {
		// The web is as large as a disc of that share of the windscreen.
		vec2 size = windscreen_rect.zw - windscreen_rect.xy;
		float radius = max(sqrt(cracks * size.x * size.y / PI), 0.0001);
		vec2 from_impact = glass_at - (windscreen_rect.xy + crack_center * size);
		vec2 shard;
		crack_line = crack_web(from_impact, radius, shard, crack_dust) * windscreen;
		crack_dust *= windscreen;
		// Each shard shows the world behind it a little out of place, and
		// never the cabin there.
		vec2 shifted = uv + shard * crack_shift * windscreen * vec2(1.0 / aspect, 1.0);
		look_uv = mix(shifted, uv, cabin_at(shifted));
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
		// The glass smears the world, not what stands before it. A texel of
		// that mipmap is a mix of whatever it covers; cabin_smear is the
		// cabin's part of the very same texel (its colour, and in its alpha
		// its share), so that part is taken out again and what is left is
		// weighed by the world's share.
		float middle = clamp(rain_blur_center, 0.0001, 1.0);
		vec4 own = texture(cabin_smear, look_uv);
		vec3 world = (textureLod(screen_texture, look_uv, level).rgb - own.rgb) * middle;
		float share = (1.0 - own.a) * middle;
		for (int tap = 0; tap < 4; tap++) {
			vec2 at = look_uv + reach * BLUR_TAPS[tap];
			own = texture(cabin_smear, at);
			world += (textureLod(screen_texture, at, level).rgb - own.rgb) * 0.25 * (1.0 - middle);
			share += (1.0 - own.a) * 0.25 * (1.0 - middle);
		}
		// Where nothing but the cabin is near there is no world to smear.
		col = mix(textureLod(screen_texture, look_uv, 0.0).rgb, clamp(world / max(share, 0.0001), 0.0, 1.0), smoothstep(0.0, SMEAR_FLOOR, share));
	} else {
		col = textureLod(screen_texture, look_uv, 0.0).rgb;
	}

	// --- Rain in the air: streaks over the world outside ----------------------
	if (rain > 0.001 && outside > 0.0) {
		float streak = rain_streaks(vec2(uv.x * aspect, uv.y), fx_time);
		col = mix(col, rain_streak_color, streak * rain * outside * rain_streak_alpha);
	}

	// --- Haze (GDD 5.8): the windscreen clouds --------------------------------
	if (haze > 0.0005 && windscreen > 0.0) {
		// Patches where it is thinner and where it is thicker: over the whole
		// glass the veil is as thick as the snapshot says.
		vec2 patch_at = glass_at / max(haze_patch, 0.001) + vec2(fx_time * haze_drift, 0.0);
		float thin = mix(value_noise(patch_at), value_noise(patch_at * haze_fine.y + 13.0), haze_fine.x);
		col = mix(col, haze_color, clamp(haze * (1.0 + haze_mottle * (0.5 - thin)), 0.0, 1.0) * windscreen);
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
	// at its worst: its soft edge lies half inside that share and half
	// outside it. The dark comes up over the first part of the way, so that
	// nothing jumps as his Nerves pass the threshold.
	if (tunnel > 0.0005) {
		float open = mix(1.0, tunnel_min_view, tunnel);
		float soft = 0.5 * max(tunnel_feather, 0.001);
		float edge = smoothstep(open - soft, open + soft, length(centred));
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
