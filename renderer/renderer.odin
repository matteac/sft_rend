package renderer


import gl "vendor:OpenGL"
import "vendor:glfw"
import stbt "vendor:stb/truetype"

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:strings"

import "base:runtime"


vert_shader_src := `
    #version 330 core
    layout (location = 0) in vec2 a_pos;
    layout (location = 1) in vec2 a_texture_coord;

    out vec2 texture_coord;

    void main() {
        gl_Position = vec4(a_pos.x, a_pos.y, 0.0, 1.0);
        texture_coord = a_texture_coord;
    }
`


frag_shader_src := `
    #version 330 core

    in vec2 texture_coord;
    uniform sampler2D screen_texture;

    out vec4 frag_color;

    void main() {
        frag_color = texture(screen_texture, texture_coord);
    }
`


Renderer :: struct {
	width:          f64,
	height:         f64,
	fb:             []u32,
	// _"private"
	_running:       bool,
	_window_handle: glfw.WindowHandle,
	_shader:        u32,
	_quad_vao:      u32,
	_quad_vbo:      u32,
	_quad_vertices: []f32,
	_texture_id:    u32,

	//
	_ltime:         f64,
	_delta:         f64,

	//
	_font_data:     []u8,
	_font_info:     stbt.fontinfo,
}


state: Renderer = {}

_compile_shader :: proc(shader: u32, shader_src: string) -> (bool, string) {
	csrc := strings.clone_to_cstring(shader_src, context.temp_allocator)
	gl.ShaderSource(shader, 1, &csrc, nil)
	gl.CompileShader(shader)

	success: i32
	info_buffer: [512]u8
	gl.GetShaderiv(shader, gl.COMPILE_STATUS, &success)
	if success != 1 {
		gl.GetShaderInfoLog(shader, len(info_buffer), nil, &info_buffer[0])
		return false, string(info_buffer[:])
	}
	return true, ""
}

_link_shader_program :: proc(program: u32, shaders: []u32) -> (bool, string) {
	for shader in shaders {
		gl.AttachShader(program, shader)
	}
	gl.LinkProgram(program)

	success: i32
	info_buffer: [512]u8
	gl.GetProgramiv(program, gl.LINK_STATUS, &success)
	if success != 1 {
		gl.GetProgramInfoLog(program, len(info_buffer), nil, &info_buffer[0])
		return false, string(info_buffer[:])
	}
	return true, ""
}

_resize_framebuffer :: proc(width, height: i32) {
	if width <= 0 || height <= 0 {
		return
	}

	state.width = cast(f64)width
	state.height = cast(f64)height

	delete(state.fb)
	state.fb = make([]u32, width * height)

	gl.BindTexture(gl.TEXTURE_2D, state._texture_id)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
}

_fbsz_cb :: proc "c" (handle: glfw.WindowHandle, width, height: i32) {
	gl.Viewport(0, 0, width, height)

	context = runtime.default_context()
	_resize_framebuffer(width, height)
}


