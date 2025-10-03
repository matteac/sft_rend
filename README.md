# sft_rend
This lets you draw pixels to a window without messing with OpenGL directly.

# Getting Started
Here's how to get a window up and running. This example draws four red squares in the corners.
```odin
package main

import "core:fmt"
import "input"
import ren "renderer"
import "vendor:glfw" // used for input constants

main :: proc() {
	handle, ok, err := ren.init(800, 600, "My App", false)
	if !ok {
		fmt.printfln("Error: %s", err)
		return
	}
	input.init(handle)

	// This uses stb_truetype, be careful with the font
	ok, err = ren.init_font("assets/VT323-Regular.ttf")
	if !ok {
		fmt.printfln("Error: %s", err)
		return
	}

	gray: ren.Color = {24, 24, 24, 255}
	red: ren.Color = {255, 0, 0, 128}

	size := ren.get_size()
	circle: ren.Circlef = {size.x / 2, size.y / 2, 16}
	circle_speed: f64 = 256

	// Main loop
	for ren.is_running() {
		delta := ren.get_delta_time()

		input.poll_events()
		size = ren.get_size()

		if input.is_key_down(glfw.KEY_A) {
			circle.x -= circle_speed * delta
		}
		if input.is_key_down(glfw.KEY_D) {
			circle.x += circle_speed * delta
		}
		if input.is_key_down(glfw.KEY_W) {
			circle.y -= circle_speed * delta
		}
		if input.is_key_down(glfw.KEY_S) {
			circle.y += circle_speed * delta
		}

		if input.is_mouse_button_down(glfw.MOUSE_BUTTON_LEFT) {
			mouse_pos := input.get_mouse_pos()
			circle.x, circle.y = mouse_pos.x, mouse_pos.y
		}

		// Draw stuff to a hidden framebuffer
		ren.clear(gray)
		ren.draw_text(fmt.tprintf("%dfps", cast(u32)(1 / delta)), 16, 16, 32, {0, 255, 0, 96})

		ren.draw_rect(0, 0, 48, 48, red, false)
		ren.draw_rect(size.x - 48, 0, 48, 48, red)
		ren.draw_rect(0, size.y - 48, 48, 48, red)
		ren.draw_rect(size.x - 48, size.y - 48, 48, 48, red, false)

		ren.draw_circle(circle.x, circle.y, circle.radius, {0, 0, 255, 128})

		ren.present()
	}
}

```

# API

## Renderer
- `init(width, height, title, vsync = true)`: Inits glfw/gl and creates a window. `vsync` is optional and defaults to `true`.
- `is_running()`: Returns `true` if the window is open.
- `clear(color)`: Fills the screen with one color.
- `draw_rect(x, y, w, h, color, fill = true)`: Draws a rectangle. `fill` is optional and defaults to `true`.
- `draw_circle(cx, cy, radius, color, fill = true)`: Draws a circle. `fill` is optional and defaults to `true`.
- `present()`: Copies the framebuffer to the screen.
- `get_size()`: Returns the window's [width, height] as a `Vec2f`.
- `get_delta_time()`: Returns the delta time in seconds.
### Text Rendering (stb_truetype)
- `init_font(path)`: Inits a font from a `.ttf` file for drawing text.
- `draw_text(text, x, y, size, color)`: Draws text using the previously initialized font.


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
The package keeps a global `Renderer` state with a 32bit per pixel framebuffer in memory. When you call `draw_rect`, you're just changing pixels in the framebuffer.
When you call `present()`, it takes that framebuffer and copies it to the GPU to be displayed.

# Build
You need to have GLFW installed. Then just run:
```bash
odin build .
```

# Todo
- More shapes
<!-- - Alpha blending -->
<!-- - Text drawing -->
