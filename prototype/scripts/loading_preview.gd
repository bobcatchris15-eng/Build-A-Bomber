extends Control
# Live 3D vehicle preview for the Battle deploy gate.
#
# WHY THIS EXISTS. The deploy gate is the last beat of the battle
# boot path, and the world-build behind it is the longest wait in
# the game (the 2026-08-19 log measured 70+ seconds before steady
# state). The gate's frosted glass + center bezel is technically
# complete but visually empty for the entire wait - the player
# watches "PREPARING DEPLOYMENT / Surveying terrain" with nothing
# else to look at. A live 3D vehicle cycling through the player's
# own designs (in their own livery) is the difference between a
# long wait and a hangar.
#
# CALLED BY deploy_gate.gd. The loading screen (Loading.tscn) also
# uses the same SceneRouter check to skip the SubViewport cost on
# the shorter Lab boot. The router's _target_path is still
# "res://scenes/Battle.tscn" while the gate is up, so the same gate
# fires in both call sites.
#
# WHAT IT COPIES FROM THE MAIN MENU. The turntable, key/rim lights,
# camera position, and rotation rate are lifted from main_menu.gd's
# _build_3d_background(). The user wanted the same look - "honestly
# just copying the one from the main menu screen is perfect" - and
# that code is the proven composition. Differences from the menu
# version:
#   * No placard UI: the gate has its own status / step text and
#     the placard would compete with it.
#   * No fallback hull types: empty roster -> hide, per the design
#     decision (a hull with no associated blueprint is not a real
#     roster entry and would mislead the player about what they're
#     about to field).
#   * Player livery is applied via match_faction_override rather
#     than is_designer=true (the menu uses is_designer=true to show
#     the unpainted kit; the gate shows what they'll actually
#     field).
#
# WHY A FIXED 3s DWELL. The user picked it over a variable dwell.
# A variable dwell would shorten for fast loads and lengthen for
# slow ones, but the slow loads are the case the preview exists to
# soften; showing each design for longer there is the point of the
# feature, not a downside.
#
# WHY A SELF-CONTAINED SCENE / SCRIPT. Embedding a SubViewport, three
# lights, a camera, a turntable, a platform, and a cycle timer in
# deploy_gate.gd would double its length and mix 3D-pipeline
# concerns with the chrome it already manages. A separate
# LoadingPreview is also testable in isolation, and the same scene
# can be embedded elsewhere (the loading screen, a future deploy-
# gate stand-in for the Proving Ground) without duplication.

const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const LiveryScript = preload("res://scripts/livery.gd")

# How long each design is shown before advancing. Fixed (not a
# fraction of total load) so the cadence is the same regardless of
# whether the load is 5 s or 60 s. The user picked this; see the
# header note on WHY A FIXED 3s DWELL.
const DWELL_SECONDS := 3.0

# Turntable rotation rate, in radians per second. Lifted directly
# from main_menu.gd:209 so the two surfaces match (a Skirmish load
# showing a rotating design should look like the same hangar the
# Main Menu does, not a different one).
const TURNTABLE_RAD_PER_SEC := 0.25

# The destination path this preview activates for. Loading_screen.gd
# reads the router's current_target_path() and only instantiates a
# LoadingPreview when it matches. The constant is duplicated on both
# sides because Godot has no project-wide constant registry; see
# scene_router.gd's WARM_SOURCES for the canonical list.
const BATTLE_PATH := "res://scenes/Battle.tscn"

# Stage anchor and camera. These numbers are copy-pasted from
# main_menu.gd:322-330 - the menu's camera framing, with the
# platform's y offset to sit a hull on. Touch only if the menu's
# numbers also change; the two surfaces MUST match or the player
# notices the same model framed differently between the two.
const STAGE_OFFSET := Vector3(0.5, -0.4, 0.0)
const CAMERA_POS := Vector3(1.2, 4.8, 15.5)
const CAMERA_ROT_DEG := Vector3(-16.0, 12.0, 0.0)
const CAMERA_FOV := 46.0


# Resolved once on _ready. The list is the cycling source; the index
# advances on a timer. _roster stays empty if the player has no
# saved + bundled designs, and the preview hides itself in that case.
var _roster: Array = []
var _index: int = 0
var _dwell_elapsed: float = 0.0

