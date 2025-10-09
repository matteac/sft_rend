package renderer


import gl "vendor:OpenGL"
import "vendor:glfw"
import stbi "vendor:stb/image"
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
	font_data, ok := os.read_entire_file(path)
	if !ok {
		return false, fmt.tprintf("Failed to read font file: %s", path)
	}

	return init_font_from_data(font_data)
}
init_font_from_data :: proc(font_data: []u8) -> (bool, string) {
	if font_data == nil {
		return false, "Font data is nil"
	}
	if state._font_data != nil {
		delete(state._font_data)
	}

	state._font_data = font_data

	off := stbt.GetFontOffsetForIndex(&state._font_data[0], 0)
	if !stbt.InitFont(&state._font_info, &state._font_data[0], off) {
		return false, "Failed to initialize font with stb_truetype"
	}

	return true, ""
}


load_texture_from_data :: proc(data: []u8) -> (Texture, bool, string) {
	tex: Texture

	w, h, n: i32
	pixels := stbi.load_from_memory(
		raw_data(data),
		cast(i32)len(data),
		&w,
		&h,
		&n,
		4, // rgba channels
	)

	if pixels == nil {
		return tex, false, "Error decoding image"
	}
	defer stbi.image_free(pixels)

	tex.width = cast(u32)w
	tex.height = cast(u32)h
	tex.data = make([]u32, w * h)
	pixel_bytes := ([^]u8)(pixels)
	for i in 0 ..< w * h {
		color := Color {
			r = pixel_bytes[i * 4 + 0],
			g = pixel_bytes[i * 4 + 1],
			b = pixel_bytes[i * 4 + 2],
			a = pixel_bytes[i * 4 + 3],
		}
		tex.data[i] = transmute(u32)color
	}

	return tex, true, ""

}
load_texture :: proc(path: string) -> (Texture, bool, string) {
	file_data, file_ok := os.read_entire_file(path, context.allocator)
	if !file_ok {
		return {}, false, fmt.tprintf("Error reading file: %s", path, context.allocator)
	}
	defer delete(file_data)

	return load_texture_from_data(file_data)

}

