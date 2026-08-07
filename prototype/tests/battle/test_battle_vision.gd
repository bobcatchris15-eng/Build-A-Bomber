extends "res://tests/suite_base.gd"
# Phase 4: what each team can see, and the shroud drawn over what it cannot.
#
# A FOG THAT REVEALS EVERYTHING PASSES EVERY NAIVE TEST. "Can team 0 see this
# thing 10 m away" is true both when the fog works and when it is broken open, so
# every check here that asserts something IS visible is paired with one asserting
# something is NOT. That pairing is the only thing separating a working fog from
# a disabled one, and the fail-open default below makes it easy to disable by
# accident.

const VisionServiceScript = preload("res://scripts/battle/vision/vision_service.gd")
const BattleHUDScript = preload("res://scripts/battle/hud/battle_hud.gd")
const BattleLayersScript = preload("res://scripts/battle/battle_layers.gd")
const SmokeVolumeScript = preload("res://scripts/smoke_volume.gd")
const StructureScript = preload("res://scripts/battle/buildings/structure.gd")

# Deliberately NOT 0 and 1. The `damageable` group is tree-wide and other suites
# leave constructs in it; scanning picks those up as extra observers on whatever
# team they carried. A leftover team-1 unit with real vision is enough to make
# "a blind team cannot see" fail, which is a cross-suite dependency reported as a
# vision bug. No other suite uses these numbers.
const TEAM_A := 7
const TEAM_B := 8


# A construct with just enough surface for the vision scan: a team meta, a
# position, a vision range, and the flag the scan writes back.
class FakeConstruct extends Node3D:
	var vision_range: float = 0.0
	var is_dead: bool = false
	var is_flying: bool = false
	var fog_hidden: bool = false
	var faction: String = "industrialists"
	var hull_node: Node3D = null
	func set_fog_visible(value: bool) -> void:
		fog_hidden = not value


# The vision service takes a Node controller (it needs get_world_3d() for the LOS
# ray and get_tree() to find constructs). A suite extends RefCounted and is not a
# Node, so `self` cannot be it - this is the stand-in.
var _stub: Node3D = null
var _spawned: Array = []


func _controller() -> Node3D:
	if _stub == null or not is_instance_valid(_stub):
		_stub = Node3D.new()
		root.add_child(_stub)
	return _stub


func _construct(team: int, at: Vector3, vision: float = 0.0) -> FakeConstruct:
	var c := FakeConstruct.new()
	c.set_meta("team", team)
	c.vision_range = vision
	root.add_child(c)
	c.global_position = at
	c.add_to_group("damageable")
	_spawned.append(c)
	return c


# The `damageable` group is global to the tree, so anything left behind here is
# picked up by the NEXT test's scan as an extra observer or target - which is a
# cross-test dependency that shows up as an inexplicable visibility result three
# suites later. Every test tears down what it made.
func _cleanup() -> void:
	for c in _spawned:
		if is_instance_valid(c):
			c.free()
	_spawned.clear()
	if is_instance_valid(_stub):
		_stub.free()
	_stub = null


# --- The layer bug this phase found ------------------------------------------

# SELECTION shared bit 5 with smoke_volume.gd's SMOKE_COLLISION_LAYER. The vision
# LOS ray masks terrain + smoke and opts into areas, so it hit every unit's own
# selection proxy and NOTHING was ever visible to anyone - which reads as "vision
# range is too small", not as a layer collision. A drag-select would also have
# returned smoke clouds as units. Pinned because the collision was invisible from
# either side alone.
func test_selection_layer_does_not_collide_with_smoke() -> bool:
	print("Running Test Suite: Layers - selection and smoke must not share a bit...")
	_cleanup()
	if BattleLayersScript.SELECTION & SmokeVolumeScript.SMOKE_COLLISION_LAYER != 0:
		print("  [FAIL] SELECTION (%d) overlaps SMOKE_COLLISION_LAYER (%d)"
			% [BattleLayersScript.SELECTION, SmokeVolumeScript.SMOKE_COLLISION_LAYER])
		return false

	# And it must not collide with anything else already spoken for either.
	var taken := {
		"TERRAIN": BattleLayersScript.TERRAIN,
		"MODULES": BattleLayersScript.MODULES,
		"UNITS": BattleLayersScript.UNITS,
		"BUILDINGS": BattleLayersScript.BUILDINGS,
		"RESOURCE_NODES": BattleLayersScript.RESOURCE_NODES,
		"SMOKE": SmokeVolumeScript.SMOKE_COLLISION_LAYER,
	}
	for name in taken:
		if BattleLayersScript.SELECTION & taken[name] != 0:
			print("  [FAIL] SELECTION overlaps %s" % name)
			return false
	print("  [PASS] selection layer is exclusive")
	return true