# 3D stage. _turntable_node is what rotates; _model_container holds
# the current unit and is the parent the new unit is built into. The
# previous unit is freed before the next is built so the stage never
# holds more than one.
var _turntable_node: Node3D = null
var _model_container: Node3D = null

# The currently-shown unit. Tracked so tree_exiting can free it
# (it lives inside a SubViewport which is otherwise detached
# silently; an explicit queue_free is the safe path).
var _current_unit: Node3D = null

# The SubViewport the stage renders into. Kept so set_active() can stop its
# render target entirely once the loading screen swaps this preview out for
# the DEPLOY panel.
var _viewport: SubViewport = null

# The blueprint manager. One per preview instance - the main menu
# also uses a fresh instance per build, and that is the
# BlueprintManagerScript's own intended usage.
var _bp_manager = null


func _ready() -> void:
	# Resolve the destination. Both call sites (loading screen and
	# deploy gate) sit while the SceneRouter's _target_path is still
	# pointing at the destination; the router only clears it after
	# the gate dismisses. So the check fires correctly in both
	# contexts. If a future caller instantiates us with no
	# SceneRouter in the tree, we hide - the empty glass-on-glass
	# of an invisible SubViewport is the right fallback, not a
	# visible 3D viewport on an unrelated screen.
	var router = get_node_or_null("/root/SceneRouter")
	if router == null or router.current_target_path() != BATTLE_PATH:
		visible = false
		set_process(false)
		return

	_bp_manager = BlueprintManagerScript.new()
	_roster = _bp_manager.list_blueprints(false)
	# Empty-roster policy is "hide entirely" - the player is not
	# about to field anything they own, and showing a default hull
	# would tell them a story the world won't. The lamps / progress
	# bar are the honest answer for an empty wait.
	if _roster.is_empty():
		visible = false
		set_process(false)
		return

	_build_stage()
	# Build the first design immediately so the player sees a unit
	# from the very first frame, not the turntable on its own.
	_build_current()
	set_process(true)


func _process(delta: float) -> void:
	# Turntable spin. The same delta is used for both the turntable
	# and the dwell timer so the rotation is independent of cycling
	# (a slow cycling rate does not slow the spin).
	if is_instance_valid(_turntable_node):
		_turntable_node.rotation.y += TURNTABLE_RAD_PER_SEC * delta

	_dwell_elapsed += delta
	if _dwell_elapsed >= DWELL_SECONDS:
		_dwell_elapsed = 0.0
		_index = (_index + 1) % _roster.size()
		_build_current()


func _build_stage() -> void:
	# The structure here mirrors main_menu.gd:273-350 (the
	# _build_3d_background block) so the two look identical from the
	# player's seat. Differences:
	#   * mouse_filter IGNORE on the SubViewportContainer - the
	#     loading screen is not interactive; clicks must pass through
	#     to anything underneath.
	#   * The viewport size scales with the Control's size rather
	#     than being a fixed 1920x1080 - the loading screen's top
	#     slot is much smaller than the full main menu, and a fixed
	#     size would either letterbox or scale oddly.
	var vp_container := SubViewportContainer.new()
	vp_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp_container.stretch = true
	vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vp_container)

	var vp := SubViewport.new()
	# The SubViewport is its own size, fed by the Container. 4x MSAA
	# matches the main menu (the alternative - 2x or off - reads as
	# a different scene).
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	vp_container.add_child(vp)
	_viewport = vp

	# Studio lighting. Key + rim is the same pair the main menu
	# uses; the menu's environmental fill (the WorldEnvironment
	# tonemap) is not relevant for a single stationary model and is
	# omitted. The result is a slightly harsher read than the
	# hangar's ACES filmic, which is fine for "here is the thing
	# you're about to field" - the player does not need glamour,
	# they need to see their livery.
	var scene_root := Node3D.new()
	vp.add_child(scene_root)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	key.light_energy = 1.2
	scene_root.add_child(key)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(25.0, 145.0, 0.0)
	rim.light_energy = 0.6
	scene_root.add_child(rim)

	# Camera. Numbers are the menu's - see CAMERA_POS / CAMERA_ROT_DEG.
	var cam := Camera3D.new()
	cam.position = CAMERA_POS
	cam.rotation_degrees = CAMERA_ROT_DEG
	cam.fov = CAMERA_FOV
	scene_root.add_child(cam)

	# Turntable. Rotates around Y; the platform is a static child
	# so it spins with the unit, which is the "model on a plate"
	# read the menu uses. A static platform with the model spinning
	# relative to it is a different look and was not what was
	# asked for.
	_turntable_node = Node3D.new()
	_turntable_node.position = STAGE_OFFSET
	scene_root.add_child(_turntable_node)

	var platform := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 4.0
	cyl.bottom_radius = 4.0
	cyl.height = 0.15
	platform.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.19, 0.22)
	mat.metallic = 0.2
	mat.roughness = 0.65
	platform.material_override = mat
	_turntable_node.add_child(platform)

	_model_container = Node3D.new()
	_turntable_node.add_child(_model_container)


