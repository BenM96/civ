class_name UiStyle
extends RefCounted
## The HUD's look, shared by every part of it (Hud and its panels): box and
## bar styles, the rust-brown buttons, headings and notes.


static func box_style(bg: Color, border: Color, border_width := 2, radius := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(8)
	return s


## Solid background for the top/bottom bars.
static func bar_style() -> StyleBoxFlat:
	var s := box_style(Color(0.1, 0.07, 0.07, 0.94), Color(0.45, 0.25, 0.18, 0.8), 0, 0)
	s.set_content_margin_all(6)
	return s


static func svg_texture(svg: String) -> Texture2D:
	var image := Image.new()
	if image.load_svg_from_string(svg, 1.25) != OK:
		return null
	return ImageTexture.create_from_image(image)


static func make_button(text: String, on_pressed: Callable) -> Button:
	var b := WrappingButton.new()  # Long tooltips wrap.
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # Keep Enter/arrows for the game.
	b.pressed.connect(on_pressed)
	style_button(b)
	return b


## A tooltip label for `text` that wraps at WrappingButton.MAX_WIDTH, or
## stays on one line if it fits.
static func wrapped_tooltip(text: String, font: Font, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	var widest := 0.0
	for line in text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	if widest > WrappingButton.MAX_WIDTH:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = WrappingButton.MAX_WIDTH
	return label


## The HUD's rust-brown button look, for any kind of button.
static func style_button(b: Button) -> void:
	var normal := box_style(Color(0.3, 0.2, 0.17), Color(0.6, 0.38, 0.28), 1, 4)
	normal.set_content_margin_all(5)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.42, 0.28, 0.22)
	hover.border_color = Color(0.95, 0.65, 0.45)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.2, 0.13, 0.11)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.18, 0.14, 0.13)
	disabled.border_color = Color(0.3, 0.24, 0.22)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)


static func heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	return l


static func note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.55)
	return l
