package input

import "vendor:glfw"

Vec2f :: [2]f64

InputState :: struct {
	kb_prev_state:    [glfw.KEY_LAST + 1]bool,
	kb_curr_state:    [glfw.KEY_LAST + 1]bool,
	mouse_pos:        Vec2f,
	mouse_prev_state: [glfw.MOUSE_BUTTON_LAST + 1]bool,
	mouse_curr_state: [glfw.MOUSE_BUTTON_LAST + 1]bool,

	// _"private"
	_window_handle:   glfw.WindowHandle,
}

state: InputState = {}

init :: proc(handle: glfw.WindowHandle) {
	state._window_handle = handle
}

poll_events :: proc() {
	glfw.PollEvents()

	state.kb_prev_state = state.kb_curr_state
	for i in 0 ..= glfw.KEY_LAST {
		state.kb_curr_state[i] = glfw.GetKey(state._window_handle, cast(i32)i) == glfw.PRESS
	}


	state.mouse_prev_state = state.mouse_curr_state
	for i in 0 ..= glfw.MOUSE_BUTTON_LAST {
		state.mouse_curr_state[i] =
			glfw.GetMouseButton(state._window_handle, cast(i32)i) == glfw.PRESS

	}

	x, y := glfw.GetCursorPos(state._window_handle)
	state.mouse_pos = {x, y}
}


is_key_down :: proc(key: i32) -> bool {
	if key > glfw.KEY_LAST {return false}
	return state.kb_curr_state[key]
}
is_key_up :: proc(key: i32) -> bool {
	if key > glfw.KEY_LAST {return false}
	return !state.kb_curr_state[key]
}

is_key_pressed :: proc(key: i32) -> bool {
	if key > glfw.KEY_LAST {return false}
	return !state.kb_prev_state[key] && state.kb_curr_state[key]
}
is_key_released :: proc(key: i32) -> bool {
	if key > glfw.KEY_LAST {return false}
	return state.kb_prev_state[key] && !state.kb_curr_state[key]
}

get_mouse_pos :: proc() -> Vec2f {
	return state.mouse_pos
}

is_mouse_button_down :: proc(button: i32) -> bool {
	if button > glfw.MOUSE_BUTTON_LAST {return false}
	return state.mouse_curr_state[button]
}
is_mouse_button_up :: proc(button: i32) -> bool {
	if button > glfw.MOUSE_BUTTON_LAST {return false}
	return !state.mouse_curr_state[button]
}

is_mouse_button_pressed :: proc(button: i32) -> bool {
	if button > glfw.MOUSE_BUTTON_LAST {return false}
	return !state.mouse_prev_state[button] && state.mouse_curr_state[button]
}
is_mouse_button_released :: proc(button: i32) -> bool {
	if button > glfw.MOUSE_BUTTON_LAST {return false}
	return state.mouse_prev_state[button] && !state.mouse_curr_state[button]
}
