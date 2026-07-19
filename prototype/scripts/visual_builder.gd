class_name VisualBuilder
# Assembles the visual mesh tree for a placed module. Prefers authored .glb
# "kit" parts (tools/blender/build_meshes.py) for a detailed/greebled look,
# falling back to the original procedural primitives when no authored asset
# exists yet. Authored cylindrical/dome/leg/mast/tank/wheel parts are built
# along local Y (matching Godot's own CylinderMesh default axis), so every
# existing runtime rotation/positioning call below applies identically to
# both the authored and procedural mesh - only the `.mesh` source differs.

const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")

static func _part(part_name: String) -> Mesh:
	return MeshAssetLoader.get_part_mesh(part_name)

static func _mesh_inst(mesh: Mesh, color: Color, emission: Color = Color(0, 0, 0, 0), emission_energy: float = 0.0) -> MeshInstance3D:
	var inst = MeshInstance3D.new()
	inst.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	inst.material_override = mat
	return inst

# Scales a fixed-dimension authored part's Node3D to hit a target Godot-space
# (width, height, depth) size, given the part's own authored base dimensions.
static func _fit_scale(target: Vector3, authored_base: Vector3) -> Vector3:
	return Vector3(
		target.x / authored_base.x if authored_base.x > 0.0 else 1.0,
		target.y / authored_base.y if authored_base.y > 0.0 else 1.0,
		target.z / authored_base.z if authored_base.z > 0.0 else 1.0
	)

