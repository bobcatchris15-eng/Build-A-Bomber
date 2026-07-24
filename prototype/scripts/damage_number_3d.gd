class_name DamageNumber3D
extends Label3D

## Floating 3D text callout for damage, healing, and salvage numbers.

var lifetime: float = 1.0
var elapsed: float = 0.0
var rise_speed: float = 2.0
var initial_scale: Vector2 = Vector2(1.2, 1.2)

static func spawn(parent: Node, pos: Vector3, amount: int, color: Color = Color(1.0, 0.25, 0.25)) -> DamageNumber3D:
	var num = DamageNumber3D.new()
	num.text = str(amount)
	num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	num.no_depth_test = true
	num.font_size = 28
	num.outline_size = 6
	num.outline_render_priority = 1
	num.modulate = color
	num.global_position = pos + Vector3(0, 1.5, 0)
	parent.add_child(num)
	return num

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= lifetime:
		queue_free()
		return

	var progress = elapsed / lifetime
	global_position.y += rise_speed * delta

	# Fade out near end of life
	if progress > 0.6:
		var alpha = 1.0 - (progress - 0.6) / 0.4
		modulate.a = alpha
