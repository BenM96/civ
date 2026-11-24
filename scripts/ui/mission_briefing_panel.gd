class_name MissionBriefingPanel
extends HudPanel
## The units in the hub's Mission Briefing room (see MissionBriefingRoom) -
## the only ones that can be given orders. Each gets a mission dropdown, a
## repeat dropdown (how many times to do it) and a Select Target button (Give
## Order for orders with no tile to pick). Besides missions, the dropdown
## offers two hub orders, which move the unit to another room: Wait (off
## duty in its Break Room, Barracks, Hangar or Garage, for the number of
## turns in the repeat dropdown) and, for an injured unit, Heal (to the Med
## Bay or Garage). Units in other rooms are in the Central Hub panel.

## Unit id -> the mission kind picked in its dropdown this session. Takes
## priority over the unit's last mission (once sent, they're the same).
var _chosen_mission: Dictionary = {}
## The repeat choices: how many times, and its label.
const REPEAT_CHOICES := [[1, "1"], [5, "5"], [10, "10"], [20, "20"], [Orders.REPEAT_FOREVER, "INF"]]
## Dropdown entries that are hub orders (a room move), not missions.
const WAIT := "wait"
const HEAL := "heal"


func _init(p_hud: Hud) -> void:
	super(p_hud)
	title = "Mission Briefing"
	button_text = "Mission Briefing"
	tooltip = "Mission Briefing: give orders to the units waiting for them (M)"
	shortcut = KEY_M
	icon_svg = """<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
<circle cx="22" cy="10" r="4.5" fill="#9fb4d6"/><path d="M14 27c1-6 4-9 8-9s7 3 8 9z" fill="#9fb4d6"/>
<circle cx="11" cy="11" r="5.5" fill="#eef4ff"/><path d="M1 29c0-7 4-11 10-11s10 4 10 11z" fill="#eef4ff"/>
</svg>"""


func get_button_text() -> String:
	var idle := player.get_units_needing_orders().size() if player else 0
	return "%s  (%d ready)" % [button_text, idle] if idle > 0 else button_text


func fill() -> void:
	var ready := player.get_units_needing_orders()
	add_heading("Ready for orders (%d)" % ready.size())
	if ready.is_empty():
		add_note("Nobody is waiting for orders.")
	for unit in ready:
		add(_make_ready_row(unit))
	var elsewhere := player.get_garrison().size() - ready.size()
	if elsewhere > 0:
		add_separator()
		add_note("%d more unit(s) in other rooms of the hub.\nOpen Central Hub (H) and drag them here to give them orders." % elsewhere)


## Name, mission dropdown, repeat dropdown (civilians, or turns for Wait,
## QRF and Intercept) and Select Target (or Give Order).
func _make_ready_row(unit: Unit) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = unit.display_name
	name_label.custom_minimum_size.x = 84
	row.add_child(name_label)
	var u := unit
	var picker := _make_mission_picker(unit)
	row.add_child(picker)
	var repeat := _make_repeat_picker()
	row.add_child(repeat)
	var target := UiStyle.make_button("Select Target", func() -> void:
		if picker.selected < 0:
			return
		var kind: String = picker.get_item_metadata(picker.selected)
		var times: int = repeat.get_item_metadata(repeat.selected) if repeat.visible else 1
		if kind == WAIT:
			hud.room_move_requested.emit(u, player.get_quarters_for(u).id, maxi(times, 0))  # INF: until moved.
		elif kind == HEAL:
			hud.room_move_requested.emit(u, _healing_room(u).id, 0)
		else:
			hud.mission_requested.emit(u, kind, times))
	target.disabled = picker.selected < 0
	# Escorts, QRF, Wait and Heal need no tile: the button gives the order
	# straight away.
	var label_for := func(i: int) -> void:
		var kind := str(picker.get_item_metadata(i)) if i >= 0 else ""
		var no_tile := i >= 0 and (kind == WAIT or kind == HEAL or not Orders.needs_target(kind, player))
		repeat.visible = _shows_repeats(u, kind)
		target.text = "Give Order" if no_tile else "Select Target"
		target.tooltip_text = "Sends the order now (no tile to pick)." if no_tile \
			else "Then click a tile on the map to send this unit there."
	label_for.call(picker.selected)
	picker.item_selected.connect(label_for)
	row.add_child(target)
	return row


## The room that heals units like `unit` (built or not), or null if none does
## (e.g. aircraft, which are repaired by refitting).
func _healing_room(unit: Unit) -> Room:
	for room in player.rooms:
		if room.heals_unit(unit):
			return room
	return null