static func build_visual(type_id: String, parent_node: Node3D, base_size: Vector3, base_color: Color, tweaks: Dictionary = {}):
	# Clear any existing visual children
	for child in parent_node.get_children():
		if child is MeshInstance3D:
			child.queue_free()

	if type_id == "basic_cannon":
		# Turret Base
		var base_mesh = _part("turret_base_round")
		var base: MeshInstance3D
		if base_mesh:
			base = _mesh_inst(base_mesh, base_color.darkened(0.2))
			base.scale = _fit_scale(Vector3(base_size.x * 1.6, base_size.y * 0.4, base_size.x * 1.6), Vector3(1.0, 0.35, 1.0))
			base.position = Vector3(0, 0, 0)
		else:
			base = MeshInstance3D.new()
			var base_cyl = CylinderMesh.new()
			base_cyl.top_radius = base_size.x * 0.8
			base_cyl.bottom_radius = base_size.x * 1.0
			base_cyl.height = base_size.y * 0.4
			base.mesh = base_cyl
			var base_mat = StandardMaterial3D.new()
			base_mat.albedo_color = base_color.darkened(0.2)
			base.material_override = base_mat
			base.position = Vector3(0, base_cyl.height / 2.0, 0)
		parent_node.add_child(base)

		# Barrel (extends along Z-axis at runtime via rotation)
		var barrel_mesh = _part("barrel_standard")
		var barrel: MeshInstance3D
		if barrel_mesh:
			barrel = _mesh_inst(barrel_mesh, Color.DIM_GRAY)
			barrel.scale = Vector3(1.0, base_size.z / 1.0, 1.0)
		else:
			barrel = MeshInstance3D.new()
			var barrel_cyl = CylinderMesh.new()
			barrel_cyl.top_radius = 0.08
			barrel_cyl.bottom_radius = 0.1
			barrel_cyl.height = base_size.z
			barrel.mesh = barrel_cyl
			var barrel_mat = StandardMaterial3D.new()
			barrel_mat.albedo_color = Color.DIM_GRAY
			barrel.material_override = barrel_mat
		barrel.position = Vector3(0, base_size.y * 0.4 + 0.1, -base_size.z / 4.0)
		barrel.rotation = Vector3(PI / 2, 0, 0)
		parent_node.add_child(barrel)

	elif type_id == "heavy_machine_gun":
		var base_mesh = _part("pintle_mount")
		var base: MeshInstance3D
		var base_h = base_size.y * 0.5
		if base_mesh:
			base = _mesh_inst(base_mesh, base_color.darkened(0.1))
			base.scale = _fit_scale(Vector3(base_size.x * 0.8, base_h, base_size.z * 0.5), Vector3(0.34, 0.22, 0.22))
			base.position = Vector3(0, 0, 0)
		else:
			base = MeshInstance3D.new()
			var base_box = BoxMesh.new()
			base_box.size = Vector3(base_size.x * 0.8, base_h, base_size.z * 0.5)
			base.mesh = base_box
			var base_mat = StandardMaterial3D.new()
			base_mat.albedo_color = base_color.darkened(0.1)
			base.material_override = base_mat
			base.position = Vector3(0, base_h / 2.0, 0)
		parent_node.add_child(base)

		# Single gun barrel
		var barrel_mesh = _part("barrel_thin")
		var barrel: MeshInstance3D
		if barrel_mesh:
			barrel = _mesh_inst(barrel_mesh, Color.BLACK)
			barrel.scale = Vector3(1.0, (base_size.z * 0.8) / 1.0, 1.0)
		else:
			barrel = MeshInstance3D.new()
			var barrel_cyl = CylinderMesh.new()
			barrel_cyl.top_radius = 0.04
			barrel_cyl.bottom_radius = 0.04
			barrel_cyl.height = base_size.z * 0.8
			barrel.mesh = barrel_cyl
			var barrel_mat = StandardMaterial3D.new()
			barrel_mat.albedo_color = Color.BLACK
			barrel.material_override = barrel_mat
		barrel.position = Vector3(0, base_h + 0.05, -base_size.z * 0.3)
		barrel.rotation = Vector3(PI / 2, 0, 0)
		parent_node.add_child(barrel)

		# Side Drum Magazine
		var drum_mesh = _part("ammo_drum")
		var drum: MeshInstance3D
		if drum_mesh:
			drum = _mesh_inst(drum_mesh, Color.DARK_SLATE_GRAY)
			drum.scale = _fit_scale(Vector3(0.3, 0.12, 0.3), Vector3(1.0, 0.4, 1.0))
		else:
			drum = MeshInstance3D.new()
			var drum_cyl = CylinderMesh.new()
			drum_cyl.top_radius = 0.15
			drum_cyl.bottom_radius = 0.15
			drum_cyl.height = 0.12
			drum.mesh = drum_cyl
			var drum_mat = StandardMaterial3D.new()
			drum_mat.albedo_color = Color.DARK_SLATE_GRAY
			drum.material_override = drum_mat
		drum.position = Vector3(0.18, base_h * 0.5, 0.0)
		drum.rotation = Vector3(0, 0, PI / 2)
		parent_node.add_child(drum)

	elif type_id == "rotary_cannon":
		var base_mesh = _part("rotary_jacket")
		var base: MeshInstance3D
		if base_mesh:
			base = _mesh_inst(base_mesh, base_color.darkened(0.2))
			base.scale = _fit_scale(Vector3(base_size.x * 1.4, base_size.y * 0.3, base_size.x * 1.4), Vector3(0.44, 0.5, 0.44))
			base.position = Vector3(0, 0, 0)
		else:
			base = MeshInstance3D.new()
			var base_cyl = CylinderMesh.new()
			base_cyl.top_radius = base_size.x * 0.7
			base_cyl.bottom_radius = base_size.x * 0.8
			base_cyl.height = base_size.y * 0.3
			base.mesh = base_cyl
			var base_mat = StandardMaterial3D.new()
			base_mat.albedo_color = base_color.darkened(0.2)
			base.material_override = base_mat
			base.position = Vector3(0, base_cyl.height / 2.0, 0)
		parent_node.add_child(base)

		# barrel count cluster
		var b_count = int(tweaks.get("barrel_count", 6.0))
		var base_h = base_size.y * 0.3
		for i in range(b_count):
			var angle = i * (2.0 * PI / b_count)
			var barrel_mesh = _part("barrel_thin")
			var barrel: MeshInstance3D
			if barrel_mesh:
				barrel = _mesh_inst(barrel_mesh, Color.BLACK)
				barrel.scale = Vector3(1.0, (base_size.z * 0.8) / 1.0, 1.0)
			else:
				barrel = MeshInstance3D.new()
				var barrel_cyl = CylinderMesh.new()
				barrel_cyl.top_radius = 0.03
				barrel_cyl.bottom_radius = 0.03
				barrel_cyl.height = base_size.z * 0.8
				barrel.mesh = barrel_cyl
				var barrel_mat = StandardMaterial3D.new()
				barrel_mat.albedo_color = Color.BLACK
				barrel.material_override = barrel_mat
			var radius_offset = 0.06
			barrel.position = Vector3(cos(angle) * radius_offset, base_h + 0.15 + sin(angle) * radius_offset, -base_size.z * 0.25)
			barrel.rotation = Vector3(PI / 2, 0, 0)
			parent_node.add_child(barrel)

	elif type_id == "gauss_railgun":
		var rail_mesh = _part("rail_array")
		if rail_mesh:
			var assembly = _mesh_inst(rail_mesh, Color(0.15, 0.15, 0.15))
			assembly.scale = _fit_scale(Vector3(base_size.x, base_size.y * 0.9, base_size.z), Vector3(0.36, 0.12, 1.6))
			assembly.position = Vector3(0, 0, -base_size.z * 0.5 + 0.05)
			var rail_mat = assembly.material_override as StandardMaterial3D
			rail_mat.emission_enabled = true
			rail_mat.emission = Color.BLUE_VIOLET
			rail_mat.emission_energy_multiplier = 0.5
			parent_node.add_child(assembly)
		else:
			var base = MeshInstance3D.new()
			var base_box = BoxMesh.new()
			base_box.size = Vector3(base_size.x, base_size.y * 0.3, base_size.z * 0.4)
			base.mesh = base_box
			var base_mat = StandardMaterial3D.new()
			base_mat.albedo_color = base_color.darkened(0.3)
			base.material_override = base_mat
			base.position = Vector3(0, base_box.size.y / 2.0, 0)
			parent_node.add_child(base)

			for side in [-1.0, 1.0]:
				var rail = MeshInstance3D.new()
				var rail_box = BoxMesh.new()
				rail_box.size = Vector3(0.08, base_size.y * 0.6, base_size.z)
				rail.mesh = rail_box
				var rail_mat = StandardMaterial3D.new()
				rail_mat.albedo_color = Color(0.15, 0.15, 0.15)
				rail_mat.emission_enabled = true
				rail_mat.emission = Color.BLUE_VIOLET
				rail_mat.emission_energy_multiplier = 0.5
				rail.material_override = rail_mat
				rail.position = Vector3(0.12 * side, base_box.size.y + rail_box.size.y / 2.0, -base_size.z * 0.3)
				parent_node.add_child(rail)

	elif type_id == "heavy_howitzer":
		var base_mesh = _part("howitzer_breech")
		var base: MeshInstance3D
		if base_mesh:
			base = _mesh_inst(base_mesh, base_color.darkened(0.2))
			base.scale = _fit_scale(Vector3(base_size.x * 0.9, base_size.y * 0.5, base_size.z * 0.5), Vector3(0.9, 0.5, 0.55))
			base.position = Vector3(0, 0, 0)
		else:
			base = MeshInstance3D.new()
			var base_box = BoxMesh.new()
			base_box.size = Vector3(base_size.x * 0.9, base_size.y * 0.5, base_size.z * 0.5)
			base.mesh = base_box
			var base_mat = StandardMaterial3D.new()
			base_mat.albedo_color = base_color.darkened(0.2)
			base.material_override = base_mat
			base.position = Vector3(0, base_box.size.y / 2.0, 0)
		parent_node.add_child(base)

		var barrel_mesh = _part("barrel_heavy")
		var barrel: MeshInstance3D
		if barrel_mesh:
			barrel = _mesh_inst(barrel_mesh, Color.DARK_SLATE_GRAY)
			barrel.scale = Vector3(1.0, base_size.z / 1.0, 1.0)
		else:
			barrel = MeshInstance3D.new()
			var barrel_cyl = CylinderMesh.new()
			barrel_cyl.top_radius = 0.16
			barrel_cyl.bottom_radius = 0.22
			barrel_cyl.height = base_size.z
			barrel.mesh = barrel_cyl
			var barrel_mat = StandardMaterial3D.new()
			barrel_mat.albedo_color = Color.DARK_SLATE_GRAY
			barrel.material_override = barrel_mat
		barrel.position = Vector3(0, base_size.y * 0.5 + 0.2, -base_size.z * 0.25)
		barrel.rotation = Vector3(PI / 2 - 0.44, 0, 0)
		parent_node.add_child(barrel)

	elif type_id == "mortar_array":
		# Base plate
		var base = MeshInstance3D.new()
		var base_box = BoxMesh.new()
		base_box.size = Vector3(base_size.x, base_size.y * 0.2, base_size.z)
		base.mesh = base_box
		var base_mat = StandardMaterial3D.new()
		base_mat.albedo_color = base_color.darkened(0.3)
		base.material_override = base_mat
		base.position = Vector3(0, base_box.size.y / 2.0, 0)
		parent_node.add_child(base)

		# tubes pointing upwards
		var tube_count = int(tweaks.get("tube_count", 2.0))
		var tube_positions = [Vector3(0, 0, 0)]
		if tube_count == 2:
			tube_positions = [Vector3(-0.2, 0, 0), Vector3(0.2, 0, 0)]
		elif tube_count == 3:
			tube_positions = [Vector3(-0.25, 0, -0.15), Vector3(0.25, 0, -0.15), Vector3(0, 0, 0.2)]
		elif tube_count >= 4:
			tube_positions = [Vector3(-0.25, 0, -0.25), Vector3(0.25, 0, -0.25), Vector3(-0.25, 0, 0.25), Vector3(0.25, 0, 0.25)]

		for pos in tube_positions:
			var tube_mesh = _part("barrel_thin")
			var tube: MeshInstance3D
			if tube_mesh:
				tube = _mesh_inst(tube_mesh, Color.DARK_SLATE_GRAY)
				tube.scale = Vector3(1.3, (base_size.y * 0.9) / 1.0, 1.3)
			else:
				tube = MeshInstance3D.new()
				var tube_cyl = CylinderMesh.new()
				tube_cyl.top_radius = 0.08
				tube_cyl.bottom_radius = 0.1
				tube_cyl.height = base_size.y * 0.9
				tube.mesh = tube_cyl
				var tube_mat = StandardMaterial3D.new()
				tube_mat.albedo_color = Color.DARK_SLATE_GRAY
				tube.material_override = tube_mat
			tube.position = Vector3(pos.x * base_size.x, base_box.size.y + (base_size.y * 0.9) / 2.0, pos.z * base_size.z)
			tube.rotation = Vector3(0.35, 0.0, 0.0)
			parent_node.add_child(tube)

	elif type_id == "spigot_mortar":
		var base = MeshInstance3D.new()
		var base_box = BoxMesh.new()
		base_box.size = Vector3(base_size.x, base_size.y * 0.3, base_size.z)
		base.mesh = base_box
		var base_mat = StandardMaterial3D.new()
		base_mat.albedo_color = base_color.darkened(0.2)
		base.material_override = base_mat
		base.position = Vector3(0, base_box.size.y / 2.0, 0)
		parent_node.add_child(base)

		# Chunky spigot mortar rod
		var rod_mesh = _part("barrel_thin")
		var rod: MeshInstance3D
		var rod_len = base_size.y * 0.4
		if rod_mesh:
			rod = _mesh_inst(rod_mesh, Color.SILVER)
			rod.scale = Vector3(0.75, rod_len / 1.0, 0.75)
		else:
			rod = MeshInstance3D.new()
			var rod_cyl = CylinderMesh.new()
			rod_cyl.top_radius = 0.06
			rod_cyl.bottom_radius = 0.06
			rod_cyl.height = rod_len
			rod.mesh = rod_cyl
			var rod_mat = StandardMaterial3D.new()
			rod_mat.albedo_color = Color.SILVER
			rod.material_override = rod_mat
		rod.position = Vector3(0, base_box.size.y + rod_len / 2.0, -base_size.z * 0.2)
		rod.rotation = Vector3(PI / 2 - 0.2, 0, 0)
		parent_node.add_child(rod)

		# Huge explosive warhead loaded on rod
		var bomb_mesh = _part("canister_small")
		var bomb: MeshInstance3D
		if bomb_mesh:
			bomb = _mesh_inst(bomb_mesh, Color.CRIMSON)
			bomb.scale = _fit_scale(Vector3(0.56, 0.45, 0.56), Vector3(0.8, 1.0, 0.8))
		else:
			bomb = MeshInstance3D.new()
			var bomb_cyl = CylinderMesh.new()
			bomb_cyl.top_radius = 0.28
			bomb_cyl.bottom_radius = 0.22
			bomb_cyl.height = 0.45
			bomb.mesh = bomb_cyl
			var bomb_mat = StandardMaterial3D.new()
			bomb_mat.albedo_color = Color.CRIMSON
			bomb.material_override = bomb_mat
		bomb.position = Vector3(0, base_box.size.y + rod_len + 0.1, -base_size.z * 0.35)
		bomb.rotation = Vector3(PI / 2 - 0.2, 0, 0)
		parent_node.add_child(bomb)

	elif type_id == "guided_missile":
		var base_mesh = _part("pintle_mount")
		var frame: MeshInstance3D
		var frame_height = base_size.y * 0.4
		if base_mesh:
			frame = _mesh_inst(base_mesh, base_color.darkened(0.2))
			frame.scale = _fit_scale(Vector3(base_size.x, frame_height, base_size.z * 0.8), Vector3(0.34, 0.22, 0.22))
			frame.position = Vector3(0, 0, 0)
		else:
			frame = MeshInstance3D.new()
			var frame_box = BoxMesh.new()
			frame_box.size = Vector3(base_size.x, frame_height, base_size.z * 0.8)
			frame.mesh = frame_box
			var frame_mat = StandardMaterial3D.new()
			frame_mat.albedo_color = base_color.darkened(0.2)
			frame.material_override = frame_mat
			frame.position = Vector3(0, frame_height / 2.0, 0)
		parent_node.add_child(frame)

		# Single long missile in launch guides
		var missile_mesh = _part("missile_body")
		var missile: MeshInstance3D
		if missile_mesh:
			missile = _mesh_inst(missile_mesh, Color.WHITE)
			missile.scale = Vector3(1.0, base_size.z / 1.0, 1.0)
		else:
			missile = MeshInstance3D.new()
			var mis_cyl = CylinderMesh.new()
			mis_cyl.top_radius = 0.02
			mis_cyl.bottom_radius = 0.08
			mis_cyl.height = base_size.z
			missile.mesh = mis_cyl
			var mis_mat = StandardMaterial3D.new()
			mis_mat.albedo_color = Color.WHITE
			missile.material_override = mis_mat
		missile.position = Vector3(0, frame_height + 0.15, -base_size.z * 0.1)
		missile.rotation = Vector3(PI / 2, 0, 0)
		parent_node.add_child(missile)

	elif type_id == "dual_stage_missile":
		# Vertical launcher silos
		var silo = MeshInstance3D.new()
		var silo_box = BoxMesh.new()
		silo_box.size = Vector3(base_size.x, base_size.y, base_size.z)
		silo.mesh = silo_box
		var silo_mat = StandardMaterial3D.new()
		silo_mat.albedo_color = base_color.darkened(0.1)
		silo.material_override = silo_mat
		silo.position = Vector3(0, base_size.y / 2.0, 0)
		parent_node.add_child(silo)

		# Rocket tip protruding slightly from top
		var tip = MeshInstance3D.new()
		var tip_mesh = SphereMesh.new()
		tip_mesh.radius = base_size.x * 0.35
		tip_mesh.height = base_size.y * 0.5
		tip.mesh = tip_mesh
		var tip_mat = StandardMaterial3D.new()
		tip_mat.albedo_color = Color.DARK_SLATE_GRAY
		tip.material_override = tip_mat
		tip.position = Vector3(0, base_size.y, 0)
		parent_node.add_child(tip)

	elif type_id == "drone_carrier":
		# Big carrier box hangar
		var carrier = MeshInstance3D.new()
		var car_box = BoxMesh.new()
		car_box.size = base_size
		carrier.mesh = car_box
		var car_mat = StandardMaterial3D.new()
		car_mat.albedo_color = base_color
		carrier.material_override = car_mat
		carrier.position = Vector3(0, base_size.y / 2.0, 0)
		parent_node.add_child(carrier)

		# Open hangar bay slot at the back/front (Z negative)
		var slot = MeshInstance3D.new()
		var slot_box = BoxMesh.new()
		slot_box.size = Vector3(base_size.x * 0.8, base_size.y * 0.5, 0.05)
		slot.mesh = slot_box
		var slot_mat = StandardMaterial3D.new()
		slot_mat.albedo_color = Color.BLACK
		slot.material_override = slot_mat
		slot.position = Vector3(0, base_size.y * 0.4, -base_size.z / 2.0 - 0.01)
		parent_node.add_child(slot)

	elif type_id == "cluster_dispenser":
		var disp = MeshInstance3D.new()
		var disp_box = BoxMesh.new()
		disp_box.size = base_size
		disp.mesh = disp_box
		var disp_mat = StandardMaterial3D.new()
		disp_mat.albedo_color = base_color.darkened(0.2)
		disp.material_override = disp_mat
		disp.position = Vector3(0, base_size.y / 2.0, 0)
		parent_node.add_child(disp)

		# Multiple dropper ports on bottom (Y=0.01)
		for x in [-0.3, 0.3]:
			for z in [-0.3, 0.3]:
				var port = MeshInstance3D.new()
				var port_cyl = CylinderMesh.new()
				port_cyl.top_radius = 0.12
				port_cyl.bottom_radius = 0.12
				port_cyl.height = 0.04
				port.mesh = port_cyl
				var port_mat = StandardMaterial3D.new()
				port_mat.albedo_color = Color.BLACK
				port.material_override = port_mat
				port.position = Vector3(x * base_size.x, 0.01, z * base_size.z)
				parent_node.add_child(port)

	elif type_id == "flamethrower":
		var base_mesh = _part("pintle_mount")
		var base: MeshInstance3D
		var base_h = base_size.y * 0.5
		if base_mesh:
			base = _mesh_inst(base_mesh, base_color.darkened(0.1))
			base.scale = _fit_scale(Vector3(base_size.x * 0.8, base_h, base_size.z * 0.4), Vector3(0.34, 0.22, 0.22))
			base.position = Vector3(0, 0, 0)
		else:
			base = MeshInstance3D.new()
			var base_box = BoxMesh.new()
			base_box.size = Vector3(base_size.x * 0.8, base_h, base_size.z * 0.4)
			base.mesh = base_box
			var base_mat = StandardMaterial3D.new()
			base_mat.albedo_color = base_color.darkened(0.1)
			base.material_override = base_mat
			base.position = Vector3(0, base_h / 2.0, 0)
		parent_node.add_child(base)

		# Flame emitter nozzle cylinder
		var nozzle_mesh = _part("barrel_thin")
		var nozzle: MeshInstance3D
		var nozzle_len = base_size.z * 0.8
		if nozzle_mesh:
			nozzle = _mesh_inst(nozzle_mesh, Color(0.15, 0.15, 0.15))
			nozzle.scale = Vector3(1.0, nozzle_len / 1.0, 1.0)
		else:
			nozzle = MeshInstance3D.new()
			var nozzle_cyl = CylinderMesh.new()
			nozzle_cyl.top_radius = 0.06
			nozzle_cyl.bottom_radius = 0.04
			nozzle_cyl.height = nozzle_len
			nozzle.mesh = nozzle_cyl
			var nozzle_mat = StandardMaterial3D.new()
			nozzle_mat.albedo_color = Color(0.15, 0.15, 0.15)
			nozzle.material_override = nozzle_mat
		nozzle.position = Vector3(0, base_h + 0.1, -base_size.z * 0.35)
		nozzle.rotation = Vector3(PI / 2, 0, 0)
		parent_node.add_child(nozzle)

		# Rear pressure fuel tanks
		var tank_mesh = _part("fuel_tank")
		var tank: MeshInstance3D
		if tank_mesh:
			tank = _mesh_inst(tank_mesh, Color.DARK_RED)
			tank.scale = _fit_scale(Vector3(0.24, base_size.y * 0.6, 0.24), Vector3(1.0, 1.0, 1.0))
		else:
			tank = MeshInstance3D.new()
			var tank_cyl = CylinderMesh.new()
			tank_cyl.top_radius = 0.12
			tank_cyl.bottom_radius = 0.12
			tank_cyl.height = base_size.y * 0.6
			tank.mesh = tank_cyl
			var tank_mat = StandardMaterial3D.new()
			tank_mat.albedo_color = Color.DARK_RED
			tank.material_override = tank_mat
		tank.position = Vector3(0, base_h * 0.4, base_size.z * 0.2)
		tank.rotation = Vector3(0, 0, PI / 2)
		parent_node.add_child(tank)

	elif type_id == "plasma_lobber":
		var base_mesh = _part("turret_base_round")
		var base: MeshInstance3D
		if base_mesh:
			base = _mesh_inst(base_mesh, base_color.darkened(0.2))
			base.scale = _fit_scale(Vector3(base_size.x * 1.6, base_size.y * 0.3, base_size.x * 1.6), Vector3(1.0, 0.35, 1.0))
			base.position = Vector3(0, 0, 0)
		else:
			base = MeshInstance3D.new()
			var base_cyl = CylinderMesh.new()
			base_cyl.top_radius = base_size.x * 0.8
			base_cyl.bottom_radius = base_size.x * 0.8
			base_cyl.height = base_size.y * 0.3
			base.mesh = base_cyl
			var base_mat = StandardMaterial3D.new()
			base_mat.albedo_color = base_color.darkened(0.2)
			base.material_override = base_mat
			base.position = Vector3(0, base_cyl.height / 2.0, 0)
		parent_node.add_child(base)

		# Glowing green plasma generator orb
		var orb = MeshInstance3D.new()
		var orb_mesh = SphereMesh.new()
		orb_mesh.radius = base_size.x * 0.45
		orb_mesh.height = base_size.x * 0.9
		orb.mesh = orb_mesh
		var orb_mat = StandardMaterial3D.new()
		orb_mat.albedo_color = Color.MEDIUM_SPRING_GREEN
		orb_mat.emission_enabled = true
		orb_mat.emission = Color.MEDIUM_SPRING_GREEN
		orb_mat.emission_energy_multiplier = 0.8
		orb.material_override = orb_mat
		orb.position = Vector3(0, base_size.y * 0.3 + orb_mesh.radius * 0.8, 0)
		parent_node.add_child(orb)

	elif type_id == "heavy_laser":
		var base_mesh = _part("pintle_mount")
		var base: MeshInstance3D
		var base_h = base_size.y * 0.4
		if base_mesh:
			base = _mesh_inst(base_mesh, base_color.darkened(0.3))
			base.scale = _fit_scale(Vector3(base_size.x, base_h, base_size.z * 0.6), Vector3(0.34, 0.22, 0.22))
			base.position = Vector3(0, 0, 0)
		else:
			base = MeshInstance3D.new()
			var base_box = BoxMesh.new()
			base_box.size = Vector3(base_size.x, base_h, base_size.z * 0.6)
			base.mesh = base_box
			var base_mat = StandardMaterial3D.new()
			base_mat.albedo_color = base_color.darkened(0.3)
			base.material_override = base_mat
			base.position = Vector3(0, base_h / 2.0, 0)
		parent_node.add_child(base)

		# Dual Barrels
		for side in [-1.0, 1.0]:
			var barrel_mesh = _part("barrel_thin")
			var barrel: MeshInstance3D
			var b_len = base_size.z * 0.8
			if barrel_mesh:
				barrel = _mesh_inst(barrel_mesh, base_color)
				barrel.scale = Vector3(1.0, b_len / 1.0, 1.0)
				var bmat = barrel.material_override as StandardMaterial3D
				bmat.emission_enabled = true
				bmat.emission = Color.RED
				bmat.emission_energy_multiplier = 0.5
			else:
				barrel = MeshInstance3D.new()
				var barrel_cyl = CylinderMesh.new()
				barrel_cyl.top_radius = 0.06
				barrel_cyl.bottom_radius = 0.08
				barrel_cyl.height = b_len
				barrel.mesh = barrel_cyl
				var barrel_mat = StandardMaterial3D.new()
				barrel_mat.albedo_color = base_color
				barrel_mat.emission_enabled = true
				barrel_mat.emission = Color.RED
				barrel_mat.emission_energy_multiplier = 0.5
				barrel.material_override = barrel_mat
			barrel.position = Vector3(0.15 * side, base_h + 0.1, -base_size.z * 0.2)
			barrel.rotation = Vector3(PI / 2, 0, 0)
			parent_node.add_child(barrel)

	elif type_id == "missile_pod":
		# Launcher body
		var body = MeshInstance3D.new()
		var body_box = BoxMesh.new()
		body_box.size = base_size
		body.mesh = body_box
		var body_mat = StandardMaterial3D.new()
		body_mat.albedo_color = base_color
		body.material_override = body_mat
		body.position = Vector3(0, base_size.y / 2.0, 0)
		parent_node.add_child(body)

		# Spawns rocket tube circles on the front face (Z-axis negative is forward)
		var grid_size = int(tweaks.get("grid_size", 4.0))
		for r in range(grid_size):
			for c in range(grid_size):
				var norm_r = (float(r) / (grid_size - 1) - 0.5) if grid_size > 1 else 0.0
				var norm_c = (float(c) / (grid_size - 1) - 0.5) if grid_size > 1 else 0.0
				var tube = MeshInstance3D.new()
				var tube_cyl = CylinderMesh.new()
				tube_cyl.top_radius = 0.08 * (4.0 / float(grid_size))
				tube_cyl.bottom_radius = tube_cyl.top_radius
				tube_cyl.height = 0.05
				tube.mesh = tube_cyl
				var tube_mat = StandardMaterial3D.new()
				tube_mat.albedo_color = Color.BLACK
				tube.material_override = tube_mat
				tube.position = Vector3(norm_r * base_size.x * 0.7, base_size.y / 2.0 + norm_c * base_size.y * 0.7, -base_size.z / 2.0 - 0.01)
				tube.rotation = Vector3(PI / 2, 0, 0)
				parent_node.add_child(tube)

	elif type_id == "ciws":
		# Round turret mount
		var mount_mesh = _part("turret_base_round")
		var mount: MeshInstance3D
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, Color.WHITE_SMOKE)
			mount.scale = _fit_scale(Vector3(base_size.x * 1.6, base_size.y * 0.3, base_size.x * 1.6), Vector3(1.0, 0.35, 1.0))
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var mount_cyl = CylinderMesh.new()
			mount_cyl.top_radius = base_size.x * 0.8
			mount_cyl.bottom_radius = base_size.x * 0.8
			mount_cyl.height = base_size.y * 0.3
			mount.mesh = mount_cyl
			var mount_mat = StandardMaterial3D.new()
			mount_mat.albedo_color = Color.WHITE_SMOKE
			mount.material_override = mount_mat
			mount.position = Vector3(0, mount_cyl.height / 2.0, 0)
		parent_node.add_child(mount)
		var mount_h = base_size.y * 0.3

		# Radar Dome sphere
		var dome_mesh = _part("sensor_dome")
		var dome: MeshInstance3D
		var dome_r = base_size.x * 0.5
		if dome_mesh:
			dome = _mesh_inst(dome_mesh, Color.WHITE)
			dome.scale = _fit_scale(Vector3(dome_r * 2.0, dome_r * 2.0 * 0.9, dome_r * 2.0), Vector3(1.0, 0.65, 1.0))
		else:
			dome = MeshInstance3D.new()
			var dome_mesh2 = SphereMesh.new()
			dome_mesh2.radius = dome_r
			dome_mesh2.height = base_size.y * 0.9
			dome.mesh = dome_mesh2
			var dome_mat = StandardMaterial3D.new()
			dome_mat.albedo_color = Color.WHITE
			dome.material_override = dome_mat
		dome.position = Vector3(0, mount_h + dome_r * 0.7, 0)
		parent_node.add_child(dome)

		# Small high-ROF gun barrel on side of dome
		var gun_mesh = _part("barrel_thin")
		var gun: MeshInstance3D
		var gun_len = base_size.z * 0.8
		if gun_mesh:
			gun = _mesh_inst(gun_mesh, Color.DARK_GRAY)
			gun.scale = Vector3(1.0, gun_len / 1.0, 1.0)
		else:
			gun = MeshInstance3D.new()
			var gun_cyl = CylinderMesh.new()
			gun_cyl.top_radius = 0.04
			gun_cyl.bottom_radius = 0.04
			gun_cyl.height = gun_len
			gun.mesh = gun_cyl
			var gun_mat = StandardMaterial3D.new()
			gun_mat.albedo_color = Color.DARK_GRAY
			gun.material_override = gun_mat
		gun.position = Vector3(dome_r * 0.8, mount_h + 0.1, -base_size.z * 0.3)
		gun.rotation = Vector3(PI / 2, 0, 0)
		parent_node.add_child(gun)

	elif type_id == "pd_laser":
		var base_mesh = _part("turret_base_round")
		var base: MeshInstance3D
		if base_mesh:
			base = _mesh_inst(base_mesh, base_color.darkened(0.2))
			base.scale = _fit_scale(Vector3(base_size.x * 1.4, base_size.y * 0.4, base_size.x * 1.4), Vector3(1.0, 0.35, 1.0))
			base.position = Vector3(0, 0, 0)
		else:
			base = MeshInstance3D.new()
			var base_cyl = CylinderMesh.new()
			base_cyl.top_radius = base_size.x * 0.7
			base_cyl.bottom_radius = base_size.x * 0.8
			base_cyl.height = base_size.y * 0.4
			base.mesh = base_cyl
			var base_mat = StandardMaterial3D.new()
			base_mat.albedo_color = base_color.darkened(0.2)
			base.material_override = base_mat
			base.position = Vector3(0, base_cyl.height / 2.0, 0)
		parent_node.add_child(base)
		var base_h = base_size.y * 0.4

		# Tiny focal crystal/housing
		var focal_mesh = _part("focal_lens")
		var focal: MeshInstance3D
		if focal_mesh:
			focal = _mesh_inst(focal_mesh, Color.LIGHT_CORAL, Color.RED, 1.0)
			focal.scale = _fit_scale(Vector3(0.24, 0.24, 0.24), Vector3(1.0, 0.8, 1.0))
		else:
			focal = MeshInstance3D.new()
			var focal_mesh2 = SphereMesh.new()
			focal_mesh2.radius = 0.12
			focal_mesh2.height = 0.24
			focal.mesh = focal_mesh2
			var focal_mat = StandardMaterial3D.new()
			focal_mat.albedo_color = Color.LIGHT_CORAL
			focal_mat.emission_enabled = true
			focal_mat.emission = Color.RED
			focal.material_override = focal_mat
		focal.position = Vector3(0, base_h + 0.05, -0.05)
		parent_node.add_child(focal)

	elif type_id == "flak_cannon":
		var base_mesh = _part("flak_breech")
		var base: MeshInstance3D
		if base_mesh:
			base = _mesh_inst(base_mesh, base_color.darkened(0.3))
			base.scale = _fit_scale(Vector3(base_size.x, base_size.y * 0.5, base_size.z * 0.6), Vector3(0.5, 0.32, 0.4))
			base.position = Vector3(0, 0, 0)
		else:
			base = MeshInstance3D.new()
			var base_box = BoxMesh.new()
			base_box.size = Vector3(base_size.x, base_size.y * 0.5, base_size.z * 0.6)
			base.mesh = base_box
			var base_mat = StandardMaterial3D.new()
			base_mat.albedo_color = base_color.darkened(0.3)
			base.material_override = base_mat
			base.position = Vector3(0, base_box.size.y / 2.0, 0)
		parent_node.add_child(base)
		var base_h = base_size.y * 0.5

		# Heavy flak barrel with massive muzzle brake cylinder
		var barrel_mesh = _part("barrel_standard")
		var barrel: MeshInstance3D
		var barrel_len = base_size.z * 0.7
		if barrel_mesh:
			barrel = _mesh_inst(barrel_mesh, Color(0.15, 0.15, 0.15))
			barrel.scale = Vector3(0.9, barrel_len / 1.0, 0.9)
		else:
			barrel = MeshInstance3D.new()
			var barrel_cyl = CylinderMesh.new()
			barrel_cyl.top_radius = 0.09
			barrel_cyl.bottom_radius = 0.09
			barrel_cyl.height = barrel_len
			barrel.mesh = barrel_cyl
			var barrel_mat = StandardMaterial3D.new()
			barrel_mat.albedo_color = Color(0.15, 0.15, 0.15)
			barrel.material_override = barrel_mat
		barrel.position = Vector3(0, base_h + 0.1, -base_size.z * 0.2)
		barrel.rotation = Vector3(PI / 2, 0, 0)
		parent_node.add_child(barrel)

		var brake_mesh = _part("muzzle_brake")
		var brake: MeshInstance3D
		if brake_mesh:
			brake = _mesh_inst(brake_mesh, Color.DARK_GRAY)
			brake.scale = _fit_scale(Vector3(0.3, 0.15, 0.3), Vector3(1.0, 0.5, 1.0))
		else:
			brake = MeshInstance3D.new()
			var brake_cyl = CylinderMesh.new()
			brake_cyl.top_radius = 0.15
			brake_cyl.bottom_radius = 0.15
			brake_cyl.height = 0.15
			brake.mesh = brake_cyl
			var brake_mat = StandardMaterial3D.new()
			brake_mat.albedo_color = Color.DARK_GRAY
			brake.material_override = brake_mat
		brake.position = Vector3(0, base_h + 0.1, -base_size.z * 0.55)
		brake.rotation = Vector3(PI / 2, 0, 0)
		parent_node.add_child(brake)

	elif type_id == "repair_array":
		# Base plate
		var base = MeshInstance3D.new()
		var base_box = BoxMesh.new()
		base_box.size = Vector3(base_size.x, 0.15, base_size.z)
		base.mesh = base_box
		var base_mat = StandardMaterial3D.new()
		base_mat.albedo_color = base_color.darkened(0.2)
		base.material_override = base_mat
		base.position = Vector3(0, base_box.size.y / 2.0, 0)
		parent_node.add_child(base)

		# Jointed mechanical welder arms
		var arm_count = int(tweaks.get("welder_count", 2.0))
		for a in range(arm_count):
			var offset_x = (float(a) / (arm_count - 1) - 0.5) * base_size.x * 0.6 if arm_count > 1 else 0.0
			var arm1 = MeshInstance3D.new()
			var arm1_mesh = CylinderMesh.new()
			arm1_mesh.top_radius = 0.05
			arm1_mesh.bottom_radius = 0.05
			arm1_mesh.height = base_size.y * 0.6
			arm1.mesh = arm1_mesh
			var arm_mat = StandardMaterial3D.new()
			arm_mat.albedo_color = Color(0.15, 0.15, 0.15)
			arm1.material_override = arm_mat
			arm1.position = Vector3(offset_x, base_box.size.y + arm1_mesh.height / 2.0, 0)
			arm1.rotation = Vector3(0.4, 0, 0)
			parent_node.add_child(arm1)

			var arm2 = MeshInstance3D.new()
			var arm2_mesh = CylinderMesh.new()
			arm2_mesh.top_radius = 0.03
			arm2_mesh.bottom_radius = 0.03
			arm2_mesh.height = base_size.y * 0.7
			arm2.mesh = arm2_mesh
			arm2.material_override = arm_mat
			arm2.position = Vector3(offset_x, base_box.size.y + arm1_mesh.height * 0.8, -arm2_mesh.height * 0.3)
			arm2.rotation = Vector3(-0.6, 0, 0)
			parent_node.add_child(arm2)

			var tip = MeshInstance3D.new()
			var tip_mesh = SphereMesh.new()
			tip_mesh.radius = 0.08
			tip_mesh.height = 0.16
			tip.mesh = tip_mesh
			var tip_mat = StandardMaterial3D.new()
			tip_mat.albedo_color = Color.CYAN
			tip_mat.emission_enabled = true
			tip_mat.emission = Color.CYAN
			tip.material_override = tip_mat
			tip.position = Vector3(offset_x, base_box.size.y + arm1_mesh.height * 0.8, -arm2_mesh.height * 0.7)
			parent_node.add_child(tip)

	elif type_id == "sensor_suite":
		# Tall thin vertical mast rod
		var mast_mesh = _part("sensor_mast")
		var mast: MeshInstance3D
		if mast_mesh:
			mast = _mesh_inst(mast_mesh, Color(0.15, 0.15, 0.15))
			mast.scale = _fit_scale(Vector3(0.14, base_size.y, 0.14), Vector3(0.1, 1.0, 0.1))
			mast.position = Vector3(0, 0, 0)
		else:
			mast = MeshInstance3D.new()
			var mast_cyl = CylinderMesh.new()
			mast_cyl.top_radius = 0.04
			mast_cyl.bottom_radius = 0.07
			mast_cyl.height = base_size.y
			mast.mesh = mast_cyl
			var mast_mat = StandardMaterial3D.new()
			mast_mat.albedo_color = Color(0.15, 0.15, 0.15)
			mast.material_override = mast_mat
			mast.position = Vector3(0, base_size.y / 2.0, 0)
		parent_node.add_child(mast)

		# Spinning radar grid dish (wide cylinder or curved plane)
		var dish = MeshInstance3D.new()
		dish.name = "RadarDish"
		var dish_cyl = CylinderMesh.new()
		# Proportional to the mast's own footprint, not a fixed absolute size -
		# the old hardcoded 0.7 radius towered over the thin 0.5-wide mast base
		# (nearly 3x its footprint), reading as a broken oversized disc rather
		# than a dish.
		dish_cyl.top_radius = base_size.x * 0.6
		dish_cyl.bottom_radius = base_size.x * 0.6
		dish_cyl.height = 0.06
		dish.mesh = dish_cyl
		var dish_mat = StandardMaterial3D.new()
		dish_mat.albedo_color = base_color
		dish.material_override = dish_mat
		dish.position = Vector3(0, base_size.y, 0)
		dish.rotation = Vector3(PI / 2 - 0.2, 0, 0)
		parent_node.add_child(dish)

	elif type_id == "logistics_tank":
		# Horizontal cylindrical tank
		var tank_mesh = _part("fuel_tank")
		var tank: MeshInstance3D
		var tank_r = base_size.y * 0.5
		if tank_mesh:
			tank = _mesh_inst(tank_mesh, base_color)
			tank.scale = _fit_scale(Vector3(tank_r * 2.0, base_size.z, tank_r * 2.0), Vector3(1.0, 1.0, 1.0))
		else:
			tank = MeshInstance3D.new()
			var tank_cyl = CylinderMesh.new()
			tank_cyl.top_radius = tank_r
			tank_cyl.bottom_radius = tank_r
			tank_cyl.height = base_size.z
			tank.mesh = tank_cyl
			var tank_mat = StandardMaterial3D.new()
			tank_mat.albedo_color = base_color
			tank.material_override = tank_mat
		tank.position = Vector3(0, tank_r, 0)
		tank.rotation = Vector3(PI / 2, 0, 0)
		parent_node.add_child(tank)

		# Metal support bands
		for z in [-0.3, 0.3]:
			var band = MeshInstance3D.new()
			var band_cyl = CylinderMesh.new()
			band_cyl.top_radius = tank_r * 1.05
			band_cyl.bottom_radius = tank_r * 1.05
			band_cyl.height = 0.08
			band.mesh = band_cyl
			var band_mat = StandardMaterial3D.new()
			band_mat.albedo_color = Color(0.15, 0.15, 0.15)
			band.material_override = band_mat
			band.position = Vector3(0, tank_r, z * base_size.z)
			band.rotation = Vector3(PI / 2, 0, 0)
			parent_node.add_child(band)

	elif type_id == "resource_harvester":
		var body = MeshInstance3D.new()
		var body_box = BoxMesh.new()
		body_box.size = base_size * Vector3(0.8, 0.6, 0.8)
		body.mesh = body_box
		var body_mat = StandardMaterial3D.new()
		body_mat.albedo_color = base_color.darkened(0.15)
		body.material_override = body_mat
		body.position = Vector3(0, body_box.size.y / 2.0, 0)
		parent_node.add_child(body)

		var arm_mesh = _part("leg_thigh")
		var arm: MeshInstance3D
		var arm_len = base_size.z * 0.7
		if arm_mesh:
			arm = _mesh_inst(arm_mesh, Color.DARK_GOLDENROD)
			arm.scale = _fit_scale(Vector3(0.2, arm_len, 0.2), Vector3(0.26, 0.55, 0.26))
		else:
			arm = MeshInstance3D.new()
			var arm_cyl = CylinderMesh.new()
			arm_cyl.top_radius = 0.1
			arm_cyl.bottom_radius = 0.06
			arm_cyl.height = arm_len
			arm.mesh = arm_cyl
			var arm_mat = StandardMaterial3D.new()
			arm_mat.albedo_color = Color.DARK_GOLDENROD
			arm.material_override = arm_mat
		arm.position = Vector3(0, body_box.size.y * 0.6, -base_size.z * 0.55)
		arm.rotation = Vector3(PI / 2 - 0.3, 0, 0)
		parent_node.add_child(arm)

	elif type_id == "wing":
		_build_wing(parent_node, base_size, base_color)
	elif type_id == "thruster":
		_build_thruster(parent_node, base_size, base_color)
	elif type_id == "propeller_prop":
		_build_propeller(parent_node, base_size, base_color, false)
	elif type_id == "pusher_prop":
		_build_propeller(parent_node, base_size, base_color, true)
	elif type_id == "paddle_wheel":
		_build_paddle_wheel(parent_node, base_size, base_color)
	elif type_id == "ship_screw":
		_build_ship_screw(parent_node, base_size, base_color)

	elif type_id == "tesla_coil":
		# Chris explicitly invited some fun/silly weapons alongside the
		# grounded ones (ENERGY_AND_BALANCE_SPEC.md #4) - a literal wound
		# coil with a glowing discharge ball on top, distinct from the
		# generic box fallback every other unhandled type gets.
		var base = MeshInstance3D.new()
		var base_cyl = CylinderMesh.new()
		base_cyl.top_radius = base_size.x * 0.45
		base_cyl.bottom_radius = base_size.x * 0.55
		base_cyl.height = base_size.y * 0.15
		base.mesh = base_cyl
		var base_mat = StandardMaterial3D.new()
		base_mat.albedo_color = Color(0.2, 0.2, 0.22)
		base.material_override = base_mat
		base.position = Vector3(0, base_cyl.height / 2.0, 0)
		parent_node.add_child(base)

		var coil_segments = 8
		var coil_height = base_size.y * 0.75
		var coil_radius = base_size.x * 0.32
		for i in range(coil_segments):
			var ring = MeshInstance3D.new()
			var torus = TorusMesh.new()
			torus.inner_radius = coil_radius - 0.03
			torus.outer_radius = coil_radius
			ring.mesh = torus
			var ring_mat = StandardMaterial3D.new()
			ring_mat.albedo_color = base_color
			ring_mat.emission_enabled = true
			ring_mat.emission = base_color
			ring_mat.emission_energy_multiplier = 0.4
			ring.material_override = ring_mat
			ring.position = Vector3(0, base_size.y * 0.2 + (coil_height * i / float(coil_segments - 1)), 0)
			parent_node.add_child(ring)

		var orb = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = base_size.x * 0.4
		sphere.height = sphere.radius * 2.0
		orb.mesh = sphere
		var orb_mat = StandardMaterial3D.new()
		orb_mat.albedo_color = Color.WHITE
		orb_mat.emission_enabled = true
		orb_mat.emission = base_color
		orb_mat.emission_energy_multiplier = 1.5
		orb.material_override = orb_mat
		orb.position = Vector3(0, base_size.y * 0.2 + coil_height + sphere.radius * 0.6, 0)
		parent_node.add_child(orb)

	else:
		# Fallback: Simple box mesh for armor and basic parts
		var mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = base_size
		mesh_inst.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = base_color
		mesh_inst.material_override = mat
		mesh_inst.position = Vector3(0, base_size.y / 2.0, 0)
		parent_node.add_child(mesh_inst)

	# Locomotion & remaining categories, split out for readability
	if type_id == "wheels":
		_build_wheels(parent_node, base_size)
	elif type_id == "omni_wheels":
		_build_omni_wheels(parent_node, base_size)
	elif type_id == "tracked_treads":
		_build_tracked_treads(parent_node, base_size, base_color)
	elif type_id == "rhomboid_treads":
		_build_rhomboid_treads(parent_node, base_size, base_color)
	elif type_id == "helicopter_rotors":
		_build_helicopter_rotors(parent_node, base_size)
	elif type_id == "hover_engine":
		_build_hover_engine(parent_node, base_size, base_color)
	elif type_id == "legs":
		_build_legs(parent_node, base_size, base_color)
	elif type_id == "anti_grav":
		_build_anti_grav(parent_node, base_size, base_color)
	elif type_id == "fixed_wing_engine":
		_build_fixed_wing_engine(parent_node, base_size, base_color)
	elif type_id == "ornithopter_wing":
		_build_ornithopter_wing(parent_node, base_size, base_color)
	elif type_id == "naval_propeller":
		_build_naval_propeller(parent_node, base_size, base_color)
	elif type_id == "buoyant_envelope":
		_build_buoyant_envelope(parent_node, base_size, base_color)
	elif type_id == "screw_drive":
		_build_screw_drive(parent_node, base_size, base_color)

	# Apply deformations to the newly constructed meshes based on the tweaks
	_apply_tweak_deformations(type_id, parent_node, tweaks, base_size)


