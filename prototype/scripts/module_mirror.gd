class_name ModuleMirror
extends RefCounted
# The single implementation of module chirality - reflecting a placed module
# across its own local X axis so a port-side copy is a genuine mirror of the
# starboard original rather than a rotated duplicate.
#
# WHY THIS FILE EXISTS: there used to be two copies of this, one in
# module_placer.gd (live placement in the Design Lab) and one in
# blueprint_manager.gd (reconstruction on load / test / battle spawn). Both
# carried a comment claiming they were kept in sync with each other. They
# weren't: only the module_placer copy compensated for the reversed triangle
# winding, so every mirrored module rendered inside-out as soon as it was
# reconstructed from a blueprint. It looked correct while you were building
# it and broke the moment you loaded, tested, or fought with it - which is
# exactly the shape of bug that survives a long time, because the screen you
# author on is the one screen where it looks right.
#
# Both call sites now route through here. If chirality needs to change, it
# changes once.

# Reflection across local X. Determinant is -1, which is the entire source of
# the winding problem compensate_culling() exists to fix.
const MIRROR_X := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))


# Applies the reflection to every visual child of `module`.
#
# Idempotent via a per-child "_mirrored" marker, and it has to be: the
# reflection is its own inverse, so a second application would silently undo
# it, and module_placer calls this once per mouse-motion frame while dragging
# a mirrored module. rebuild_visual() destroys and recreates these children,
# so fresh geometry is correctly unmarked and gets mirrored again.
static func apply(module: Node3D) -> void:
	if not module or not is_instance_valid(module):
		return
	for child in module.get_children():
		# Colliders are deliberately skipped - physics shapes are symmetric
		# enough that reflecting them buys nothing, and a negatively-scaled
		# collision shape is undefined behaviour in Godot Physics.
		if child is CollisionObject3D or not (child is Node3D):
			continue
		if child.get_meta("_mirrored", false):
			continue
		child.transform = Transform3D(
			MIRROR_X * child.transform.basis,
			MIRROR_X * child.transform.origin)
		child.set_meta("_mirrored", true)
		compensate_culling(child)


# MIRROR_X has determinant -1, so every mesh under a mirrored child renders
# with its triangle winding effectively reversed - front faces become back
# faces and get culled. The result is a module that looks hollow and
# inside-out: you see through the near surface into the far one. Godot does
# not compensate for this automatically, and it is most obvious on thin open
# shells like turret up-armour plates and wheel/tread housings, where there
# is no second surface behind to hide it.
#
# This SWAPS the cull mode rather than forcing CULL_FRONT.
#
# Forcing it was a real bug, and the one behind "left-hand locomotion modules
# render inverted". visual_builder._mesh_inst() - which builds essentially
# every procedural part, locomotion included - sets CULL_DISABLED, i.e.
# deliberately double-sided. Forcing CULL_FRONT on those did not "compensate"
# for anything: it turned culling ON for a mesh that had none, so the near
# surface vanished and you saw straight through into the far one. The
# compensation was CAUSING the inversion it was meant to prevent.
#
# A double-sided mesh has no winding problem to fix, because both faces are
# already drawn. Only single-sided meshes need the swap.
#
# Each mesh carries its own material_override (visual_builder.gd builds a
# fresh StandardMaterial3D per instance), so this cannot leak onto the
# unmirrored side.
static func compensate_culling(node: Node) -> void:
	if node is MeshInstance3D:
		var mat = (node as MeshInstance3D).material_override
		if mat is BaseMaterial3D:
			match mat.cull_mode:
				BaseMaterial3D.CULL_BACK:
					mat.cull_mode = BaseMaterial3D.CULL_FRONT
				BaseMaterial3D.CULL_FRONT:
					mat.cull_mode = BaseMaterial3D.CULL_BACK
				_:
					# CULL_DISABLED: already double-sided, nothing to fix.
					pass
	for child in node.get_children():
		compensate_culling(child)
