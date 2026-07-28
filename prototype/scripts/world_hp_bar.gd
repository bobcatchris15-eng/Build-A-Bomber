extends RefCounted
class_name WorldHPBar
# VISUAL_AND_UX_POLISH_PLAN.md A4 / VISUAL_IMPROVEMENT_PLAN.md chunk F:
# replaces the `Label3D` + `■□` ASCII bar pattern duplicated three times
# (battle_unit.gd, building.gd, target_dummy.gd) with the already-authored
# but never-wired `inworld_hp_bar.gdshader`/`selection_ring.gdshader`
# (found under `res://shaders/`, dated before this session - a real
# segmented-bar gradient + damage-flash shader and a self-animating
# rotating-dash pulsing ring, both built and sitting unused). This helper
# is the one place that instantiates/updates them, so the three callers
# can't drift the way the three independent Label3D implementations had.
#
# `render_mode billboard` was added to inworld_hp_bar.gdshader (it shipped
# without it) so the bar always faces the camera the same way Label3D's
# own `billboard = BILLBOARD_ENABLED` did - rts_camera.gd's pitch varies
# 42-62° with zoom, so a non-billboarded flat quad would foreshorten
# differently per zoom level. The selection ring is deliberately NOT
# billboarded - it already lies flat on the ground (matching the old
# TorusMesh's orientation), which is what makes its rotating dashes read
# as a ring from an overhead RTS camera instead of a spinning line.

const HP_BAR_SHADER = preload("res://shaders/inworld_hp_bar.gdshader")
const SELECTION_RING_SHADER = preload("res://shaders/selection_ring.gdshader")

# team == 0 (player) reads green at full health, matching every other
# player-owned UI element in this project; any other team reads orange -
# the same GREEN-vs-ORANGE_RED distinction the old Label3D.modulate made,
# now just the shader's own "color_full" endpoint instead of a whole-bar
# tint (color_mid/color_low - amber/red - stay the shader's shared default
# for every team, since "badly hurt" should read the same regardless of
# owner).
const TEAM_COLOR_FULL = Color(0.2, 0.9, 0.3, 1.0)
const ENEMY_COLOR_FULL = Color(0.95, 0.5, 0.15, 1.0)

static func create_bar(parent: Node3D, local_pos: Vector3, team: int, width: float = 1.6, height: float = 0.22, segments: float = 10.0) -> MeshInstance3D:
	var mesh_inst = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(width, height)
	mesh_inst.mesh = quad
	mesh_inst.position = local_pos
	var mat = ShaderMaterial.new()
	mat.shader = HP_BAR_SHADER
	mat.set_shader_parameter("hp_ratio", 1.0)
	mat.set_shader_parameter("segments", segments)
	mat.set_shader_parameter("color_full", TEAM_COLOR_FULL if team == 0 else ENEMY_COLOR_FULL)
	mesh_inst.material_override = mat
	parent.add_child(mesh_inst)
	return mesh_inst

static func update_bar(bar: MeshInstance3D, pct: float) -> void:
	if not is_instance_valid(bar): return
	var mat = bar.material_override as ShaderMaterial
	if not mat: return
	mat.set_shader_parameter("hp_ratio", clamp(pct, 0.0, 1.0))

# The shader's own damage_flash uniform (a brief white-blend on the fill) -
# kicked to 1.0 and tweened back down, rather than update_bar() setting it
# directly every call, since update_bar() runs on plenty of non-damage
# updates too (e.g. a harvester's cargo pickup nudging a caller to refresh).
static func flash_damage(bar: MeshInstance3D) -> void:
	if not is_instance_valid(bar): return
	var mat = bar.material_override as ShaderMaterial
	if not mat: return
	mat.set_shader_parameter("damage_flash", 1.0)
	var tween = bar.create_tween()
	tween.tween_method(func(v: float): mat.set_shader_parameter("damage_flash", v), 1.0, 0.0, 0.25)

static func set_bar_visible(bar: MeshInstance3D, is_visible: bool) -> void:
	if is_instance_valid(bar):
		bar.visible = is_visible

static func free_bar(bar: MeshInstance3D) -> void:
	if is_instance_valid(bar):
		bar.queue_free()

# Flat on the ground (rotated -90° around X, like the old TorusMesh), sized
# so the shader's own fixed 0.42 outer-radius UV geometry matches `radius`
# in world units. The shader animates itself (rotating dashes + pulse, both
# driven by TIME) - no per-frame script driving needed, unlike the old
# TorusMesh + StandardMaterial3D, which had no motion at all.
static func create_selection_ring(parent: Node3D, radius: float) -> MeshInstance3D:
	var mesh_inst = MeshInstance3D.new()
	var quad = QuadMesh.new()
	# The shader's ring sits at UV-space distance 0.42 from center (a
	# FRACTION of the quad's own size, not world units) - a quad of side S
	# puts the ring's world-space radius at 0.42*S, so solving for the quad
	# side that puts the ring at world radius `radius` is S = radius / 0.42,
	# not radius*2/0.42 (which doubled it - caught via a real screenshot,
	# not headless tests, since this is a pure visual-scale bug).
	var side = radius / 0.42
	quad.size = Vector2(side, side)
	mesh_inst.mesh = quad
	mesh_inst.rotation_degrees = Vector3(-90, 0, 0)
	mesh_inst.position = Vector3(0, 0.08, 0)
	var mat = ShaderMaterial.new()
	mat.shader = SELECTION_RING_SHADER
	mesh_inst.material_override = mat
	mesh_inst.visible = false
	parent.add_child(mesh_inst)
	return mesh_inst