init :: proc(w, h: i32, title: cstring, vsync: bool = true) -> (glfw.WindowHandle, bool, string) {
	state.width = cast(f64)w
	state.height = cast(f64)h
	state._running = true
	state._quad_vertices = {
		// texture coords (V flipped)
		-1.0,
		1.0,
		0.0,
		0.0, // tf
		-1.0,
		-1.0,
		0.0,
		1.0, // bl
		1.0,
		-1.0,
		1.0,
		1.0, // br
		-1.0,
		1.0,
		0.0,
		0.0, // tl
		1.0,
		-1.0,
		1.0,
		1.0, // br
		1.0,
		1.0,
		1.0,
		0.0, // tr
	}

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

	if !glfw.Init() {
		return nil, false, "Error initializing GLFW"
	}

	state._window_handle = glfw.CreateWindow(
		cast(i32)state.width,
		cast(i32)state.height,
		title,
		nil,
		nil,
	)

	if state._window_handle == nil {
		return nil, false, "Error creating GLFW window"
	}

	glfw.MakeContextCurrent(state._window_handle)
	gl.load_up_to(3, 3, glfw.gl_set_proc_address)
	glfw.SetFramebufferSizeCallback(state._window_handle, _fbsz_cb)

	if vsync {
		glfw.SwapInterval(1)
	} else {
		glfw.SwapInterval(0)
	}


	vert_shader := gl.CreateShader(gl.VERTEX_SHADER)
	ok, err_str := _compile_shader(vert_shader, vert_shader_src)
	if !ok {
		return nil, false, fmt.tprintf(
			"Error compiling vertex shader: %s",
			err_str,
			context.allocator,
		)
	}
	frag_shader := gl.CreateShader(gl.FRAGMENT_SHADER)
	ok, err_str = _compile_shader(frag_shader, frag_shader_src)
	if !ok {
		return nil, false, fmt.tprintf(
			"Error compiling fragment shader: %s",
			err_str,
			context.allocator,
		)
	}

	state._shader = gl.CreateProgram()
	ok, err_str = _link_shader_program(state._shader, {vert_shader, frag_shader})
	if !ok {
		return nil, false, fmt.tprintf(
			"Error linking shader program: %s",
			err_str,
			context.allocator,
		)
	}
	gl.DeleteShader(vert_shader)
	gl.DeleteShader(frag_shader)

	gl.GenVertexArrays(1, &state._quad_vao)
	gl.GenBuffers(1, &state._quad_vbo)
	gl.GenTextures(1, &state._texture_id)

	gl.BindVertexArray(state._quad_vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, state._quad_vbo)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(state._quad_vertices) * size_of(f32),
		&state._quad_vertices[0],
		gl.STATIC_DRAW,
	)
	gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(f32) * 4, 0)
	gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, size_of(f32) * 4, size_of(f32) * 2)
	gl.EnableVertexAttribArray(1)
	gl.BindTexture(gl.TEXTURE_2D, state._texture_id)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)

	_resize_framebuffer(cast(i32)state.width, cast(i32)state.height)


	return state._window_handle, true, ""
}

init_font :: proc(path: string) -> (bool, string) {
	if state._font_data != nil {
		delete(state._font_data)
	}

	font_data, ok := os.read_entire_file(path)
	if !ok {
		return false, fmt.tprintf("Failed to read font file: %s", path)
	}

	state._font_data = font_data

	off := stbt.GetFontOffsetForIndex(&state._font_data[0], 0)
	if !stbt.InitFont(&state._font_info, &state._font_data[0], off) {
		return false, "Failed to initialize font with stb_truetype"
	}

	return true, ""
}

/* 
draw_pixel :: #force_inline proc(x, y: i32, color: Color) {
	if x >= 0 && x < cast(i32)state.width && y >= 0 && y < cast(i32)state.height {
		state.fb[y * cast(i32)state.width + x] = transmute(u32)color
	}
}
*/
draw_pixel :: #force_inline proc(x, y: i32, color: Color) {
	if x >= 0 && x < cast(i32)state.width && y >= 0 && y < cast(i32)state.height {
		index := y * cast(i32)state.width + x

		if color.a == 0 {
			return
		}

		packed_b := state.fb[index]
		B := transmute(Color)packed_b

		if color.a == 255 {
			state.fb[index] = transmute(u32)color
			return
		}

		a_raw := cast(u32)color.a
		b_raw := cast(u32)B.a

		a_inv := 255 - a_raw

		t2_alpha := (b_raw * a_inv + 127) / 255

		a_out := a_raw + t2_alpha

		out: Color
		out.a = cast(u8)a_out

		final_divisor := a_out * 255

		r_num := cast(u32)color.r * a_raw * 255 + cast(u32)B.r * b_raw * a_inv
		out.r = cast(u8)((r_num + final_divisor / 2) / final_divisor)

		g_num := cast(u32)color.g * a_raw * 255 + cast(u32)B.g * b_raw * a_inv
		out.g = cast(u8)((g_num + final_divisor / 2) / final_divisor)

		b_num := cast(u32)color.b * a_raw * 255 + cast(u32)B.b * b_raw * a_inv
		out.b = cast(u8)((b_num + final_divisor / 2) / final_divisor)


		state.fb[index] = transmute(u32)out
	}
}

