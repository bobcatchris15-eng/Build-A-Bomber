class_name DesignVerdict
extends RefCounted
# Turns a DesignStats.analyze() result into plain-language judgements.
#
# WHY THIS EXISTS. The Design Lab's telemetry rail is accurate and asks the
# player to be an engineer: it prints structure, weight, cost, DPS and drivetrain
# load, and leaves them to work out whether any of that is GOOD. A parametric
# tool leads with the constraint state - Fusion 360 says "Fully Constrained" in
# two words before showing a single dimension, and Onshape colours an
# over-defined sketch. The numbers stay; they stop being the first thing read.
#
# THE HARD RULE: THIS FILE COMPUTES NOTHING. Every value comes from the analyze()
# result it is handed. stat_calculator.gd has twice had to delete a local
# re-derivation that drifted from the real model - a capacity calculation that
# knew 4 locomotion types out of 17, and an armour table that showed the
# explosive threshold labelled as energy. A verdict that disagreed with the row
# beneath it would be worse than no verdict at all, so this only ever reads,
# compares against a threshold, and phrases.
#
# PURE AND SCENE-FREE ON PURPOSE. It takes a Dictionary and returns an Array of
# Dictionaries. That is what lets it be tested directly, without a Lab, without a
# hull, and without a rendered frame - which is why it is the first piece of the
# Design Lab work rather than a detail of the rail.

const Tokens = preload("res://scripts/ui_tokens.gd")

# Ordered worst-first. The rail shows the highest severity present, so the order
# here IS the priority order.
enum Severity { BLOCKING, WARNING, NOTE, GOOD }

# A design is "over capacity" the moment load_ratio exceeds 1.0 - that is
# drivetrain.gd's own is_overloaded flag, not a threshold invented here. But a
# 2% overload is not worth shouting about, so the VERDICT threshold is a little
# above the mechanical one and says so.
const OVERLOAD_NAG_RATIO := 1.05
# Below this fraction of the chassis rating, a design is leaving speed unused.
const UNDERLOAD_NOTE_RATIO := 0.55
# Power headroom under this fraction of generation reads as brownout risk.
const POWER_TIGHT_FRACTION := 0.1


