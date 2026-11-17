// World bend (GDD 13.5): the simulation road is always straight; curves are
// drawn by bending the world sideways with distance ahead of the car.
// Used by everything outside the cabin: road, vehicles, roadside props.
//
// The bend and the haze are global shader parameters (project settings,
// shader_globals), so every material that uses this shader follows them,
// an artist's scene included.
shader_type spatial;
render_mode unshaded, world_vertex_coords;

// Flat placeholder colour (GDD 16.1).
uniform vec4 albedo : source_color = vec4(1.0);
// 1 for a light (head lamp, tail lamp, beacon): seen through dark and haze.
uniform float lit = 0.0;

// Sideways offset per metre ahead, squared (1/m). Positive bends to the right.
global uniform float world_bend;
// World z of the car: distance ahead is measured from here toward -Z.
global uniform float world_bend_origin_z;
// What he cannot see fades into this colour between these distances (m).
global uniform vec4 world_fog_color : source_color;
global uniform float world_fog_near;
global uniform float world_fog_far;

varying float away;

void vertex() {
	float ahead = world_bend_origin_z - VERTEX.z;
	// How far from the car, which is at the world's origin across the road.
	away = length(vec2(VERTEX.x, ahead));
	float bent = max(0.0, ahead);
	VERTEX.x += world_bend * bent * bent;
}

void fragment() {
	float hidden = smoothstep(world_fog_near, world_fog_far, away) * (1.0 - lit);
	ALBEDO = mix(albedo.rgb, world_fog_color.rgb, hidden);
}
