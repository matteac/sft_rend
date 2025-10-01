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

	// 0xAABBGGRR
	gray: ren.Color = {24, 24, 24, 255}
	red: ren.Color = {255, 0, 0, 128}

	size := ren.get_size()
	circle: ren.Circlef = {size.x / 2, size.y / 2, 16}
	circle_speed: f64 = 256

	// Main loop
	for ren.is_running() {
		delta := ren.get_delta_time()
		fmt.printfln("%fms delta | %d fps", delta * 1000, cast(u32)(1 / delta))

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
		ren.draw_rect(0, 0, 48, 48, red, false)
		ren.draw_rect(size.x - 48, 0, 48, 48, red)
		ren.draw_rect(0, size.y - 48, 48, 48, red)
		ren.draw_rect(size.x - 48, size.y - 48, 48, 48, red, false)

		ren.draw_circle(circle.x, circle.y, circle.radius, {0, 0, 255, 128})

		ren.present()
	}
}

