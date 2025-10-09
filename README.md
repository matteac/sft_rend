# sft_rend
This lets you draw pixels to a window without messing with OpenGL directly.

# Getting Started
Here's how to get a window up and running. This example draws a movable circle and a static rectangle.
```odin
package main

import "core:fmt"
import "vendor:glfw"

import "input"
import ren "renderer"

main :: proc() {
	handle, ok, err_str := ren.init(800, 600, "Renderer Example", false)
	input.init(handle)

	ok, err_str = ren.init_font("assets/VT323-Regular.ttf")

	SPEED :: 200
	BACKGROUND_COLOR :: ren.Color{15, 15, 20, 255}
	RECT_COLOR :: ren.Color{220, 70, 70, 255}
	CIRCLE_COLOR :: ren.Color{70, 70, 220, 255}
	TEXT_COLOR :: ren.Color{220, 220, 220, 255}


	circle := ren.Circlef{300, 300, 80}

	show_outline := false

	for ren.is_running() {
		delta := ren.get_delta_time()

		input.poll_events()

		if input.is_key_pressed(glfw.KEY_SPACE) {
			show_outline = !show_outline
		}

		if input.is_key_down(glfw.KEY_A) {
			circle.x -= SPEED * delta
		}
		if input.is_key_down(glfw.KEY_D) {
			circle.x += SPEED * delta
		}
		if input.is_key_down(glfw.KEY_W) {
			circle.y -= SPEED * delta
		}
		if input.is_key_down(glfw.KEY_S) {
			circle.y += SPEED * delta
		}


		ren.clear(BACKGROUND_COLOR)

		if show_outline {
			ren.draw_rect(100, 100, 200, 150, 1, RECT_COLOR)
			ren.draw_circle(circle.x, circle.y, circle.radius, 1, CIRCLE_COLOR)
		} else {
			ren.fill_rect(100, 100, 200, 150, RECT_COLOR)
			ren.fill_circle(circle.x, circle.y, circle.radius, CIRCLE_COLOR)
		}

		ren.draw_text("Renderer Example", 20, 20, 32, TEXT_COLOR)
		ren.draw_text("Press SPACE to show outline", 20, 60, 24, TEXT_COLOR)
		ren.present()
	}
}
```

# API

## Renderer
### Core
- `init(width, height, title, vsync = true)`: Inits glfw/gl and creates a window. `vsync` is optional and defaults to `true`.
- `present()`: Copies the framebuffer to the screen.
- `is_running()`: Returns `true` if the window is open.
- `get_size()`: Returns the window's [width, height] as a `Vec2f`.
- `get_delta_time()`: Returns the delta time in seconds.
### Rendering
- `clear(color)`: Fills the screen with one color.
- `draw_pixel(x, y, color)`: Draws a single pixel.
- `draw_rect(x, y, w, h, thickness, color)`: Draws the outline of a rectangle.
- `fill_rect(x, y, w, h, color)`: Draws a filled rectangle.
- `draw_circle(cx, cy, radius, thickness, color)`: Draws the outline of a circle.
- `fill_circle(cx, cy, radius, color)`: Draws a filled circle.
- `draw_line(x1, y1, x2, y2, thickness, color)`: Draws a line between two points.
- `draw_triangle(v1, v2, v3, thickness, color)`: Draws the outline of a triangle.
- `fill_triangle(v1, v2, v3, color)`: Draws a filled triangle.
### Text Rendering (stb_truetype)
- `init_font(path)`: Inits a font from a `.ttf` file for drawing text.
- `init_font_from_data(data)`: Inits a font from a `[]u8` in memory.
- `draw_text(text, x, y, size, color)`: Draws text using the previously initialized font.
### Texture rendering
- `load_texture(path)`: Loads a texture from an image. Uses `stb_image` to decode the image into a texture.
- `load_texture_from_data(data)`: Loads a texture from a `[]u8` in memory. Uses `stb_image` to decode the bytes into a texture.
- `draw_texture(x, y, texture)`: Draws a texture at its original scale.


## Input
- `init(handle)`: Initializes the input system. Get the `handle` from `renderer.init(...)`.
- `poll_events()`: Updates the state of all keys and buttons and polls events from glfw.
### Keyboard
- `is_key_down(key)`: Returns `true` if the key is being held down.
- `is_key_up(key)`: Returns `true` if the key is not being held down.
- `is_key_pressed(key)`: Returns `true` for the single tick the key is pressed.
- `is_key_released(key)`: Returns `true` for the single tick the key is released.
### Mouse
- `get_mouse_pos()`: Returns the mouse [x, y] as a `Vec2f`.
- `is_mouse_button_down(button)`: Returns `true` if the button is being held down.
- `is_mouse_button_up(button)`: Returns `true` if the button is not being held down.
- `is_mouse_button_pressed(button)`: Returns `true` for the single tick the button is pressed.
- `is_mouse_button_released(button)`: Returns `true` for the single tick the button is released.

# How it works
The package keeps a global `Renderer` state with a 32bit per pixel framebuffer in memory. When you call `draw_` or `fill_`, you're just changing pixels in the framebuffer.
When you call `present()`, it takes that framebuffer and copies it to the GPU to be displayed.

# Build
You need to have GLFW installed. Then just run:
```bash
odin build .
```

# Todo
- More shapes
- Move error handling to [`Maybe(T)`](https://odin-lang.org/docs/overview/#maybet)
<!-- - Alpha blending -->
<!-- - Text drawing -->


# Credits
- Font VT323 [Peter Hull](peter.hull@oikoi.com)
- Font Cotham Sans [Sebastien Sanfilippo](www.love-letters.be)
- Mushroom Sprite Pack [Peter Field](peterfield2006.itch.io)