/* 
draw_pixel :: #force_inline proc(x, y: i32, color: Color) {
	if x >= 0 && x < cast(i32)state.width && y >= 0 && y < cast(i32)state.height {
		state.fb[y * cast(i32)state.width + x] = transmute(u32)color
	}
}
*/
draw_pixel :: #force_inline proc(x, y: u32, color: Color) {
	if x >= 0 && x < cast(u32)state.width && y >= 0 && y < cast(u32)state.height {
		index := y * cast(u32)state.width + x

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

draw_texture :: proc(x, y: f64, tex: Texture) {
	if x >= state.width ||
	   y >= state.height ||
	   x + cast(f64)tex.width <= 0 ||
	   y + cast(f64)tex.height <= 0 {
		return
	}

	min_screen_x := math.max(0, x)
	max_screen_x := math.min(state.width, x + cast(f64)tex.width)
	min_screen_y := math.max(0, y)
	max_screen_y := math.min(state.height, y + cast(f64)tex.height)

	start_tx: u32 = 0
	if x < 0 {
		start_tx = cast(u32)(-x)
	}

	start_ty: u32 = 0
	if y < 0 {
		start_ty = cast(u32)(-y)
	}

	ty := start_ty
	for py in cast(u32)min_screen_y ..< cast(u32)max_screen_y {
		tx := start_tx
		for px in cast(u32)min_screen_x ..< cast(u32)max_screen_x {
			tex_index := ty * tex.width + tx
			tex_color := transmute(Color)tex.data[tex_index]
			draw_pixel(px, py, tex_color)

			tx += 1
		}
		ty += 1
	}
}

fill_rect :: proc(x, y: f64, w, h: f64, color: Color) {
	if x + w <= 0 || y + h <= 0 || x >= state.width || y >= state.height {
		return
	}

	min_px := math.floor(x)
	max_px := math.ceil(x + w)
	min_py := math.floor(y)
	max_py := math.ceil(y + h)

	min_px = math.max(0, min_px)
	max_px = math.min(state.width, max_px)
	min_py = math.max(0, min_py)
	max_py = math.min(state.height, max_py)

	for py in min_py ..< max_py {
		for px in min_px ..< max_px {
			cover_x := math.max(0, math.min(px + 1, x + w) - math.max(px, x))
			cover_y := math.max(0, math.min(py + 1, y + h) - math.max(py, y))
			coverage := cover_x * cover_y

			if coverage > 0 {
				final_color := color
				final_color.a = cast(u8)(cast(f64)color.a * coverage)
				draw_pixel(cast(u32)px, cast(u32)py, final_color)
			}
		}
	}
}
draw_rect :: proc(x, y, w, h, thickness: f64, color: Color) {
	if thickness <= 0 || thickness * 2 > w || thickness * 2 > h {
		return
	}
	fill_rect(x, y, w, thickness, color)
	fill_rect(x, y + h - thickness, w, thickness, color)
	fill_rect(x, y + thickness, thickness, h - 2 * thickness, color)
	fill_rect(x + w - thickness, y + thickness, thickness, h - 2 * thickness, color)
}

fill_circle :: proc(cx, cy, radius: f64, color: Color) {
	if radius <= 0 {
		return
	}

	start_x := math.max(0, cx - radius - 1)
	end_x := math.min(state.width, cx + radius + 1)
	start_y := math.max(0, cy - radius - 1)
	end_y := math.min(state.height, cy + radius + 1)

	for y in start_y ..< end_y {
		for x in start_x ..< end_x {
			dx := x - cx
			dy := y - cy
			dist_sq := dx * dx + dy * dy
			dist := math.sqrt(dist_sq)

			edge_dist := dist - radius

			coverage := 1.0 - math.clamp(edge_dist + 0.5, 0, 1)

			if coverage > 0 {
				final_color := color
				final_color.a = cast(u8)(cast(f64)color.a * coverage)

				draw_pixel(cast(u32)x, cast(u32)y, final_color)
			}
		}
	}
}
draw_circle :: proc(cx, cy, radius, thickness: f64, color: Color) {
	if radius <= 0 || thickness <= 0 {
		return
	}

	half_thick := thickness / 2

	outer_radius := radius + half_thick + 1
	min_px := math.floor(cx - outer_radius)
	max_px := math.ceil(cx + outer_radius)
	min_py := math.floor(cy - outer_radius)
	max_py := math.ceil(cy + outer_radius)

	min_px = math.max(0, min_px)
	max_px = math.min(state.width, max_px)
	min_py = math.max(0, min_py)
	max_py = math.min(state.height, max_py)

	for py in min_py ..< max_py {
		for px in min_px ..< max_px {
			dx := (px + 0.5) - cx
			dy := (py + 0.5) - cy
			dist_from_center := math.sqrt(dx * dx + dy * dy)

			dist_from_outline := dist_from_center - radius

			coverage := math.clamp(0.5 - (math.abs(dist_from_outline) - half_thick), 0, 1)

			if coverage > 0 {
				final_color := color
				final_color.a = cast(u8)(cast(f64)color.a * coverage)
				draw_pixel(cast(u32)px, cast(u32)py, final_color)
			}
		}
	}
}

draw_line :: proc(x1, y1, x2, y2, thickness: f64, color: Color) {
	if thickness <= 0 {
		return
	}

	half_thick := thickness / 2

	a := Vec2f{x1, y1}
	b := Vec2f{x2, y2}
	ab := b - a

	min_px := math.floor(math.min(x1, x2) - half_thick - 1)
	max_px := math.ceil(math.max(x1, x2) + half_thick + 1)
	min_py := math.floor(math.min(y1, y2) - half_thick - 1)
	max_py := math.ceil(math.max(y1, y2) + half_thick + 1)

	min_px = math.max(0, min_px)
	max_px = math.min(state.width, max_px)
	min_py = math.max(0, min_py)
	max_py = math.min(state.height, max_py)

	len_sq := linalg.dot(ab, ab)

	for py in min_py ..< max_py {
		for px in min_px ..< max_px {
			p := Vec2f{px + 0.5, py + 0.5}
			ap := p - a

			dist: f64
			if len_sq == 0 {
				dist = linalg.length(ap)
			} else {
				t := linalg.dot(ap, ab) / len_sq
				t_clamped := math.clamp(t, 0, 1)
				closest_point := a + ab * t_clamped
				dist = linalg.distance(p, closest_point)
			}

			coverage := math.clamp(0.5 - (dist - half_thick), 0, 1)

			if coverage > 0 {
				final_color := color
				final_color.a = cast(u8)(cast(f64)color.a * coverage)
				draw_pixel(cast(u32)px, cast(u32)py, final_color)
			}
		}
	}
}

_edge_function :: proc(a, b, p: Vec2f) -> f64 {
	return (p.x - a.x) * (b.y - a.y) - (p.y - a.y) * (b.x - a.x)
}

fill_triangle :: proc(v1, v2, v3: Vec2f, color: Color) {
	min_x := math.floor(math.min(v1.x, math.min(v2.x, v3.x)) - 1)
	max_x := math.ceil(math.max(v1.x, math.max(v2.x, v3.x)) + 1)
	min_y := math.floor(math.min(v1.y, math.min(v2.y, v3.y)) - 1)
	max_y := math.ceil(math.max(v1.y, math.max(v2.y, v3.y)) + 1)

	min_x = math.max(0, min_x)
	max_x = math.min(state.width, max_x)
	min_y = math.max(0, min_y)
	max_y = math.min(state.height, max_y)

	e1_len := linalg.distance(v1, v2)
	e2_len := linalg.distance(v2, v3)
	e3_len := linalg.distance(v3, v1)

	for y in min_y ..< max_y {
		for x in min_x ..< max_x {
			p := Vec2f{x + 0.5, y + 0.5}

			d1 := _edge_function(v1, v2, p) / e1_len
			d2 := _edge_function(v2, v3, p) / e2_len
			d3 := _edge_function(v3, v1, p) / e3_len

			dist := math.max(d1, math.max(d2, d3))

			coverage := math.clamp(0.5 - dist, 0, 1)

			if coverage > 0 {
				final_color := color
				final_color.a = cast(u8)(cast(f64)color.a * coverage)
				draw_pixel(cast(u32)x, cast(u32)y, final_color)
			}
		}
	}
}

draw_triangle :: proc(v1, v2, v3: Vec2f, thickness: f64, color: Color) {
	draw_line(v1.x, v1.y, v2.x, v2.y, thickness, color)
	draw_line(v2.x, v2.y, v3.x, v3.y, thickness, color)
	draw_line(v3.x, v3.y, v1.x, v1.y, thickness, color)
}

draw_text :: proc(text: string, x, y: f64, size: f64, color: Color) {
	if state._font_data == nil {
		fmt.eprintln("Error: draw_text called before init_font")
		return
	}

	scale := stbt.ScaleForPixelHeight(&state._font_info, cast(f32)size)

	asc, desc, lg: i32
	stbt.GetFontVMetrics(&state._font_info, &asc, &desc, &lg)

	cx := x
	cy := math.floor(y + cast(f64)asc * cast(f64)scale)

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
						final_color := color
						final_color.a = cast(u8)(cast(f64)alpha * (cast(f64)color.a / 255.0))

						draw_pixel(
							cast(u32)(draw_pos_x + cast(f64)col),
							cast(u32)(draw_pos_y + cast(f64)row),
							final_color,
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
