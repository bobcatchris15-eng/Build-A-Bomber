extends SceneTree

# End-to-end check that fog reaches the MINIMAP, not just the world.
#
# _composite_fog() is full of defensive early-returns (no director, no vision,
# reveal_all, empty image). Every one of them makes the minimap render exactly
# as it did before this change, so "no errors in the log" is not evidence the
# feature works. This drives the real BattleHUD against a real VisionService
# and reads the pixels back.
#
# Run (NO --quit: this probe awaits frames, and --quit exits on the first one,
# which produces a completely silent run rather than a failure):
#   ./Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script tools/probe_minimap_fog.gd

const BattleHUDScript = preload("res://scripts/battle/hud/battle_hud.gd")
const VisionServiceScript = preload("res://scripts/battle/vision/vision_service.gd")
const MapCatalogScript = preload("res://scripts/map_catalog.gd")


# BattleHUD.setup() and _refresh_minimap() reach for more of the director than
# the fog path needs (selection, camera, alerts, the view indicator). Stubbing
# them keeps the probe's output to the thing being measured - an error-spewing
# probe is one nobody trusts the PASS line of.
class StubSelection extends Node:
	signal selection_changed
	var selected: Array = []


class StubAlerts extends Node:
	signal alert_raised


class StubDirector extends Node:
	var vision = null
	var selection = null
	var alerts = null
	var camera = null
	var current_map: Dictionary = {}


func _init() -> void:
	# The HUD calls get_tree().get_nodes_in_group() during a refresh, so it has
	# to be genuinely inside the tree first - _init() runs before that is true.
	await process_frame
	var map: Dictionary = MapCatalogScript.get_map(MapCatalogScript.DEFAULT_MAP_ID)
	var half: float = map.get("map_half_extents", 80.0)

	var director := StubDirector.new()
	director.current_map = map
	director.selection = StubSelection.new()
	director.alerts = StubAlerts.new()
	root.add_child(director)
	director.add_child(director.selection)
	director.add_child(director.alerts)

	var vision = VisionServiceScript.new()
	vision.setup(director, 0, half, 1.0)
	director.vision = vision

	var hud = BattleHUDScript.new()
	root.add_child(hud)
	hud.setup(director, 0, map)
	await process_frame

	var before: Image = hud.minimap_image()
	var mid := Vector2i(before.get_width() / 2, before.get_height() / 2)
	var pre: Color = before.get_pixel(mid.x, mid.y)

	# Nothing has ever been seen, so the whole minimap should go black.
	hud._refresh_minimap()
	var post: Color = hud.minimap_image().get_pixel(mid.x, mid.y)

	print("MINIMAP_FOG: unexplored  before=%s after=%s" % [str(pre), str(post)])
	var pre_luma: float = (pre.r + pre.g + pre.b) / 3.0
	var post_luma: float = (post.r + post.g + post.b) / 3.0
	if post_luma > 0.02:
		print("MINIMAP_FOG: *** FAIL *** unexplored terrain should be black, luma=%.4f" % post_luma)
		quit(1)
		return
	if pre_luma <= 0.02:
		print("MINIMAP_FOG: *** PROBE BUG *** baked terrain was already black")
		quit(1)
		return

	# Now reveal the middle of the map and confirm that pixel comes back.
	# reveal_area() is the real beacon entry point (illumination ammo uses it),
	# and it folds into the same scan the shroud reads.
	vision.reveal_area(0, Vector3.ZERO, half * 0.5, 60.0)
	vision.tick()
	hud._refresh_minimap()
	var lit: Color = hud.minimap_image().get_pixel(mid.x, mid.y)
	var lit_luma: float = (lit.r + lit.g + lit.b) / 3.0
	print("MINIMAP_FOG: revealed    after=%s luma=%.4f (baked was %.4f)" % [
		str(lit), lit_luma, pre_luma])
	if not is_equal_approx(lit_luma, pre_luma):
		print("MINIMAP_FOG: *** FAIL *** revealed terrain should match the baked colour")
		quit(1)
		return

	print("MINIMAP_FOG: minimap distinguishes revealed from unrevealed")
	quit(0)
