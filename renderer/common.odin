package renderer

Vec2i :: [2]i32
Vec3i :: [3]i32

Vec2f :: [2]f64
Vec3f :: [3]f64


Texture :: struct {
	height: u32,
	width:  u32,
	data:   []u32,
}

Color :: struct {
	r, g, b, a: u8,
}

Rectf :: struct {
	x, y, w, h: f64,
}

Circlef :: struct {
	x, y, radius: f64,
}
