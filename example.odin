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
		ren.draw_rect(size[0] - 20, 0, 20, 20, red)
		ren.draw_rect(0, size[1] - 20, 20, 20, red)
		ren.draw_rect(size[0] - 20, size[1] - 20, 20, 20, red)

		ren.present()
	}
}
