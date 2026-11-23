class_name UITheme
## Shared theme + settings panel for menu and pause screen.

const ACCENT := Color(1.0, 0.42, 0.17)


static func _sb(bg: Color, border: Color, bw := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(10)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 26
	t.set_stylebox("normal", "Button", _sb(Color(0.08, 0.11, 0.18, 0.95), Color(0.3, 0.38, 0.55)))
	t.set_stylebox("hover", "Button", _sb(Color(0.14, 0.18, 0.3, 0.95), ACCENT))
	t.set_stylebox("pressed", "Button", _sb(ACCENT, Color.WHITE))
	t.set_stylebox("focus", "Button", _sb(Color(0, 0, 0, 0), ACCENT))
	t.set_stylebox("disabled", "Button", _sb(Color(0.08, 0.08, 0.1, 0.6), Color(0.2, 0.2, 0.25)))
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.55))
	t.set_stylebox("panel", "PanelContainer", _sb(Color(0.05, 0.07, 0.12, 0.96), Color(0.3, 0.38, 0.55), 2))
	t.set_stylebox("panel", "Panel", _sb(Color(0.05, 0.07, 0.12, 0.9), Color(0.3, 0.38, 0.55), 2))
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	t.set_constant("outline_size", "Label", 4)
	return t


static func button(text: String, cb: Callable, min_w := 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 64)
	b.pressed.connect(func():
		Game.click()
		cb.call())
	return b
