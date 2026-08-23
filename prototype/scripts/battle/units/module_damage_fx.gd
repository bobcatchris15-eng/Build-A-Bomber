extends RefCounted
# Per-module damage feedback: what losing a fight looks like ON THE MODULE.
#
# Two cues, both strictly cosmetic - nothing here moves a number in
# damage_model.gd or damage_resolver.gd, and nothing draws from SimRNG (the
# sim stream's length is load-bearing for replays; cosmetic effects use Godot's
# global stream or nothing at all):
#
#   * DESTROYED (a strip lands). A one-shot explosion at the module's position -
#     fire burst, debris chunks, a smoke puff, a short light flash and an SFX.
#     The caller queue_free()s the module, so every effect parents to the
#     UNIT'S PARENT (the container the match spawns units into), never to the
#     dying node - the old runtime's reflex was to attach FX to the thing being
#     freed, which cut every effect off at frame one.
#
#   * DAMAGED (below DAMAGED_THRESHOLD HP but still mounted). The module grows
#     a continuous smoke leak and wears a cracked stencil card on its top and
#     forward faces, so a half-stripped vehicle READS as half-stripped mid-fight
#     instead of changing state only when a part comes off. Applied once per
#     module - repeated hits stack neither emitters nor stickers (meta guard).
#
# Everything an overlay adds lives under one child subtree named FX_CONTAINER.
# module_volume.gd excludes that name from measurement (an overlay draws ON a
# module, not AS the module - sticker quads must not fatten click colliders or
# ride-height solves), and battle_wreck.gd strips it from wreck duplicates
# (the carcass's charred pass sets material_override on every MeshInstance3D
# and would flatten each alpha-cutout card into an opaque black quad).
#
# Preload-only, no class_name - same reasoning as module_volume.gd: nothing
# here may depend on the .godot class cache being warm.

const VFXBurstScript = preload("res://scripts/vfx_burst.gd")
const VFXEffectsScript = preload("res://scripts/vfx_effects.gd")
const ModuleVolumeScript = preload("res://scripts/module_volume.gd")

## Fraction of max module HP at which a surviving module starts smoking and
## wears the damaged stencil.
const DAMAGED_THRESHOLD := 0.30

## Name of the overlay subtree added under a damaged module. Must stay in sync
## with module_volume.gd's OVERLAY_PREFIXES entry.
const FX_CONTAINER := "DamageFX"

static var _crack_tex: ImageTexture = null
static var _sticker_mat: StandardMaterial3D = null


# A module died to a strip hit. One burst, sized by the module's bulk so a
# popped sensor does not detonate like an ammo rack.
static func module_destroyed(unit: Node3D, module: Node3D) -> void:
	var root := _fx_parent(unit, module)
	if root == null:
		return
	var pos := _world_pos(module, unit)
	var s := clampf(_bulk(module), 0.7, 1.8)
	VFXBurstScript.spawn(root, pos + Vector3(0, 0.25 * s, 0),
		Color(1.0, 0.55, 0.18), int(14.0 * s), 0.32, 150.0, 2.5 * s, 6.5 * s,
		Vector3(0, -4.0, 0), 0.7 * s, 1.4 * s)
	# Dark debris falling under gravity: the burst reads as the part coming
	# APART rather than as a muzzle flash that happened to be at its position.
	VFXBurstScript.spawn(root, pos,
		Color(0.16, 0.14, 0.12), int(8.0 * s), 0.45, 120.0, 2.0 * s, 4.5 * s,
		Vector3(0, -12.0, 0), 0.6, 1.1, VFXBurstScript.get_box_mesh())
	VFXEffectsScript.smoke_puff(root, pos, 1.4 * s, 12, Color(0.16, 0.15, 0.13, 0.6))
	_flash(root, pos + Vector3(0, 0.4 * s, 0), s)
	_play_sound(unit, pos)