## Whether the repeat dropdown is shown for `kind`: always for civilians;
## military units never repeat orders, so for them it only shows for orders
## that last a number of turns (Wait, QRF, Intercept).
func _shows_repeats(unit: Unit, kind: String) -> bool:
	if unit.unit_type == Unit.UnitType.CIVILIAN:
		return true
	return kind in [WAIT, "qrf", "intercept"]


## How many times to do the order: 1, 5, 10, 20 or forever (INF). Always
## starts on 1.
func _make_repeat_picker() -> OptionButton:
	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE  # Keep Enter for End Turn.
	UiStyle.style_button(picker)
	for choice: Array in REPEAT_CHOICES:
		var i := picker.item_count
		picker.add_item(choice[1])
		picker.set_item_metadata(i, choice[0])
	picker.selected = 0
	picker.tooltip_text = "How many times to do this order (for Wait, QRF and Intercept, how many turns; Heal and Regroup ignore it). Military units never repeat orders, so for them it only shows for Wait, QRF and Intercept."
	picker.tooltip_text += " Each time the unit gets back to Mission Briefing it's given the order again (if it's hurt, once it's healed). INF keeps going until you press Cancel in Field while it's waiting to set out, or press RTB in Central Hub."
	return picker


## A dropdown of `unit`'s missions. Opens on the mission the unit did last
## (Unit.last_mission_kind), and remembers a new pick per unit so it
## survives the panel being rebuilt.
func _make_mission_picker(unit: Unit) -> OptionButton:
	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE  # Keep Enter for End Turn.
	# Same width on every row (not sized to the longest entry), so rows line up.
	picker.fit_to_longest_item = false
	picker.clip_text = true
	picker.custom_minimum_size.x = 150
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyle.style_button(picker)
	# What you've picked for it just now, else the mission it did last time.
	var remembered: String = _chosen_mission.get(unit.id, unit.last_mission_kind)
	for choice in _mission_choices(unit):
		var i := picker.item_count
		picker.add_item(choice[1])
		picker.set_item_metadata(i, choice[0])
		# A 5th entry, if there is one, says why it's unavailable.
		var why: String = choice[4] if choice.size() > 4 else "Can't afford: %s" % choice[2].to_lower()
		picker.set_item_tooltip(i, choice[2] if choice[3] else why)
		picker.set_item_disabled(i, not choice[3])
	# Select the remembered mission if it's still possible, else the first one that is.
	picker.selected = -1
	for i in picker.item_count:
		if not picker.is_item_disabled(i) and (picker.selected < 0 or picker.get_item_metadata(i) == remembered):
			picker.selected = i
	var id := unit.id
	picker.item_selected.connect(func(i: int) -> void:
		_chosen_mission[id] = picker.get_item_metadata(i))
	return picker


