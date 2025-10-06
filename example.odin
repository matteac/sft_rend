package main

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:slice"

import "input"
import ren "renderer"
import "vendor:glfw" // used for input constants and time

Star :: struct {
	pos:   ren.Vec2f,
	speed: f64,
}

Particle :: struct {
	pos:      ren.Vec2f,
	vel:      ren.Vec2f,
	lifetime: f64,
	max_life: f64,
}

main :: proc() {
	handle, ok, err_str := ren.init(1000, 600, "Renderer Demo", false)
	if !ok {
		fmt.eprintfln("Error initializing renderer: %s", err_str)
		return
	}
	input.init(handle)

	ok, err_str = ren.init_font("assets/VT323-Regular.ttf")
	if !ok {
		fmt.eprintfln("Error initializing font: %s", err_str)
		return
	}

	BACKGROUND_COLOR :: ren.Color{15, 15, 20, 255}
	PLAYER_COLOR :: ren.Color{220, 70, 70, 255}
	RECT_COLOR :: ren.Color{70, 220, 70, 255}
	CIRCLE_COLOR :: ren.Color{70, 70, 220, 255}
	TRIANGLE_COLOR :: ren.Color{220, 220, 70, 255}
	TEXT_COLOR :: ren.Color{220, 220, 220, 255}

	screen_size := ren.get_size()

	player_pos := ren.Vec2f{150, screen_size.y / 2}
	player_size := ren.Vec2f{40, 40}
	PLAYER_SPEED :: 400.0

	show_outlines := false

	stars: [100]Star
	for i in 0 ..< len(stars) {
		stars[i] = {
			pos   = {rand.float64() * screen_size.x, rand.float64() * screen_size.y},
			speed = rand.float64_range(20, 80),
		}
	}

	particles: [dynamic]Particle
	particles_per_second := 500.0
	particle_spawn_timer: f64 = 0


	for ren.is_running() {
		delta := ren.get_delta_time()
		input.poll_events()

		if input.is_key_pressed(glfw.KEY_O) {
			particles_per_second -= 100
		}
		if input.is_key_pressed(glfw.KEY_P) {
			particles_per_second += 100
		}

		if input.is_key_down(glfw.KEY_W) {
			player_pos.y -= PLAYER_SPEED * delta
		}
		if input.is_key_down(glfw.KEY_S) {
			player_pos.y += PLAYER_SPEED * delta
		}
		if input.is_key_down(glfw.KEY_A) {
			player_pos.x -= PLAYER_SPEED * delta
		}
		if input.is_key_down(glfw.KEY_D) {
			player_pos.x += PLAYER_SPEED * delta
		}

		if input.is_key_pressed(glfw.KEY_SPACE) {
			show_outlines = !show_outlines
		}

		if input.is_mouse_button_down(glfw.MOUSE_BUTTON_LEFT) {
			mouse_pos := input.get_mouse_pos()
			particle_spawn_timer += delta
			spawn_interval := 1.0 / particles_per_second

			for particle_spawn_timer > spawn_interval {
				angle := rand.float64() * 2 * math.PI
				speed := rand.float64_range(50, 150)
				life := rand.float64_range(0.5, 1.5)
				append(
					&particles,
					Particle {
						mouse_pos,
						{math.cos(angle) * speed, math.sin(angle) * speed},
						life,
						life,
					},
				)
				particle_spawn_timer -= spawn_interval
			}
		}

		for &star in stars {
			star.pos.x -= star.speed * delta
			if star.pos.x < 0 {
				star.pos.x = screen_size.x
				star.pos.y = rand.float64() * screen_size.y
			}
		}

		// update particles
		for i := len(particles) - 1; i >= 0; i -= 1 {
			particles[i].pos += particles[i].vel * delta
			particles[i].lifetime -= delta
			particles[i].vel.y += 98.0 * delta // gravity
			if particles[i].lifetime <= 0 {
				ordered_remove(&particles, i)
			}
		}


		time := glfw.GetTime()
		ren.clear(BACKGROUND_COLOR)

		// Rectangle stretching
		rect_w := 100 + math.sin(time * 2) * 40

		// Circle moving
		circle_y := 350 + math.cos(time) * 100

		// Triangle rotating
		center := ren.Vec2f{800, 250}
		radius := 80.0
		v1 := ren.Vec2f{center.x + math.cos(time) * radius, center.y + math.sin(time) * radius}
		v2 := ren.Vec2f {
			center.x + math.cos(time + 2 * math.PI / 3) * radius,
			center.y + math.sin(time + 2 * math.PI / 3) * radius,
		}
		v3 := ren.Vec2f {
			center.x + math.cos(time + 4 * math.PI / 3) * radius,
			center.y + math.sin(time + 4 * math.PI / 3) * radius,
		}

		for star in stars {
			ren.draw_pixel(cast(i32)star.pos.x, cast(i32)star.pos.y, {200, 200, 255, 150})
		}


		if show_outlines {
			ren.draw_rect(400, 100, rect_w, 80, RECT_COLOR)
			ren.draw_circle(500, circle_y, 50, CIRCLE_COLOR)
			ren.draw_triangle(v1, v2, v3, TRIANGLE_COLOR)
			ren.draw_rect(
				player_pos.x - player_size.x / 2,
				player_pos.y - player_size.y / 2,
				player_size.x,
				player_size.y,
				PLAYER_COLOR,
			)

		} else {
			ren.fill_rect(400, 100, rect_w, 80, RECT_COLOR)
			ren.fill_circle(500, circle_y, 50, CIRCLE_COLOR)
			ren.fill_triangle(v1, v2, v3, TRIANGLE_COLOR)
			ren.fill_rect(
				player_pos.x - player_size.x / 2,
				player_pos.y - player_size.y / 2,
				player_size.x,
				player_size.y,
				PLAYER_COLOR,
			)
		}


		for particle in particles {
			alpha_ratio := particle.lifetime / particle.max_life
			alpha := cast(u8)(math.clamp(alpha_ratio, 0, 1) * 255)
			ren.fill_rect(particle.pos.x, particle.pos.y, 2, 2, {255, 220, 100, alpha})
		}

		ren.draw_text("Demo", 20, 20, 28, TEXT_COLOR)
		ren.draw_text("Use WASD to move the red rectangle", 20, 60, 24, TEXT_COLOR)
		ren.draw_text("Hold Left Click to spawn particles", 20, 90, 24, TEXT_COLOR)
		ren.draw_text("Press SPACE to toggle outlines", 20, 120, 24, TEXT_COLOR)
		ren.draw_text(
			"Press O/P to Decrese/Increase the particle spawn rate",
			20,
			150,
			24,
			TEXT_COLOR,
		)


		particle_text := fmt.tprintf("%.0f Particles per second", particles_per_second)
		ren.draw_text(particle_text, 20, screen_size.y - 24, 24, TEXT_COLOR)

		fps_text := fmt.tprintf("FPS: %d", cast(i32)(1.0 / delta))
		ren.draw_text(fps_text, screen_size.x - 150, 20, 24, TEXT_COLOR)

		ren.present()
	}
}
