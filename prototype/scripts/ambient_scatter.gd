extends Node3D
# ONE DRAW CALL PER TREE SPECIES INSTEAD OF ONE PER TREE.
#
# The ambient scatter (terrain_builder.gd's _spawn_ambient_trees /
# _spawn_ambient_ores, up to 1000 trees + 800 ore) used to instantiate a full
# glTF subtree per scattered item. Measured on a built skirmish world with
# tools/probe_skirmish_census.gd, BEFORE a single unit spawns:
#
#     nodes 6977 | meshinst 2560 (surfaces 4292) | multimesh 0
#
# 4292 surfaces is 4292 draw calls of decorative scenery, submitted every
# frame, on a top-down camera that has most of the map on screen at once so
# frustum culling reclaims very little. That is the render-side half of the
# skirmish slowdown; the CPU half was the matching 1895 no-op _physics_process
# dispatches (see resource_node.gd setup()'s note).
#
# Nothing about a scattered tree varies per instance except its transform,
# which is exactly what MultiMesh is for - the same reasoning greeble_field.gd
# already applies to hull rivets, just at map scale.
#
# WHY THE ResourceNode STAYS. Only the VISUAL moves here. Each scattered item
# keeps its own ResourceNode (group membership, amount, harvest(), the
# no-regrow contract), because that is real gameplay state a harvester queries
# per item and it cannot be flattened into a vertex buffer. What the node
# loses is its own MeshInstance3D subtree; it gets a handle into a batch
# instead and drives its instance's transform through set_node_transform().
#
# ORDERING CONTRACT: register() during the scatter pass, then commit() ONCE.
# Registering after commit() is a no-op and pushes an error - the MultiMesh
# instance buffers are sized at commit time, and growing them per late arrival
# would reallocate the whole buffer on the RenderingServer for every one.
#
# register() takes the NODE, not a transform, and commit() reads
# global_transform off it at commit time. That is deliberate: terrain_greebles.
# gd's spawn_ambient_tree() applies its per-instance yaw AFTER setup() returns,
# so a transform captured during registration would bake in the pre-yaw pose
# and the whole forest would face the same way. Reading at commit means
# "however the scatter pass finally left this node" is what gets baked, with no
# ordering contract on the caller at all.

# Harvested from one throwaway instantiation of each distinct scatter scene:
# the flattened list of {mesh, local transform} that its glTF subtree
# contains. Instantiating the PackedScene once per SPECIES instead of once per
# TREE is itself a large chunk of the map-build time this replaces.
# Deliberately no `class_name` (project gotcha: class_name globals are not
# reliable in scripts run headless before the .godot cache exists) - reached
# through this helper off the node the scatter is being parented to, which is
# the only handle resource_node.gd has at setup() time.
const NODE_NAME := "AmbientScatter"

static func get_or_create(parent: Node3D) -> Node3D:
	if parent == null:
		return null
	var existing := parent.get_node_or_null(NODE_NAME)
	if existing != null:
		return existing
	var batcher = (load("res://scripts/ambient_scatter.gd") as GDScript).new()
	batcher.name = NODE_NAME
	parent.add_child(batcher)
	return batcher


var _templates: Dictionary = {}      # scene_path -> Array[{mesh, xform}]
var _pending: Dictionary = {}        # scene_path -> Array[Node3D]
var _batches: Dictionary = {}        # scene_path -> Array[MultiMeshInstance3D]
var _committed: bool = false


# Returns a handle the caller keeps and hands back to set_node_transform().
# Null when the scene has no drawable geometry at all, so a caller can fall
# back to its own mesh path rather than silently rendering nothing.
func register(scene_path: String, node: Node3D):
	if _committed:
		push_error("AmbientScatter.register() after commit() - ignored: " + scene_path)
		return null
	if not _templates.has(scene_path):
		var t := _build_template(scene_path)
		if t.is_empty():
			return null
		_templates[scene_path] = t
		_pending[scene_path] = []
	var slot: int = _pending[scene_path].size()
	_pending[scene_path].append(node)
	return {"path": scene_path, "slot": slot}


