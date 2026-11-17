// World bend (GDD 13.5): the simulation road is always straight; curves are
// drawn by bending the world sideways with distance ahead of the car.
// Used by everything outside the cabin: road, vehicles, roadside props.
shader_type spatial;
render_mode unshaded, world_vertex_coords;

// Flat placeholder colour (GDD 16.1).
uniform vec4 albedo : source_color = vec4(1.0);
// Sideways offset per metre ahead, squared (1/m). Positive bends to the right.
uniform float bend = 0.0;
// World z of the car: distance ahead is measured from here toward -Z.
uniform float bend_origin_z = 0.0;

void vertex() {
	float ahead = max(0.0, bend_origin_z - VERTEX.z);
	VERTEX.x += bend * ahead * ahead;
}

void fragment() {
	ALBEDO = albedo.rgb;
}