# Returns an Array of {severity, headline, detail} dictionaries, worst first.
# Empty only when handed something that is not an analyze() result at all.
static func evaluate(stats: Dictionary) -> Array:
	var out: Array = []
	if stats.is_empty():
		return out

	var dt: Dictionary = stats.get("drivetrain", {})
	var wr: Dictionary = stats.get("weapon_range", {})
	var power: Dictionary = stats.get("power", {})

	# --- Blocking: the design cannot do its job at all ------------------------

	# No locomotion is not automatically wrong - a pillbox foundation is a real,
	# intentional design - so this is phrased as a statement of what it IS rather
	# than as an error. Getting this wrong would nag every defence structure the
	# player ever builds.
	if not bool(dt.get("has_locomotion", false)):
		out.append(_v(Severity.NOTE, "STATIC EMPLACEMENT",
			"No drive fitted. This design cannot move; it can still be placed as a defence."))
	elif bool(dt.get("is_overloaded", false)) \
			and float(dt.get("load_ratio", 0.0)) >= OVERLOAD_NAG_RATIO:
		var lost := float(dt.get("speed_lost_to_overload", 0.0))
		out.append(_v(Severity.BLOCKING, "OVER CAPACITY",
			"%s kg on %s kg of drive. Top speed cut by %.1f m/s." % [
				_round(dt.get("weight", 0.0)), _round(dt.get("capacity", 0.0)), lost]))

	if not bool(stats.get("has_weapons", false)):
		# Harvesters and scouts are legitimately unarmed, and DesignStats already
		# knows which is which - so this distinguishes them instead of calling a
		# harvester a mistake.
		if bool(stats.get("is_harvester", false)):
			out.append(_v(Severity.NOTE, "HARVESTER",
				"Unarmed by design. This is the only unit that earns rather than spends."))
		else:
			out.append(_v(Severity.WARNING, "UNARMED",
				"No weapon fitted. This design cannot damage anything."))

	# --- Power ----------------------------------------------------------------
	var generation := float(power.get("generation", 0.0))
	var draw := float(power.get("draw", 0.0))
	if draw > 0.0 and generation <= 0.0:
		out.append(_v(Severity.BLOCKING, "UNPOWERED",
			"Draws %s power and generates none. Energy systems will not run." % _round(draw)))
	elif generation > 0.0 and draw > generation:
		out.append(_v(Severity.WARNING, "POWER DEFICIT",
			"Draws %s against %s generated." % [_round(draw), _round(generation)]))
	elif generation > 0.0 and (generation - draw) < generation * POWER_TIGHT_FRACTION:
		out.append(_v(Severity.NOTE, "POWER TIGHT",
			"Only %s spare. One more energy system will brown out." % _round(generation - draw)))

	# --- Speed notes ----------------------------------------------------------
	# CAPACITY-LIMITED IS ITS OWN VERDICT because the fix is different, and that
	# distinction is drivetrain.gd's, not one invented here: when the chassis
	# rather than the powerplant is the ceiling, adding thrust or shedding weight
	# does nothing and the answer is a different locomotion type.
	if bool(dt.get("capacity_limited", false)) and not bool(dt.get("is_overloaded", false)):
		out.append(_v(Severity.NOTE, "CHASSIS LIMITED",
			"The drive type caps this design at %.1f m/s. More thrust will not help." % [
				float(dt.get("chassis_top_speed", 0.0))]))
	elif bool(dt.get("is_underloaded", false)) \
			and float(dt.get("load_ratio", 1.0)) <= UNDERLOAD_NOTE_RATIO:
		out.append(_v(Severity.NOTE, "RUNNING LIGHT",
			"Well under capacity: +%.1f m/s from the spare drive." % [
				float(dt.get("speed_gained_from_underload", 0.0))]))

	# --- Spotting -------------------------------------------------------------
	# A weapon that outranges its own vision is a real and very unintuitive trap:
	# the unit cannot see what it could shoot, so it needs a spotter to be worth
	# anything. weapon_range.gd already works out which weapons those are.
	var needs_spotter: Array = wr.get("spotter_required", [])
	if not needs_spotter.is_empty():
		out.append(_v(Severity.WARNING, "OUTRANGES ITS OWN VISION",
			"%d weapon(s) reach past this design's sight. Without a spotter they cannot engage." % [
				needs_spotter.size()]))

	# --- All clear ------------------------------------------------------------
	# Only when nothing else fired. "BALANCED" alongside a warning would be the
	# interface contradicting itself.
	if out.is_empty():
		out.append(_v(Severity.GOOD, "BALANCED",
			"Within capacity, armed, and powered."))

	out.sort_custom(func(a, b): return a["severity"] < b["severity"])
	return out


# The single verdict the rail leads with: the worst one present.
static func headline(stats: Dictionary) -> Dictionary:
	var all := evaluate(stats)
	return all[0] if not all.is_empty() else {}


# The colour a severity is drawn in. Maps onto the SIGNAL palette rather than
# inventing one, so a blocking verdict is the same red as damage everywhere else.
static func color_for(severity: int) -> Color:
	match severity:
		Severity.BLOCKING: return Tokens.SIGNAL_ALERT
		Severity.WARNING: return Tokens.SIGNAL_HAZARD
		Severity.GOOD: return Tokens.SIGNAL_GO
		_: return Tokens.SIGNAL_INFO


static func _v(severity: int, headline_text: String, detail: String) -> Dictionary:
	return {"severity": severity, "headline": headline_text, "detail": detail}


# Whole numbers with thousands separators. A weight or a power figure with three
# decimal places in a headline reads as machine output rather than as a verdict.
static func _round(value) -> String:
	var n := int(round(float(value)))
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out
