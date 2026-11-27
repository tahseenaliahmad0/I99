// The cabin's picture, smeared as the rain smears the view (GDD 16.4; a
// helper of post_fx.gdshader, drawn by PostFxView in a picture of its own,
// never on the screen).
//
// The rain's blur reads the view from a mipmap, and a texel of a mipmap is
// a mix of whatever it covers: the world behind the glass and what of the
// cabin stands before it. To take the cabin out of that mix again, the post
// effects need the cabin's picture from the very same mipmap. This shader
// gives it: over a copy of the cabin's picture it writes that picture's
// mipmap of the level the blur reads now (the same arithmetic as in
// post_fx.gdshader, and the same numbers).
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
// How blurred the rain has made the windscreen (the post effects' uniform),
// and the share of the view's height over which the fully blurred view is
// smeared (postfx_rain_blur_radius).
uniform float rain_blur : hint_range(0.0, 1.0) = 0.0;
uniform float rain_blur_radius;

void fragment() {
	float radius = rain_blur * rain_blur_radius;
	float level = max(log2(max(radius / SCREEN_PIXEL_SIZE.y, 1.0)) - 1.0, 0.0);
	COLOR = textureLod(screen_texture, SCREEN_UV, level);
}
