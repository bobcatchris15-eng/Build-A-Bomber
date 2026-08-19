extends Node3D
# The Armor Bay's surrounding 3D environment: a dark stained wood desktop
# (wood_desktop.gdshader) with paint supplies scattered around the model,
# rather than the LabEnvironment cutting mat + cardboard model-kit boxes.
#
# WHY A SEPARATE SCRIPT/SCENE FROM LabEnvironment. The Lab and HullBuilder
# share a LabEnvironment because they both build vehicles - the mat reads
# as a model-builder's bench and the kraft boxes are the kit parts you are
# working from. The Armor Bay reframes as a paint station (armor is just
# paint), so the floor and props have to change. Sharing the same scene
# would have meant a "mode" flag swapping materials at runtime, which is
# the kind of conditional the original armor_bay_screen.gd comment was
# written to avoid.
#
# Paint supplies are procedural primitives - CylinderMesh for bottles,
# BoxMesh for tubes, a low CylinderMesh for the palette disc. Everything
# is DOF-blurred anyway, so they read as paint-station shapes rather
# than as detailed props. Albedo colours are the player's livery colours
# where possible (the paint ON the bench matches the paint ON the model),
# falling back to a neutral workshop palette.
#
# The world position of the desktop and the prop layout are deliberate:
#   * desktop at y = -12 (same as LabEnvironment's mat, so any
#     module_placer.gd logic that referenced "the floor at y = -12"
#     still finds it)
#   * props in a ring around (0, 0), leaving the centre clear for the
#     floating hull at y = 2.5

const Tokens = preload("res://scripts/ui_tokens.gd")
const LiveryScript = preload("res://scripts/livery.gd")


# Per-bottle / tube / palette stand-alone materials so the prop albedo
# stays editable from one place. These match the player-facing paint
# stations in real workshops: a few favourite colours, plus a couple of
# neutral workshop tones (thinner black, primer white).
#
# `bottle_lid_*` is the slightly darker metallic lid on top of each
# bottle. The colour gap between bottle and lid is what reads as "this
# is a bottle" rather than "this is a coloured cylinder".
const PAINT_PALETTE := [
	{"name": "olive_drab",   "bottle": Color(0.380, 0.420, 0.220), "lid": Color(0.18, 0.16, 0.12)},
	{"name": "desert_tan",   "bottle": Color(0.760, 0.620, 0.380), "lid": Color(0.20, 0.18, 0.14)},
	{"name": "field_grey",   "bottle": Color(0.420, 0.430, 0.410), "lid": Color(0.16, 0.14, 0.12)},
	{"name": "oxide_red",    "bottle": Color(0.560, 0.260, 0.180), "lid": Color(0.18, 0.14, 0.12)},
	{"name": "navy_steel",   "bottle": Color(0.220, 0.300, 0.420), "lid": Color(0.14, 0.16, 0.18)},
	{"name": "primer_white", "bottle": Color(0.860, 0.840, 0.780), "lid": Color(0.22, 0.20, 0.16)},
]


func _ready() -> void:
	_build_desktop()
	_build_paint_supplies()


func _build_desktop() -> void:
	# The desktop shader + the floor mesh that carries it. A BoxMesh 50x50
	# centred at y = -12.05 so the visible top surface lands at y = -12
	# (the ground the props sit on).
	var wood_shader: Shader = preload("res://shaders/wood_desktop.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = wood_shader
	mat.set_shader_parameter("paint_smudge_seed", randf() * 100.0)

	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(50.0, 0.1, 50.0)
	var floor := MeshInstance3D.new()
	floor.name = "WoodDesktop"
	floor.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -12.05, 0.0))
	floor.mesh = floor_mesh
	floor.material_override = mat
	add_child(floor)


# Three bottles, two tubes, one palette disc. The shapes are deliberately
# mixed so the silhouette reads as "scattered workshop props" rather than
# "an orderly row of identical objects". All props live below y = -11 so
# they're below the floating hull (y = 2.5) and well within DOF blur.
func _build_paint_supplies() -> void:
	# Bottles: 0.25 radius, 0.7 tall cylinders with a 0.28-radius, 0.08-tall
	# darker lid on top. Placed at three points around the desktop so they
	# read as a small group when DOF-blurred.
	var bottle_positions := [
		{"pos": Vector3(8.5, -11.7, 5.5), "rot": 0.18, "scale": Vector3(1.0, 1.0, 1.0)},
		{"pos": Vector3(9.6, -11.7, 6.8), "rot": -0.42, "scale": Vector3(0.85, 1.1, 0.85)},
		{"pos": Vector3(-7.2, -11.7, 8.5), "rot": 1.15, "scale": Vector3(0.95, 0.95, 0.95)},
	]
	for i in range(bottle_positions.size()):
		var spec: Dictionary = bottle_positions[i]
		var palette: Dictionary = PAINT_PALETTE[i % PAINT_PALETTE.size()]
		_add_bottle(spec["pos"], float(spec["rot"]), spec["scale"], palette)

	# Tubes: 0.5 long, 0.18 wide, 0.16 tall flat boxes. Lying on their
	# side on the desktop - read as a paint tube viewed from any angle.
	var tube_positions := [
		{"pos": Vector3(-9.5, -11.85, 6.0), "rot_y": 0.7, "scale": Vector3(1.0, 1.0, 1.0)},
		{"pos": Vector3(7.0, -11.85, 8.5), "rot_y": -0.3, "scale": Vector3(0.9, 0.9, 1.1)},
	]
	for i in range(tube_positions.size()):
		var spec: Dictionary = tube_positions[i]
		var palette: Dictionary = PAINT_PALETTE[(i + 3) % PAINT_PALETTE.size()]
		_add_tube(spec["pos"], float(spec["rot_y"]), spec["scale"], palette)

	# Palette disc: a low cylinder, slightly off-centre, with a couple of
	# faint coloured dots on top (small flat cylinders) suggesting
	# recent mixes. Lighter base so the colours stand out.
	var palette_pos := Vector3(6.5, -11.92, 9.5)
	_add_palette(palette_pos)


