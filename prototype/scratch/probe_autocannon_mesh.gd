extends SceneTree
# Scratch: measures the re-authored autocannon receiver against the family it is
# supposed to match, and against the one constant that must NOT move.
#
# visual_builder.gd hardcodes AUTOCANNON_RECEIVER_FRONT_Z = -0.102, MEASURED from
# this .glb, and positions the barrel off it. Its own comment says "re-measure if
# either mesh changes" - the last time these two disagreed the barrel floated
# 0.058 clear of the receiver. Every addition in this pass is at Blender -Y
# (rearward) which maps to Godot +Z, so the front face should be untouched; this
# proves it rather than assuming it.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_autocannon_mesh.gd --path .

const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")

const PARTS := [
	"autocannon_receiver", "autocannon_barrel", "autocannon_mount",
	"hmg_receiver", "amr_buffer", "recoilless_venturi", "mk19_receiver",
]

func _init():
	print("part                       front Z    back Z   depth    width   height   tris")
	var rows := {}
	for name in PARTS:
		var mesh: Mesh = MeshAssetLoader.get_part_mesh(name)
		if mesh == null:
			print("  %-24s <missing>" % name)
			continue
		var aabb := mesh.get_aabb()
		var tris := 0
		for s in range(mesh.get_surface_count()):
			var arrays = mesh.surface_get_arrays(s)
			if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
				tris += arrays[Mesh.ARRAY_INDEX].size() / 3
			elif arrays[Mesh.ARRAY_VERTEX] != null:
				tris += arrays[Mesh.ARRAY_VERTEX].size() / 3
		rows[name] = aabb
		print("  %-24s %7.3f  %7.3f  %6.3f  %6.3f  %6.3f  %5d" % [
			name, aabb.position.z, aabb.position.z + aabb.size.z,
			aabb.size.z, aabb.size.x, aabb.size.y, tris])

	print("")
	if not rows.has("autocannon_receiver"):
		print("FAIL: autocannon_receiver did not load")
		quit(1)
		return
	var rec: AABB = rows["autocannon_receiver"]

	# 1. The measured constant must still hold.
	var front: float = rec.position.z
	var expected: float = VisualBuilder.AUTOCANNON_RECEIVER_FRONT_Z
	print("front face  : %.4f   constant AUTOCANNON_RECEIVER_FRONT_Z = %.4f   %s" % [
		front, expected, "ok" if absf(front - expected) < 0.004 else "<-- MISMATCH, barrel will float or sink"])

	# 2. Rearward reach should now be in family with the other guns. In Godot
	#    space the rear is +Z, so this is the AABB's max Z.
	var back: float = rec.position.z + rec.size.z
	print("rear reach  : %.4f" % back)
	for peer in ["hmg_receiver", "amr_buffer"]:
		if rows.has(peer):
			var p: AABB = rows[peer]
			print("   vs %-16s %.4f" % [peer, p.position.z + p.size.z])
	var in_family := back >= 0.28
	print("in family   : %s (wants >= 0.28; it was 0.225 before this pass)" % ("ok" if in_family else "NO - still short"))

	# 3. The rear group must not have become the widest or tallest thing on the
	#    gun - VISUAL_ART_DIRECTION.md keeps detail at detail scale, and the
	#    ammo drum already had to be cut down once for exactly this reason.
	var ok_silhouette := rec.size.x <= 0.34 and rec.size.y <= 0.34
	print("silhouette  : width %.3f  height %.3f  %s" % [
		rec.size.x, rec.size.y, "ok" if ok_silhouette else "<-- rear group is dominating"])

	quit(0 if (absf(front - expected) < 0.004 and in_family and ok_silhouette) else 1)