# A module took strip damage and LIVED. Below the threshold it gains the smoke
# leak and the stencil, once.
static func module_damaged(_unit: Node3D, module: Node3D) -> void:
	if module == null or not is_instance_valid(module) \
			or not module.has_meta("module_data"):
		return
	if module.has_meta("_damage_fx_applied"):
		return
	var data = module.get_meta("module_data")
	if data == null:
		return
	var max_hp: float = float(data.get_hp())
	if max_hp <= 0.0:
		return
	var hp: float = float(module.get_meta("current_hp")) \
		if module.has_meta("current_hp") else max_hp
	if hp / max_hp >= DAMAGED_THRESHOLD:
		return
	module.set_meta("_damage_fx_applied", true)

	var aabb := ModuleVolumeScript.merged_aabb(ModuleVolumeScript.clip_boxes(module))
	var container := Node3D.new()
	container.name = FX_CONTAINER
	module.add_child(container)

	var smoke := VFXEffectsScript.make_damage_smoke(container,
		clampf(_bulk(module), 0.6, 1.6))
	# Emit from the module's upper half so the plume does not spend its first
	# metre climbing through the geometry it is leaking from.
	smoke.position = Vector3(0, aabb.size.y * 0.4, 0)

	if aabb.size.length_squared() > 0.0:
		_add_stickers(container, aabb)


# --- Explosion internals ------------------------------------------------------

static func _bulk(module: Node3D) -> float:
	var aabb := ModuleVolumeScript.merged_aabb(ModuleVolumeScript.clip_boxes(module))
	return (aabb.size.x + aabb.size.y + aabb.size.z) * 0.16


# Where the burst happens: the module's own position while it is still in the
# tree, falling back to the unit for anything already detached. global_position
# on an out-of-tree node is an engine error spam, not a value, so both reads
# are gated.
static func _world_pos(module: Node3D, unit: Node3D) -> Vector3:
	if module != null and is_instance_valid(module) and module.is_inside_tree():
		return module.global_position
	if unit != null and is_instance_valid(unit) and unit.is_inside_tree():
		return unit.global_position
	return Vector3.ZERO


# Effects must outlive the dying module, so prefer the unit's parent (the
# scene container, which survives both the module and the unit), then the
# unit itself (which survives the module at minimum).
static func _fx_parent(unit: Node3D, module: Node3D) -> Node3D:
	if unit != null and is_instance_valid(unit):
		var p := unit.get_parent()
		if p is Node3D:
			return p
		return unit
	if module != null and is_instance_valid(module):
		var mp := module.get_parent()
		return mp if mp is Node3D else module
	return null


static func _flash(parent: Node3D, pos: Vector3, s: float) -> void:
	var light := OmniLight3D.new()
	light.name = "StripFlash"
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 2.5 * s
	light.omni_range = 6.0 * s
	parent.add_child(light)
	light.global_position = pos
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.35)
	tw.finished.connect(func():
		if is_instance_valid(light):
			light.queue_free())


static func _play_sound(unit: Node3D, pos: Vector3) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var am: Node = unit.get_node_or_null("/root/AudioManager")
	if am == null:
		return
	# impact_module_lost is the designed cue for exactly this event; the
	# generic explosion bank covers any manifest missing it.
	var key := "impact_module_lost"
	if not am.has_sound(key):
		key = "explosion"
	am.play_sfx_3d(key, pos, null, 55.0)


# --- Damaged stencil ----------------------------------------------------------

static func _add_stickers(container: Node3D, aabb: AABB) -> void:
	var tex := _crack_texture()
	var half := aabb.size * 0.5
	var centre := aabb.get_center()

	# Top face first: the RTS camera looks down, so this is the one that has to
	# carry the cue.
	var top_span := clampf(minf(half.x, half.z) * 1.4, 0.22, 1.2)
	_card(container, tex, centre + Vector3(0, half.y + 0.02, 0),
		Vector2(top_span, top_span), Basis(Vector3.RIGHT, -PI * 0.5),
		"DamageStencilTop")

	# Forward face. Vehicles face local -Z - the same convention
	# ModuleCatalog.classify_facet() uses - so that is where a flanker sees it.
	_card(container, tex, centre + Vector3(0, 0, -half.z - 0.02),
		Vector2(clampf(half.x * 1.2, 0.2, 1.0), clampf(half.y * 1.2, 0.18, 0.9)),
		Basis(Vector3.UP, PI), "DamageStencilFront")


