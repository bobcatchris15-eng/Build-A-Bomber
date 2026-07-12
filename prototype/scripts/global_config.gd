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
