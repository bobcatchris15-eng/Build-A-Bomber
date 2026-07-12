class_name GlobalConfig

# Tweakable global scaling ratios.
# If a weapon doubles in size (volume increases by 8x), these multipliers
# determine how aggressively the stats increase. 
# A value of 1.0 means linear scaling with volume.
# A value of 0.5 means it scales at half the rate of the volume increase.

static var weight_scale_factor: float = 1.0
static var hp_scale_factor: float = 0.8
static var dps_scale_factor: float = 0.75
static var cost_scale_factor: float = 0.9

# Stat rounding (Chris's instruction): round to the nearest 0.5 at the point
# stats are COMPUTED, not just where they're displayed - so a UI label and
# the actual combat math it describes are never out of sync. Called from
# module_data.gd's getters and auto_weapon.gd's tweak-multiplier chains,
# the two places floating-point noise from chained tweak multipliers (each
# a 0.1-step slider, not exactly representable in binary) actually enters
# the pipeline.
static func round_to_half(x: float) -> float:
	return round(x * 2.0) / 2.0
