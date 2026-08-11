extends RefCounted
# The simulation's random number stream. The ONLY source of randomness that is
# allowed to influence a match outcome.
#
# THE PROBLEM THIS SOLVES. Every random draw in the battle runtime used to come
# from Godot's global RandomNumberGenerator - `randf()`, `randf_range()`,
# `pick_random()` are all methods on it, so they all pull from one shared
# sequence. auto_weapon.gd alone makes roughly forty draws per engagement for
# sparks, muzzle scatter, debris and smoke puffs, and those were interleaved
# with the hit/miss roll at _roll_hit(), the reacquire stagger, and the salvo
# scatter that decides where an AoE actually lands. unit.gd's subsystem-strip
# roll and its choice of WHICH module to strip came off the same stream.
#
# One shared stream means cosmetic draws and simulation draws advance the same
# counter. Two clients that agree on every rule but disagree on one visual -
# because one of them skipped a spark on a dropped frame, or is running at a
# graphics setting that spawns fewer puffs, or simply culled an effect that was
# offscreen - immediately disagree about the next hit roll. Seeding does not
# fix that; the streams have to be SEPARATE. This file is the sim stream.
# `randf()` and friends remain the cosmetic stream and are deliberately left
# alone everywhere they only place a visual.
#
# This is a prerequisite for any multiplayer model, and it pays for itself
# immediately in testability: with the sim stream seeded, a combat sequence is
# reproducible, so a flaky damage test becomes a deterministic one.
#
# WHAT THIS DOES NOT CLAIM. It does not make the simulation deterministic.
# unit.gd drives movement through CharacterBody3D.move_and_slide() and
# NavigationAgent3D, neither of which is bit-deterministic across machines or
# even across frame-rate variation, and float accumulation in _physics_process
# is order-sensitive. Fixing that is a much larger decision that has not been
# made. This file fixes exactly one thing - that the random stream a second
# client must agree on is no longer polluted by the one it must not.
#
#
# WHY A STATIC HOLDER RATHER THAN AN INJECTED INSTANCE OR AN AUTOLOAD
# ---------------------------------------------------------------------------
# Three shapes were available:
#
#   1. An instance owned by match_director.gd and handed down. Rejected. The
#      two heaviest consumers (unit.gd, auto_weapon.gd) reach the controller by
#      duck-typing through `get_tree().current_scene`, and that lookup is
#      documented as unreliable in this very codebase - see the long comment on
#      auto_weapon.gd's _effects_parent(), where a null current_scene silently
#      broke every shot in the test harness because run_tests.gd instantiates
#      scenes straight under the tree root. An RNG that returns null in a
#      harness is an RNG that cannot be tested, and a weapon module several
#      nodes deep would need the reference threaded through unit_assembly for
#      no gain. The Design Lab also previews live weapons with no match
#      director in existence at all.
#
#   2. An autoload. Rejected. It needs a project.godot edit, and every new
#      autoload invalidates the gitignored .godot import cache in a way that
#      breaks a direct headless run with a misleading "Identifier not declared"
#      error (see CLAUDE.md's Tests section). A global singleton is also more
#      reach than this needs - nothing wants to connect to it or hold it.
#
#   3. A static holder consumed via `const SimRNG = preload(...)`. Chosen.
#      battle_profiler.gd is the exact precedent: static state on a preloaded
#      script, pulled in by unit.gd and auto_weapon.gd by the same idiom.
#      preload() of one path yields one GDScript resource, so every consumer
#      shares one stream by construction. It works with zero wiring in a test,
#      in the Design Lab, and in a match; and it gives the reset a single
#      obvious home (begin_match, below).
#
# The cost of a static holder is that state outlives a match - which is why
# begin_match() must be called at match start rather than relying on the
# initial value. That is the one-line hook in match_director.gd.
#
#
# HOW TO USE IT
# ---------------------------------------------------------------------------
#   const SimRNG = preload("res://scripts/battle/sim_rng.gd")
#   if SimRNG.randf() < chance: ...            # a roll that decides an outcome
#   var m = SimRNG.pick(candidates)             # a choice that decides an outcome
#   var s = SimRNG.scatter_xz(radius)           # an offset that moves damage
#
# And the rule for deciding which stream a new draw belongs to:
#
#   SIM       anything a second client must agree on - damage, hit rolls,
#             targeting, whether and which subsystem is stripped, where an AoE
#             centre lands, where a persistent entity (mine, drone, missile,
#             decoy) is created, and any timing that gates the above.
#   COSMETIC  sparks, debris, smoke puffs, tracer jitter, screen-space
#             wobble, decal choice, audio pitch variation. These stay on the
#             global randf(). Converting them would defeat the entire point of
#             the split, because then a client that skips one desynchronises
#             again.
#
# When in doubt, follow the value: if it can reach a take_damage(), a
# _deal_aoe_damage(), a spawn() of something that persists, or a decision about
# what to shoot, it is SIM.

# The stream. One RandomNumberGenerator, owned here, never handed out for
# reseeding - rng() exists for the callers that need to pass a real generator
# into an API that takes one (MapCatalog.assign_spawns, for instance).
static var _rng := RandomNumberGenerator.new()

