class_name SpecPlacard
extends PanelContainer
# ONE specification widget, rendered in four places.
#
# THIS IS THE LOAD-BEARING IDEA OF THE WHOLE REDESIGN, so it is worth stating
# plainly. The game's premise is that you design the units. Four different
# screens show a design's specification and, before this, all four invented their
# own layout:
#
#   main_menu.gd          _update_placard_ui()   hand-built stat rows
#   stat_calculator.gd    the telemetry rail     a different set, different order
#   the battle HUD        NOTHING AT ALL         you could not see what you selected
#   after_action_report   a third table
#
# So the player's own work was described to them in three different vocabularies
# and then, at the moment it mattered most - in a fight - not at all. Making it
# one component with four detail levels turns four unrelated screens into one
# continuous conversation about the same object.
#
# HOW IT STAYS FROM BECOMING A GOD-WIDGET. Four explicit levels, each with a
# FIXED field list declared in FIELDS below and asserted by a test. It does not
# take a "show these fields" array, because that is how a shared widget becomes a
# layout engine with sixteen callers each passing something slightly different.
# A fifth caller wanting a fifth level is the signal to split this, not to add a
# fifth entry.
#
# NOTHING IS RE-DERIVED HERE. Every value comes from DesignStats.analyze() or
# from the blueprint dictionary. stat_calculator.gd has twice had to delete a
# local re-derivation that drifted - a capacity calculation that knew 4
# locomotion types of 17, and an armour table showing the explosive threshold
# labelled as energy. This widget formats; it does not compute.

const Tokens = preload("res://scripts/ui_tokens.gd")
const UIShell = preload("res://scripts/ui_shell.gd")
const ModuleCatalogScript = preload("res://scripts/module_catalog.gd")
const DamageResolverScript = preload("res://scripts/damage_resolver.gd")

enum Level {
	FRONT_DESK,   # the menu turntable - identity and a headline or two
	LAB,          # the Design Lab rail - the full engineering picture
	BATTLE,       # the selection panel - what matters while being shot at
	RECORD,       # a design's service dossier
}

# Field id -> human label. The ids are what the level lists below refer to, so a
# typo is a missing row rather than a wrong one.
const LABELS := {
	"hull_class": "Hull Class",
	"faction": "Affiliation",
	"envelope": "Envelope (LxWxH)",
	"modules": "Fitted Modules",
	"armour": "Armour",
	"thresholds": "Thresholds",
	"weight": "Weight",
	"speed": "Top Speed",
	"cost": "Cost",
	"dps": "Damage / sec",
	"range": "Engagement Range",
	"health": "Structure",
	"order": "Current Order",
	"stance": "Stance",
	"sorties": "Sorties",
	"kills": "Confirmed Kills",
	"losses": "Losses",
}

# WHICH FIELDS EACH LEVEL SHOWS, and the order they appear in.
#
# The orders are deliberately NOT the same, because the question each screen
# answers is not the same. The Lab is asked "is this design any good"; the battle
# is asked "is this unit about to die". Health leads in battle and is absent from
# the menu. What IS constant is that a field means the same thing and is
# formatted the same way everywhere it appears - that is the consistency worth
# having, not identical row order.
const FIELDS := {
	Level.FRONT_DESK: ["hull_class", "modules", "armour", "weight", "cost"],
	Level.LAB: ["hull_class", "envelope", "modules", "armour", "thresholds",
		"weight", "speed", "dps", "range", "cost"],
	Level.BATTLE: ["health", "order", "stance", "armour", "dps", "range", "speed"],
	Level.RECORD: ["hull_class", "sorties", "kills", "losses", "cost", "armour"],
}

@export var level: Level = Level.FRONT_DESK

var _title: Label = null
var _subtitle: Label = null
var _rows: VBoxContainer = null
var _row_values: Dictionary = {}


func _ready() -> void:
	theme_type_variation = "CardPanel"
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, Tokens.SPACE_MD)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Tokens.SPACE_XS)
	margin.add_child(col)

	_title = Label.new()
	_title.theme_type_variation = "HeadingLabel"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)

	_subtitle = Label.new()
	_subtitle.theme_type_variation = "HintLabel"
	col.add_child(_subtitle)

	col.add_child(HSeparator.new())

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	col.add_child(_rows)


# --- Population --------------------------------------------------------------

