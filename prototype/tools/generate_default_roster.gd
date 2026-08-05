extends SceneTree
# RETIRED. Do not revive this approach.
#
# This built the default roster programmatically: create a hull StaticBody3D with
# a BoxShape3D collider, call module_placer.update_locomotion(), then place each
# weapon at `y = col_box.size.y / 2.0` - the top of the BOX.
#
# WHY THAT CANNOT WORK. A hull's visible body is not its collision box. Hulls are
# SDF/marching-cubes meshes that slope, taper and dip, and the Design Lab places a
# part by raycasting onto that MESH. Measured against a real Lab-authored design
# on landing_craft_hull, whose box half-height is 1.20:
#
#     autocannon        z=-2.75   y=0.60
#     mortar_array      z= 2.00   y=0.05
#     smoke_discharger  z=-3.75   y=0.00
#
# Three parts all on facet "top", none of them anywhere near 1.20. This generator
# put every one of them at 1.20, i.e. floating above the real surface, and did the
# same for locomotion because update_locomotion() derives its stations from the
# collider too. On a hull narrower than its box at the mount point, the treads
# read as detached from the vehicle - which is exactly what they looked like.
#
# It also had a second bug that masked the first for a long time:
# update_locomotion() finds hull dimensions with
# hull.get_node_or_null("CollisionShape3D"), and a node created with .new() is
# auto-named "@CollisionShape3D@<id>" by Godot 4, so the lookup always missed and
# EVERY unit silently used the fallback Vector3(4.0, 1.0, 6.0) - the size
# suite_base.gd calls the "reference" hull. Naming the node fixed that, positions
# started varying per hull, and the designs were still wrong, because the box was
# never the right thing to measure against.
#
# THE PIPELINE NOW: author the design in the Design Lab, save it, and copy the
# JSON out of user://blueprints/ into assets/blueprints/default_roster/. A design
# that came out of the Lab is achievable in the Lab by construction, which is the
# property this generator could not provide at any level of effort.
#
# The only edit needed on the way in is the "id" field, because
# blueprint_manager.load_blueprint() builds its path as
# default_roster/<id>.json - so the id and the filename have to agree.
#
# Kept as a file rather than deleted so the reasoning survives with the code it
# is about; git history has the 200-line original.

func _init():
	print("tools/generate_default_roster.gd is RETIRED - see the comment at the top.")
	print("")
	print("The default roster is now hand-authored in the Design Lab and copied")
	print("out of user://blueprints/. Generating placements against a hull's")
	print("collision box cannot produce valid designs, because the Lab mounts")
	print("parts on the hull MESH and the two are different shapes.")
	quit(1)
