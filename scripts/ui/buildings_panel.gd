class_name BuildingsPanel
extends HudPanel
## The buildings inside the hub. (Building new ones will come here later.)


func _init(p_hud: Hud) -> void:
	super(p_hud)
	title = "Buildings"
	button_text = "Buildings"
	tooltip = "Buildings in your hub (B)"
	shortcut = KEY_B
	## A greenhouse: a glass dome with a sprout inside.
	icon_svg = """<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
<rect x="2" y="25" width="28" height="4" rx="1" fill="#9fb4d6"/>
<path d="M4 25a12 12 0 0 1 24 0z" fill="#bfe6ff" fill-opacity="0.45" stroke="#eef4ff" stroke-width="2"/>
<path d="M16 25v-9" stroke="#7dff7a" stroke-width="2.5"/>
<path d="M16 19c-4 0-6-2-6-5 4 0 6 2 6 5zm0-2c0-3 2-5 6-5 0 3-2 5-6 5z" fill="#7dff7a"/>
</svg>"""


func get_button_text() -> String:
	var built := player.buildings.size() if player else 0
	return "Buildings  (%d)" % built if built > 0 else button_text


func fill() -> void:
	add_heading("In your hub (%d)" % player.buildings.size())
	if player.buildings.is_empty():
		add_note("No buildings yet.")
	for building in player.buildings:
		var label := Label.new()
		var output := building.get_output_text()
		label.text = building.display_name + ("  (%s)" % output if output != "" else "")
		label.tooltip_text = building.description
		label.mouse_filter = Control.MOUSE_FILTER_PASS  # So the tooltip shows.
		add(label)