static func _card(parent: Node3D, tex: Texture2D, pos: Vector3,
		size: Vector2, basis: Basis, card_name: String) -> void:
	var card := MeshInstance3D.new()
	# Distinct names: add_child quietly renames a second identical
	# "DamageStencil" to "@DamageStencil@2", which broke anything looking for
	# the cards by name.
	card.name = card_name
	var quad := QuadMesh.new()
	quad.size = size
	card.mesh = quad
	card.material_override = _sticker_material(tex)
	parent.add_child(card)
	card.position = pos
	card.basis = basis
	# Pop-in, purely as polish. Only while inside the tree: a tween on a
	# detached node never processes and would leave the sticker at 5% scale.
	if card.is_inside_tree():
		card.scale = Vector3.ONE * 0.05
		var tw := card.create_tween()
		tw.tween_property(card, "scale", Vector3.ONE, 0.15)


static func _sticker_material(tex: Texture2D) -> StandardMaterial3D:
	if _sticker_mat != null:
		return _sticker_mat
	var mat := StandardMaterial3D.new()
	# Same recipe as HullDecals' decal material: alpha scissor rather than
	# blended transparency (no sorting artefacts against the hull), nearest
	# filtering (crisp stencil edge, not a soft blob), double-sided so a card
	# seen edge-on from behind never vanishes.
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.75
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# A whisper of emission so the crack still reads on the shadow side of a
	# hull at dusk-map lighting.
	mat.emission_enabled = true
	mat.emission = Color(0.28, 0.07, 0.02)
	mat.emission_energy_multiplier = 0.55
	_sticker_mat = mat
	return mat


# The crack mark itself, drawn once into a cached ImageTexture. Deterministic
# seed for the same reason tools/audio is deterministic: a cached procedural
# asset must come out identical every run.
static func _crack_texture() -> ImageTexture:
	if _crack_tex != null:
		return _crack_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var centre := Vector2(n, n) * 0.5

	# Irregular scorch blotch under everything: sin-perturbed disc, dark
	# enough to read as burnt paint on any livery colour.
	for x in range(n):
		for y in range(n):
			var d := Vector2(x, y) - centre
			var r := centre.x * 0.40 * (0.78 + 0.22 * sin(d.angle() * 5.0 + 1.3))
			if d.length() <= r:
				img.set_pixel(x, y, Color(0.10, 0.08, 0.07, 0.92))

	# Jagged cracks radiating out of the burn, charcoal core with occasional
	# amber segments - heat damage, not a scratch.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260823
	for i in range(7):
		var ang := TAU * float(i) / 7.0 + rng.randf_range(-0.25, 0.25)
		var dir := Vector2(cos(ang), sin(ang))
		var reach := centre.x * rng.randf_range(0.85, 1.0)
		var steps := maxi(int(reach * 0.5), 2)
		for stp in range(steps):
			var t := float(stp) / float(steps)
			var p := centre + dir * (t * reach) \
				+ dir.orthogonal() * rng.randf_range(-2.5, 2.5)
			var w := lerpf(2.4, 0.9, t)
			_plot(img, p, w, Color(0.09, 0.07, 0.06))
			if stp % 3 == 0:
				_plot(img, p, w * 0.45, Color(0.95, 0.55, 0.15))

	_crack_tex = ImageTexture.create_from_image(img)
	return _crack_tex


static func _plot(img: Image, p: Vector2, radius: float, col: Color) -> void:
	var n := img.get_width()
	var x0 := int(maxf(p.x - radius, 0.0))
	var x1 := int(minf(p.x + radius, float(n - 1)))
	var y0 := int(maxf(p.y - radius, 0.0))
	var y1 := int(minf(p.y + radius, float(n - 1)))
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			img.set_pixel(x, y, col)
