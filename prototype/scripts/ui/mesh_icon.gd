class_name MeshIcon
extends SubViewportContainer
# A small live 3D prop standing in for a flat control glyph - the toggle
# switch, rotary selector, rocker, knurled dial, DZUS fastener and latch
# authored in tools/blender/build_ui_props.py, mounted beside the REAL
# CheckBox/OptionButton/HSlider it illustrates.
#
# WHY A PROP NEXT TO THE CONTROL, NOT A REPLACEMENT FOR IT. Godot's native
# controls already carry keyboard focus, screen-reader-adjacent accessibility
# hooks, and every existing test that clicks a CheckBox or drags an HSlider.
# Rebuilding that on raw 3D geometry - hit-testing a rotated mesh inside a
# SubViewport, re-deriving focus order - is a much larger and riskier project
# than what was asked for: this game already treats hardware as real meshes
# everywhere else (every hull, every weapon), and the settings/Lab chrome
# should not be the one place that is flat glyphs pretending otherwise. The
# mesh reads the state; the native control still owns the input.
#
# CHEAP ON PURPOSE. Chris: "a fully modern and fluid UI/UX" does not mean a
# few dozen live-rendered dials eating a frame budget meant for the
# battlefield. The SubViewport renders ONCE per state change
# (render_target_update_mode = UPDATE_ONCE, not UPDATE_ALWAYS) rather than
# continuously - a settings row that never changes costs nothing to redraw.

const Tokens = preload("res://scripts/ui_tokens.gd")

@export var mesh_path: String = ""
@export var icon_size: Vector2i = Vector2i(40, 40)

var _viewport: SubViewport = null
var _mesh_instance: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _rig: Node3D = null


func _ready() -> void:
	custom_minimum_size = Vector2(icon_size)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	if mesh_path != "":
		load_mesh(mesh_path)


func _build() -> void:
	_viewport = SubViewport.new()
	_viewport.size = icon_size
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)

	_rig = Node3D.new()
	_viewport.add_child(_rig)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.58)
	env.ambient_light_energy = 0.9
	env_node.environment = env
	_rig.add_child(env_node)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.97, 0.9)
	key.light_energy = 1.2
	key.rotation_degrees = Vector3(-52, -35, 0)
	_rig.add_child(key)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.55, 1.4)
	cam.rotation_degrees = Vector3(-20, 0, 0)
	cam.fov = 28.0
	_rig.add_child(cam)

	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.42, 0.43, 0.45, 1.0)
	_material.metallic = 0.55
	_material.roughness = 0.35

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.position = Vector3(0, -0.05, 0)
	_mesh_instance.material_override = _material
	_rig.add_child(_mesh_instance)


func load_mesh(path: String) -> void:
	mesh_path = path
	if not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var instance := packed.instantiate()
	var src := _find_mesh(instance)
	if src != null:
		_mesh_instance.mesh = src.mesh
	instance.free()
	_redraw()


# ON/armed state - SIGNAL_GO amber-to-green accent versus neutral gunmetal,
# same signal vocabulary as every other affordance in the game rather than an
# invented "3D icon" palette.
func set_active(active: bool) -> void:
	if _material == null:
		return
	if active:
		_material.albedo_color = Color(0.30, 0.34, 0.30, 1.0)
		_material.emission_enabled = true
		_material.emission = Tokens.SIGNAL_GO
		_material.emission_energy_multiplier = 0.6
	else:
		_material.albedo_color = Color(0.42, 0.43, 0.45, 1.0)
		_material.emission_enabled = false
	_redraw()


# For the rotary selector / knurled dial: turns the whole prop about its own
# Y axis, so a discrete choice (index/count) or a continuous value
# (fraction 0..1 over a fixed arc) both read as a real turned position rather
# than a redrawn glyph.
func set_turn_degrees(degrees: float) -> void:
	if _mesh_instance == null:
		return
	_mesh_instance.rotation_degrees.y = degrees
	_redraw()


func set_turn_fraction(fraction: float, arc_degrees: float = 270.0) -> void:
	set_turn_degrees((clampf(fraction, 0.0, 1.0) - 0.5) * arc_degrees)


func _redraw() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


static func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
