class_name MatchStats
extends RefCounted
# Per-design bookkeeping for the after-action report.
#
# WHY IT EXISTS. after_action_report.gd has been fully written and completely
# orphaned since before this rebuild - OPERATIONS_PLAN.md calls that out - and
# the reason it stayed orphaned is that nothing produced the dictionary it wants:
# blueprint name -> {built, kills, damage_dealt, damage_taken_*, metal_spent,
# hull_type}. The battle layer knew how to spawn a design and how to kill one and
# recorded neither.
#
# KEYED ON THE DESIGN NAME, not on the unit. A report about "what did my Bulwark
# MBT actually do this match" is the question worth answering - it is the one
# that feeds back into the Design Lab - and that has to survive every individual
# Bulwark dying.
#
# ATTRIBUTION IS BEST-EFFORT AND HONEST ABOUT IT. A kill is credited only when
# the killing blow arrives with a source that names a design; splash from a
# detonating harvester, or a unit driven into the sea, lands in nobody's column
# rather than being guessed at. An inflated kill count would be worse than a
# missing one, because the whole point of the report is to inform a redesign.

var _designs: Dictionary = {}
var _elapsed: float = 0.0


func tick(delta: float) -> void:
	_elapsed += delta


func duration() -> float:
	return _elapsed


func _row(design_name: String, hull_type: String = "") -> Dictionary:
	if not _designs.has(design_name):
		_designs[design_name] = {
			"built": 0,
			"lost": 0,
			"kills": 0,
			"damage_dealt": 0.0,
			"damage_taken_kinetic": 0.0,
			"damage_taken_thermal": 0.0,
			"damage_taken_explosive": 0.0,
			"damage_taken_energy": 0.0,
			"metal_spent": 0,
			"hull_type": hull_type,
		}
	elif hull_type != "" and _designs[design_name]["hull_type"] == "":
		_designs[design_name]["hull_type"] = hull_type
	return _designs[design_name]


func record_built(blueprint: Dictionary, metal_cost: int) -> void:
	var row := _row(_name_of(blueprint), blueprint.get("hull_type", ""))
	row["built"] += 1
	row["metal_spent"] += metal_cost


func record_lost(blueprint: Dictionary) -> void:
	_row(_name_of(blueprint))["lost"] += 1


func record_kill(killer_blueprint: Dictionary) -> void:
	if killer_blueprint.is_empty():
		return
	_row(_name_of(killer_blueprint))["kills"] += 1


# `damage_class` is the resolver's own vocabulary, so an unrecognised one is
# dropped rather than silently folded into kinetic - a wrong column is harder to
# notice than a missing number.
func record_damage(dealer: Dictionary, taker: Dictionary,
		amount: float, damage_class: String) -> void:
	if amount <= 0.0:
		return
	if not dealer.is_empty():
		_row(_name_of(dealer))["damage_dealt"] += amount
	if taker.is_empty():
		return
	var key := "damage_taken_" + damage_class
	var row := _row(_name_of(taker))
	if row.has(key):
		row[key] += amount


static func _name_of(blueprint: Dictionary) -> String:
	return str(blueprint.get("name", "UNNAMED"))


# Exactly the shape after_action_report.setup() expects.
func to_report() -> Dictionary:
	return _designs.duplicate(true)


func is_empty() -> bool:
	return _designs.is_empty()
