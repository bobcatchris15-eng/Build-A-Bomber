extends Node3D

const BlueprintManager = preload("res://scripts/blueprint_manager.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const TerrainBuilder = preload("res://scripts/terrain_builder.gd")
const ResourceFieldScript = preload("res://scripts/battle/economy/resource_field.gd")

@onready var vehicle_spawn_point = $VehicleSpawnPoint
@onready var camera = $Camera3D

var vehicle: CharacterBody3D
var vehicle_hull: Node3D
var target_dummies: Array[Node] = []
var target_destination: Vector3 = Vector3.ZERO
var locomotion_type: String = "wheels" # still used for the rotor-spin cosmetic

var current_map: Dictionary = {
	"name": "test_range",
	"map_half_extents": 100.0,
	"surface_zones": [
		{"type": "marsh", "center": Vector3(15, 0, -10), "half_extents": Vector2(5, 20)},
		{"type": "rocky", "center": Vector3(27, 0, -10), "half_extents": Vector2(5, 20)},
		{"type": "snow_mud", "center": Vector3(39, 0, -10), "half_extents": Vector2(5, 20)},
		{"type": "sand", "center": Vector3(51, 0, -10), "half_extents": Vector2(5, 20)},
		{"type": "gravel", "center": Vector3(63, 0, -10), "half_extents": Vector2(5, 20)},
		{"type": "forest", "center": Vector3(75, 0, -10), "half_extents": Vector2(5, 20)},
		{"type": "ice", "center": Vector3(87, 0, -10), "half_extents": Vector2(5, 20)}
	],
	"resource_nodes": [
		{"type": "metal", "amount": 1000, "position": Vector3(-15, 0, -10)},
		{"type": "crystal", "amount": 1000, "position": Vector3(-25, 0, -10)},
		{"type": "lumber", "amount": 1000, "position": Vector3(-35, 0, -10)},
		{"type": "oil", "amount": 1000, "position": Vector3(-45, 0, -10)}
	],
	"ground_color": Color(0.2, 0.26, 0.21)
}

var ground_nav_map: RID
var water_nav_map: RID
var amphibious_nav_map: RID
var deep_water_nav_map: RID
var _ground_nav_regions: Array = []
var _amphibious_nav_regions: Array = []
var _nav_tile_rects: Array = []
var _water_nav_region: RID
var _deep_water_nav_region: RID

func _ready():
	_setup_terrain()
	_spawn_resources()
	_spawn_vehicle()
	_spawn_target_dummies()
	
	# Connect & Style UI buttons
	var return_btn = get_node_or_null("UI/ReturnButton") as Button
	if return_btn:
		return_btn.text = "RETURN TO DESIGN LAB"
		# Theme BAKELITE, no override. This was the same "plastic sprue gate"
		# treatment stat_calculator.gd carried - a hand-built fill with a saturated
		# 6px left border and a matching font colour - and the Test Range had its own
		# green/amber pair of it, drifted from the Design Lab's green/amber pair for
		# the same kinds of action. Neither of these two is destructive or primary:
		# going back to the Lab and resetting the dummies are both plain navigation.
		return_btn.pressed.connect(_on_return_pressed)
		
	var reset_dummies_btn = get_node_or_null("UI/ResetDummiesButton") as Button
	if reset_dummies_btn:
		reset_dummies_btn.text = "RESET TARGET DUMMIES"
		reset_dummies_btn.pressed.connect(_on_reset_dummies_pressed)

	# Instantiate live tuning overlay
	var tuning_panel_script = load("res://scripts/debug_tuning_panel.gd")
	if tuning_panel_script and OS.is_debug_build():
		var tuning_panel = Control.new()
		tuning_panel.set_script(tuning_panel_script)
		tuning_panel.name = "DebugTuningPanel"
		add_child(tuning_panel)

func _spawn_vehicle():
	# Test Range's vehicle now runs the EXACT same battle_unit.gd script
	# Skirmish units do (Chris's explicit ask: "the behavior of the unit
	# there should match the behavior in the battle" - positioning to bring
	# the strongest facet's weapons to bear, whole-vehicle-aim for
	# frame_built weapons, kiting, and the auto-engage-on-sight added this
	# pass). player_vehicle.gd was a hand-rolled parallel implementation
	# with none of that AI - a player-driven vehicle could walk right past
	# a dummy shooting at it with no attempt to maneuver, which never
	# happens in a real match. setup() already does everything this
	# function used to do by hand (hull reconstruction, HP, collision
	# shape, weapons, move speed, energy, vision, nav, HP bar) - single
	# source of truth, can't drift from Skirmish again.
	vehicle = CharacterBody3D.new()
	vehicle.name = "PlayerVehicle"
	vehicle.set_script(load("res://scripts/battle_unit.gd"))
	add_child(vehicle)
	vehicle.add_to_group("player_vehicle") # target_dummy.gd's missile-at-player targeting looks for this

	# Instantiate a temporary BlueprintManager instance to access helpers
	var bp_manager = BlueprintManager.new()
	add_child(bp_manager)

	var blueprint_data = bp_manager.load_blueprint("user://blueprint.json")
	if blueprint_data.is_empty():
		blueprint_data = {
			"version": 1.0,
			"hull_type": "medium_hull",
			"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
			"modules": []
		}

	var locomotion = blueprint_data.get("locomotion", {})
	locomotion_type = locomotion.get("type_id", "wheels") # still used for the rotor-spin cosmetic below

	vehicle.setup(blueprint_data, 0, bp_manager)
	remove_child(bp_manager) # Clean up
	bp_manager.queue_free()

	vehicle_hull = vehicle.hull_node
	if not vehicle_hull:
		return

	# Spawn ground vehicles slightly above the floor so they drop down
	# safely without clipping; flying units start at their real cruise
	# altitude (setup() already set target_altitude via the trait system).
	var spawn_pos = vehicle_spawn_point.global_position
	spawn_pos.y += vehicle.target_altitude if vehicle.is_flying else 1.0
	vehicle.global_position = spawn_pos

	vehicle.died.connect(_on_vehicle_died)

	# Dynamic creation of Player HP Label in Battlefield UI
	var ui_node = get_node_or_null("UI")
	if ui_node:
		var hp_label = Label.new()
		hp_label.name = "PlayerHPLabel"
		hp_label.position = Vector2(20, 20)
		hp_label.theme_type_variation = "HUDValueLabel"
		ui_node.add_child(hp_label)
		update_player_hp_ui()

func _on_vehicle_died(_unit):
	# Same "restart battle scene after a short delay" UX player_vehicle.gd's
	# die() used to own directly - battle_unit.gd's die() is Skirmish-
	# generic (just frees the unit + emits the signal), so Test Range's
	# own scene-reload behavior lives here instead.
	get_tree().create_timer(2.0).timeout.connect(func():
		get_tree().reload_current_scene()
	)

func _spawn_target_dummies():
	# Clear old dummies
	for dummy in target_dummies:
		if is_instance_valid(dummy):
			dummy.queue_free()
	target_dummies.clear()
	
	var points = [
		Vector3(-5, 1.0, -15),
		Vector3(5, 1.0, -15),
		Vector3(15, 1.0, -15)
	]
	
	var bp_manager = BlueprintManager.new()
	add_child(bp_manager)
	
	var bps = ["res://data/loadout/bulwark_mbt.json", "res://data/loadout/rattler_scout.json", "res://data/loadout/wasp_rocket_buggy.json"]
	
	for i in range(points.size()):
		var pos = points[i]
		var dummy_unit = CharacterBody3D.new()
		dummy_unit.name = "EnemyTarget"
		dummy_unit.set_script(load("res://scripts/battle_unit.gd"))
		add_child(dummy_unit)
		
		var dummy_bp = bp_manager.load_blueprint(bps[i])
		dummy_unit.setup(dummy_bp, 1, bp_manager, "technocrats")
		dummy_unit.add_to_group("targets") # auto_weapon.gd's targeting scan requires this group

		# Set height above ground
		var spawn_pos = pos
		spawn_pos.y = terrain_height_at(pos)
		spawn_pos.y += dummy_unit.target_altitude if dummy_unit.is_flying else 1.0
		dummy_unit.global_position = spawn_pos
		
		target_dummies.append(dummy_unit)
		
		dummy_unit.set_meta("pace_timer", 0.0)
		dummy_unit.set_meta("pace_dir", 1.0)
		dummy_unit.set_meta("start_x", pos.x)
		
	bp_manager.queue_free()

func _spawn_resources():
	for entry in current_map.get("resource_nodes", []):
		var field := Node3D.new()
		field.set_script(ResourceFieldScript)
		add_child(field)
		var pos: Vector3 = entry.get("position", Vector3.ZERO)
		field.global_position = Vector3(pos.x, terrain_height_at(pos), pos.z)
		field.setup(entry.get("type", "metal"), entry.get("amount", 1000), self)

func get_ground_nav_map() -> RID:
	return ground_nav_map

func get_water_nav_map() -> RID:
	return water_nav_map

func get_amphibious_nav_map() -> RID:
	return amphibious_nav_map

func get_deep_water_nav_map() -> RID:
	return deep_water_nav_map

func terrain_height_at(pos: Vector3) -> float:
	return TerrainBuilder.height_at(current_map, pos.x, pos.z)

func get_surface_type_at(pos: Vector3) -> String:
	return TerrainBuilder.get_surface_type_at(current_map, pos)

func _setup_terrain():
	var holes = []
	var nav = TerrainBuilder.build_navmeshes(current_map, holes)
	ground_nav_map = nav.ground_map
	water_nav_map = nav.water_map
	amphibious_nav_map = nav.amphibious_map
	deep_water_nav_map = nav.deep_water_map
	_ground_nav_regions = nav.ground_regions
	_amphibious_nav_regions = nav.amphibious_regions
	_nav_tile_rects = nav.tile_rects
	_water_nav_region = nav.water_region
	_deep_water_nav_region = nav.deep_water_region
	
	var ground = get_node_or_null("Ground")
	if ground:
		ground.position = Vector3.ZERO
		var generated = TerrainBuilder.build_ground_visual_mesh(current_map)
		var mesh_inst = ground.get_node_or_null("MeshInstance3D")
		if mesh_inst:
			mesh_inst.mesh = generated.mesh
			mesh_inst.material_override = TerrainBuilder.build_ground_material_heightmap(current_map.get("ground_color", Color(0.2, 0.26, 0.21)))
		var col = ground.get_node_or_null("CollisionShape3D")
		if col:
			col.shape = generated.shape
			col.scale = generated.get("collision_scale", Vector3.ONE)
	
	TerrainBuilder.spawn_visuals(current_map, self)

func _exit_tree() -> void:
	for rid in _ground_nav_regions + _amphibious_nav_regions + [
			_water_nav_region, _deep_water_nav_region,
			ground_nav_map, water_nav_map, amphibious_nav_map, deep_water_nav_map]:
		if rid.is_valid():
			NavigationServer3D.free_rid(rid)

func _unhandled_input(event):
	# Click to move vehicle (Right click or Left click on ground)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT or (event.button_index == MOUSE_BUTTON_LEFT and not event.shift_pressed):
			var space_state = get_world_3d().direct_space_state
			var mouse_pos = event.position
			var ray_origin = camera.project_ray_origin(mouse_pos)
			var ray_end = ray_origin + camera.project_ray_normal(mouse_pos) * 1000.0
			
			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
			query.collision_mask = 1 # Ground layer
			var result = space_state.intersect_ray(query)
			
			if result:
				target_destination = result.position
				if is_instance_valid(vehicle):
					vehicle.order_move(target_destination)

				# Spawn a brief destination marker
				_create_move_marker(target_destination)

func _create_move_marker(pos: Vector3):
	var marker = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	marker.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.GREEN
	mat.emission_enabled = true
	mat.emission = Color.GREEN
	marker.material_override = mat
	add_child(marker)
	marker.global_position = pos
	
	var timer = get_tree().create_timer(0.5)
	timer.timeout.connect(func(): marker.queue_free())

func _physics_process(delta):
	# Movement, gravity/altitude, energy regen, and order-based combat
	# maneuvering (approach/flank/kite/whole-vehicle-aim/auto-engage) are
	# all owned by vehicle's own battle_unit.gd script now - it runs its
	# own _physics_process (Godot calls it automatically, no manual
	# invocation needed here) and already does everything the block that
	# used to live here did by hand, plus the combat AI it never had.
	
	# Pace target dummies
	for dummy in target_dummies:
		if is_instance_valid(dummy):
			var t = dummy.get_meta("pace_timer", 0.0)
			t += delta
			if t > 4.0:
				var dir = dummy.get_meta("pace_dir", 1.0) * -1.0
				dummy.set_meta("pace_dir", dir)
				var start_x = dummy.get_meta("start_x", dummy.global_position.x)
				dummy.order_move(Vector3(start_x + dir * 6.0, dummy.global_position.y, dummy.global_position.z))
				dummy.set_meta("pace_timer", 0.0)
			else:
				dummy.set_meta("pace_timer", t)

	if not is_instance_valid(vehicle):
		return

	update_player_hp_ui()

	# Spin helicopter rotors if present. Previously grabbed get_child(0),
	# which is whichever mount/strut mesh happens to be built first (not the
	# blades) - same stale-lookup bug battle_unit.gd had until 702e2dc fixed
	# it there by name instead; this path never got that fix, so Test Range
	# rotors silently spun the wrong (static-looking) piece instead of the
	# actual blade ring.
	if is_instance_valid(vehicle_hull):
		for child in vehicle_hull.get_children():
			if child.has_meta("module_data"):
				var data = child.get_meta("module_data")
				if data.type_id == "helicopter_rotors":
					var rotor = child.get_node_or_null("RotorBlades")
					if rotor:
						rotor.rotate_y(15.0 * delta)
				elif data.type_id == "hover_engine":
					var mid_ring = child.get_node_or_null("HoverRingMid")
					if mid_ring:
						mid_ring.rotate_x(12.0 * delta)
					var inner_ring = child.get_node_or_null("HoverRingInner")
					if inner_ring:
						inner_ring.rotate_y(18.0 * delta)
						# See battle_unit.gd's matching comment - the inner
						# ring tumbles on two axes, not one.
						inner_ring.rotate_z(7.0 * delta)
				elif data.type_id == "legs":
					# Shared with battle_unit.gd rather than copied. This block
					# used to be its own second implementation, and the copy had
					# already drifted: it snapped straight to 0 when parked
					# instead of settling, and ignored speed entirely, so a
					# walker crossing the Test Range strode at exactly the same
					# cadence whether it was crawling or flat out. That is the
					# same class of drift that left the rotors here spinning the
					# wrong node - see the comment further up.
					var rate: float = clampf(vehicle.velocity.length() / 6.0, 0.0, 1.0)
					VisualBuilder.pose_leg(child, Time.get_ticks_msec() / 1000.0,
						child.get_meta("leg_phase", 0.0), rate, delta)

	# Update Camera to follow vehicle
	var target_cam_pos = vehicle.global_position + Vector3(0, 12, 12)
	camera.global_position = camera.global_position.lerp(target_cam_pos, 5.0 * delta)
	camera.look_at(vehicle.global_position + Vector3(0, 0.5, 0), Vector3.UP)

# terrain_height_at is now handled by TerrainBuilder.

func _on_return_pressed():
	var router = get_node_or_null("/root/SceneRouter")
	if router:
		router.goto("res://scenes/MainLab.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainLab.tscn")

func _on_reset_dummies_pressed():
	_spawn_target_dummies()

func update_player_hp_ui():
	var hp_label = get_node_or_null("UI/PlayerHPLabel") as Label
	if hp_label and is_instance_valid(vehicle):
		var hp_pct = clamp(vehicle.hp / vehicle.max_hp, 0.0, 1.0)
		var bar_length = 15
		var filled = int(hp_pct * bar_length)
		var bar_str = ""
		for i in range(filled):
			bar_str += "■"
		for i in range(bar_length - filled):
			bar_str += "□"
			
		var faction_str = FactionCatalog.get_faction_name(FactionCatalog.DEFAULT_FACTION)
		if is_instance_valid(vehicle_hull) and vehicle_hull.has_meta("faction"):
			faction_str = FactionCatalog.get_faction_name(vehicle_hull.get_meta("faction"))
			
		hp_label.text = "Player HP: %d/%d [%s] (%s)" % [int(vehicle.hp), int(vehicle.max_hp), bar_str, faction_str]
		# GO -> ALERT across the health range, rather than Color.GREEN -> Color.RED.
		# The raw engine constants are fully-saturated primaries that appear nowhere
		# in ui_tokens.gd; the signal pair means the same thing here as it does on
		# the power bar and the game-over card. Set as a font colour, not modulate,
		# which tints children too.
		hp_label.add_theme_color_override("font_color",
			Tokens.SIGNAL_GO.lerp(Tokens.SIGNAL_ALERT, 1.0 - hp_pct))
