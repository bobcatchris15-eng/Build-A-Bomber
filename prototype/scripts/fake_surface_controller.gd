extends Node
# Minimal test-support double for the duck-typed get_surface_type_at()
# contract battle_unit.gd's _recalculate_terrain_speed_multiplier() checks
# for - used by run_tests.gd's terrain-differentiation test to drive real
# movement across a fixed surface type without needing a full Skirmish
# scene/navmesh bake.

var surface_type: String = ""

func get_surface_type_at(_pos: Vector3) -> String:
	return surface_type

# Also implements terrain_height_at() (flat ground, always 0.0) so
# battle_unit.gd's _physics_process() Y-branch lerps toward a real height
# instead of free-falling under gravity with no floor collision to catch
# it - a synthetic unit with no CollisionShape3D would otherwise pick up
# unbounded downward velocity over many manual ticks, which measurably
# distorts horizontal move_and_slide() distance in a way real gameplay
# (where every unit's Y is always lerped, never gravity-fallen, per
# terrain_builder.gd's own header comment) never exhibits.
func terrain_height_at(_pos: Vector3) -> float:
	return 0.0
