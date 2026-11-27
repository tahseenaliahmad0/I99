shader_type canvas_item;
// Mirrored cabin (GDD 17.1): "Mirrors the screen for left-handed mouse
// users." Everything drawn before this layer (the road, the cabin, the post
// effects) is shown left to right reversed. What is drawn after it (the
// subtitles, the numeric HUD) reads as always.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

void fragment() {
	COLOR = texture(screen_texture, vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y));
}
