extends Node3D

const BlueprintManager = preload("res://scripts/blueprint_manager.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")

@onready var vehicle_spawn_point = $VehicleSpawnPoint
@onready var camera = $Camera3D

var vehicle: CharacterBody3D
var vehicle_hull: Node3D
var target_dummies: Array[Node] = []
var target_destination: Vector3 = Vector3.ZERO
var locomotion_type: String = "wheels" # still used for the rotor-spin cosmetic

func _ready():
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
		Vector3(-10, 0.5, -10),
		Vector3(10, 0.5, -15),
		Vector3(0, 0.5, -20),
		Vector3(-15, 0.5, -5),
		Vector3(15, 0.5, -5)
	]
	
	for pos in points:
		var dummy_scene = load("res://scenes/TargetDummy.tscn")
		if dummy_scene:
			var dummy = dummy_scene.instantiate()
			add_child(dummy)
			dummy.global_position = pos
			target_dummies.append(dummy)

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

## The arena floor's height, for battle_unit.gd's ground snap.
##
## Duck-typed exactly like skirmish.gd's terrain_height_at() - battle_unit.gd
## checks `get_parent().has_method("terrain_height_at")` and, finding nothing
## here, fell through to its gravity + is_on_floor() fallback instead. That
## fallback rests the unit on whatever collider it has, and the only collider a
## ground unit has is the one around its HULL - so the hull came to rest on the
## floor with the wheels/legs/treads buried underneath it. That is the "the
## locomotors fall through the ground in the test arena, leaving the vehicles
## sliding around on their belly" report (Chris, 2026-08-03): Skirmish never
## showed it because Skirmish DOES implement this method, so it used the
## analytic snap and put the unit's origin - i.e. its ground contact point - on
## the ground where it belongs.
##
## Constant because this arena is one flat slab, not a heightmap: the Ground
## StaticBody3D is a 100x1x100 box centred at y=-0.5, so its top face is y=0.
## Read from the node rather than hardcoded, so moving the slab in the scene
## cannot silently desync the two.
const ARENA_FLOOR_Y := 0.0

func terrain_height_at(_pos: Vector3) -> float:
	var ground := get_node_or_null("Ground") as Node3D
	if ground == null:
		return ARENA_FLOOR_Y
	var shape := ground.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape == null or not (shape.shape is BoxShape3D):
		return ARENA_FLOOR_Y
	return ground.global_position.y + shape.position.y + (shape.shape as BoxShape3D).size.y * 0.5

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
