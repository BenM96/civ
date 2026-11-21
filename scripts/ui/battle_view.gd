class_name BattleView
extends Control
## Replays one battle on a screen of its own (see Hud.play_battle()): the
## battle's hexes - where enemies met (outlined) and every tile around them -
## blown up to fill the screen with every unit standing on them, then each shot in the order Combat fired it - the shooter pulses, a
## bullet flies, the target flashes and loses HP. Units that break run off
## the screen by the nearest edge; units that die burst and fade away.
##
## Everything comes from the battle's report (see Combat), so this only
## draws - the battle has already been fought by the time it plays.

## Emitted when the replay ends. `skip_rest` is true if the player asked to
## skip every remaining battle this turn.
signal finished(skip_rest: bool)

## Seconds for each part of a shot at normal speed.
const PULSE_TIME := 0.15
const BULLET_TIME := 0.25
const HIT_TIME := 0.3
const FLEE_TIME := 0.7
const DIE_TIME := 0.6
## Big battles play faster, so no replay runs much longer than this many
## shots' worth of time.
const MAX_SHOTS_AT_FULL_TIME := 12
## Space kept clear for the title and the buttons.
const MARGIN_TOP := 70.0
const MARGIN_BOTTOM := 90.0
const MARGIN_SIDE := 40.0

var _report: Dictionary
var _map: HexMap
## Unit id -> what's drawn for it: {"base": Vector2 (its spot in its hex),
## "offset": Vector2 (running away), "scale", "alpha", "flash" (0..1 white),
## "hp" (float, animated), "dead": bool, "radius": float}.
var _units := {}
var _hex_size := 1.0
var _origin := Vector2.ZERO
## The bullet in flight: {"from", "to", "t"}, or empty.
var _bullet := {}
## Floating text: [{"text", "pos", "color", "t"}].
var _popups: Array[Dictionary] = []
var _speed := 1.0
var _skip := false
var _skip_rest := false
var _footer: Label


func setup(report: Dictionary, map: HexMap) -> void:
	_report = report
	_map = map
	for id in report["units"]:
		var u: Dictionary = report["units"][id]
		_units[id] = {"base": Vector2.ZERO, "offset": Vector2.ZERO, "scale": 1.0, "alpha": 1.0,
			"flash": 0.0, "hp": float(u["hp"]), "dead": false, "radius": 20.0}
	var shots: int = report["events"].size()
	_speed = clampf(float(MAX_SHOTS_AT_FULL_TIME) / maxf(shots, 1.0), 0.35, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # Nothing reaches the map.

	var title := Label.new()
	title.text = "Battle at %s" % _hexes_text()
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 12
	add_child(title)

	var sides := Label.new()
	sides.text = "  vs  ".join(_side_names())
	sides.modulate = Color(1, 1, 1, 0.75)
	sides.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sides.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sides.offset_top = 48
	add_child(sides)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -MARGIN_BOTTOM + 8
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(bottom)
	_footer = Label.new()
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_footer)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	bottom.add_child(buttons)
	buttons.add_child(_make_button("Skip", func() -> void: _skip = true))
	buttons.add_child(_make_button("Skip all battles", func() -> void:
		_skip = true
		_skip_rest = true))

	resized.connect(_layout)
	_layout()


## Plays the whole battle, then emits `finished`.
func play() -> void:
	await get_tree().process_frame  # So callers can always await `finished`.
	await _wait(0.5)
	for event: Dictionary in _report["events"]:
		if _skip:
			break
		if event["type"] == "flee":
			_popup("Flees!", event["unit"], Color(1.0, 0.85, 0.4))
			await _flee(event["unit"])
		else:
			await _shoot(event)
	if not _skip:
		_footer.text = _report["message"]
		await _wait(1.6 / _speed)  # Time to read the result (not sped up).
	finished.emit(_skip_rest)


# --- Animation steps -------------------------------------------------------

func _shoot(event: Dictionary) -> void:
	var shooter: Dictionary = _units[event["from"]]
	var target: Dictionary = _units[event["to"]]
	# The shooter pulses...
	await _animate(PULSE_TIME, func(t: float) -> void: shooter["scale"] = 1.0 + 0.3 * sin(t * PI))
	# ...a bullet flies...
	var from := _unit_pos(shooter)
	var to := _unit_pos(target)
	await _animate(BULLET_TIME, func(t: float) -> void: _bullet = {"from": from, "to": to, "t": t})
	_bullet = {}
	# ...and the target flashes and loses HP.
	var hp_before: float = target["hp"]
	var hp_after := float(event["hp"])
	if event["damage"] > 0:
		_popup("-%d" % event["damage"], event["to"], Color(1.0, 0.35, 0.3))
	else:
		_popup("no effect", event["to"], Color(0.8, 0.8, 0.8))
	await _animate(HIT_TIME, func(t: float) -> void:
		target["flash"] = 1.0 - t
		target["hp"] = lerpf(hp_before, hp_after, t))
	match event["result"]:
		"dead":
			await _die(event["to"])
		"broken":
			_popup("Breaks!", event["to"], Color(1.0, 0.85, 0.4))
			await _flee(event["to"])