static func _build_wheels(parent_node: Node3D, base_size: Vector3):
	var wheel_mesh = _part("wheel_hub")
	var wheel: MeshInstance3D
	if wheel_mesh:
		wheel = _mesh_inst(wheel_mesh, Color.BLACK)
		wheel.scale = _fit_scale(Vector3(base_size.y, base_size.x * 0.7, base_size.y), Vector3(0.9, 0.35, 0.9))
	else:
		wheel = MeshInstance3D.new()
		var wheel_cyl = CylinderMesh.new()
		wheel_cyl.top_radius = base_size.y / 2.0
		wheel_cyl.bottom_radius = base_size.y / 2.0
		wheel_cyl.height = base_size.x * 0.7
		wheel.mesh = wheel_cyl
		var wheel_mat = StandardMaterial3D.new()
		wheel_mat.albedo_color = Color.BLACK
		wheel.material_override = wheel_mat
	wheel.position = Vector3(0, base_size.y / 2.0, 0)
	wheel.rotation = Vector3(0, 0, PI / 2)
	parent_node.add_child(wheel)

	# Inner Hubcap
	var hub = MeshInstance3D.new()
	var hub_cyl = CylinderMesh.new()
	hub_cyl.top_radius = (base_size.y / 2.0) * 0.5
	hub_cyl.bottom_radius = (base_size.y / 2.0) * 0.5
	hub_cyl.height = (base_size.x * 0.7) * 1.05
	hub.mesh = hub_cyl
	var hub_mat = StandardMaterial3D.new()
	hub_mat.albedo_color = Color.SILVER
	hub.material_override = hub_mat
	hub.position = Vector3(0, base_size.y / 2.0, 0)
	hub.rotation = Vector3(0, 0, PI / 2)
	parent_node.add_child(hub)


