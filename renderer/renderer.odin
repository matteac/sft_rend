package renderer


import gl "vendor:OpenGL"
import "vendor:glfw"

import "core:fmt"
import "core:math"
import "core:strings"

import "base:runtime"


vert_shader_src :: `
    #version 330 core
    layout (location = 0) in vec2 a_pos;
    layout (location = 1) in vec2 a_texture_coord;

    out vec2 texture_coord;

    void main() {
        gl_Position = vec4(a_pos.x, a_pos.y, 0.0, 1.0);
        texture_coord = a_texture_coord;
    }
`


frag_shader_src :: `
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
	fb:             []u32, // RGBA TODO: implement alpha blending (https://en.wikipedia.org/wiki/Alpha_compositing)
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
}


state: Renderer = {}

compile_shader :: proc(shader: u32, shader_src: string) -> (bool, string) {
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

link_shader_program :: proc(program: u32, shaders: []u32) -> (bool, string) {
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

resize_framebuffer :: proc(width, height: i32) {
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
	resize_framebuffer(width, height)
}


init :: proc(w, h: i32, title: cstring, vsync: bool) -> (glfw.WindowHandle, bool, string) {
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

	if !vsync {
		glfw.SwapInterval(0)
	}


	vert_shader := gl.CreateShader(gl.VERTEX_SHADER)
	ok, err_str := compile_shader(vert_shader, vert_shader_src)
	if !ok {
		return nil, false, fmt.tprintf(
			"Error compiling vertex shader: %s",
			err_str,
			context.allocator,
		)
	}
	frag_shader := gl.CreateShader(gl.FRAGMENT_SHADER)
	ok, err_str = compile_shader(frag_shader, frag_shader_src)
	if !ok {
		return nil, false, fmt.tprintf(
			"Error compiling fragment shader: %s",
			err_str,
			context.allocator,
		)
	}

	state._shader = gl.CreateProgram()
	ok, err_str = link_shader_program(state._shader, {vert_shader, frag_shader})
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

	resize_framebuffer(cast(i32)state.width, cast(i32)state.height)


	return state._window_handle, true, ""
}

/* 
_draw_pixel :: #force_inline proc(x, y: i32, color: Color) {
	if x >= 0 && x < cast(i32)state.width && y >= 0 && y < cast(i32)state.height {
		state.fb[y * cast(i32)state.width + x] = transmute(u32)color
	}
}
*/
_draw_pixel :: #force_inline proc(x, y: i32, color: Color) {
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
	for x in 0 ..< state.width {
		for y in 0 ..< state.height {
			_draw_pixel(cast(i32)x, cast(i32)y, color)
		}
	}
}


draw_rect :: proc(x, y: f64, w, h: f64, color: Color, fill: bool = true) {
	if x >= state.width || y >= state.height || x + w <= 0 || y + h <= 0 {
		return
	}

	start_x := math.max(x, 0)
	start_y := math.max(y, 0)
	end_x := math.min(x + w, state.width)
	end_y := math.min(y + h, state.height)


	if fill {
		// filled
		for row in start_y ..< end_y {
			for col in start_x ..< end_x {
				_draw_pixel(cast(i32)col, cast(i32)row, color)
			}
		}
	} else {
		// outline
		for col in start_x ..< end_x {
			_draw_pixel(cast(i32)col, cast(i32)start_y, color)
			_draw_pixel(cast(i32)col, cast(i32)end_y - 1, color)
		}
		for row in start_y ..< end_y {
			_draw_pixel(cast(i32)start_x, cast(i32)row, color)
			_draw_pixel(cast(i32)end_x - 1, cast(i32)row, color)
		}
	}

}

draw_circle :: proc(cx, cy, radius: f64, color: Color, fill: bool = true) {

	if radius <= 0 {
		return
	}

	if fill {
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
					_draw_pixel(cast(i32)x, cast(i32)y, color)
				}
			}
		}
	} else {
		cx := cast(i32)cx
		cy := cast(i32)cy
		x: i32 = cast(i32)radius
		y: i32 = 0
		err := 1 - x

		for x >= y {
			_draw_pixel(cx + x, cy + y, color)
			_draw_pixel(cx + y, cy + x, color)
			_draw_pixel(cx - y, cy + x, color)
			_draw_pixel(cx - x, cy + y, color)
			_draw_pixel(cx - x, cy - y, color)
			_draw_pixel(cx - y, cy - x, color)
			_draw_pixel(cx + y, cy - x, color)
			_draw_pixel(cx + x, cy - y, color)

			y += 1
			if err <= 0 {
				err += 2 * y + 1
			} else {
				x -= 1
				err += 2 * (y - x) + 1
			}
		}
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

