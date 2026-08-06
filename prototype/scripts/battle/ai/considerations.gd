class_name Considerations
extends RefCounted
# The curves a utility score is built out of.
#
# WHY THESE ARE SEPARATE FROM THE COMMANDER. A utility AI is
# U(a) = sum over i of w_i * c_i(x_i): weights are the AI's personality, and the
# considerations are the shape of each input. Keeping the curves here means they
# are pure functions of a number - assertable directly, with no game, no economy
# and no opponent - and the commander is left holding only the decision.
#
# WHY CURVES AT ALL, rather than thresholds. The old enemy_ai.gd asked binary
# questions: is 40% of the player's army airborne, yes or no. That produces a
# step - nothing, nothing, nothing, total commitment - and it is why its
# counter-picking read as either oblivious or clairvoyant with nothing between.
# A curve lets "a bit of air" produce a bit of anti-air.
#
# Every consideration returns 0..1. That is the contract the weighted sum
# depends on: a curve that returns 1.5 silently outranks its own weight.


# Linear ramp from 0 at `low` to 1 at `high`, clamped. The workhorse.
static func ramp(x: float, low: float, high: float) -> float:
	if is_equal_approx(high, low):
		return 0.0 if x < low else 1.0
	return clampf((x - low) / (high - low), 0.0, 1.0)


# The inverse: 1 while scarce, falling to 0 once plentiful. For "how badly do I
# need another one of these".
static func falloff(x: float, low: float, high: float) -> float:
	return 1.0 - ramp(x, low, high)


# Sharpens or softens a normalised value. exponent > 1 makes a consideration
# indifferent until its input gets serious (good for threats); < 1 makes it react
# early and then saturate (good for needs).
static func curve(normalised: float, exponent: float) -> float:
	return pow(clampf(normalised, 0.0, 1.0), exponent)


# A share of a whole, guarding the empty case. Used constantly - "what fraction
# of their army is airborne" is meaningless with no army, and must read as no
# threat rather than as a division by zero.
static func share(part: float, whole: float) -> float:
	if whole <= 0.0:
		return 0.0
	return clampf(part / whole, 0.0, 1.0)


# An action's score: its weight times the AVERAGE of its considerations.
#
# THE AVERAGE IS LOAD-BEARING, and summing instead is a trap worth naming. A raw
# sum makes an action's ceiling proportional to how many considerations it
# happens to have, so a 4-consideration action at weight 1.0 tops out at 4.0
# while a 2-consideration action at weight 1.6 tops out at 3.2 - and the weight
# table, which is supposed to BE the AI's priorities, stops ordering anything.
#
# Measured: DEFEND (weight 1.6, the highest in the table) lost to EXPAND_ECONOMY
# (weight 1.0) while the AI's base was being raided, purely because expanding had
# more boxes to tick. Averaging first makes weight mean what it says.
#
# Any consideration at zero still zeroes the action outright. That is the veto:
# "build an anti-air unit" with no factory able to build it is not a weak idea,
# it is an impossible one, and no amount of threat should keep it on the list.
static func score(weight: float, values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		var value: float = clampf(v, 0.0, 1.0)
		if is_zero_approx(value):
			return 0.0
		total += value
	return weight * (total / float(values.size()))