# The seed the current match is running on. Kept separately from _rng.seed
# because RandomNumberGenerator.seed reports the CURRENT internal state, not the
# value it was seeded with - reading it back after a few draws returns something
# that will not reproduce the match. This is the number a replay file or a
# netcode handshake would carry, so it has to survive the draws.
static var _match_seed: int = 0

# Whether begin_match() has ever run. Only used by the diagnostic below; the
# stream is usable before it (a Design Lab preview or a unit test that never
# starts a match still gets sane values), it just is not reproducible.
static var _seeded: bool = false


# --- Seeding ------------------------------------------------------------------

# Start a match on the rule set's seed. Call once, at match start, BEFORE
# anything spawns - the reacquire stagger in auto_weapon.gd's _ready() and the
# initial fire-phase offset are both sim draws, so a unit created before this
# runs is drawing from the previous match's tail.
#
# `rule_set` is untyped so this file does not have to depend on MatchRuleSet
# (which would be a cycle waiting to happen the first time the rule set wants a
# roll of its own) and so a caller with no rule set at all - a test, the Test
# Range before it builds one - can pass null and still get a valid stream.
#
# Returns the seed actually used, which is what a caller would record.
static func begin_match(rule_set = null) -> int:
	var requested: int = 0
	if rule_set != null and "sim_seed" in rule_set:
		requested = int(rule_set.sim_seed)
	var actual := seed_with(requested)
	# Write the resolved seed back so the rule set carries the real number
	# rather than the 0 sentinel. This is what makes "save this match's config
	# and replay it" work: to_dict() then serialises a seed that reproduces the
	# match, not a request to roll a fresh one.
	if rule_set != null and "sim_seed" in rule_set:
		rule_set.sim_seed = actual
	return actual


# Seed the stream directly. `s == 0` means "unset" and gets a genuinely random
# seed instead.
#
# THE ZERO CASE IS LOAD-BEARING. An int field defaults to 0, so every rule set
# that nobody has explicitly seeded arrives here with 0. Passing that straight
# to RandomNumberGenerator.seed is legal and would make every single match in
# the game roll the identical sequence - identical hit rolls, identical strip
# choices, in the same order, forever. That failure is silent and looks like
# balance drift rather than a bug, which is exactly why it is handled here at
# the one chokepoint rather than trusted to callers. A match that wants
# reproducibility sets a non-zero seed; everything else gets a fresh one and
# can read it back from current_seed() afterwards.
#
# Returns the seed actually installed.
static func seed_with(s: int) -> int:
	var actual := s
	if actual == 0:
		# randomize() seeds from system entropy; reading .seed back immediately
		# (before any draw) gives the value that reproduces this stream.
		var picker := RandomNumberGenerator.new()
		picker.randomize()
		actual = int(picker.seed)
		# Vanishingly unlikely, but 0 is the sentinel and must never be the
		# installed seed or current_seed() would claim the match was unseeded.
		if actual == 0:
			actual = 1
	_rng.seed = actual
	_match_seed = actual
	_seeded = true
	return actual


# The seed this match is running on - the value to put in a replay header or a
# netcode handshake. 0 means begin_match()/seed_with() has never run.
static func current_seed() -> int:
	return _match_seed


static func is_seeded() -> bool:
	return _seeded


# --- Draws ---------------------------------------------------------------------
#
# Deliberately mirrors the global API's names and argument order, so converting
# a call site is a prefix and nothing else. That keeps the diff reviewable: a
# reader can see that `randf() >= miss_chance` became
# `SimRNG.randf() >= miss_chance` and that no behaviour moved with it.

static func randf() -> float:
	return _rng.randf()


static func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


static func randi() -> int:
	return int(_rng.randi())


static func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


# The sim-stream replacement for Array.pick_random(). Returns null on an empty
# array rather than erroring, matching pick_random()'s own behaviour, so a
# caller that already guards on is_empty() reads the same.
#
# IMPORTANT: it must not draw at all when there is nothing to pick, or an empty
# candidate list on one client and a one-entry list on another would desync the
# stream on top of whatever caused the disagreement.
static func pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[_rng.randi() % arr.size()]


# A horizontal scatter offset, y left at zero. This exists because the pattern
# `Vector3(randf_range(-r, r), 0.0, randf_range(-r, r))` appears at four sim
# call sites in auto_weapon.gd (rocket-artillery dispersion, mortar-salvo aim,
# cluster-bomblet dispersal, mine-laying spread) and each one decides where
# damage or a persistent entity lands. Naming it makes those sites self-
# documenting as sim draws rather than looking like more muzzle jitter.
#
# Draw order is x then z, matching the inline form it replaces exactly - which
# matters, because changing the number or order of draws changes every
# subsequent value in the stream.
static func scatter_xz(radius: float) -> Vector3:
	var x := _rng.randf_range(-radius, radius)
	var z := _rng.randf_range(-radius, radius)
	return Vector3(x, 0.0, z)


# The live generator, for APIs that take a RandomNumberGenerator rather than
# calling back into here - MapCatalog.assign_spawns() and assign_base_zones()
# both accept one and construct an unseeded generator when handed null.
#
# Handed out read-write because RandomNumberGenerator has no const form. Do not
# reseed it through this handle; use seed_with() so _match_seed stays honest.
static func rng() -> RandomNumberGenerator:
	return _rng