## Runs off the screen by the nearest edge.
func _flee(id: int) -> void:
	var v: Dictionary = _units[id]
	# Straight out through the nearest edge of the screen.
	var pos := _unit_pos(v)
	var exits := [
		[pos.x, Vector2.LEFT],
		[size.x - pos.x, Vector2.RIGHT],
		[pos.y, Vector2.UP],
		[size.y - pos.y, Vector2.DOWN],
	]
	var nearest: Array = exits[0]
	for exit: Array in exits:
		if exit[0] < nearest[0]:
			nearest = exit
	var dir: Vector2 = nearest[1]
	var distance: float = nearest[0] + v["radius"] * 3.0 + 60.0  # Clear of the edge, label too.
	await _animate(FLEE_TIME, func(t: float) -> void:
		v["offset"] = dir * distance * t * t  # Speeds up as it goes.
		v["alpha"] = 1.0 - t * 0.5)
	v["alpha"] = 0.0


## Turns red, swells and fades away.
func _die(id: int) -> void:
	var v: Dictionary = _units[id]
	v["dead"] = true
	_popup("Destroyed", id, Color(1.0, 0.3, 0.25))
	await _animate(DIE_TIME, func(t: float) -> void:
		v["scale"] = 1.0 + t * 0.6
		v["alpha"] = 1.0 - t)


func _popup(text: String, id: int, color: Color) -> void:
	var v: Dictionary = _units[id]
	var popup := {"text": text, "pos": _unit_pos(v) - Vector2(0, v["radius"] + 10), "color": color, "t": 0.0}
	_popups.append(popup)
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		popup["t"] = t
		queue_redraw(), 0.0, 1.0, 0.9 * _speed)
	tween.tween_callback(func() -> void: _popups.erase(popup))


## Runs `step` with t going 0 -> 1 over `seconds` (scaled by the speed),
## redrawing as it goes. Ends at once if the player skips.
func _animate(seconds: float, step: Callable) -> void:
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		step.call(t)
		queue_redraw(), 0.0, 1.0, seconds * _speed)
	while tween.is_valid() and tween.is_running() and not _skip:
		await get_tree().process_frame
	if tween.is_valid():
		tween.kill()
	step.call(1.0)
	queue_redraw()


func _wait(seconds: float) -> void:
	await _animate(seconds, func(_t: float) -> void: pass)


# --- Layout and drawing ----------------------------------------------------

## Fits the battle's hexes into the space between the title and buttons, and
## places each unit in its hex.
func _layout() -> void:
	var hexes: Array = _report["hexes"]
	var bounds := Rect2(Hex.to_pixel(hexes[0], 1.0), Vector2.ZERO)
	for h: Vector2i in hexes:
		for corner in Hex.corners(Hex.to_pixel(h, 1.0), 1.0):
			bounds = bounds.expand(corner)
	var area := Rect2(MARGIN_SIDE, MARGIN_TOP, size.x - MARGIN_SIDE * 2, size.y - MARGIN_TOP - MARGIN_BOTTOM)
	if area.size.x <= 0 or area.size.y <= 0 or bounds.size.x <= 0:
		return
	_hex_size = minf(area.size.x / bounds.size.x, area.size.y / bounds.size.y)
	_origin = area.get_center() - bounds.get_center() * _hex_size

	# Units in each hex, by colony then id, in a grid.
	var by_hex := {}
	for id in _report["units"]:
		var h: Vector2i = _report["units"][id]["hex"]
		if not by_hex.has(h):
			by_hex[h] = []
		by_hex[h].append(id)
	for h in by_hex:
		var ids: Array = by_hex[h]
		ids.sort_custom(func(a: int, b: int) -> bool:
			var fa: int = _report["units"][a]["faction"]
			var fb: int = _report["units"][b]["faction"]
			return fa < fb or (fa == fb and a < b))
		var cols := ceili(sqrt(ids.size()))
		var rows := ceili(float(ids.size()) / cols)
		# Rows get extra height for the name and HP under each unit.
		var cell := minf(_hex_size * 1.15 / cols, _hex_size * 1.2 / (rows * 1.35))
		var radius := minf(minf(cell * 0.28, _hex_size * 0.2), 44.0)
		var center := _hex_center(h)
		for i in ids.size():
			var col := i % cols
			var row := i / cols
			var v: Dictionary = _units[ids[i]]
			v["base"] = center + Vector2((col - (cols - 1) / 2.0) * cell, ((row - (rows - 1) / 2.0) * 1.35 - 0.15) * cell)
			v["radius"] = radius
	queue_redraw()


func _hex_center(h: Vector2i) -> Vector2:
	return _origin + Hex.to_pixel(h, 1.0) * _hex_size


