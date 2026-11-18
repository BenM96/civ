class_name CameraController
extends Camera2D
## WASD / arrow keys to pan, mouse wheel to zoom, middle mouse to drag.

@export var pan_speed := 900.0
@export var zoom_factor := 1.15
@export var min_zoom := 0.35
@export var max_zoom := 2.5

var _bounds := Rect2()
var _dragging := false


func focus_on(world_pos: Vector2) -> void:
	position = world_pos
	_clamp()


func set_bounds(rect: Rect2) -> void:
	_bounds = rect
	_clamp()


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1
	if dir != Vector2.ZERO:
		position += dir.normalized() * pan_speed * delta / zoom.x
		_clamp()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(zoom_factor, mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(1.0 / zoom_factor, mb.position)
			MOUSE_BUTTON_MIDDLE:
				_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		position -= (event as InputEventMouseMotion).relative / zoom.x
		_clamp()


## Zooms while keeping the world point under the cursor fixed.
func _zoom_at(factor: float, screen_pos: Vector2) -> void:
	var half_view := get_viewport_rect().size / 2.0
	var world_under := position + (screen_pos - half_view) / zoom.x
	var z := clampf(zoom.x * factor, min_zoom, max_zoom)
	zoom = Vector2(z, z)
	position = world_under - (screen_pos - half_view) / z
	_clamp()


func _clamp() -> void:
	if _bounds.has_area():
		position = position.clamp(_bounds.position, _bounds.end)