static func _build_omni_wheels(parent_node: Node3D, base_size: Vector3):
	# Batch E task 5: mecanum-style wheel - a real mecanum wheel's tell is
	# a ring of small diagonal rollers around its circumference (that's
	# literally what lets it push sideways), so this is deliberately built
	# to look different from a plain wheel_hub, not just a recolor.
	var hub = MeshInstance3D.new()
	var hub_cyl = CylinderMesh.new()
	hub_cyl.top_radius = base_size.y * 0.42
	hub_cyl.bottom_radius = base_size.y * 0.42
	hub_cyl.height = base_size.x * 0.55
	hub.mesh = hub_cyl
	var hub_mat = StandardMaterial3D.new()
	hub_mat.albedo_color = Color(0.15, 0.15, 0.18)
	hub_mat.metallic = 0.6
	hub_mat.roughness = 0.4
	hub.material_override = hub_mat
	hub.position = Vector3(0, base_size.y / 2.0, 0)
	hub.rotation = Vector3(0, 0, PI / 2)
	parent_node.add_child(hub)

	# Ring of small diagonal rollers around the hub's circumference - each
	# one angled ~45 degrees to its own tangent, the actual mecanum-wheel
	# look.
	var roller_count = 9
	var roller_mat = StandardMaterial3D.new()
	roller_mat.albedo_color = Color.SILVER
	roller_mat.metallic = 0.7
	roller_mat.roughness = 0.3
	for i in range(roller_count):
		var angle = TAU * float(i) / float(roller_count)
		var y = sin(angle) * base_size.y * 0.4
		var z = cos(angle) * base_size.y * 0.4
		var roller = MeshInstance3D.new()
		var roller_cyl = CylinderMesh.new()
		roller_cyl.top_radius = base_size.y * 0.12
		roller_cyl.bottom_radius = base_size.y * 0.12
		roller_cyl.height = base_size.y * 0.28
		roller.mesh = roller_cyl
		roller.material_override = roller_mat
		roller.position = Vector3(0, base_size.y / 2.0 + y, z)
		# Tangent-ish orientation (angle offset by 45deg) plus the tilt
		# that makes each roller's own axis diagonal to the wheel's
		# rotation axis - the actual mechanical trick a real mecanum
		# wheel uses, reproduced here as a static visual cue.
		roller.rotation = Vector3(angle, 0, deg_to_rad(45.0))
		parent_node.add_child(roller)


