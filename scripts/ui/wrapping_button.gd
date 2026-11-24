class_name WrappingButton
extends Button
## A Button whose tooltip wraps onto several lines instead of running off
## the side of the screen (Godot's own tooltips are one line per line of
## text, however long). Short tooltips stay on one line. UiStyle.make_button()
## makes these.

## Widest a tooltip gets before it wraps, in pixels.
const MAX_WIDTH := 420.0


func _make_custom_tooltip(for_text: String) -> Object:
	return UiStyle.wrapped_tooltip(for_text, get_theme_font("font"), get_theme_font_size("font_size"))