func _unit_pos(v: Dictionary) -> Vector2:
	return v["base"] + v["offset"]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.03, 0.03, 0.88))
	# Surrounding hexes first, then the core (where enemies met) outlined on top.
	for in_core in [false, true]:
		for h: Vector2i in _report["hexes"]:
			if (h in _report["core"]) != in_core:
				continue
			var tile := _map.get_tile(h) if _map else null
			var color := Terrain.get_color(tile.terrain) if tile else Color(0.82, 0.42, 0.2)
			var corners := Hex.corners(_hex_center(h), _hex_size * 0.97)
			draw_colored_polygon(corners, color if in_core else color.darkened(0.15))
			var outline := corners.duplicate()
			outline.append(corners[0])
			if in_core:
				draw_polyline(outline, Color(1.0, 0.8, 0.35), 4.0, true)
			else:
				draw_polyline(outline, color.darkened(0.45), 3.0, true)

	var font := ThemeDB.fallback_font
	for id in _units:
		var v: Dictionary = _units[id]
		if v["alpha"] <= 0.0:
			continue
		var info: Dictionary = _report["units"][id]
		var pos := _unit_pos(v)
		var r: float = v["radius"] * v["scale"]
		var a: float = v["alpha"]
		var body: Color = info["color"]
		if v["dead"]:
			body = Color(0.9, 0.2, 0.15)
		body = body.lerp(Color.WHITE, v["flash"])
		draw_circle(pos, r + r * 0.25, _with_alpha(Faction.get_color(info["faction"]), a))
		draw_circle(pos, r + r * 0.1, Color(0, 0, 0, 0.8 * a))
		draw_circle(pos, r, _with_alpha(body, a))
		var letter: String = str(info["type"]).left(1)
		_draw_centered(font, letter, pos, roundi(r * 1.1), Color(0.1, 0.1, 0.1, a))
		if v["dead"]:
			var d := r * 0.6
			draw_line(pos + Vector2(-d, -d), pos + Vector2(d, d), Color(0.1, 0, 0, a), 4.0)
			draw_line(pos + Vector2(-d, d), pos + Vector2(d, -d), Color(0.1, 0, 0, a), 4.0)
		# HP bar and name underneath.
		var bar := Rect2(pos + Vector2(-r, r * 1.35), Vector2(r * 2.0, maxf(4.0, r * 0.18)))
		draw_rect(bar, Color(0, 0, 0, 0.85 * a))
		var fraction := clampf(v["hp"] / float(info["max_hp"]), 0.0, 1.0)
		var fill := Color(0.4, 0.9, 0.35) if v["hp"] >= info["max_hp"] / 2.0 else Color(0.95, 0.3, 0.25)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), _with_alpha(fill, a))
		var text_size := clampi(roundi(r * 0.4), 9, 16)
		var unit_name: String = info["name"]
		if r < 20.0:  # Small: "Infantry 2" -> "Inf 2", so neighbours' labels don't collide.
			unit_name = "%s %s" % [str(info["type"]).left(3), unit_name.get_slice(" ", unit_name.get_slice_count(" ") - 1)]
		_draw_centered(font, unit_name, Vector2(pos.x, bar.end.y + text_size * 0.9), text_size, Color(1, 1, 1, a))
		_draw_centered(font, ("HP %d/%d" if r >= 20.0 else "%d/%d") % [maxi(roundi(v["hp"]), 0), info["max_hp"]],
			Vector2(pos.x, bar.end.y + text_size * 2.1), text_size, Color(1, 1, 1, 0.75 * a))

	if not _bullet.is_empty():
		var p: Vector2 = _bullet["from"].lerp(_bullet["to"], _bullet["t"])
		var tail: Vector2 = _bullet["from"].lerp(_bullet["to"], maxf(_bullet["t"] - 0.25, 0.0))
		draw_line(tail, p, Color(1.0, 0.9, 0.5, 0.6), 3.0)
		draw_circle(p, 6.0, Color(1.0, 0.95, 0.6))

	for popup in _popups:
		var t: float = popup["t"]
		var c: Color = popup["color"]
		_draw_centered(font, popup["text"], popup["pos"] - Vector2(0, 30 * t), 22, _with_alpha(c, 1.0 - t * t))


func _draw_centered(font: Font, text: String, center: Vector2, font_size: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	draw_string(font, center + Vector2(-width / 2.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


func _hexes_text() -> String:
	var parts: PackedStringArray = []
	for h: Vector2i in _report["core"]:
		parts.append("(%d, %d)" % [h.x, h.y])
	return ", ".join(parts)


## Each colony in the battle, e.g. ["Your colony (2)", "Pink colony (1)"].
func _side_names() -> PackedStringArray:
	var counts := {}
	for id in _report["units"]:
		var f: int = _report["units"][id]["faction"]
		counts[f] = counts.get(f, 0) + 1
	var factions := counts.keys()
	factions.sort()
	var names: PackedStringArray = []
	for f in factions:
		names.append("%s (%d)" % [Faction.get_display_name(f), counts[f]])
	return names


func _make_button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 36)
	b.pressed.connect(on_pressed)
	return b