clear :: proc(color: Color) {
	for i in 0 ..< len(state.fb) {
		// background doesnt need alpha blending
		state.fb[i] = transmute(u32)color
	}
}

fill_rect :: proc(x, y: f64, w, h: f64, color: Color) {
	if x >= state.width || y >= state.height || x + w <= 0 || y + h <= 0 {
		return
	}

	start_x := math.max(x, 0)
	start_y := math.max(y, 0)
	end_x := math.min(x + w, state.width)
	end_y := math.min(y + h, state.height)

	for row in start_y ..< end_y {
		for col in start_x ..< end_x {
			draw_pixel(cast(i32)col, cast(i32)row, color)
		}
	}
}
draw_rect :: proc(x, y: f64, w, h: f64, color: Color) {
	if x >= state.width || y >= state.height || x + w <= 0 || y + h <= 0 {
		return
	}

	start_x := math.max(x, 0)
	start_y := math.max(y, 0)
	end_x := math.min(x + w, state.width)
	end_y := math.min(y + h, state.height)


	for col in start_x ..< end_x {
		draw_pixel(cast(i32)col, cast(i32)start_y, color)
		draw_pixel(cast(i32)col, cast(i32)end_y - 1, color)
	}
	for row in start_y ..< end_y {
		draw_pixel(cast(i32)start_x, cast(i32)row, color)
		draw_pixel(cast(i32)end_x - 1, cast(i32)row, color)
	}

}

fill_circle :: proc(cx, cy, radius: f64, color: Color) {
	if radius <= 0 {
		return
	}

	start_x := math.max(0, cx - radius)
	end_x := math.min(state.width, cx + radius + 1)
	start_y := math.max(0, cy - radius)
	end_y := math.min(state.height, cy + radius + 1)

	radius_sq := radius * radius

	for y in start_y ..< end_y {
		for x in start_x ..< end_x {
			dx := x - cx
			dy := y - cy
			if dx * dx + dy * dy <= radius_sq {
				draw_pixel(cast(i32)x, cast(i32)y, color)
			}
		}
	}
}
draw_circle :: proc(cx, cy, radius: f64, color: Color) {
	if radius <= 0 {
		return
	}

	cx := cast(i32)cx
	cy := cast(i32)cy
	x: i32 = cast(i32)radius
	y: i32 = 0
	err := 1 - x

	for x >= y {
		draw_pixel(cx + x, cy + y, color)
		draw_pixel(cx + y, cy + x, color)
		draw_pixel(cx - y, cy + x, color)
		draw_pixel(cx - x, cy + y, color)
		draw_pixel(cx - x, cy - y, color)
		draw_pixel(cx - y, cy - x, color)
		draw_pixel(cx + y, cy - x, color)
		draw_pixel(cx + x, cy - y, color)

		y += 1
		if err <= 0 {
			err += 2 * y + 1
		} else {
			x -= 1
			err += 2 * (y - x) + 1
		}
	}
}

draw_line :: proc(x1, y1, x2, y2: f64, color: Color) {
	dx := x2 - x1
	dy := y2 - y1

	steps := math.max(math.abs(dx), math.abs(dy))
	if steps == 0 {
		draw_pixel(cast(i32)x1, cast(i32)y1, color)
		return
	}

	x_inc := dx / steps
	y_inc := dy / steps

	x, y := x1, y1
	for i in 0 ..= steps {
		draw_pixel(cast(i32)x, cast(i32)y, color)
		x += x_inc
		y += y_inc
	}
}