static func _build_tracked_treads(parent_node: Node3D, base_size: Vector3, base_color: Color):
	var belt_mesh = _part("tread_plate")
	var belt: MeshInstance3D
	if belt_mesh:
		belt = _mesh_inst(belt_mesh, base_color)
		belt.scale = _fit_scale(base_size, Vector3(1.0, 0.3, 1.0))
	else:
		belt = MeshInstance3D.new()
		var belt_box = BoxMesh.new()
		belt_box.size = base_size
		belt.mesh = belt_box
		var belt_mat = StandardMaterial3D.new()
		belt_mat.albedo_color = base_color
		belt.material_override = belt_mat
	belt.position = Vector3(0, base_size.y / 2.0, 0)
	parent_node.add_child(belt)

	# Roller wheels along the bottom
	var roller_mesh = _part("wheel_hub")
	for i in range(4):
		var roller: MeshInstance3D
		if roller_mesh:
			roller = _mesh_inst(roller_mesh, Color.DARK_SLATE_GRAY)
			roller.scale = _fit_scale(Vector3(base_size.y * 0.5, base_size.x * 1.1, base_size.y * 0.5), Vector3(0.9, 0.35, 0.9))
		else:
			roller = MeshInstance3D.new()
			var roller_cyl = CylinderMesh.new()
			roller_cyl.top_radius = base_size.y * 0.25
			roller_cyl.bottom_radius = base_size.y * 0.25
			roller_cyl.height = base_size.x * 1.1
			roller.mesh = roller_cyl
			var roller_mat = StandardMaterial3D.new()
			roller_mat.albedo_color = Color.DARK_SLATE_GRAY
			roller.material_override = roller_mat
		var z_pos = -base_size.z / 3.0 + (i * base_size.z / 4.5)
		roller.position = Vector3(0, base_size.y * 0.1, z_pos)
		roller.rotation = Vector3(0, 0, PI / 2)
		parent_node.add_child(roller)


static func _build_rhomboid_treads(parent_node: Node3D, base_size: Vector3, base_color: Color):
	# Batch E task 4: WWI Mark IV silhouette - the track loop wraps all the
	# way around the hull (up and over the top), not just the bottom sides
	# like _build_tracked_treads' flat plate-plus-rollers. Built as a ring
	# of link plates traced around an ellipse in the local Y-Z plane
	# (base_size.y is deliberately much taller than a normal tread's, and
	# base_size.z longer, so the loop genuinely extends above/below and
	# fore/aft of the hull body it's mounted beside - see the catalog
	# entry's size field).
	var link_count = 22
	var radius_y = base_size.y * 0.46
	var radius_z = base_size.z * 0.46
	var link_mesh = _part("tread_plate")
	var mat: StandardMaterial3D
	if not link_mesh:
		mat = StandardMaterial3D.new()
		mat.albedo_color = base_color

	for i in range(link_count):
		var angle = TAU * float(i) / float(link_count)
		var y = sin(angle) * radius_y
		var z = cos(angle) * radius_z
		var link: MeshInstance3D
		if link_mesh:
			link = _mesh_inst(link_mesh, base_color)
			link.scale = _fit_scale(Vector3(base_size.x * 0.85, base_size.y * 0.12, base_size.z * 0.16), Vector3(1.0, 0.3, 1.0))
		else:
			link = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(base_size.x * 0.85, base_size.y * 0.12, base_size.z * 0.16)
			link.mesh = box
			link.material_override = mat
		link.position = Vector3(0, y, z)
		# Tangent-to-the-loop orientation so each link plate faces along
		# the belt's direction of travel rather than all facing the same
		# way - an ellipse's exact tangent angle isn't simply angle+90deg
		# once radius_y != radius_z, but it's a close enough approximation
		# for a static, non-simulated part to read correctly.
		link.rotation = Vector3(angle + PI / 2.0, 0, 0)
		parent_node.add_child(link)

	# Two idler drums at the fore/aft turning points (where the loop
	# reverses direction) - breaks up the ring into a recognizable "track
	# horn" shape at each end, echoing the real Mark IV's pointed track horns.
	var drum_mesh = _part("wheel_hub")
	for z_end in [radius_z, -radius_z]:
		var drum: MeshInstance3D
		if drum_mesh:
			drum = _mesh_inst(drum_mesh, Color.DARK_SLATE_GRAY)
			drum.scale = _fit_scale(Vector3(base_size.y * 0.55, base_size.x * 0.9, base_size.y * 0.55), Vector3(0.9, 0.35, 0.9))
		else:
			drum = MeshInstance3D.new()
			var drum_cyl = CylinderMesh.new()
			drum_cyl.top_radius = base_size.y * 0.28
			drum_cyl.bottom_radius = base_size.y * 0.28
			drum_cyl.height = base_size.x * 0.9
			drum.mesh = drum_cyl
			var drum_mat = StandardMaterial3D.new()
			drum_mat.albedo_color = Color.DARK_SLATE_GRAY
			drum.material_override = drum_mat
		drum.position = Vector3(0, 0, z_end)
		drum.rotation = Vector3(0, 0, PI / 2)
		parent_node.add_child(drum)


static func _build_helicopter_rotors(parent_node: Node3D, base_size: Vector3):
	# Spindle / Shaft
	var shaft = MeshInstance3D.new()
	var shaft_cyl = CylinderMesh.new()
	shaft_cyl.top_radius = 0.05
	shaft_cyl.bottom_radius = 0.05
	shaft_cyl.height = base_size.y * 0.8
	shaft.mesh = shaft_cyl
	var shaft_mat = StandardMaterial3D.new()
	shaft_mat.albedo_color = Color.DARK_GRAY
	shaft.material_override = shaft_mat
	shaft.position = Vector3(0, shaft_cyl.height / 2.0, 0)
	parent_node.add_child(shaft)

	# Cross Blades
	var blades = MeshInstance3D.new()
	blades.name = "BladeRotator"
	var blade_mesh = BoxMesh.new()
	blade_mesh.size = Vector3(base_size.x, 0.03, 0.2)
	blades.mesh = blade_mesh
	var blade_mat = StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.1, 0.1, 0.1)
	blades.material_override = blade_mat
	blades.position = Vector3(0, shaft_cyl.height, 0)
	parent_node.add_child(blades)

	# Second perpendicular blade
	var blade2 = MeshInstance3D.new()
	blade2.name = "BladeRotator2"
	var blade_mesh2 = BoxMesh.new()
	blade_mesh2.size = Vector3(0.2, 0.03, base_size.x)
	blade2.mesh = blade_mesh2
	blade2.material_override = blade_mat
	blade2.position = Vector3(0, shaft_cyl.height + 0.01, 0)
	parent_node.add_child(blade2)


static func _build_hover_engine(parent_node: Node3D, base_size: Vector3, base_color: Color):
	var pad_mesh = _part("hover_ring")
	if pad_mesh:
		var pad = _mesh_inst(pad_mesh, base_color, base_color, 1.0)
		pad.scale = _fit_scale(Vector3(base_size.x, base_size.y * 1.4, base_size.x), Vector3(1.2, 0.2, 1.2))
		pad.position = Vector3(0, base_size.y / 2.0, 0)
		parent_node.add_child(pad)
	else:
		# Outer Ring / Disc
		var pad = MeshInstance3D.new()
		var pad_cyl = CylinderMesh.new()
		pad_cyl.top_radius = base_size.x / 2.0
		pad_cyl.bottom_radius = base_size.x / 2.0
		pad_cyl.height = base_size.y
		pad.mesh = pad_cyl
		var pad_mat = StandardMaterial3D.new()
		pad_mat.albedo_color = base_color.darkened(0.2)
		pad.material_override = pad_mat
		pad.position = Vector3(0, base_size.y / 2.0, 0)
		parent_node.add_child(pad)

		# Inner Glow
		var glow = MeshInstance3D.new()
		var glow_cyl = CylinderMesh.new()
		glow_cyl.top_radius = pad_cyl.top_radius * 0.7
		glow_cyl.bottom_radius = pad_cyl.bottom_radius * 0.7
		glow_cyl.height = pad_cyl.height * 1.05
		glow.mesh = glow_cyl
		var glow_mat = StandardMaterial3D.new()
		glow_mat.albedo_color = base_color
		glow_mat.emission_enabled = true
		glow_mat.emission = base_color
		glow_mat.emission_energy_multiplier = 1.0
		glow.material_override = glow_mat
		glow.position = Vector3(0, base_size.y / 2.0, 0)
		parent_node.add_child(glow)


