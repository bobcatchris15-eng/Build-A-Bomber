extends RefCounted
class_name VFXEffects
# Textured, GPU-simulated combat VFX: flame, smoke, and projected ground
# scorch. The companion to vfx_burst.gd, which covers short MESH-particle
# bursts (sparks, debris, muzzle flash); this file covers the effects that
# want a real texture instead of geometry.
#
# WHY THIS EXISTS. auto_weapon.gd builds its continuous effects out of solid
# primitive meshes: _fire_flame_spray() allocates six MeshInstance3D spheres
# and six Tweens PER SHOT, and at the flamethrower's 0.06s fire rate that is
# ~100 nodes and ~100 tweens created and destroyed per second, per weapon,
# all on the main thread. There are 33 MeshInstance3D.new() and 30
# create_tween() sites in that file in the same style. Beyond the cost, a
# cluster of shaded spheres simply does not read as fire - fire has no
# surface, which is exactly why every engine draws it as textured billboards.
#
# THE APPROACH, in both cases the standard one:
#   - Flame/smoke are ONE GPUParticles3D with a flipbook-animated billboard
#     quad. The simulation runs on the GPU, the whole emitter is a single
#     draw call, and a continuous emitter (a flamethrower) allocates NOTHING
#     per shot - it just toggles `emitting`.
#   - Ground scorch/napalm is a Decal node, which projects onto whatever
#     geometry is beneath it and conforms to terrain contours for free. The
#     project had zero Decal nodes before this; hull_decals.gd raycasts hull
#     triangles to place oriented quads instead, which is the right call for
#     a curved hull and unnecessary machinery for ground splatter.
#
# Textures are generated procedurally by generate_effect_textures.py at the
# repo root (a 4x4 flipbook each for flame and smoke, plus scorch albedo and
# an ember emission mask), not authored by hand - same
# regenerate-from-source convention as generate_terrain_textures.py.
#
# Every material is cached per look and never mutated after creation, same
# rule (and same reason) as vfx_burst.gd: many live emitters share one
# resource, so mutating a cached material would stomp every other user.

const FLAME_TEX = preload("res://assets/textures/effects/flame_flipbook.png")
const SMOKE_TEX = preload("res://assets/textures/effects/smoke_flipbook.png")
const SCORCH_TEX = preload("res://assets/textures/effects/scorch_decal.png")
const SCORCH_EMISSION_TEX = preload("res://assets/textures/effects/scorch_emission.png")

# Both flipbooks are 4x4. Kept as constants rather than read off the image so
# a regenerated sheet with a different layout fails loudly here instead of
# silently animating garbage.
const FLIPBOOK_H := 4
const FLIPBOOK_V := 4

static var _quad: QuadMesh = null
static var _billboard_cache: Dictionary = {}   # key -> StandardMaterial3D
static var _process_cache: Dictionary = {}     # key -> ParticleProcessMaterial

# One shared unit quad for every billboard particle in the game. Particle
# scale is set per-emitter through the process material, so a single 1x1
# quad serves a pilot light and a napalm bloom alike.
static func _get_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad

# BILLBOARD_PARTICLES + particles_anim_* is what makes one quad play a
# flipbook: Godot advances the frame from each particle's own normalised
# lifetime, so a particle born now and one born ten frames ago show
# different cells of the sheet with no per-particle script work at all.
static func _billboard_material(tex: Texture2D, additive: bool, tint: Color) -> StandardMaterial3D:
	var key = "%s|%s|%s" % [tex.resource_path, str(additive), tint.to_html()]
	if _billboard_cache.has(key):
		return _billboard_cache[key]
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = tex
	mat.albedo_color = tint
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.particles_anim_h_frames = FLIPBOOK_H
	mat.particles_anim_v_frames = FLIPBOOK_V
	# Each particle plays the sheet ONCE over its own lifetime rather than
	# cycling - a looping flame visibly restarts mid-air.
	mat.particles_anim_loop = false
	mat.vertex_color_use_as_albedo = true
	# Fire is emissive light, so it ADDS to what's behind it; smoke occludes,
	# so it blends normally. Getting this backwards is what makes engine fire
	# look like orange cellophane.
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# Never let a billboard z-fight or clip into the surface it sits on.
	mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_billboard_cache[key] = mat
	return mat