_is_point_in_triangle :: proc(p, a, b, c: Vec2f) -> bool {
	d1 := (p.x - a.x) * (b.y - a.y) - (p.y - a.y) * (b.x - a.x)
	d2 := (p.x - b.x) * (c.y - b.y) - (p.y - b.y) * (c.x - b.x)
	d3 := (p.x - c.x) * (a.y - c.y) - (p.y - c.y) * (a.x - c.x)

	has_neg := (d1 < 0) || (d2 < 0) || (d3 < 0)
	has_pos := (d1 > 0) || (d2 > 0) || (d3 > 0)

	return !(has_neg && has_pos)
}
fill_triangle :: proc(v1, v2, v3: Vec2f, color: Color) {
	min_x := math.floor(math.min(v1.x, math.min(v2.x, v3.x)))
	max_x := math.ceil(math.max(v1.x, math.max(v2.x, v3.x)))
	min_y := math.floor(math.min(v1.y, math.min(v2.y, v3.y)))
	max_y := math.ceil(math.max(v1.y, math.max(v2.y, v3.y)))

	min_x = math.max(0, min_x)
	min_y = math.max(0, min_y)
	max_x = math.min(state.width, max_x)
	max_y = math.min(state.height, max_y)

	for y in min_y ..< max_y {
		for x in min_x ..< max_x {
			point_to_check := Vec2f{cast(f64)x + 0.5, cast(f64)y + 0.5}
			if _is_point_in_triangle(point_to_check, v1, v2, v3) {
				draw_pixel(cast(i32)x, cast(i32)y, color)
			}
		}
	}
}

draw_triangle :: proc(v1, v2, v3: Vec2f, color: Color) {
	draw_line(v1.x, v1.y, v2.x, v2.y, color)
	draw_line(v2.x, v2.y, v3.x, v3.y, color)
	draw_line(v3.x, v3.y, v1.x, v1.y, color)
}

draw_text :: proc(text: string, x, y: f64, size: f64, color: Color) {
	if state._font_data == nil {
		fmt.eprintln("Error: draw_text called before onit_font")
		return
	}

	scale := stbt.ScaleForPixelHeight(&state._font_info, cast(f32)size)

	asc, desc, lg: i32
	stbt.GetFontVMetrics(&state._font_info, &asc, &desc, &lg)

	cx := x
	cy := y + cast(f64)asc * cast(f64)scale

	prev_ch: rune = -1
	for ch in text {
		if ch == '\n' {
			cx = x
			cy += cast(f64)(asc - desc + lg) * cast(f64)scale
			prev_ch = -1
			continue
		}

		kern_advance := stbt.GetCodepointKernAdvance(&state._font_info, prev_ch, ch)
		cx += cast(f64)kern_advance * cast(f64)scale

		w, h, xoff, yoff: i32
		bitmap := stbt.GetCodepointBitmap(
			&state._font_info,
			scale,
			scale,
			ch,
			&w,
			&h,
			&xoff,
			&yoff,
		)

		if bitmap != nil {
			draw_pos_x := math.floor(cx) + f64(xoff)
			draw_pos_y := math.floor(cy) + f64(yoff)

			for row in 0 ..< h {
				for col in 0 ..< w {
					alpha := bitmap[row * w + col]
					if alpha > 0 {
						draw_pixel(
							cast(i32)(draw_pos_x + cast(f64)col),
							cast(i32)(draw_pos_y + cast(f64)row),
							color,
						)
					}
				}
			}
			stbt.FreeBitmap(bitmap, nil)
		}

		advance_width: i32
		stbt.GetCodepointHMetrics(&state._font_info, ch, &advance_width, nil)
		cx += cast(f64)advance_width * cast(f64)scale

		prev_ch = ch
	}
}

present :: proc() {
	gl.BindTexture(gl.TEXTURE_2D, state._texture_id)
	gl.TexSubImage2D(
		gl.TEXTURE_2D,
		0,
		0,
		0,
		cast(i32)state.width,
		cast(i32)state.height,
		gl.RGBA,
		gl.UNSIGNED_BYTE,
		&state.fb[0],
	)

	gl.ClearColor(0, 0, 0, 1)
	gl.Clear(gl.COLOR_BUFFER_BIT)

	gl.UseProgram(state._shader)
	gl.BindVertexArray(state._quad_vao)
	gl.DrawArrays(gl.TRIANGLES, 0, 6)

	glfw.SwapBuffers(state._window_handle)

	ntime := glfw.GetTime()
	state._delta = ntime - state._ltime
	state._ltime = ntime
}


get_size :: proc() -> Vec2f {
	return {state.width, state.height}
}

get_delta_time :: proc() -> f64 {
	return state._delta
}

is_running :: proc() -> bool {
	return state._running && !glfw.WindowShouldClose(state._window_handle)
}