static func _build_legs(parent_node: Node3D, base_size: Vector3, base_color: Color):
	# Upper thigh segment (angled cylinder)
	var thigh_mesh = _part("leg_thigh")
	var thigh: MeshInstance3D
	var thigh_len = base_size.y * 0.5
	if thigh_mesh:
		thigh = _mesh_inst(thigh_mesh, base_color)
		thigh.scale = _fit_scale(Vector3(0.24, thigh_len, 0.24), Vector3(0.26, 0.55, 0.26))
	else:
		thigh = MeshInstance3D.new()
		var thigh_cyl = CylinderMesh.new()
		thigh_cyl.top_radius = 0.12
		thigh_cyl.bottom_radius = 0.08
		thigh_cyl.height = thigh_len
		thigh.mesh = thigh_cyl
		var leg_mat = StandardMaterial3D.new()
		leg_mat.albedo_color = base_color
		thigh.material_override = leg_mat
	thigh.position = Vector3(0, base_size.y * 0.75, 0)
	thigh.rotation = Vector3(0, 0, PI / 6)
	parent_node.add_child(thigh)

	# Lower shin segment (angled cylinder)
	var shin_mesh = _part("leg_shin")
	var shin: MeshInstance3D
	var shin_len = base_size.y * 0.6
	if shin_mesh:
		shin = _mesh_inst(shin_mesh, Color(0.15, 0.15, 0.15))
		shin.scale = _fit_scale(Vector3(0.18, shin_len, 0.18), Vector3(0.18, 0.5, 0.18))
	else:
		shin = MeshInstance3D.new()
		var shin_cyl = CylinderMesh.new()
		shin_cyl.top_radius = 0.08
		shin_cyl.bottom_radius = 0.05
		shin_cyl.height = shin_len
		shin.mesh = shin_cyl
		var shin_mat = StandardMaterial3D.new()
		shin_mat.albedo_color = Color(0.15, 0.15, 0.15)
		shin.material_override = shin_mat
	shin.position = Vector3(base_size.y * 0.2, base_size.y * 0.3, 0)
	shin.rotation = Vector3(0, 0, -PI / 8)
	parent_node.add_child(shin)

	# Flat foot pad
	var foot = MeshInstance3D.new()
	var foot_box = BoxMesh.new()
	foot_box.size = Vector3(base_size.x * 0.7, 0.06, base_size.z * 0.7)
	foot.mesh = foot_box
	var foot_mat = StandardMaterial3D.new()
	foot_mat.albedo_color = Color(0.15, 0.15, 0.15)
	foot.material_override = foot_mat
	foot.position = Vector3(base_size.y * 0.1, 0.03, 0)
	parent_node.add_child(foot)


static func _build_anti_grav(parent_node: Node3D, base_size: Vector3, base_color: Color):
	var ring_mesh = _part("antigrav_ring")
	if ring_mesh:
		for r in range(2):
			var ring = _mesh_inst(ring_mesh, base_color, base_color, 0.8)
			ring.scale = _fit_scale(Vector3(base_size.x * (0.8 + r * 0.4), base_size.y * 2.0, base_size.x * (0.8 + r * 0.4)), Vector3(1.0, 0.14, 1.0))
			ring.position = Vector3(0, base_size.y / 2.0 + r * 0.05, 0)
			parent_node.add_child(ring)
	else:
		# Concentric glowing rings
		for r in range(2):
			var ring = MeshInstance3D.new()
			var ring_cyl = CylinderMesh.new()
			ring_cyl.top_radius = base_size.x * (0.4 + r * 0.2)
			ring_cyl.bottom_radius = ring_cyl.top_radius
			ring_cyl.height = base_size.y
			ring.mesh = ring_cyl
			var ring_mat = StandardMaterial3D.new()
			ring_mat.albedo_color = base_color
			ring_mat.emission_enabled = true
			ring_mat.emission = base_color
			ring_mat.emission_energy_multiplier = 0.8
			ring.material_override = ring_mat
			ring.position = Vector3(0, base_size.y / 2.0 + r * 0.05, 0)
			parent_node.add_child(ring)


static func _build_fixed_wing_engine(parent_node: Node3D, base_size: Vector3, base_color: Color):
	# Tapered nacelle pod, oriented along local Z (forward). No authored
	# asset yet (Traits B3 proof-of-concept, procedural like several other
	# fallback visuals) - see DECISIONS_NEEDED.md on why new Blender-
	# authored geometry is deferred.
	var nacelle = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = base_size.y * 0.55
	cyl.bottom_radius = base_size.y * 0.4
	cyl.height = base_size.z
	nacelle.mesh = cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.metallic = 0.6
	mat.roughness = 0.3
	nacelle.material_override = mat
	nacelle.rotation = Vector3(PI / 2.0, 0, 0)
	parent_node.add_child(nacelle)

	var intake = MeshInstance3D.new()
	var intake_cyl = CylinderMesh.new()
	intake_cyl.top_radius = base_size.y * 0.35
	intake_cyl.bottom_radius = base_size.y * 0.35
	intake_cyl.height = 0.08
	intake.mesh = intake_cyl
	var intake_mat = StandardMaterial3D.new()
	intake_mat.albedo_color = Color(0.05, 0.05, 0.05)
	intake.material_override = intake_mat
	intake.rotation = Vector3(PI / 2.0, 0, 0)
	intake.position = Vector3(0, 0, -base_size.z / 2.0 - 0.02)
	parent_node.add_child(intake)


static func _build_ornithopter_wing(parent_node: Node3D, base_size: Vector3, base_color: Color):
	# Batch E task 3: flapping-wing flight, deliberately a different
	# silhouette from both fixed_wing_engine (a cylindrical nacelle - no
	# wing surface at all, just an engine pod) and the flat glider "wing"
	# add-on module (_build_wing, above - a plain rectangular panel).
	# A bat/pterosaur-style angled membrane: a small shoulder joint block
	# close to the hull, then a tapered, dihedral-angled (raised) membrane
	# with visible rib struts, tapering to a swept tip - reads as an
	# organic wing shape even static, since there's no real flap animation
	# baked into the mesh itself (the actual flapping motion is a runtime
	# rotation in battle_unit.gd, not a rigged/animated mesh).
	var shoulder = MeshInstance3D.new()
	var shoulder_box = BoxMesh.new()
	shoulder_box.size = Vector3(base_size.x * 0.35, base_size.y * 0.7, base_size.z * 0.35)
	shoulder.mesh = shoulder_box
	var joint_mat = StandardMaterial3D.new()
	joint_mat.albedo_color = Color(0.3, 0.28, 0.25)
	joint_mat.metallic = 0.4
	joint_mat.roughness = 0.5
	shoulder.material_override = joint_mat
	parent_node.add_child(shoulder)

	# The membrane itself lives under a pivot node so battle_unit.gd's
	# flap animation has a single, clean rotation target (same pattern as
	# helicopter_rotors spinning its own first child).
	var pivot = Node3D.new()
	pivot.name = "WingPivot"
	pivot.position = Vector3(base_size.x * 0.2, base_size.y * 0.15, 0)
	parent_node.add_child(pivot)

	var membrane = MeshInstance3D.new()
	var membrane_box = BoxMesh.new()
	membrane_box.size = Vector3(base_size.x * 0.75, base_size.y * 0.15, base_size.z * 0.85)
	membrane.mesh = membrane_box
	var mem_mat = StandardMaterial3D.new()
	mem_mat.albedo_color = base_color
	mem_mat.metallic = 0.05
	mem_mat.roughness = 0.85
	membrane.material_override = mem_mat
	membrane.position = Vector3(base_size.x * 0.42, 0, 0)
	membrane.rotation = Vector3(0, 0, deg_to_rad(12.0))
	pivot.add_child(membrane)

	var tip = MeshInstance3D.new()
	var tip_box = BoxMesh.new()
	tip_box.size = Vector3(base_size.x * 0.35, base_size.y * 0.1, base_size.z * 0.45)
	tip.mesh = tip_box
	tip.material_override = mem_mat
	tip.position = Vector3(base_size.x * 0.85, base_size.y * 0.12, -base_size.z * 0.1)
	tip.rotation = Vector3(0, 0, deg_to_rad(20.0))
	pivot.add_child(tip)

	# Rib struts - thin diagonal bars across the membrane, the visual cue
	# that reads as "wing bones under skin" rather than a solid panel.
	for i in range(3):
		var rib = MeshInstance3D.new()
		var rib_box = BoxMesh.new()
		rib_box.size = Vector3(base_size.x * 0.7, base_size.y * 0.04, base_size.z * 0.06)
		rib.mesh = rib_box
		var rib_mat = StandardMaterial3D.new()
		rib_mat.albedo_color = Color(0.22, 0.17, 0.12)
		rib.material_override = rib_mat
		var z_pos = -base_size.z * 0.3 + i * base_size.z * 0.3
		rib.position = Vector3(base_size.x * 0.42, base_size.y * 0.08, z_pos)
		rib.rotation = Vector3(0, 0, deg_to_rad(12.0))
		pivot.add_child(rib)


static func _build_naval_propeller(parent_node: Node3D, base_size: Vector3, base_color: Color):
	# Stern housing + a small blade cluster - new movement paradigm
	# proof-of-concept (Traits B3), procedural like the fixed-wing engine.
	var housing = MeshInstance3D.new()
	var housing_cyl = CylinderMesh.new()
	housing_cyl.top_radius = base_size.x * 0.4
	housing_cyl.bottom_radius = base_size.x * 0.5
	housing_cyl.height = base_size.z * 0.7
	housing.mesh = housing_cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = base_color.darkened(0.2)
	mat.metallic = 0.7
	mat.roughness = 0.4
	housing.material_override = mat
	housing.rotation = Vector3(PI / 2.0, 0, 0)
	parent_node.add_child(housing)

	for i in range(3):
		var blade = MeshInstance3D.new()
		var blade_box = BoxMesh.new()
		blade_box.size = Vector3(0.04, base_size.x * 0.7, 0.12)
		blade.mesh = blade_box
		var blade_mat = StandardMaterial3D.new()
		blade_mat.albedo_color = Color.SILVER
		blade.material_override = blade_mat
		blade.position = Vector3(0, 0, base_size.z * 0.4)
		blade.rotate_z(i * (TAU / 3.0))
		parent_node.add_child(blade)


static func _build_buoyant_envelope(parent_node: Node3D, base_size: Vector3, base_color: Color):
	# One small cruise-motor nacelle on an outrigger strut - deliberately
	# modest (buoyancy does the actual lifting, this is just steering/
	# cruise thrust), distinct from fixed_wing_engine's bigger nacelle. One
	# instance per call, same convention as fixed_wing_engine/tracked_treads
	# - update_locomotion() places a matched pair (left/right) so the
	# vehicle's real weight/thrust contribution reflects two physical
	# motors, not one asymmetric one.
	var strut_mat = StandardMaterial3D.new()
	strut_mat.albedo_color = base_color.darkened(0.3)
	var nacelle_mat = StandardMaterial3D.new()
	nacelle_mat.albedo_color = base_color.darkened(0.15)
	nacelle_mat.metallic = 0.6
	nacelle_mat.roughness = 0.35
	var blade_mat = StandardMaterial3D.new()
	blade_mat.albedo_color = Color.SILVER

	var strut = MeshInstance3D.new()
	var strut_box = BoxMesh.new()
	strut_box.size = Vector3(base_size.x * 0.5, 0.04, 0.04)
	strut.mesh = strut_box
	strut.material_override = strut_mat
	strut.position = Vector3(base_size.x * 0.25, 0, 0)
	parent_node.add_child(strut)

	var nacelle = MeshInstance3D.new()
	var nacelle_cyl = CylinderMesh.new()
	nacelle_cyl.top_radius = base_size.y * 0.3
	nacelle_cyl.bottom_radius = base_size.y * 0.25
	nacelle_cyl.height = base_size.z * 0.6
	nacelle.mesh = nacelle_cyl
	nacelle.material_override = nacelle_mat
	nacelle.rotation = Vector3(PI / 2.0, 0, 0)
	nacelle.position = Vector3(base_size.x * 0.5, 0, 0)
	parent_node.add_child(nacelle)

	for i in range(2):
		var blade = MeshInstance3D.new()
		var blade_box = BoxMesh.new()
		blade_box.size = Vector3(0.02, base_size.y * 0.55, 0.08)
		blade.mesh = blade_box
		blade.material_override = blade_mat
		blade.position = Vector3(base_size.x * 0.5, 0, -base_size.z * 0.35)
		blade.rotate_z(i * (TAU / 2.0))
		parent_node.add_child(blade)


