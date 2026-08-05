class_name Stance
extends RefCounted
# What a unit does when nobody is telling it anything.
#
# WHY THIS IS SEPARATE FROM Order. An order is a task that completes; a stance is
# a standing policy that outlives every order the unit is given. Folding stance
# into the order enum - the obvious shortcut - means re-declaring the policy on
# every command, and losing it the moment a unit finishes moving.
#
# The old runtime had no stances at all. It had ONE hardcoded policy, spelled out
# in battle_unit.gd:145-154: weapons always fire at anything in range, and a unit
# with no order at all starts hunting after a couple of seconds idle. That is
# roughly AGGRESSIVE with a delay, applied to everything, with no way to ask for
# anything else - so an artillery piece parked behind a line would wander off
# after its own targets, and a picket could not be told to simply stay put.

enum Kind {
	# Never move on the unit's own initiative. Weapons still fire at whatever
	# comes into range - holding position is about the wheels, not the guns. This
	# is what artillery, pickets and anything deliberately positioned wants.
	HOLD_POSITION,
	# Fire back, and pursue only far enough to answer what is shooting at you.
	# The safe default: units defend themselves without unravelling a formation
	# by chasing a scout across the map.
	RETURN_FIRE,
	# Actively seek targets within vision once idle. What the old runtime did to
	# everything, now something you opt into.
	AGGRESSIVE,
}

# The default for a newly built unit. RETURN_FIRE rather than AGGRESSIVE because
# a group that scatters after every passing target is worse than one that needs
# to be told to attack - and the old behaviour's own bug reports were all
# "my units wandered off".
const DEFAULT := Kind.RETURN_FIRE


# How far a unit will stray from its post to answer a threat, as a multiple of
# its weapon range. HOLD_POSITION is zero: it does not chase at all.
static func pursuit_range_multiplier(kind: Kind) -> float:
	match kind:
		Kind.HOLD_POSITION:
			return 0.0
		Kind.RETURN_FIRE:
			return 1.25
		Kind.AGGRESSIVE:
			return 3.0
	return 1.0


# Whether an idle unit in this stance goes looking for trouble rather than
# waiting for it.
static func seeks_targets(kind: Kind) -> bool:
	return kind == Kind.AGGRESSIVE


static func label(kind: Kind) -> String:
	match kind:
		Kind.HOLD_POSITION:
			return "HOLD POSITION"
		Kind.RETURN_FIRE:
			return "RETURN FIRE"
		Kind.AGGRESSIVE:
			return "AGGRESSIVE"
	return "UNKNOWN"


static func all() -> Array:
	return [Kind.HOLD_POSITION, Kind.RETURN_FIRE, Kind.AGGRESSIVE]