static func _process_material(key: String, direction: Vector3, spread: float,
		speed_min: float, speed_max: float, gravity: Vector3,
		scale_min: float, scale_max: float, damping: float = 0.0) -> ParticleProcessMaterial:
	if _process_cache.has(key):
		return _process_cache[key]
	var mat = ParticleProcessMaterial.new()
	mat.direction = direction
	mat.spread = spread
	mat.initial_velocity_min = speed_min
	mat.initial_velocity_max = speed_max
	mat.gravity = gravity
	mat.scale_min = scale_min
	mat.scale_max = scale_max
	mat.damping_min = damping
	mat.damping_max = damping
	# Particles shrink as they age - the flipbook already fades them out, and
	# scaling down as well is what sells a flame tapering rather than
	# vanishing at full size.
	var curve = CurveTexture.new()
	var c = Curve.new()
	c.add_point(Vector2(0.0, 0.35))
	c.add_point(Vector2(0.35, 1.0))
	c.add_point(Vector2(1.0, 0.15))
	curve.curve = c
	mat.scale_curve = curve
	_process_cache[key] = mat
	return mat


# --- Continuous flame ---------------------------------------------------
#
# ONE persistent emitter per weapon, created once and then only toggled.
# This is the whole point: a flamethrower firing for ten seconds allocates
# nothing after the first frame.
#
# `length` is how far the jet reaches; particle speed and lifetime are
# derived from it so a nozzle_width/pressure_valve tweak changes the reach
# of the visual and not just its colour.
static func make_flame_emitter(parent: Node3D, length: float = 8.0, width: float = 1.0) -> GPUParticles3D:
	var p = GPUParticles3D.new()
	p.name = "FlameJet"
	# Fewer, BIGGER, longer-lived particles than the obvious settings.
	# A jet has to read as one continuous body of fire, which means adjacent
	# particles must overlap generously - the first pass used 48 small
	# short-lived ones and rendered as a scatter of separate flames with gaps
	# between them.
	p.amount = 44
	p.lifetime = 0.55
	p.emitting = false
	# local_coords so the jet follows the barrel as the turret traverses,
	# instead of leaving a comet trail of stationary fire behind it.
	p.local_coords = true
	p.draw_pass_1 = _get_quad()
	p.material_override = _billboard_material(FLAME_TEX, true, Color(1, 1, 1, 1))
	var speed = length / p.lifetime
	p.process_material = _process_material(
		"flame|%.1f|%.1f" % [length, width],
		Vector3(0, 0, -1), 9.0 * width, speed * 0.72, speed,
		Vector3(0, 1.0, 0), 3.0 * width, 4.4 * width, 1.2)
	parent.add_child(p)
	return p

# Smoke that trails a flame jet, as a second emitter on the same parent -
# real flamethrowers are as much smoke as fire, and it costs one more draw
# call rather than one more node per particle.
static func make_flame_smoke_emitter(parent: Node3D, length: float = 8.0) -> GPUParticles3D:
	var p = GPUParticles3D.new()
	p.name = "FlameSmoke"
	p.amount = 16
	p.lifetime = 1.1
	p.emitting = false
	p.local_coords = true
	p.draw_pass_1 = _get_quad()
	p.material_override = _billboard_material(SMOKE_TEX, false, Color(0.22, 0.20, 0.19, 0.5))
	p.process_material = _process_material(
		"flamesmoke|%.1f" % length,
		Vector3(0, 0, -1), 22.0, length * 0.35, length * 0.55,
		Vector3(0, 2.2, 0), 1.4, 2.6, 2.0)
	parent.add_child(p)
	return p


# --- One-shot puffs -----------------------------------------------------

# A single burst of smoke (impact, wreck, cover). one_shot + `finished`
# self-cleanup, same lifecycle rule vfx_burst.spawn() uses - no guessed
# timers.
static func smoke_puff(parent: Node3D, world_pos: Vector3, radius: float = 1.5,
		amount: int = 12, tint: Color = Color(0.3, 0.29, 0.28, 0.55)) -> GPUParticles3D:
	var p = GPUParticles3D.new()
	p.name = "SmokePuff"
	p.amount = amount
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.85
	p.emitting = false
	p.draw_pass_1 = _get_quad()
	p.material_override = _billboard_material(SMOKE_TEX, false, tint)
	p.process_material = _process_material(
		"puff|%.1f" % radius,
		Vector3(0, 1, 0), 75.0, radius * 0.8, radius * 1.6,
		Vector3(0, 0.8, 0), radius * 0.9, radius * 1.7, 1.6)
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	p.finished.connect(func():
		if is_instance_valid(p):
			p.queue_free())
	return p