static func _build_screw_drive(parent_node: Node3D, base_size: Vector3, base_color: Color):
	# One helical auger drum - the real distinguishing silhouette of an
	# amphibious screw-propelled vehicle (see screw_drum's own comment in
	# tools/blender/build_meshes.py for the historical reference). One
	# instance per call, same convention as tracked_treads - update_
	# locomotion() places a matched left/right pair.
	var drum_mesh = _part("screw_drum")
	var drum: MeshInstance3D
	if drum_mesh:
		# Authored along local Z already (tools/blender/build_meshes.py's
		# build_screw_drum) - no runtime rotation needed, unlike
		# wheel_hub/hover_ring which are authored Y-vertical.
		drum = _mesh_inst(drum_mesh, base_color)
		drum.scale = _fit_scale(Vector3(base_size.y * 0.85, base_size.y * 0.85, base_size.z), Vector3(0.29, 0.29, 1.6))
	else:
		drum = MeshInstance3D.new()
		var drum_cyl = CylinderMesh.new()
		drum_cyl.top_radius = base_size.y * 0.4
		drum_cyl.bottom_radius = base_size.y * 0.4
		drum_cyl.height = base_size.z
		drum.mesh = drum_cyl
		var drum_mat = StandardMaterial3D.new()
		drum_mat.albedo_color = base_color
		drum.material_override = drum_mat
		drum.rotation = Vector3(PI / 2.0, 0, 0)
	parent_node.add_child(drum)


static func _build_wing(parent_node: Node3D, base_size: Vector3, base_color: Color):
	# Flat swept panel - no aerodynamic simulation, purely a weight_capacity
	# attachment (see module_catalog.gd's "weight_capacity_bonus").
	var panel = MeshInstance3D.new()
	var panel_box = BoxMesh.new()
	panel_box.size = Vector3(base_size.x, base_size.y * 0.6, base_size.z)
	panel.mesh = panel_box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.metallic = 0.5
	mat.roughness = 0.4
	panel.material_override = mat
	parent_node.add_child(panel)

	# Swept tip - a smaller box fused near the outer edge to break up the
	# plain rectangle silhouette.
	var tip = MeshInstance3D.new()
	var tip_box = BoxMesh.new()
	tip_box.size = Vector3(base_size.x * 0.25, base_size.y * 0.45, base_size.z * 0.6)
	tip.mesh = tip_box
	tip.material_override = mat
	tip.position = Vector3(base_size.x * 0.45, 0, -base_size.z * 0.15)
	parent_node.add_child(tip)


static func _build_thruster(parent_node: Node3D, base_size: Vector3, base_color: Color):
	# Jet/rocket nacelle - no visible blades (reads as reaction thrust, not
	# a propeller), distinct from propeller_prop/pusher_prop/ship_screw.
	var nacelle = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = base_size.y * 0.5
	cyl.bottom_radius = base_size.y * 0.45
	cyl.height = base_size.z * 0.75
	nacelle.mesh = cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.metallic = 0.75
	mat.roughness = 0.3
	nacelle.material_override = mat
	nacelle.rotation = Vector3(PI / 2.0, 0, 0)
	parent_node.add_child(nacelle)

	var exhaust = MeshInstance3D.new()
	var exhaust_cyl = CylinderMesh.new()
	exhaust_cyl.top_radius = base_size.y * 0.5
	exhaust_cyl.bottom_radius = base_size.y * 0.35
	exhaust_cyl.height = base_size.z * 0.3
	exhaust.mesh = exhaust_cyl
	var exhaust_mat = StandardMaterial3D.new()
	exhaust_mat.albedo_color = Color(1.0, 0.5, 0.1)
	exhaust_mat.emission_enabled = true
	exhaust_mat.emission = Color(1.0, 0.4, 0.05)
	exhaust_mat.emission_energy_multiplier = 1.2
	exhaust.material_override = exhaust_mat
	exhaust.rotation = Vector3(PI / 2.0, 0, 0)
	exhaust.position = Vector3(0, 0, base_size.z * 0.55)
	parent_node.add_child(exhaust)


## Geometric Polish Pass (Section 3): a real thinning taper for
## propeller/screw blades - thick chord at the hub, narrow at the tip -
## instead of a constant-cross-section BoxMesh. Spans along local Y
## (0=root, span=tip); tapers chord along local Z; thickness (local X)
## stays constant along the span, matching how a real blade is built.
static func _build_tapered_blade_mesh(thickness: float, root_chord: float, tip_chord: float, span: float) -> ArrayMesh:
	var hx = thickness * 0.5
	var hz0 = root_chord * 0.5
	var hz1 = tip_chord * 0.5
	var root_pts = [
		Vector3(-hx, 0.0, -hz0), Vector3(hx, 0.0, -hz0),
		Vector3(hx, 0.0, hz0), Vector3(-hx, 0.0, hz0),
	]
	var tip_pts = [
		Vector3(-hx, span, -hz1), Vector3(hx, span, -hz1),
		Vector3(hx, span, hz1), Vector3(-hx, span, hz1),
	]
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(4):
		var a = root_pts[i]
		var b = root_pts[(i + 1) % 4]
		var c = tip_pts[(i + 1) % 4]
		var d = tip_pts[i]
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
	st.add_vertex(root_pts[0]); st.add_vertex(root_pts[2]); st.add_vertex(root_pts[1])
	st.add_vertex(root_pts[0]); st.add_vertex(root_pts[3]); st.add_vertex(root_pts[2])
	st.add_vertex(tip_pts[0]); st.add_vertex(tip_pts[1]); st.add_vertex(tip_pts[2])
	st.add_vertex(tip_pts[0]); st.add_vertex(tip_pts[2]); st.add_vertex(tip_pts[3])
	st.generate_normals()
	return st.commit()


static func _build_propeller(parent_node: Node3D, base_size: Vector3, base_color: Color, pusher: bool):
	# Flat 3-blade fan on a hub, forward-facing (tractor) by default -
	# pusher_prop passes pusher=true to flip which end the blades sit on,
	# the "visually distinct placement/orientation" the task asked for,
	# with zero extra mount-system code (purely which local Z the blades
	# and hub are authored toward).
	var facing = 1.0 if pusher else -1.0
	var hub = MeshInstance3D.new()
	var hub_cyl = CylinderMesh.new()
	hub_cyl.top_radius = base_size.x * 0.25
	hub_cyl.bottom_radius = base_size.x * 0.22
	hub_cyl.height = base_size.z * 0.5
	hub.mesh = hub_cyl
	var hub_mat = StandardMaterial3D.new()
	hub_mat.albedo_color = base_color.darkened(0.3)
	hub_mat.metallic = 0.7
	hub.material_override = hub_mat
	hub.rotation = Vector3(PI / 2.0, 0, 0)
	hub.position = Vector3(0, 0, facing * base_size.z * 0.3)
	parent_node.add_child(hub)

	var blade_mat = StandardMaterial3D.new()
	blade_mat.albedo_color = Color.SILVER
	var blade_mesh = _build_tapered_blade_mesh(0.03, 0.14, 0.045, base_size.x * 0.9)
	for i in range(3):
		var blade = MeshInstance3D.new()
		blade.mesh = blade_mesh
		blade.material_override = blade_mat
		blade.position = Vector3(0, 0, facing * base_size.z * 0.55)
		blade.rotate_z(i * (TAU / 3.0))
		parent_node.add_child(blade)


static func _build_paddle_wheel(parent_node: Node3D, base_size: Vector3, base_color: Color):
	# Steamship-style side paddle wheel: a disc whose face points sideways
	# (matching a side hull mount) with flat paddle blades radiating from
	# the rim - distinct from ship_screw's twisted blades or
	# naval_propeller's stern fan.
	var disc = MeshInstance3D.new()
	var disc_cyl = CylinderMesh.new()
	disc_cyl.top_radius = base_size.x * 0.45
	disc_cyl.bottom_radius = base_size.x * 0.45
	disc_cyl.height = base_size.y * 0.2
	disc.mesh = disc_cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = base_color.darkened(0.1)
	mat.metallic = 0.5
	mat.roughness = 0.6
	disc.material_override = mat
	disc.rotation = Vector3(0, 0, PI / 2.0)
	parent_node.add_child(disc)

	var paddle_mat = StandardMaterial3D.new()
	paddle_mat.albedo_color = base_color.darkened(0.35)
	for i in range(6):
		var paddle = MeshInstance3D.new()
		var paddle_box = BoxMesh.new()
		paddle_box.size = Vector3(base_size.y * 0.18, base_size.x * 0.35, base_size.z * 0.85)
		paddle.mesh = paddle_box
		paddle.material_override = paddle_mat
		paddle.rotation = Vector3(0, 0, PI / 2.0)
		paddle.rotate_x(i * (TAU / 6.0))
		parent_node.add_child(paddle)


static func _build_ship_screw(parent_node: Node3D, base_size: Vector3, base_color: Color):
	# Twisted (pitched) blade screw propeller - the real distinguishing
	# "screw" look vs. paddle_wheel's flat radial paddles or
	# naval_propeller's flat 3-blade fan.
	var hub = MeshInstance3D.new()
	var hub_cyl = CylinderMesh.new()
	hub_cyl.top_radius = base_size.x * 0.15
	hub_cyl.bottom_radius = base_size.x * 0.15
	hub_cyl.height = base_size.z * 0.7
	hub.mesh = hub_cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.metallic = 0.75
	mat.roughness = 0.3
	hub.material_override = mat
	hub.rotation = Vector3(PI / 2.0, 0, 0)
	parent_node.add_child(hub)

	var blade_mat = StandardMaterial3D.new()
	blade_mat.albedo_color = Color.SILVER
	var blade_mesh = _build_tapered_blade_mesh(0.025, base_size.x * 0.38, base_size.x * 0.12, base_size.x * 0.55)
	for i in range(4):
		var blade = MeshInstance3D.new()
		blade.mesh = blade_mesh
		blade.material_override = blade_mat
		blade.rotation.x = 0.5
		blade.rotate_z(i * (TAU / 4.0))
		parent_node.add_child(blade)


# MOUNTING_AND_ARMOR_SPEC.md #3: generic (not per-weapon-type-bespoke) mount
# hardware, added on top of whatever build_visual() already constructed for
# this type_id. Column-axis model (per Chris, 2026-07-19): the click point
# defines a column axis pointing from the click toward the hull's
# longitudinal centerline; the weapon sits at the OUTER end of that column.
# "turret" and "frame_built" add nothing extra - the tank cannon's existing
# enclosed-turret look is correct as-is, and a frame-built weapon's
# differentiation comes entirely from being built into the hull (no
# column, no extra geometry). For "pintle" (the new catch-all independent-
# traverse mount), the visual is a chunky post running along the column
# direction, with a base plate at the hull end and the weapon sitting at
# the far end. A column axis is treated as "vertical" if its dot with
# world-UP is larger than its dot with any horizontal axis - draws a
# standing post; otherwise draws a horizontal arm (same shape, rotated to
# match the column).
#
# column_dir (local to parent_node's space) is the column direction
# POINTING FROM THE HULL TOWARD THE WEAPON (i.e. away from the hull's
# centerline). column_dir is normalized; zero-length is treated as UP.
# column_length is the distance from the hull surface to the weapon.
static func add_mount_hardware(parent_node: Node3D, mount_style: String, base_size: Vector3, column_dir: Vector3 = Vector3.UP, column_length: float = 0.0):
	var old = parent_node.get_node_or_null("MountHardware")
	if old:
		parent_node.remove_child(old)
		old.free()

	if mount_style == "turret" or mount_style == "frame_built":
		return

	var n = column_dir.normalized() if column_dir.length() > 0.001 else Vector3.UP
	# A column axis counts as "vertical" when world-UP is the dominant
	# component (absolute Y is largest). Otherwise the column is treated
	# as horizontal/sideways, including the diagonal case (corner click)
	# where the column points diagonally through the hull - the post just
	# tilts to match.
	var is_vertical = abs(n.y) >= abs(n.x) and abs(n.y) >= abs(n.z)

	var hardware = Node3D.new()
	hardware.name = "MountHardware"
	parent_node.add_child(hardware)

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.12)

	# Effective post length: whatever column_length was provided, or fall
	# back to a sensible default based on the weapon's own size so a small
	# weapon on a tall column still reads as "mounted" without floating.
	var effective_length = column_length if column_length > 0.01 else max(base_size.y * 1.5, 0.6)

	if is_vertical:
		# Vertical post (top/bottom click): the chunky column lives at
		# the hull surface, with a base plate flush against whatever
		# local surface the click hit. The post extends upward (or
		# downward if n.y < 0) by effective_length. The weapon's own
		# origin is already at the far end of the column (set by
		# module_placer.gd's column-axis model) - the post just visually
		# spans the gap, not the weapon.
		var cyl = CylinderMesh.new()
		var radius = max(0.06, base_size.x * 0.22)
		cyl.top_radius = radius
		cyl.bottom_radius = radius * 1.15
		cyl.height = max(0.1, effective_length)
		var post = MeshInstance3D.new()
		post.mesh = cyl
		post.material_override = mat
		# Post spans from the hull surface to the weapon end. The weapon
		# itself sits at distance effective_length along n from the hull
		# surface; the post needs to span the SAME distance, with its
		# center at effective_length/2 along -n.
		post.position = -n * (effective_length * 0.5)
		# Quaternion(UP, n) rotates the post's default up-axis to n -
		# identity for n=UP (the original top-click case), 180 for
		# n=DOWN (inverted post for a bottom click), smoothly tilted
		# for any other vertical-leaning direction.
		post.transform.basis = Basis(Quaternion(Vector3.UP, n))
		hardware.add_child(post)

		# Base plate at the hull end (the END the weapon is NOT at).
		# Placed at -n * effective_length relative to the weapon.
		hardware.add_child(_build_pintle_base_plate(n, base_size, -n * effective_length))
	else:
		# Horizontal/diagonal arm (side or corner click): the column
		# axis lies mostly in the horizontal plane, so a single post
		# isn't visually right (it'd be lying flat against the hull).
		# Use a short bracket stub at the hull end, then a horizontal
		# beam reaching out along n to the weapon - same chunky
		# material as the vertical post, just oriented to the column.
		var cyl = CylinderMesh.new()
		var radius = max(0.05, base_size.x * 0.16)
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = max(0.1, effective_length)
		var arm = MeshInstance3D.new()
		arm.mesh = cyl
		arm.material_override = mat
		# Same position+rotation logic as the vertical post, just
		# driven by a horizontal n.
		arm.position = -n * (effective_length * 0.5)
		arm.transform.basis = Basis(Quaternion(Vector3.UP, n))
		hardware.add_child(arm)

		# Base plate at the hull end.
		hardware.add_child(_build_pintle_base_plate(n, base_size, -n * effective_length))