## Every mission `unit` may be given, as [kind, label, tooltip, affordable],
## in the order the dropdown lists them. Driven by the unit's
## allowed_missions, so a new unit type needs no HUD changes.
func _mission_choices(unit: Unit) -> Array:
	var choices := []
	if unit.can_take("move"):
		choices.append(["move", "Move", "Walk to a tile, then come home.", true])
	if unit.can_take("guard"):
		choices.append(["guard", "Guard (%d turns)" % GuardMission.GUARD_TURNS,
			"Hold a tile for %d turns, fighting any enemy that comes onto it, then come home." % GuardMission.GUARD_TURNS, true])
	if unit.can_take("escort"):
		for other in player.units:
			var m := EscortMission.new(other.id)
			if m.get_invalid_reason(unit) == "":
				var plans := "" if other.mission == null else " (%s)" % other.mission.get_description()
				choices.append(["escort:%d" % other.id, "Escort %s%s" % [other.display_name, plans],
					"Follow %s wherever it goes and fight beside it, then come home with it. Sets off as soon as %s does - no target to pick." % [
						other.display_name, other.display_name], true])
	var refit := player.get_refit_turns(unit)
	if unit.can_take("sortie"):
		choices.append(["sortie", "Sortie",
			"Pick any tile but a hub. Before anyone on the ground moves, flies straight there and fights whoever is on it (and anyone who walks onto it); flies home at the end of the same turn, then refits in the Hangar for %d turns (fully repairing it)." % refit, true])
	if unit.can_take("intercept"):
		choices.append(["intercept", "Intercept",
			"Stand by in the Hangar for the number of turns picked in the next dropdown (INF: until you drag it out). When enemy aircraft come onto our structures or onto or next to our hub, flies straight at them that same turn (nearest the hub first, 2 of ours for each of theirs), fights, and flies home at the end of the turn. Then it refits for %d turns and goes back on standby." % refit, true])
	if unit.can_take("carpet_bomb"):
		choices.append(["carpet_bomb", "Carpet Bomb",
			"Pick a tile with something man-made on it, or an enemy hub. Before anyone on the ground moves, flies straight there; if it comes through the battle, it flattens everything man-made on the tile (leaving rubble) or knocks 1 off the hub's health, then flies home that turn and refits for %d turns." % refit, true])
	if unit.can_take("qrf"):
		choices.append(["qrf", "QRF (quick reaction force)",
			"Stand by in the QRF room - or, if you have an FOB linked to the hub, pick the hub or an FOB on the map to be based at - for the number of turns picked in the next dropdown (INF: until you drag it out or recall it). After everyone else has moved each turn, head for the nearest enemy on one of our extractors or belts; come back when they've gone. Hurt, it goes to be healed and then back on duty. When the time is up it comes to Mission Briefing (once it's home, if it's out chasing).", true])
	if unit.can_take("regroup"):
		choices.append(["regroup", "Regroup",
			"Regroup the whole ground army: every military unit comes home (dropping its mission - QRF units carry on with theirs) and stands by in the QRF room (defending like the QRF, healing when hurt) until all of them are home and at full health. Then they all come to Mission Briefing together. Aircraft aren't part of it.", true])
	if unit.can_take("capture"):
		choices.append(["capture", "Capture",
			"Take over another colony's extractor, conveyor belt or command point. Takes %d turns on the spot." % CaptureMission.CAPTURE_TURNS, true])
	if unit.can_take("harvest"):
		choices.append(["harvest", "Harvest", "Bring back 1 resource from a deposit.", true])
	if unit.can_take("build"):
		for b in player.buildables:
			# Line jobs pay as they go, so they're always offered; the order
			# itself says if you can't afford to start.
			if b.line_of == b.id:
				var extra := "" if b.requires.is_empty() else " (and %ss where missing)" % " / ".join(
					b.requires.map(func(r: String) -> String: return player.get_buildable(r).display_name))
				choices.append(["build:" + b.id, "Build %ss (%s each)" % [b.display_name, b.get_cost_text()],
					"Pick a tile: builds a %s%s on every tile from the hub to there, paying as it goes. Stops and comes home if you run out." % [
						b.display_name, extra], true])
			elif b.line_of != "":
				var line_name := player.get_buildable(b.line_of).display_name
				var locked := player.get_buildable_refusal(b)
				var label := "Build %s (%s, + %ss to hub)" % [b.display_name, b.get_cost_text(), line_name]
				choices.append(["build:" + b.id, label + ("  - %s" % locked if locked != "" else ""),
					"Pick %s: lays foundations and %ss from the hub to it where missing, then builds the %s. Pays as it goes." % [b.site_name,
						line_name, b.display_name], locked == "", "Can't yet: %s." % locked])
			else:
				choices.append(["build:" + b.id, "Build %s (%s)" % [b.display_name, b.get_cost_text()],
					"Costs %s." % b.get_cost_text(), player.can_afford(b.cost)])
	if unit.can_take("demolish"):
		choices.append(["demolish", "Demolish",
			"Tear down foundations, bridges, extractors, conveyors or command points on a tile, leaving rubble - or, from next to an enemy hub, knock 1 off its health (at 0 that colony is out). Takes %d turns on the spot." % DemolitionBuildable.new().build_turns, true])
	# Hub orders: move to another room.
	var healer := _healing_room(unit)
	if healer and unit.is_injured():
		var refusal := player.get_room_move_refusal(unit, healer.id)
		choices.append([HEAL, "Heal (%s)" % healer.display_name,
			"Go to the %s to be healed (%d/%d HP). Comes back to Mission Briefing once fully healed." % [
				healer.display_name, unit.health, unit.max_health],
			refusal == "", "Can't yet: %s." % refusal])
	var quarters := player.get_quarters_for(unit)
	if quarters:
		choices.append([WAIT, "Wait (off duty)",
			"Go off duty in the %s for the number of turns picked in the next dropdown, then come back to Mission Briefing (INF: stay until you drag it out). Units off duty don't need orders, so idle turns can be skipped." % quarters.display_name,
			true])
	return choices