func set_roster(roster: Array) -> void:
	# Replace the cycling source with the match's actual roster.
	# Called by the loading screen AFTER attach_battle_scene() has
	# added the Battle to the tree and the match director's
	# synchronous _ready has populated its `roster` array. The
	# loading screen calls this so the preview only cycles through
	# the units the player is bringing into THIS match - cycling
	# through the entire library is what showed the wrong vehicle
	# mid-build and made the player think the world was being
	# assembled out of stuff they did not draft.
	#
	# Same roster-empty -> hide policy as _ready. The user's match
	# never has an empty roster (the director's _ready adds a
	# harvester if the picked list lacks one), so in practice
	# this branch never fires - the safety is here for the
	# edge case the test-range launcher would hit if the player
	# cleared the test subject.
	_roster = roster
	_index = 0
	if _roster.is_empty():
		visible = false
		set_process(false)
		return
	if not visible:
		visible = true
		set_process(true)
	# Rebuild the current unit immediately so the player sees the
	# new roster's first design, not whatever was being shown
	# before (which was either the entire-library default or a
	# prior match's leftover).
	_build_current()


func set_active(active: bool) -> void:
	# Full stop, not just visible = false. UPDATE_ALWAYS renders the 3D stage
	# into its texture every frame regardless of whether anything draws the
	# texture, so hiding the Control alone would keep burning GPU on a model
	# nobody can see. Called by the loading screen when it swaps this preview
	# out for the DEPLOY panel at world_ready.
	if active and _roster.is_empty():
		return
	set_process(active)
	visible = active
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE \
			if active else SubViewport.UPDATE_DISABLED


func _build_current() -> void:
	# Free the previous unit. queue_free is deferred; the new unit is
	# added immediately, so the stage briefly holds two - that is
	# fine, the previous one disappears within a frame and freeing it
	# explicitly (rather than waiting for tree_exiting) keeps the
	# stage memory-bounded during a long load.
	if is_instance_valid(_current_unit):
		_current_unit.queue_free()
		_current_unit = null

	if _model_container == null or _roster.is_empty():
		return

	var entry: Dictionary = _roster[_index]
	var path: String = str(entry.get("path", ""))
	if path == "":
		return
	# Untyped on the call site (see _build_current's note): the
	# BlueprintManager is not globally named, so the parser cannot
	# infer load_blueprint()'s Dictionary return through _bp_manager.
	var data = _bp_manager.load_blueprint(path)
	if data.is_empty():
		# Bad blueprint (corrupt JSON, missing hull, etc.) - skip
		# silently. The next index tick will advance; logging here
		# would be noise on a load screen.
		return

	# is_designer=false so the player's livery is applied (the menu
	# uses is_designer=true to show the unpainted kit). The livery id
	# is the player's own ("player"), which is what the LiveryScript
	# resolves to load_player() / user://livery.json.
	#
	# Untyped deliberately: _bp_manager is untyped (BlueprintManager
	# has no class_name), so the parser cannot infer the return of
	# reconstruct_vehicle() through it. main_menu.gd's preview uses
	# the same untyped pattern; matching it here keeps the parse
	# rules consistent.
	var vehicle = _bp_manager.reconstruct_vehicle(
		data, _model_container, false, LiveryScript.PLAYER_ID)
	_current_unit = vehicle


func _notification(what: int) -> void:
	# Explicit free on the way out. The SubViewport is detached
	# silently when the loading screen itself is freed, but the
	# unit's resources (materials, mesh cache entries) are owned by
	# the SubViewport and live until GC. Freeing explicitly clears
	# them now, which matters because the loading screen is reused
	# across scene transitions - a long match -> design lab ->
	# long match would accumulate units otherwise.
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_current_unit):
		_current_unit.queue_free()
		_current_unit = null