# A base plate that conforms to the actual local surface (flat for a
# top/bottom deck, tilted for a sloped glacis or similar), with a ring of
# bolt greebles and a raised center hub so it reads as a real mounting
# bracket rather than a bare disc.
#
# Design refinement from Chris: rather than trying to fit the plate flush
# against the local surface angle everywhere (a thin flush plate can show
# a visible gap at the rim if the real surface deviates from the assumed
# normal at all), the plate is a genuinely chunky disc/short-column whose
# BULK extends deep into the hull - any angle mismatch gets absorbed
# inside that intersection instead of showing as a gap, so the plate
# doesn't need to be geometrically perfect against every surface angle.
# The disc is built asymmetrically: its outer (visible) face stays right
# at the nominal flush position exactly as before, but it extends much
# further inward than its outer profile would suggest. The hub/bolt ring
# stay anchored to that same nominal surface position, so they still read
# as sitting on top of the mount, visible - only the disc's own body is
# deliberately over-buried.
static func _build_pintle_base_plate(local_normal: Vector3, base_size: Vector3, flush_position: Vector3) -> Node3D:
	var n = local_normal.normalized() if local_normal.length() > 0.001 else Vector3.UP
	# Small residual embed for the whole assembly - avoids a hairline
	# z-fighting seam even in the perfectly-flat/no-mismatch case.
	var embed_depth = max(0.02, base_size.y * 0.05)

	var plate_root = Node3D.new()
	plate_root.name = "BasePlate"
	# Quaternion(UP, n) is the shortest-arc rotation taking the plate's
	# default "face points up" orientation to point along the real
	# surface normal - identity when n IS up (the original flat-deck
	# case), smoothly tilted for anything angled. One formula covers both,
	# no separate "is this exactly flat" branch needed.
	plate_root.transform = Transform3D(Basis(Quaternion(Vector3.UP, n)), flush_position - n * embed_depth)

	var plate_radius = max(0.12, base_size.x * 0.42)
	var plate_thickness = max(0.08, base_size.y * 0.14)
	var plate_mat = StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.16, 0.16, 0.17)

	# Buried depth scales off the plate's own RADIUS, not hull size - the
	# radius is what actually determines how big a rim gap an angle
	# mismatch would create, so a wider plate needs proportionally deeper
	# burial to keep that gap hidden.
	var embed_extra = plate_radius * 0.35
	var disc = MeshInstance3D.new()
	var disc_cyl = CylinderMesh.new()
	disc_cyl.top_radius = plate_radius
	disc_cyl.bottom_radius = plate_radius
	disc_cyl.height = plate_thickness + embed_extra
	disc.mesh = disc_cyl
	disc.material_override = plate_mat
	# Shifted down by half the extra burial so the OUTER face stays at
	# the same y=+thickness/2 the hub/bolts already assume, while the
	# inner face reaches embed_extra deeper than before.
	disc.position = Vector3(0, -embed_extra * 0.5, 0)
	plate_root.add_child(disc)

	# Raised center hub - reads as the swivel bearing the post actually
	# turns in, not just a flat washer.
	var hub = MeshInstance3D.new()
	var hub_cyl = CylinderMesh.new()
	hub_cyl.top_radius = plate_radius * 0.38
	hub_cyl.bottom_radius = plate_radius * 0.44
	hub_cyl.height = plate_thickness * 1.6
	hub.mesh = hub_cyl
	hub.material_override = plate_mat
	hub.position = Vector3(0, plate_thickness * 0.55, 0)
	plate_root.add_child(hub)

	# Bolt ring around the rim - the actual "this is bolted to the hull"
	# greeble detail Chris asked for.
	var bolt_mat = StandardMaterial3D.new()
	bolt_mat.albedo_color = Color(0.24, 0.24, 0.26)
	var bolt_count = 6
	for i in range(bolt_count):
		var angle = i * TAU / bolt_count
		var bolt = MeshInstance3D.new()
		var bolt_cyl = CylinderMesh.new()
		bolt_cyl.top_radius = plate_radius * 0.09
		bolt_cyl.bottom_radius = plate_radius * 0.09
		bolt_cyl.height = plate_thickness * 1.8
		bolt.mesh = bolt_cyl
		bolt.material_override = bolt_mat
		bolt.position = Vector3(cos(angle) * plate_radius * 0.78, plate_thickness * 0.2, sin(angle) * plate_radius * 0.78)
		plate_root.add_child(bolt)

	return plate_root

static func rebuild_visual(module: Node3D):
	if not module or not module.has_meta("module_data"): return
	var data = module.get_meta("module_data")
	var catalog_data = preload("res://scripts/module_catalog.gd").get_module_data(data.type_id)
	if catalog_data:
		build_visual(data.type_id, module, catalog_data.size, catalog_data.color, data.tweaks)
		if module.has_meta("mount_style"):
			# column_dir is the new column-axis normal (points from the
			# hull surface toward the weapon). Legacy blueprints saved
			# under the old system may carry only "mount_normal" (the
			# surface normal the click hit) - that's the same vector in
			# the limit, and add_mount_hardware treats them identically
			# for the common "clicked on a flat facet" case. column_length
			# is the new field; legacy blueprints don't have it, the
			# default falls back to a sensible weapon-relative size.
			var col_dir = module.get_meta("column_dir", module.get_meta("mount_normal", Vector3.UP))
			var col_length = module.get_meta("column_length", 0.0)
			add_mount_hardware(module, module.get_meta("mount_style"), catalog_data.size, col_dir, col_length)

static func _apply_tweak_deformations(type_id: String, parent: Node3D, tweaks: Dictionary, base_size: Vector3):
	var children = parent.get_children().filter(func(c): return c is MeshInstance3D)
	if children.is_empty(): return

	match type_id:
		"basic_cannon":
			if children.size() > 1:
				var caliber = tweaks.get("caliber", 1.0)
				var length = tweaks.get("barrel_length", 1.0)
				children[1].scale = Vector3(caliber, length, caliber)
		"heavy_machine_gun":
			if children.size() > 2:
				var drum = tweaks.get("drum_size", 1.0)
				children[2].scale = Vector3(drum, drum, drum)
		"rotary_cannon":
			var motor = tweaks.get("motor_size", 1.0)
			children[0].scale = Vector3(motor, motor, motor)
			var cal = tweaks.get("caliber", 1.0)
			for i in range(1, children.size()):
				children[i].scale = Vector3(cal, 1.0, cal)
		"gauss_railgun":
			# When the authored "rail_array" mesh is present (it is - it ships
			# in assets/models/parts/), build_visual() adds exactly ONE child
			# (the combined assembly), not a separate base+rails like the
			# procedural fallback. The old "skip children[0], stretch the
			# rest" loop was a no-op whenever children.size() == 1, so this
			# tweak was silently dead in the actual running game.
			var rail_len = tweaks.get("rail_length", 1.0)
			if children.size() == 1:
				# Authored assembly: baseline scale.z already encodes
				# base_size.z via _fit_scale, so multiply, don't overwrite.
				children[0].scale.z *= rail_len
			else:
				for i in range(1, children.size()):
					children[i].scale.z = rail_len
		"cluster_dispenser":
			# Was entirely absent from this switch - the "Dispersion Matrix
			# Size" slider changed the stored value but affected nothing:
			# no visual, and (until module_data.gd's whitelist fix) no stat
			# either. Scale the dispenser body's footprint to at least give
			# it a visible, physically-sensible effect.
			var dispersion = tweaks.get("dispersion", 1.0)
			children[0].scale = Vector3(dispersion, 1.0, dispersion)
		"heavy_howitzer":
			if children.size() > 1:
				var elev = tweaks.get("elevation", 1.0)
				children[1].scale = Vector3(elev, elev, elev)
		"spigot_mortar":
			var rod_thick = tweaks.get("rod_thickness", 1.0)
			if children.size() > 1:
				children[1].scale = Vector3(rod_thick, 1.0, rod_thick)
			if children.size() > 2:
				children[2].scale = Vector3(rod_thick * 1.2, 1.0, rod_thick * 1.2)
		"guided_missile":
			if children.size() > 1:
				var engine = tweaks.get("engine_length", 1.0)
				var seeker = tweaks.get("seeker_size", 1.0)
				children[1].scale = Vector3(seeker, engine, seeker)
		"dual_stage_missile":
			if children.size() > 1:
				var payload = tweaks.get("payload_size", 1.0)
				children[1].scale = Vector3(payload, payload, payload)
		"flamethrower":
			var nozzle = tweaks.get("nozzle_width", 1.0)
			var valve = tweaks.get("pressure_valve", 1.0)
			if children.size() > 1:
				children[1].scale = Vector3(nozzle, 1.0, nozzle)
			if children.size() > 2:
				children[2].scale = Vector3(valve, valve, valve)
		"heavy_laser":
			var lens = tweaks.get("lens_aperture", 1.0)
			for i in range(1, children.size()):
				children[i].scale = Vector3(lens, 1.0, lens)
		"plasma_lobber":
			if children.size() > 1:
				var cont = tweaks.get("containment", 1.0)
				children[1].scale = Vector3(cont, cont, cont)
		"ciws":
			if children.size() > 2:
				var dish = tweaks.get("radar_dish", 1.0)
				children[2].scale = Vector3(dish, dish, dish)
		"pd_laser":
			if children.size() > 1:
				var cooling = tweaks.get("cooling_jacket", 1.0)
				children[1].scale = Vector3(cooling, cooling, cooling)
		"flak_cannon":
			if children.size() > 2:
				var fuse = tweaks.get("fuse_setting", 1.0)
				children[2].scale = Vector3(fuse, fuse, fuse)
		"resource_harvester":
			if children.size() > 1:
				var ext = tweaks.get("extractor_size", 1.0)
				children[1].scale = Vector3(ext, ext, ext)
		"sensor_suite":
			# children[0] = mast, children[1] = dish. The "mast_height" tweak
			# was scaling the dish's thickness instead of the mast's height -
			# the slider looked like it did something but the label was a lie.
			# Multiply (not overwrite) the existing scale, since build_visual()
			# already scaled the mast to base_size.y via _fit_scale before this
			# runs. Dish rides the mast top proportionally to mast_h.
			if children.size() > 0:
				var mast_h = tweaks.get("mast_height", 1.0)
				children[0].scale.y *= mast_h
				if children.size() > 1:
					children[1].position.y = base_size.y * mast_h
		"logistics_tank":
			if children.size() > 0:
				var cap = tweaks.get("tank_capacity", 1.0)
				children[0].scale = Vector3(cap, cap, cap)