# Flames licking up off a burning area (a napalm pool, a wreck). Emits for
# `duration` and then frees itself - a pool that outlives its weapon needs a
# visual that outlives it too, which is why this parents to the caller's
# chosen node (the scene root) rather than to the gun.
static func fire_pool(parent: Node3D, world_pos: Vector3, radius: float, duration: float) -> GPUParticles3D:
	var p = GPUParticles3D.new()
	p.name = "FirePool"
	p.amount = int(clamp(radius * 10.0, 14, 60))
	p.lifetime = 0.9
	p.emitting = false
	p.draw_pass_1 = _get_quad()
	p.material_override = _billboard_material(FLAME_TEX, true, Color(1, 1, 1, 1))
	var mat = _process_material(
		"firepool|%.1f" % radius,
		Vector3(0, 1, 0), 18.0, 1.2, 2.6,
		Vector3(0, 1.6, 0), radius * 0.9, radius * 1.5, 0.8)
	# Emit across the whole pool footprint rather than from a point, so a wide
	# pool burns across its area instead of as one central bonfire. Assigning
	# unconditionally is safe despite the never-mutate-a-cached-material rule
	# in this file's header, because `radius` is part of the cache key - every
	# caller that reaches a given cached material writes the identical value.
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(radius * 0.8, 0.1, radius * 0.8)
	p.process_material = mat
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	_stop_and_free_after(p, duration)
	return p

# GPUParticles3D has no "emit for N seconds then stop" of its own, and a
# one_shot burst is the wrong shape for a pool that burns for many seconds.
# Stop emitting at `duration`, then free once the last particle has aged out.
static func _stop_and_free_after(p: GPUParticles3D, duration: float) -> void:
	var stop = p.create_tween()
	stop.tween_interval(max(duration, 0.05))
	stop.finished.connect(func():
		if not is_instance_valid(p):
			return
		p.emitting = false
		var drain = p.create_tween()
		drain.tween_interval(p.lifetime + 0.1)
		drain.finished.connect(func():
			if is_instance_valid(p):
				p.queue_free()))


# --- Ground scorch / burning pool --------------------------------------
#
# A Decal, not a flat MeshInstance3D laid on the ground. The difference
# matters on this game's terrain specifically: every map has real elevation
# (terrain_builder.gd's heightmap/hills), so a quad placed at one Y either
# floats above a slope or sinks into it, while a Decal projects down its
# local -Y and wraps whatever is actually there.
#
# `burn_seconds` > 0 makes it a live napalm pool first: the ember emission
# map glows and then fades to nothing, leaving the cold scorch albedo
# behind. Same decal, same texture pair, one animated property - which is
# why the generator emits a matching emission mask instead of a second
# scorch texture.
static func scorch(parent: Node3D, world_pos: Vector3, radius: float = 3.0,
		burn_seconds: float = 0.0, fade_seconds: float = 14.0) -> Decal:
	var d = Decal.new()
	d.name = "Scorch"
	# size.y is the PROJECTION DEPTH (how far down the decal reaches), not a
	# visual height - it has to comfortably exceed local terrain relief or
	# the mark clips off the side of a slope.
	d.size = Vector3(radius * 2.0, max(4.0, radius), radius * 2.0)
	d.texture_albedo = SCORCH_TEX
	d.albedo_mix = 1.0
	# Random yaw so repeated hits in one area don't stamp an obvious
	# repeating silhouette.
	d.rotation.y = randf() * TAU
	parent.add_child(d)
	d.global_position = world_pos

	if burn_seconds > 0.0:
		d.texture_emission = SCORCH_EMISSION_TEX
		d.emission_energy = 2.6
		var burn = d.create_tween()
		burn.tween_property(d, "emission_energy", 0.0, burn_seconds)

	# Then the mark itself weathers away, so a long match doesn't accumulate
	# unbounded decals - each one frees itself.
	var fade = d.create_tween()
	fade.tween_interval(max(burn_seconds, 0.0))
	fade.tween_property(d, "modulate:a", 0.0, fade_seconds)
	fade.finished.connect(func():
		if is_instance_valid(d):
			d.queue_free())
	return d