# --- Visibility --------------------------------------------------------------

func test_vision_hides_the_distant_and_reveals_the_near() -> bool:
	print("Running Test Suite: Vision - per-team sets actually hide things...")
	_cleanup()
	var vision = VisionServiceScript.new()
	vision.setup(_controller(), TEAM_A, 80.0)

	var scout := _construct(TEAM_A, Vector3.ZERO, 40.0)
	var near := _construct(TEAM_B, Vector3(0, 0, 10.0))
	var far := _construct(TEAM_B, Vector3(0, 0, 300.0))
	vision.tick()

	if not vision.is_visible_to_team(near, TEAM_A):
		print("  [FAIL] a hostile 10 m from a 40 m scout is not visible")
		return false
	# The half that matters. Without this the test passes on a fog that is simply
	# switched off.
	if vision.is_visible_to_team(far, TEAM_A):
		print("  [FAIL] a hostile 300 m away is visible - the fog reveals everything")
		return false
	if not far.fog_hidden:
		print("  [FAIL] fog_hidden was not written onto the unseen construct")
		return false
	if near.fog_hidden:
		print("  [FAIL] fog_hidden was set on a construct that IS seen")
		return false

	# Allies are always mutually visible regardless of range - vision gates what
	# you know about the ENEMY, not where your own units are.
	if not vision.is_visible_to_team(scout, TEAM_A):
		print("  [FAIL] a team cannot see its own unit")
		return false

	# Asymmetry: team 1's constructs have no vision at all here, so team 1 must
	# NOT see the scout. A single shared fog_hidden flag could not express this,
	# which is why visibility is stored per team.
	if vision.is_visible_to_team(scout, TEAM_B):
		print("  [FAIL] a blind team can see - visibility is not per-team")
		return false
	print("  [PASS] per-team visibility")
	return true


# BUILDINGS HAVE TO SEE, and they did not.
#
# VisionService reads `vision_range` off anything in the `damageable` group and
# defaults to 0.0 for whatever does not declare one - a deliberately quiet
# default, since not everything damageable is an observer. Structure never
# declared one, so a base counted as a thing to BE seen and never as a thing that
# sees, and fog sat over the player's own buildings.
#
# Asserted through the real Structure rather than a stub construct, because the
# defect was precisely that the real one was missing a property the stub would
# have been given.
func test_buildings_lift_fog_around_a_base() -> bool:
	print("Running Test Suite: Vision - buildings light their own ground...")
	_cleanup()
	var vision = VisionServiceScript.new()
	vision.setup(_controller(), TEAM_A, 80.0)

	var hq := StructureScript.new()
	root.add_child(hq)
	hq.setup("hq", TEAM_A)
	hq.global_position = Vector3.ZERO

	if hq.vision_range <= 0.0:
		print("  [FAIL] an HQ declares no vision range at all: %f" % hq.vision_range)
		return false

	# A hostile well inside the HQ's reach, with no friendly UNIT anywhere - so
	# the only thing that can possibly be spotting it is the building.
	var near := _construct(TEAM_B, Vector3(0, 0, hq.vision_range * 0.5))
	var far := _construct(TEAM_B, Vector3(0, 0, hq.vision_range * 6.0))
	vision.tick()

	if not vision.is_visible_to_team(near, TEAM_A):
		print("  [FAIL] a hostile %.1f m from the HQ is not visible - buildings lift no fog"
			% (hq.vision_range * 0.5))
		return false
	# The other half, or this passes against a fog that is simply off.
	if vision.is_visible_to_team(far, TEAM_A):
		print("  [FAIL] a hostile far outside the HQ's reach is visible")
		return false

	# A power plant should not out-see the command building it is parked beside.
	var plant := StructureScript.new()
	root.add_child(plant)
	plant.setup("power_plant", TEAM_A)
	if plant.vision_range >= hq.vision_range:
		print("  [FAIL] a power plant (%.1f) sees as far as the HQ (%.1f)"
			% [plant.vision_range, hq.vision_range])
		return false
	print("  [PASS] HQ sees %.1f m, power plant %.1f m" % [hq.vision_range, plant.vision_range])
	return true


