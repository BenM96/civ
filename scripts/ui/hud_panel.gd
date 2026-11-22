class_name HudPanel
extends RefCounted
## One section of the HUD's bottom bar (Central Hub, Mission Briefing, Field,
## Training, Buildings, Research):
## its button and the panel it opens above the bar. Hud owns the panel frame
## and calls fill() whenever it needs redrawing; each section only adds its
## own rows to `list`.
##
## Panels don't change the game themselves: they ask through Hud's signals
## (e.g. hud.train_requested), which the game turns into orders.
##
## To add a section: make a script extending HudPanel that sets the fields
## below in _init() and overrides fill() (and get_button_text() for a count
## on its button), then add it to Hud.Section and Hud._make_panels().

var hud: Hud
## Shown at the top of the open panel, e.g. "In the Field".
var title := ""
## The bottom-bar button's text when there's nothing to count, e.g. "Field".
var button_text := ""
## Tooltip for the bottom-bar button, e.g. "Units in the field (F)".
var tooltip := ""
## Key that opens/closes the panel.
var shortcut := KEY_NONE
## SVG for the bottom-bar button's icon.
var icon_svg := ""
## How wide the open panel is (it grows taller to fit its rows).
var panel_width := 380.0

## Set by Hud before each fill().
var player: Player
var list: VBoxContainer


func _init(p_hud: Hud) -> void:
	hud = p_hud


## Adds this panel's rows to `list` for `player`. Override.
func fill() -> void:
	pass


## The bottom-bar button's text, e.g. "Units  (2 ready)". Override to add a
## count; `player` may be null before the game has started.
func get_button_text() -> String:
	return button_text


# --- Helpers for filling the list ------------------------------------------

func add(control: Control) -> void:
	list.add_child(control)


func add_heading(text: String) -> void:
	add(UiStyle.heading(text))


func add_note(text: String) -> void:
	add(UiStyle.note(text))


func add_separator() -> void:
	add(HSeparator.new())