func _add_bottle(pos: Vector3, rot_y: float, scale: Vector3, palette: Dictionary) -> void:
	var bottle_root := Node3D.new()
	bottle_root.transform = Transform3D(Basis().rotated(Vector3.UP, rot_y), pos)
	bottle_root.scale = scale
	bottle_root.name = "PaintBottle"
	add_child(bottle_root)

	var body := CylinderMesh.new()
	body.top_radius = 0.25
	body.bottom_radius = 0.25
	body.height = 0.7
	var body_inst := MeshInstance3D.new()
	body_inst.mesh = body
	body_inst.material_override = _make_paint_material(
		palette["bottle"], 0.55, 0.35)
	# Centre at y = 0.35 so the body's bottom sits on y = 0 (the desk)
	body_inst.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.35, 0.0))
	bottle_root.add_child(body_inst)

	var lid := CylinderMesh.new()
	lid.top_radius = 0.27
	lid.bottom_radius = 0.27
	lid.height = 0.08
	var lid_inst := MeshInstance3D.new()
	lid_inst.mesh = lid
	lid_inst.material_override = _make_paint_material(
		palette["lid"], 0.70, 0.45)
	# Lid sits on top of the body
	lid_inst.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.74, 0.0))
	bottle_root.add_child(lid_inst)


func _add_tube(pos: Vector3, rot_y: float, scale: Vector3, palette: Dictionary) -> void:
	var tube_root := Node3D.new()
	tube_root.transform = Transform3D(Basis().rotated(Vector3.UP, rot_y), pos)
	tube_root.scale = scale
	tube_root.name = "PaintTube"
	add_child(tube_root)

	var tube := BoxMesh.new()
	tube.size = Vector3(0.5, 0.16, 0.18)
	var inst := MeshInstance3D.new()
	inst.mesh = tube
	inst.material_override = _make_paint_material(
		palette["bottle"], 0.55, 0.40)
	tube_root.add_child(inst)

	# A small darker end cap on the tube's nozzle side, so the tube reads
	# as having a cap and the silhouette is a paint tube rather than a
	# brick.
	var cap := BoxMesh.new()
	cap.size = Vector3(0.06, 0.18, 0.20)
	var cap_inst := MeshInstance3D.new()
	cap_inst.mesh = cap
	cap_inst.material_override = _make_paint_material(
		palette["lid"], 0.75, 0.40)
	cap_inst.transform = Transform3D(Basis.IDENTITY, Vector3(0.28, 0.0, 0.0))
	tube_root.add_child(cap_inst)


func _add_palette(pos: Vector3) -> void:
	var palette_root := Node3D.new()
	palette_root.transform = Transform3D(Basis(), pos)
	palette_root.name = "Palette"
	add_child(palette_root)

	# Palette disc: a very flat cylinder, light wooden tone so the colour
	# blobs on top stand out.
	var disc := CylinderMesh.new()
	disc.top_radius = 0.65
	disc.bottom_radius = 0.65
	disc.height = 0.04
	var disc_inst := MeshInstance3D.new()
	disc_inst.mesh = disc
	disc_inst.material_override = _make_paint_material(
		Color(0.86, 0.78, 0.58), 0.75, 0.45)
	disc_inst.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.02, 0.0))
	palette_root.add_child(disc_inst)

	# A few coloured blobs on the palette. Short flat cylinders at
	# varying positions, using a couple of the palette colours so the
	# palette reads as having been used recently.
	var blob_positions := [
		{"pos": Vector3(0.15, 0.0, 0.05), "col": PAINT_PALETTE[0]["bottle"], "r": 0.16},
		{"pos": Vector3(-0.20, 0.0, 0.15), "col": PAINT_PALETTE[3]["bottle"], "r": 0.14},
		{"pos": Vector3(0.05, 0.0, -0.20), "col": PAINT_PALETTE[4]["bottle"], "r": 0.12},
		{"pos": Vector3(-0.10, 0.0, -0.05), "col": PAINT_PALETTE[1]["bottle"], "r": 0.13},
	]
	for spec in blob_positions:
		var blob_mesh := CylinderMesh.new()
		blob_mesh.top_radius = float(spec["r"])
		blob_mesh.bottom_radius = float(spec["r"])
		blob_mesh.height = 0.02
		var blob_inst := MeshInstance3D.new()
		blob_inst.mesh = blob_mesh
		blob_inst.material_override = _make_paint_material(
			spec["col"], 0.45, 0.55)
		blob_inst.transform = Transform3D(Basis.IDENTITY, Vector3(spec["pos"].x, 0.05, spec["pos"].z))
		palette_root.add_child(blob_inst)


func _make_paint_material(albedo: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = roughness
	m.metallic = metallic
	# Slight specular kicker so the painted bottles catch the warm key light.
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return m