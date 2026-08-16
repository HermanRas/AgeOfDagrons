// Rim of a sprite, in a flat colour -- what a unit hidden behind a building is
// drawn as, so the player can see somebody is back there (PLAN.md 3.1).
//
// SAMPLES ONLY INSIDE ITS OWN ATLAS FRAME. Every sprite here is a region of a
// shared atlas page, so a naive neighbour-sample walks straight into whatever
// frame was packed next door and rims the unit with pieces of another animation.
// `region_min`/`region_max` are this frame's bounds in UV, and `frame_alpha`
// returns 0 outside them -- which is also what lets the outline be drawn on a
// rect EXPANDED past the frame, where the rim actually has to live: isobake
// crops frames tight, so there is no transparent margin inside one to draw into.
shader_type canvas_item;
render_mode unshaded;

uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec2 region_min = vec2(0.0);
uniform vec2 region_max = vec2(1.0);
uniform float width_px = 2.0;

// `tex` is passed in rather than read from the built-in: Godot's shading
// language does not expose TEXTURE (or any other built-in) inside a
// user-defined function, only in the stage that declares it.
float frame_alpha(sampler2D tex, vec2 uv) {
	if (uv.x < region_min.x || uv.y < region_min.y
			|| uv.x > region_max.x || uv.y > region_max.y) {
		return 0.0;
	}
	return texture(tex, uv).a;
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * width_px;
	float here = frame_alpha(TEXTURE, UV);

	// Eight neighbours, not four: with only the axes, every diagonal edge comes
	// out notched, which at 40 px reads as a damaged sprite rather than an
	// outline.
	float near = 0.0;
	near = max(near, frame_alpha(TEXTURE, UV + vec2(px.x, 0.0)));
	near = max(near, frame_alpha(TEXTURE, UV - vec2(px.x, 0.0)));
	near = max(near, frame_alpha(TEXTURE, UV + vec2(0.0, px.y)));
	near = max(near, frame_alpha(TEXTURE, UV - vec2(0.0, px.y)));
	near = max(near, frame_alpha(TEXTURE, UV + px));
	near = max(near, frame_alpha(TEXTURE, UV - px));
	near = max(near, frame_alpha(TEXTURE, UV + vec2(px.x, -px.y)));
	near = max(near, frame_alpha(TEXTURE, UV - vec2(px.x, -px.y)));

	// The rim is where the sprite is NOT but something next to it is.
	COLOR = vec4(line_color.rgb, near * (1.0 - here) * line_color.a);
}
