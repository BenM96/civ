class_name ResearchPanel
extends HudPanel
## The colony's research (see Tech, TechTrees): one column per tech tree,
## each showing the tech that can be researched now (its cost, what it does,
## and a Research button - or why it can't be yet), the one after it greyed
## out, and what's been researched on that tree already. Research is paid in
## Electrum and finished at the end of the turn (via hud.research_requested).

const COLUMN_WIDTH := 300.0
const GAP := 10

const CARD_COLOR := Color(0.2, 0.15, 0.14, 0.95)
const NEXT_COLOR := Color(0.13, 0.1, 0.1, 0.95)
const READY_BORDER := Color(0.4, 0.85, 1.0, 0.8)
const BLOCKED_BORDER := Color(1, 1, 1, 0.15)


func _init(p_hud: Hud) -> void:
	super(p_hud)
	title = "Research"
	button_text = "Research"
	tooltip = "Research new technologies with Electrum (R)"
	shortcut = KEY_R
	panel_width = TechTrees.TREE_COUNT * COLUMN_WIDTH + (TechTrees.TREE_COUNT - 1) * GAP + 16
	## A flask with a bubbling blue liquid.
	icon_svg = """<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
<path d="M12 3h8M13 3v9L5 26a2 2 0 0 0 2 3h18a2 2 0 0 0 2-3L19 12V3" fill="none" stroke="#eef4ff" stroke-width="2.2" stroke-linejoin="round"/>
<path d="M8.5 21h15l2.3 4.2a1 1 0 0 1-.9 1.5H7.1a1 1 0 0 1-.9-1.5z" fill="#3d8cff"/>
<circle cx="14" cy="17" r="1.6" fill="#7fb6ff"/><circle cx="18" cy="14" r="1.1" fill="#7fb6ff"/>
</svg>"""


func get_button_text() -> String:
	var researching := player.research_queue.size() if player else 0
	return "Research  (%d)" % researching if researching > 0 else button_text


func fill() -> void:
	if player.tech_trees == null:
		add_note("No tech trees in this game.")
		return
	var electrum := player.get_resource(ResourceDeposit.Type.ELECTRUM)
	add_note("Paid in Electrum (you have %d); finished at the end of the turn. Each tree is researched in order." % electrum)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP)
	for tree in player.tech_trees.trees.size():
		row.add_child(_make_tree_column(tree))
	add(row)


## One tree: the tech available now, the one after it, and what's done.
func _make_tree_column(tree: int) -> VBoxContainer:
	var ids: Array = player.tech_trees.trees[tree]
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = COLUMN_WIDTH
	column.add_theme_constant_override("separation", 6)
	var done: Array[String] = []
	for tech_id: String in ids:
		if player.has_tech(tech_id):
			done.append(tech_id)
	column.add_child(UiStyle.heading("Tree %d  (%d/%d researched)" % [tree + 1, done.size(), ids.size()]))
	var position := done.size()
	if position >= ids.size():
		column.add_child(UiStyle.note("Every tech on this tree is researched."))
	else:
		column.add_child(_make_current_card(ids[position]))
		if position + 1 < ids.size():
			column.add_child(_make_next_card(ids[position + 1]))
	if not done.is_empty():
		column.add_child(_small("Researched: " + ", ".join(done.map(
			func(tech_id: String) -> String: return TechList.get_tech(tech_id).display_name))))
	return column


## The tech that can be researched next on its tree, with a Research button
## (or Cancel if it's already paid for this turn).
func _make_current_card(tech_id: String) -> PanelContainer:
	var tech := TechList.get_tech(tech_id)
	var reason := player.get_research_refusal(tech_id)
	var researching := tech_id in player.research_queue
	var border := READY_BORDER if reason == "" or researching else BLOCKED_BORDER
	var card := _card(CARD_COLOR, border)
	var lines: VBoxContainer = card.get_child(0)
	lines.add_child(_title_line(tech))
	lines.add_child(_small(tech.get_effect_text(), 0.85))
	if tech.requires != "":
		lines.add_child(_small("Needs: %s" % TechList.get_tech(tech.requires).display_name))
	var cost := player.get_research_cost(tech_id)
	if researching:
		var row := HBoxContainer.new()
		var label := _small("Researching - done at the end of the turn", 0.9)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var cancel := UiStyle.make_button("Cancel", func() -> void: hud.cancel_research_requested.emit(tech_id))
		cancel.tooltip_text = "Call it off and get back %s." % ResourceDeposit.format_cost(cost)
		row.add_child(cancel)
		lines.add_child(row)
	else:
		var button := UiStyle.make_button("Research - %s" % ResourceDeposit.format_cost(cost),
			func() -> void: hud.research_requested.emit(tech_id))
		button.disabled = reason != ""
		button.tooltip_text = ("Can't research yet: %s." % reason) if reason != "" else "Pay now; researched at the end of the turn."
		lines.add_child(button)
		if reason != "":
			var why := _small("Can't yet: %s" % reason, 0.9)
			why.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
			lines.add_child(why)
	return card


## The tech after the current one: shown so you can plan, but greyed out.
func _make_next_card(tech_id: String) -> PanelContainer:
	var tech := TechList.get_tech(tech_id)
	var card := _card(NEXT_COLOR, BLOCKED_BORDER)
	card.modulate = Color(1, 1, 1, 0.6)
	var lines: VBoxContainer = card.get_child(0)
	var top := _small("Next on this tree - %s" % ResourceDeposit.format_cost(player.get_research_cost(tech_id)), 0.8)
	lines.add_child(top)
	lines.add_child(_title_line(tech))
	lines.add_child(_small(tech.get_effect_text(), 0.85))
	if tech.requires != "":
		lines.add_child(_small("Needs: %s" % TechList.get_tech(tech.requires).display_name))
	return card


## "Tank Destroyer" with "Tier 3" on the right.
func _title_line(tech: Tech) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = tech.display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var tier := _small("Tier %d" % tech.tier, 0.7)
	tier.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(tier)
	return row


func _card(bg: Color, border: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.box_style(bg, border, 2, 6))
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 3)
	card.add_child(lines)
	return card


func _small(text: String, alpha := 0.7) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = Color(1, 1, 1, alpha)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