# The generic entry point: a field id -> already-formatted string dictionary.
# Callers that have a DesignStats result use from_stats() instead.
func show_values(design_name: String, subtitle: String, values: Dictionary) -> void:
	if _rows == null:
		return
	_title.text = design_name.to_upper()
	_subtitle.text = subtitle
	for child in _rows.get_children():
		child.queue_free()
	_row_values.clear()

	for field in FIELDS[level]:
		# A field the caller has no value for is SKIPPED, not rendered blank.
		# An empty row reads as "this design has no armour", which is a
		# different and much worse claim than "not measured here".
		if not values.has(field):
			continue
		var label: String = LABELS.get(field, field)
		_row_values[field] = UIShell.stat_row(_rows, label, str(values[field]))


# Formats a blueprint dictionary plus an optional DesignStats result into the
# field set this level wants. The FORMATTING lives here so a weight reads
# "1,240 kg" identically on all four screens; the COMPUTATION does not.
static func values_from(blueprint: Dictionary, stats: Dictionary = {}) -> Dictionary:
	var out := {}

	var hull_type := str(blueprint.get("hull_type", ""))
	if hull_type != "":
		out["hull_class"] = _prettify(hull_type)
		var data: Dictionary = ModuleCatalogScript.get_module_data(hull_type)
		var dim = data.get("dimensions", Vector3.ZERO)
		if dim is Vector3 and dim != Vector3.ZERO:
			out["envelope"] = "%.1f x %.1f x %.1f m" % [dim.z, dim.x, dim.y]

	var hs = blueprint.get("hull_size", {})
	if hs is Dictionary and hs.has("x"):
		out["envelope"] = "%.1f x %.1f x %.1f m" % [
			float(hs.get("z", 0.0)), float(hs.get("x", 0.0)), float(hs.get("y", 0.0))]

	if blueprint.has("faction"):
		out["faction"] = _prettify(str(blueprint["faction"]))

	var modules = blueprint.get("modules", [])
	if modules is Array:
		out["modules"] = str(modules.size())

	var material := str(blueprint.get("armor_material", ""))
	var thickness := float(blueprint.get("armor_thickness", 1.0))
	if material != "":
		out["armour"] = "%s %.1fx" % [_prettify(material), thickness]
		# Kinetic / thermal / explosive, in that order, matching the order
		# damage_resolver.gd's ARMOR_TABLE declares them. A previous version of
		# this readout elsewhere showed the explosive threshold labelled as
		# energy; taking all three from one call in one order is the fix.
		var k: Vector2 = DamageResolverScript.get_material_threshold(material, "kinetic", thickness)
		var t: Vector2 = DamageResolverScript.get_material_threshold(material, "thermal", thickness)
		var e: Vector2 = DamageResolverScript.get_material_threshold(material, "explosive", thickness)
		out["thresholds"] = "K %.0f  T %.0f  E %.0f" % [k.x, t.x, e.x]

	# Everything below comes from DesignStats.analyze(), which makes the same
	# Drivetrain / WeaponRange / ModuleCatalog calls battle_unit.gd makes on the
	# unit it spawns. If it is absent the rows are simply skipped.
	# KEY NAMES ARE DesignStats.analyze()'s OWN, checked against its schema rather
	# than guessed. The plausible-sounding "total_weight" / "total_cost" /
	# "max_range" / "max_hp" are all wrong; the real keys are below. A wrong key
	# here would not error - has() simply returns false and the row silently
	# disappears, which is the worst kind of bug for a readout.
	if stats.has("weight"):
		out["weight"] = "%s kg" % _thousands(int(stats["weight"]))
	if stats.has("top_speed"):
		out["speed"] = "%.1f m/s" % float(stats["top_speed"])
	# cost_credits, not cost_metal + cost_crystal. Metal and crystal are the
	# AUTHORING inputs (crystal converts at 2x); credits is the single number the
	# economy actually spends, so it is the one a player compares designs on.
	if stats.has("cost_credits"):
		out["cost"] = "%s cr" % _thousands(int(stats["cost_credits"]))
	if stats.has("dps"):
		out["dps"] = "%.0f" % float(stats["dps"])
	if stats.has("longest_range"):
		out["range"] = "%.0f m" % float(stats["longest_range"])
	# Structure is the hull plus the pool its modules contribute, which is what
	# battle_unit.gd actually fights with - hull_hp alone understates it.
	if stats.has("hull_hp"):
		out["health"] = str(int(float(stats["hull_hp"])
			+ float(stats.get("module_hp_pool", 0.0))))

	return out


func from_blueprint(design_name: String, subtitle: String,
		blueprint: Dictionary, stats: Dictionary = {}) -> void:
	show_values(design_name, subtitle, values_from(blueprint, stats))


static func _prettify(id: String) -> String:
	if id == "":
		return "-"
	return id.replace("_", " ").capitalize()


# Thousands separators, because a five-digit cost is the number a player compares
# most often and "12400" versus "1240" is a genuinely easy misread at a glance.
static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out