# Fails open before the first scan, deliberately. A closed default stops every
# weapon in the game from firing until the first fog tick lands, which is a far
# louder failure than one tick of over-sharing.
func test_visibility_fails_open_before_the_first_scan() -> bool:
	print("Running Test Suite: Vision - unscanned fails open, not closed...")
	_cleanup()
	var vision = VisionServiceScript.new()
	vision.setup(_controller(), TEAM_A, 80.0)
	var enemy := _construct(TEAM_B, Vector3(0, 0, 500.0))
	if not vision.is_visible_to_team(enemy, TEAM_A):
		print("  [FAIL] visibility failed CLOSED before any scan - weapons would never fire")
		return false
	# A freed or null construct is never visible, scan or no scan.
	if vision.is_visible_to_team(null, TEAM_A):
		print("  [FAIL] null reported as visible")
		return false
	print("  [PASS] fail-open default")
	return true


# Reveal happens at plain range; something already visible only drops out past a
# WIDER one. Without the gap a construct sitting exactly on the boundary flickers
# in and out every tick as millimetre position deltas cross a single threshold.
func test_reveal_hide_hysteresis_has_a_dead_zone() -> bool:
	print("Running Test Suite: Vision - reveal/hide hysteresis dead zone...")
	_cleanup()
	if VisionServiceScript.HIDE_RANGE_MULT <= 1.0:
		print("  [FAIL] HIDE_RANGE_MULT is %.2f - no dead zone, so boundary flicker returns"
			% VisionServiceScript.HIDE_RANGE_MULT)
		return false

	var vision = VisionServiceScript.new()
	vision.setup(_controller(), TEAM_A, 200.0)
	var scout := _construct(TEAM_A, Vector3.ZERO, 40.0)
	# Inside the dead zone: past plain vision range, but within the hide radius.
	var edge := _construct(TEAM_B, Vector3(0, 0, 44.0))

	# Not yet seen, and beyond plain range, so it must NOT be revealed.
	vision.tick()
	if vision.is_visible_to_team(edge, TEAM_A):
		print("  [FAIL] something past vision range was revealed on first sight")
		return false

	# Walk it inside, get it seen, then back out into the dead zone. It must STAY
	# seen - that is the whole point of the second threshold.
	edge.global_position = Vector3(0, 0, 30.0)
	vision.tick()
	if not vision.is_visible_to_team(edge, TEAM_A):
		print("  [FAIL] a construct well inside vision range was not revealed")
		return false
	edge.global_position = Vector3(0, 0, 44.0)
	vision.tick()
	if not vision.is_visible_to_team(edge, TEAM_A):
		print("  [FAIL] an already-seen construct dropped out inside the dead zone")
		return false

	# Past the hide radius it must finally drop.
	edge.global_position = Vector3(0, 0, 40.0 * VisionServiceScript.HIDE_RANGE_MULT + 5.0)
	vision.tick()
	if vision.is_visible_to_team(edge, TEAM_A):
		print("  [FAIL] a construct past the hide radius stayed visible")
		return false
	print("  [PASS] hysteresis dead zone")
	return true


# A flare is a stationary observer owned by the team that fired it, and
# deliberately needs no line of sight - lighting an area from above is the entire
# reason you fire one over a ridge.
func test_reveal_beacons_light_an_area_and_expire() -> bool:
	print("Running Test Suite: Vision - illumination beacons...")
	_cleanup()
	var vision = VisionServiceScript.new()
	vision.setup(_controller(), TEAM_A, 200.0)
	# TEAM_A needs a construct that EXISTS but cannot see - vision_range 0 - not no
	# construct at all. A team with nothing on the field is never a viewing team,
	# so it never gets scanned, and is_visible_to_team correctly falls open for it.
	# Testing against an absent team would be testing the fail-open default rather
	# than the beacon.
	var blind := _construct(TEAM_A, Vector3.ZERO, 0.0)
	var hidden := _construct(TEAM_B, Vector3(0, 0, 120.0))
	vision.tick()
	if vision.is_visible_to_team(hidden, TEAM_A):
		print("  [FAIL] a construct 120 m from a blind observer is visible")
		return false

	vision.reveal_area(TEAM_A, hidden.global_position, 30.0, 60.0)
	vision.tick()
	if not vision.is_visible_to_team(hidden, TEAM_A):
		print("  [FAIL] a beacon over a construct did not reveal it")
		return false

	# The beacon belongs to the team that FIRED it. TEAM_B sits inside the lit
	# circle and gains nothing from TEAM_A's flare - a shared beacon would hand
	# both sides the same intelligence and make scouting pointless.
	# Inside the lit circle but NOT on top of `hidden`. Sharing a position makes
	# the distance zero, which any observer trivially satisfies - the assertion
	# would then be about coincident nodes rather than about who owns the flare.
	var lit_enemy := _construct(TEAM_A, Vector3(6.0, 0, 120.0), 0.0)
	# Out of radius is not lit, for the team that DID fire it.
	var outside := _construct(TEAM_B, Vector3(0, 0, 200.0))
	vision.tick()
	if vision.is_visible_to_team(lit_enemy, TEAM_B):
		print("  [FAIL] a beacon revealed for the team that did not fire it")
		return false
	if vision.is_visible_to_team(outside, TEAM_A):
		print("  [FAIL] a construct outside the beacon radius was revealed")
		return false
	print("  [PASS] reveal beacons")
	return true


