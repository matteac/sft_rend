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


Vec2i :: [2]i32

Renderer :: struct {
	width:          i32,
	height:         i32,
	fb:             []u32, // RGBA TODO: implement alpha blending (https://en.wikipedia.org/wiki/Alpha_compositing)
	// _"private"
	_running:       bool,
	_window_handle: glfw.WindowHandle,
	_shader:        u32,
	_quad_vao:      u32,
	_quad_vbo:      u32,
	_quad_vertices: []f32,
	_texture_id:    u32,
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
	if width == 0 || height == 0 {
		return
	}

	state.width = width
	state.height = height

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


init :: proc(w, h: i32, title: cstring, vsync: bool) -> (bool, string) {
	state.width = w
	state.height = h
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
		return false, "Error initializing GLFW"
	}

	state._window_handle = glfw.CreateWindow(state.width, state.width, title, nil, nil)
	if state._window_handle == nil {
		return false, "Error creating GLFW window"
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
		return false, fmt.tprintf("Error compiling vertex shader: %s", err_str, context.allocator)
	}
	frag_shader := gl.CreateShader(gl.FRAGMENT_SHADER)
	ok, err_str = compile_shader(frag_shader, frag_shader_src)
	if !ok {
		return false, fmt.tprintf(
			"Error compiling fragment shader: %s",
			err_str,
			context.allocator,
		)
	}

	state._shader = gl.CreateProgram()
	ok, err_str = link_shader_program(state._shader, {vert_shader, frag_shader})
	if !ok {
		return false, fmt.tprintf("Error linking shader program: %s", err_str, context.allocator)
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

	resize_framebuffer(state.width, state.height)


	return true, ""
}

clear :: proc(color: u32) {
	for i in 0 ..< len(state.fb) {
		state.fb[i] = color
	}
}
draw_rect :: proc(x, y: i32, w, h: i32, color: u32) {
	if x >= state.width || y >= state.height || x + w <= 0 || y + h <= 0 {
		return
	}

	start_x := math.max(x, 0)
	start_y := math.max(y, 0)
	end_x := math.min(x + w, state.width)
	end_y := math.min(y + h, state.height)

	for y in start_y ..< end_y {
		row_offset := y * state.width
		for x in start_x ..< end_x {
			state.fb[row_offset + x] = color
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
		state.width,
		state.height,
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
	glfw.PollEvents()
}


get_size :: proc() -> Vec2i {
	return {state.width, state.height}
}

is_running :: proc() -> bool {
	return state._running && !glfw.WindowShouldClose(state._window_handle)
}
