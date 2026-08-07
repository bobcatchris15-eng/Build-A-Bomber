extends RefCounted
# The in-battle surface finish: knocks the gloss off everything on the field.
#
# WHY IT IS A SEPARATE PASS AND NOT A CHANGE TO ARMOR_PBR. Those values are
# tuned, and hull_material_builder.gd carries the scar tissue to prove it - a
# documented regression where dropping hardened_steel's roughness produced
# blown-out anisotropic hotspots, another where raising metallic made armor read
# DARKER in ambient light because diffuse reflectance scales with (1-metallic).
# Editing them would reopen both, and would do it in the Design Lab, where the
# glossy read is CORRECT: the Lab is a showcase, one vehicle under studio
# lighting, examined up close.
#
# The battlefield is the opposite case. Dozens of small vehicles at RTS zoom,
# each a few dozen pixels tall, under a moving camera. At that size a sharp
# specular highlight covers a large fraction of the object and swims as the
# camera pans, which reads as shimmer - and shimmer at a distance is very easily
# mistaken for a framerate problem, because both present as "the units are not
# settling". So this is a per-context finish, applied to what is spawned into a
# match and to nothing else.
#
# It rides the shader's EXISTING roughness_bias uniform, which was left in place
# for exactly this kind of use and has been unused since per-faction roughness
# was walked back. No shader change, no new uniform, and the Lab is untouched.

# A FLOOR AND A CEILING, NOT A NUDGE. The first version of this applied a
# roughness BIAS of +0.22 and scaled metallic by 0.82, and the honest result was
# that Chris could not tell it had run. Two reasons, both structural:
#
#   THE BIAS IS CLAMPED. The shader declares roughness_bias as
#   hint_range(-0.3, 0.3), so it cannot on its own take hardened_steel's 0.42
#   anywhere near matte - and a proportional metallic scale leaves a strongly
#   metallic material still strongly metallic.
#
#   THE BLOB IS SEPARATE. hull_faction_material.gdshader adds a deliberate hard
#   specular highlight in light() - `SPECULAR_LIGHT += ... spec_blob *
#   toon_specular_strength * gloss_gain` - which is the comic-book gloss the art
#   direction asks for. Roughness only reaches it through gloss_gain, which still
#   sat at 0.55 after the bias. THAT is what reads as "shiny", and nothing about
#   biasing roughness was ever going to turn it down.
#
# So the battlefield finish now states absolute targets and drives the blob
# directly. The Design Lab keeps every one of these values untouched.
const ROUGHNESS_FLOOR := 0.82
const METALLIC_CEILING := 0.12
# The comic highlight, kept rather than zeroed: at zero the hulls lose their
# form-reading entirely and go flat, which is a different kind of wrong. This is
# a fifth of the shader's 0.5 default.
const TOON_SPECULAR := 0.1

# TWO HAZARDS THIS GUARDS AGAINST, both of which produce a wrong result quietly:
#
#   COMPOUNDING. metallic is SCALED, so touching the same Material twice halves
#   it twice. One vehicle's hull and its modules frequently share a single
#   material instance, and a naive walk would visit it once per MeshInstance3D -
#   a unit with six greebles would come out at 0.82^7 of its intended metallic,
#   which is not a subtle difference. `seen` makes application idempotent within
#   a call.
#
#   SHARED MESH RESOURCES. A material stored ON the Mesh (surface_get_material)
#   belongs to the mesh resource, which Godot shares across every instance that
#   loaded the same file - including the ones in the Design Lab. Writing through
#   that reference would apply the battlefield finish to the showcase, which is
#   the one thing this whole file exists to avoid. Only per-instance overrides
#   are touched; a mesh whose material lives on the resource keeps it.
static func apply(node: Node) -> void:
	_walk(node, {})


static func _walk(node: Node, seen: Dictionary) -> void:
	if node is MeshInstance3D:
		_finish(node.material_override, seen)
		for i in range(node.get_surface_override_material_count()):
			_finish(node.get_surface_override_material(i), seen)
	for child in node.get_children():
		_walk(child, seen)


static func _finish(mat: Material, seen: Dictionary) -> void:
	if mat == null or seen.has(mat.get_instance_id()):
		return
	seen[mat.get_instance_id()] = true

	if mat is ShaderMaterial:
		# Duck-typed per uniform rather than on the shader resource: hulls,
		# greebles and decals are all ShaderMaterials and only some are the
		# faction hull shader. Godot silently ignores a parameter the shader does
		# not declare, so the guard is about not pretending to have done anything.
		if mat.shader == null:
			return
		# The bias is zeroed and the base roughness raised instead. Leaving a
		# +0.22 bias on top of a raised roughness would just clamp at 1.0 and
		# make the knob untunable from here on.
		if _has_uniform(mat.shader, "roughness_bias"):
			mat.set_shader_parameter("roughness_bias", 0.0)
		if _has_uniform(mat.shader, "roughness"):
			mat.set_shader_parameter("roughness", maxf(
				_num(mat, "roughness", 0.4), ROUGHNESS_FLOOR))
		if _has_uniform(mat.shader, "metallic"):
			mat.set_shader_parameter("metallic", minf(
				_num(mat, "metallic", 0.6), METALLIC_CEILING))
		if _has_uniform(mat.shader, "toon_specular_strength"):
			mat.set_shader_parameter("toon_specular_strength", TOON_SPECULAR)
		return

	if mat is StandardMaterial3D:
		mat.roughness = maxf(mat.roughness, ROUGHNESS_FLOOR)
		mat.metallic = minf(mat.metallic, METALLIC_CEILING)
		# StandardMaterial3D keeps a specular term of its own, independent of
		# metallic - a non-metallic material at the 0.5 default still throws a
		# clear highlight, which is most of what the 62 module materials on a
		# typical unit were doing.
		mat.metallic_specular = minf(mat.metallic_specular, 0.15)


# A shader uniform's current value, falling back to `fallback` when it has never
# been assigned - get_shader_parameter() returns null for an unset uniform rather
# than the default written in the shader source, and float(null) is 0.0, which
# would silently drive roughness the wrong way.
static func _num(mat: ShaderMaterial, name: String, fallback: float) -> float:
	var value = mat.get_shader_parameter(name)
	return float(value) if value != null else fallback


static func _has_uniform(shader: Shader, name: String) -> bool:
	for entry in shader.get_shader_uniform_list():
		if str(entry.get("name", "")) == name:
			return true
	return false