# Higher ground sees further, capped, and flying units are excluded - they are
# already up, and stacking altitude on altitude double-counts one advantage.
func test_effective_vision_elevation_bonus_is_capped_and_skips_flyers() -> bool:
	print("Running Test Suite: Vision - elevation bonus, cap, flyer exemption...")
	_cleanup()
	var vision = VisionServiceScript.new()
	# No controller, so terrain_height_at is unavailable and elevation reads zero -
	# which must degrade to plain vision rather than crashing.
	vision.setup(null, TEAM_A, 80.0)
	var ground := _construct(TEAM_A, Vector3.ZERO, 50.0)
	if not is_equal_approx(vision.effective_vision(ground), 50.0):
		print("  [FAIL] with no controller vision should be unmodified, got ",
			vision.effective_vision(ground))
		return false

	var flyer := _construct(TEAM_A, Vector3.ZERO, 50.0)
	flyer.is_flying = true
	if not is_equal_approx(vision.effective_vision(flyer), 50.0):
		print("  [FAIL] a flyer should get no elevation bonus")
		return false

	# The cap has to actually bind, or a tall enough map makes one unit omniscient.
	var capped: float = 1.0 + VisionServiceScript.ELEVATION_CAP \
		* VisionServiceScript.ELEVATION_BONUS_PER_UNIT
	if capped > 2.0:
		print("  [FAIL] the elevation cap allows more than a 2x vision multiplier (%.2fx)" % capped)
		return false
	print("  [PASS] elevation bonus (max %.2fx)" % capped)
	return true


# --- Minimap -----------------------------------------------------------------

# The minimap is a real Image specifically so this assertion can exist: headless
# never rasterizes a SubViewport, so a render-to-texture minimap would be
# untestable. Reading a pixel back is the payoff for that decision.
func test_minimap_bakes_terrain_and_draws_blips() -> bool:
	print("Running Test Suite: HUD - minimap pixel readback...")
	_cleanup()
	var hud = BattleHUDScript.new()
	root.add_child(hud)
	var map: Dictionary = MapCatalog.get_map(MapCatalog.DEFAULT_MAP_ID)
	hud.setup(_controller(), TEAM_A, map)

	var image: Image = hud.minimap_image()
	if image == null or image.get_width() <= 0:
		print("  [FAIL] the minimap produced no image")
		hud.queue_free()
		return false

	# The static bake must not be a flat fill - a single-colour minimap is
	# indistinguishable from a broken one at a glance.
	var first: Color = image.get_pixel(0, 0)
	var varied := false
	for x in range(image.get_width()):
		for y in range(image.get_height()):
			if not image.get_pixel(x, y).is_equal_approx(first):
				varied = true
				break
		if varied:
			break
	if not varied:
		print("  [FAIL] the baked terrain is a single flat colour")
		hud.queue_free()
		return false

	# Cell mapping must be bounded for anything, including well off-map, or a
	# stray unit writes outside the image.
	for probe in [Vector2(0, 0), Vector2(9999, 9999), Vector2(-9999, -9999)]:
		var cell: Vector2i = hud.world_to_cell(probe.x, probe.y)
		if cell.x < 0 or cell.x >= image.get_width() \
				or cell.y < 0 or cell.y >= image.get_height():
			print("  [FAIL] world_to_cell(%s) escaped the image: %s" % [str(probe), str(cell)])
			hud.queue_free()
			return false
	hud.queue_free()
	print("  [PASS] minimap bake and bounds")
	return true
