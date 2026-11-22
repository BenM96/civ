class_name TechTrees
extends RefCounted
## This game's tech trees: every tech in TechList dealt out to TREE_COUNT
## trees, TECHS_PER_TREE_TIER per tree per tier, tier 1 first - so each tree
## goes 2 tier-1 techs, 2 tier-2 techs, and so on. Which techs land on which
## tree (and in which order within a tier) is shuffled from the map's seed,
## so every colony in a game shares the same trees, and a saved game gets
## the same ones back without storing them.
##
## A tree is researched in order: each tech needs the one before it on its
## tree, and the Nth costs N Electrum (see get_cost()). A tech may also need
## another (Tech.requires) on any tree - always from a lower tier, so a
## tree can never get stuck waiting on something behind itself.

const TREE_COUNT := 3
const TECHS_PER_TREE_TIER := 2

## Tree index -> its tech ids, in research order.
var trees: Array = []


func _init(seed_value: int) -> void:
	TechList.check()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 23
	for i in TREE_COUNT:
		trees.append([])
	for tier in range(1, TechList.tier_count() + 1):
		var ids: Array[String] = []
		for t in TechList.in_tier(tier):
			ids.append(t.id)
		# Fisher-Yates with our own rng (Array.shuffle() would use the global one).
		for i in range(ids.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp := ids[i]
			ids[i] = ids[j]
			ids[j] = tmp
		for i in ids.size():
			trees[(i / TECHS_PER_TREE_TIER) % TREE_COUNT].append(ids[i])


## Electrum it costs to research the tech at `position` (0 = first) on its tree.
static func get_cost(position: int) -> int:
	return position + 1


## Which tree a tech is on and where: [tree, position], or [-1, -1].
func find(tech_id: String) -> Array:
	for tree in trees.size():
		var position: int = trees[tree].find(tech_id)
		if position >= 0:
			return [tree, position]
	return [-1, -1]


## Electrum it costs to research `tech_id`.
func get_cost_of(tech_id: String) -> int:
	return get_cost(find(tech_id)[1])


## The tech before `tech_id` on its tree (it must be researched first), or "".
func get_previous(tech_id: String) -> String:
	var at := find(tech_id)
	return trees[at[0]][at[1] - 1] if at[1] > 0 else ""