func commit() -> void:
	if _committed:
		return
	_committed = true
	for path in _pending:
		var nodes: Array = _pending[path]
		if nodes.is_empty():
			continue
		var xforms: Array = []
		for n in nodes:
			xforms.append((n as Node3D).global_transform if is_instance_valid(n) else Transform3D().scaled(Vector3.ZERO))
		var parts: Array = _templates[path]
		var made: Array[MultiMeshInstance3D] = []
		for part in parts:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part["mesh"]
			mm.instance_count = xforms.size()
			var local: Transform3D = part["xform"]
			for i in range(xforms.size()):
				mm.set_instance_transform(i, (xforms[i] as Transform3D) * local)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			# Same call as the per-tree path made: the top-down camera looks
			# straight down on a tree's own canopy, so its shadow is a smudge
			# on itself that also darkens the ground pixels where a unit's
			# gameplay-relevant shadow lands. See resource_node.gd's own
			# AMBIENT SHADOWS ARE OFF note - this is that decision preserved
			# through the batching change, not a new one.
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.name = "Scatter_%s_%d" % [path.get_file().get_basename(), made.size()]
			add_child(mmi)
			made.append(mmi)
		_batches[path] = made


# Re-place one scattered item - used for the depletion shrink. Scaling to zero
# is how an item is removed: MultiMesh has no per-instance visibility flag and
# resizing instance_count would renumber every slot after it, invalidating
# every other node's handle.
func set_node_transform(handle, xform: Transform3D) -> void:
	if handle == null or not _committed:
		return
	var path: String = handle["path"]
	if not _batches.has(path):
		return
	var slot: int = handle["slot"]
	var parts: Array = _templates[path]
	var mmis: Array = _batches[path]
	for i in range(mmis.size()):
		var mm: MultiMesh = (mmis[i] as MultiMeshInstance3D).multimesh
		if slot < mm.instance_count:
			mm.set_instance_transform(slot, xform * (parts[i]["xform"] as Transform3D))


# Instantiates the scene once, walks it for MeshInstance3D descendants, and
# records each one's mesh plus its transform RELATIVE TO THE SCENE ROOT. That
# relative transform is what lets a multi-part asset (a trunk mesh and a
# canopy mesh sitting at different heights) survive batching: each part
# becomes its own MultiMesh, and the parts stay welded because every one of
# them is placed by the same per-item transform composed with its own offset.
#
# Surface materials come along for free - they live on the Mesh resource
# itself, which is what MultiMesh draws with. That preserves the "authored
# assets keep their baked-in glTF materials" contract resource_node.gd's
# spawn path documents (a tree's trunk vs. canopy are separate surfaces).
func _build_template(scene_path: String) -> Array:
	if not ResourceLoader.exists(scene_path):
		return []
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return []
	var probe := packed.instantiate() as Node3D
	if probe == null:
		return []
	var parts: Array = []
	# Transform is accumulated down the walk rather than read from
	# global_transform: the probe is deliberately never added to the
	# SceneTree (instantiating 20 species is cheap, adding and removing them
	# is not), and global_transform is only meaningful for a node that is
	# inside a tree. Composing local transforms by hand is exact here and
	# needs no tree at all.
	var stack: Array = [{"node": probe, "xform": Transform3D.IDENTITY}]
	while not stack.is_empty():
		var entry: Dictionary = stack.pop_back()
		var node: Node = entry["node"]
		var xform: Transform3D = entry["xform"]
		if node is Node3D:
			xform = xform * (node as Node3D).transform
		for c in node.get_children():
			stack.append({"node": c, "xform": xform})
		if node is MeshInstance3D and node.mesh != null:
			parts.append({"mesh": node.mesh, "xform": xform})
	probe.free()
	return parts
