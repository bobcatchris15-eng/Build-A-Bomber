class_name PointerGain
extends RefCounted

# Unified speed-dependent pointer and camera transfer function (Phase 11, D17).
# Monotonic non-linear transfer function providing high-velocity damping and low-velocity precision.

const PRECISION_FACTOR := 0.20


static func apply_gain(raw_delta: Vector2, sensitivity: float = 1.0, curve_power: float = 1.25) -> Vector2:
	var mag := raw_delta.length()
	if mag < 0.0001:
		return Vector2.ZERO

	# Transfer function: f(v) = v^p with sensitivity scaling
	# Guaranteed strictly monotonic for curve_power >= 1.0
	var scaled_mag: float = pow(mag * 0.05, maxf(curve_power, 1.0)) * 20.0 * sensitivity
	# Blend smoothly between linear at micro-movements and power curve at higher speeds
	var final_mag: float = lerpf(mag * sensitivity, scaled_mag, clampf(mag / 50.0, 0.0, 1.0))
	return raw_delta.normalized() * final_mag


static func compute_scaled_delta(raw_delta: Vector2, sensitivity: float = 1.0, precision_mode: bool = false) -> Vector2:
	var delta := apply_gain(raw_delta, sensitivity)
	if precision_mode:
		delta *= PRECISION_FACTOR
	return delta


static func apply_scalar_gain(raw_val: float, sensitivity: float = 1.0, precision_mode: bool = false) -> float:
	var sign_val := signf(raw_val)
	var mag := absf(raw_val)
	var scaled := pow(mag, 1.15) * sensitivity
	if precision_mode:
		scaled *= PRECISION_FACTOR
	return sign_val * scaled
