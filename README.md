# sft_rend
This lets you draw pixels to a window without messing with OpenGL directly.

# Getting Started
Here's how to get a window up and running. This example draws four red squares in the corners.
```odin
package main

import "core:fmt"
import ren "renderer"

main :: proc() {
	ok, err := ren.init(800, 600, "My App", false)
	if !ok {
		fmt.printfln("Error: %s", err)
		return
	}

	// 0xAABBGGRR
	gray: u32 = 0xff181818
	red: u32 = 0xff0000ff

	// Main loop
	for ren.is_running() {
		size := ren.get_size()

		// Draw stuff to a hidden framebuffer
		ren.clear(gray)
		ren.draw_rect(0, 0, 20, 20, red)
		ren.draw_rect(size.x - 20, 0, 20, 20, red)
		ren.draw_rect(0, size.y - 20, 20, 20, red)
		ren.draw_rect(size.x - 20, size.y - 20, 20, 20, red)

		ren.present()
	}
}
```

# API
- `init(width, height, title, vsync)`: Inits glfw/gl and creates a window.
- `is_running()`: Returns true if the window is open.
- `clear(color)``: Fills the screen with one color.
- `draw_rect(x, y, w, h, color)`: Draws a rectangle.
- `present()`: Copies the framebuffer to the screen.
- `get_size()`: Returns the window's [width, height].

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
- Alpha blending
- Input handling 
- Text drawing
