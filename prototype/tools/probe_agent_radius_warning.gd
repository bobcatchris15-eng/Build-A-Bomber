extends SceneTree

# Determines exactly what agent_radius value silences Godot 4.7.1's
# "Property agent_radius is ceiled to cell_size voxel units and loses
# precision" warning, at the cell_size values terrain_builder.gd actually
# produces.
#
# The question this answers: does the engine compare the snapped radius with
# exact float equality or with is_equal_approx()? If exact, snapping in
# GDScript risks a float that re-ceils one voxel WIDER than intended - which
# would silently change clearance, and clearance is what
# test_spawn_fairness_lint_passes_a_real_map_scaled_up_4x is sensitive to.
#
# Run:
#   ./Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script tools/probe_agent_radius_warning.gd --quit

# The live spread: 0.25 is the small-map floor (_nav_cell_size), 1.87 is
# open_plains at world_scale 4, 3.33 is scattered_peaks' tile cell size,
# 5.95 is scattered_peaks' open-water cell size.
const CELL_SIZES: Array = [0.25, 0.5, 1.0, 1.87, 2.5, 3.33, 5.95]
const RADII: Array = [1.0, 0.1]


func _flat_quad(size: float) -> PackedVector3Array:
	# One big walkable quad - enough source geometry for Recast to bake
	# something, which is all we need to trigger the warning path.
	var v := PackedVector3Array()
	v.append(Vector3(-size, 0.0, -size))
	v.append(Vector3(size, 0.0, -size))
	v.append(Vector3(size, 0.0, size))
	v.append(Vector3(-size, 0.0, -size))
	v.append(Vector3(size, 0.0, size))
	v.append(Vector3(-size, 0.0, size))
	return v


func _bake(cell_size: float, agent_radius: float) -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = cell_size
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_max_climb = cell_size * 1.5
	nav_mesh.agent_radius = agent_radius
	var source := NavigationMeshSourceGeometryData3D.new()
	source.add_faces(_flat_quad(cell_size * 60.0), Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)


func _init() -> void:
	print("=== RAW (current behaviour: agent_radius set verbatim) ===")
	for cs in CELL_SIZES:
		for r in RADII:
			print("--- cell_size=%.4f agent_radius=%.4f  (any warning above is from this bake)" % [cs, r])
			_bake(cs, r)

	print("")
	print("=== SNAPPED (radius ceiled to cell_size, climb floored to cell_height) ===")
	for cs in CELL_SIZES:
		for r in RADII:
			var voxels: int = maxi(1, int(ceil(r / cs)))
			var snapped: float = float(voxels) * cs
			# Report the round-trip the engine itself would do, so we can see
			# whether float noise pushes the re-ceil to a wider voxel count.
			var round_trip: int = int(ceil(snapped / cs))
			var climb_voxels: int = maxi(1, int(floor((cs * 1.5) / 0.25)))
			var climb: float = float(climb_voxels) * 0.25
			print("--- cell_size=%.4f r=%.4f -> voxels=%d snapped=%.9f re-ceil=%d %s | climb %.4f -> %.9f" % [
				cs, r, voxels, snapped, round_trip,
				"OK" if round_trip == voxels else "*** RE-CEIL DRIFTED ***",
				cs * 1.5, climb])
			_bake_snapped(cs, snapped, climb)

	print("")
	print("=== done. A clean SNAPPED section means snapping silences both warnings. ===")
	quit()


func _bake_snapped(cell_size: float, agent_radius: float, agent_max_climb: float) -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = cell_size
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_max_climb = agent_max_climb
	nav_mesh.agent_radius = agent_radius
	var source := NavigationMeshSourceGeometryData3D.new()
	source.add_faces(_flat_quad(cell_size * 60.0), Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
