extends Node
# Skirmish enemy commander. Simple but relentless:
# - keeps a harvester working
# - queues affordable units from its roster
# - launches attack waves at the player HQ on a ramping timer

var skirmish: Node3D = null
var team: int = 1

var produce_timer: float = 0.0
var wave_timer: float = 0.0
var harvester_check_timer: float = 0.0
var structure_check_timer: float = 0.0
var roster_index: int = 0
var wave_number: int = 0
var _last_hq_hp: float = -1.0

const PRODUCE_INTERVAL: float = 14.0
const FIRST_WAVE_DELAY: float = 60.0
const WAVE_INTERVAL: float = 55.0
const PITY_METAL: int = 10
const PITY_CRYSTAL: int = 3
const STRUCTURE_CHECK_INTERVAL: float = 8.0
const MANUFACTORY_TIERS: Array = ["light", "medium", "heavy"]
const MAX_AI_DEFENSES: int = 3

# Configurable enemy/team count (pre-match settings ask) was scoped down to
# AI difficulty instead - see DECISIONS_NEEDED.md. Scales the same timers/
# pity-trickle every difficulty level already had, rather than adding new
# knobs: "hard" produces/attacks faster and recovers from a bad economy
# quicker, "easy" does the opposite. Real effect, not cosmetic - these
# multipliers directly drive _physics_process()'s own timer thresholds.
const DIFFICULTY_TIMER_MULT = {"easy": 1.4, "normal": 1.0, "hard": 0.65}
const DIFFICULTY_PITY_MULT = {"easy": 0.5, "normal": 1.0, "hard": 1.8}

var produce_interval: float = PRODUCE_INTERVAL
var wave_interval: float = WAVE_INTERVAL
var pity_metal: int = PITY_METAL
var pity_crystal: int = PITY_CRYSTAL

func setup(skirmish_node: Node3D):
	skirmish = skirmish_node
	var difficulty = skirmish.ai_difficulty if "ai_difficulty" in skirmish else "normal"
	var timer_mult = DIFFICULTY_TIMER_MULT.get(difficulty, 1.0)
	produce_interval = PRODUCE_INTERVAL * timer_mult
	wave_interval = WAVE_INTERVAL * timer_mult
	var pity_mult = DIFFICULTY_PITY_MULT.get(difficulty, 1.0)
	pity_metal = int(PITY_METAL * pity_mult)
	pity_crystal = int(PITY_CRYSTAL * pity_mult)
	wave_timer = wave_interval - FIRST_WAVE_DELAY * timer_mult # first wave after FIRST_WAVE_DELAY (scaled)

func _physics_process(delta):
	if not skirmish or skirmish.game_over: return

	produce_timer += delta
	wave_timer += delta
	harvester_check_timer += delta
	structure_check_timer += delta

	if produce_timer >= produce_interval:
		produce_timer = 0.0
		_try_produce()

	if wave_timer >= wave_interval:
		wave_timer = 0.0
		_launch_wave()

	if harvester_check_timer >= 10.0:
		harvester_check_timer = 0.0
		_ensure_harvester()
		# Small pity trickle so the AI never fully stalls
		skirmish.add_resources(team, pity_metal, pity_crystal)

	if structure_check_timer >= STRUCTURE_CHECK_INTERVAL:
		structure_check_timer = 0.0
		_rebuild_lost_manufactories()
		_build_power_plant_if_needed()
		_defend_hq_if_under_attack()

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const BuildingScript = preload("res://scripts/building.gd")

func _combat_roster() -> Array:
	var list = []
	for entry in skirmish.enemy_roster:
		if entry.is_defense: continue
		# Defensive - the bundled enemy blueprints are legal by construction,
		# but the AI should never waste resources building a design that
		# can't actually do anything, same gate the player is held to.
		if not ModuleCatalog.validate_build_legality(entry.blueprint).valid: continue
		var is_harv = false
		for mod in entry.blueprint.get("modules", []):
			if mod.get("type_id", "") == "resource_harvester":
				is_harv = true
				break
		if not is_harv:
			list.append(entry)
	return list

# --- Counter-picking (FABLE_REVIEW.md 2.1) ---
# A crude but real read of what the player is fielding, so the AI's next
# build feels like a response instead of a fixed cycle - the review's own
# suggested minimum viable version. Two clear signals only: lots of air,
# lots of heavy armor. If either is a real majority of the player's live
# combat units, bias toward an affordable roster entry that actually answers
# it; otherwise (or if the roster has no such entry available right now)
# fall through unchanged to the existing round-robin cycle below - this is a
# bias layered on the existing production loop, not a replacement for it.
const ANTI_AIR_WEAPONS = ["ciws", "flak_cannon", "pd_laser"]
const ANTI_ARMOR_WEAPONS = ["gauss_railgun", "artillery", "ion_cannon", "tesla_coil"]
const COUNTER_SCOUT_MIN_UNITS = 2
const COUNTER_SCOUT_MAJORITY = 0.4

func _scout_player_threat() -> String:
	var units = skirmish.get_team_units(0, true)
	if units.size() < COUNTER_SCOUT_MIN_UNITS:
		return ""
	var flying = 0
	var armored = 0
	for u in units:
		if not is_instance_valid(u): continue
		if "is_flying" in u and u.is_flying:
			flying += 1
		if is_instance_valid(u.hull_node) and u.hull_node.has_meta("armor_thickness") and u.hull_node.get_meta("armor_thickness") >= 2.0:
			armored += 1
	# Air checked first: an armored flyer should still draw AA - air is the
	# harder problem for this roster (auto-hit + the air-pierce bug 1.8 fixed
	# were both about how dominant airborne already is).
	if float(flying) / units.size() >= COUNTER_SCOUT_MAJORITY:
		return "air"
	if float(armored) / units.size() >= COUNTER_SCOUT_MAJORITY:
		return "armor"
	return ""

func _entry_counters(entry, threat: String) -> bool:
	var weapon_list = ANTI_AIR_WEAPONS if threat == "air" else ANTI_ARMOR_WEAPONS
	for mod in entry.blueprint.get("modules", []):
		if mod.get("type_id", "") in weapon_list:
			return true
	return false

# Shared by both the counter-pick and round-robin paths: an AI-only
# self-throttle (never queue more than 2 deep per tier - keeps the AI from
# dumping its whole bankroll into one tier's line the instant it can afford
# to) in front of the real production path (RTS_CORE_ROADMAP.md A1's
# production.enqueue(), the same one skirmish.gd's build bar calls). Returns
# whether it actually queued.
func _queue_entry(entry) -> bool:
	var tier = ModuleCatalog.get_hull_size_tier(entry.blueprint.get("hull_type", "medium_hull"))
	if skirmish.production.queue_depth(team, tier) >= 2:
		return false
	return skirmish.production.enqueue(team, entry.blueprint, skirmish.enemy_faction, entry.cost_metal, entry.cost_crystal).queued

func _try_produce():
	var combat = _combat_roster()
	if combat.is_empty(): return

	var threat = _scout_player_threat()
	if threat != "":
		for entry in combat:
			if _entry_counters(entry, threat) and _queue_entry(entry):
				return

	# Cycle through the roster; skip what we don't have the right manufactory
	# tier for yet (size-tiered manufactories - see ModuleCatalog.
	# get_hull_size_tier()) or that tier's queue is already at its self-
	# throttle depth. RTS_CORE_ROADMAP.md D1: no longer skips on
	# affordability - queuing something the AI can't yet fully afford is
	# fine now, it just drip-feeds/pauses like anything else once it's the
	# front item. Checked per-entry, not once upfront, since different
	# roster entries can need different tiers.
	for i in range(combat.size()):
		var entry = combat[(roster_index + i) % combat.size()]
		if _queue_entry(entry):
			roster_index = (roster_index + i + 1) % combat.size()
			return

func _ensure_harvester():
	for u in skirmish.get_team_units(team):
		if u.is_harvester:
			return
	var harv_bp = skirmish._find_harvester_blueprint(skirmish.enemy_roster)
	if harv_bp.is_empty(): return
	var cost = skirmish.blueprint_cost(harv_bp)
	skirmish.production.enqueue(team, harv_bp, skirmish.enemy_faction, cost.x, cost.y)

# RTS_CORE_ROADMAP.md 1.3, items 1-2: "the enemy AI has never placed a
# building" - the base was pre-placed complete at match start and the AI
# never rebuilt a destroyed manufactory or reacted to its own low-power
# state. Both queue through the exact same production.enqueue_structure()
# the player's build bar calls (D4's drip-fed cost, C2's legality) - the
# only AI-specific part is _skip-if-already-pending, since a rebuild takes
# real build time and skirmish.gd's has_factory_of_tier()/get_team_factory()
# both correctly exclude a still-under-construction (build_incomplete)
# manufactory, which would otherwise look "missing" and re-queue every
# check forever.
func _structure_pending(kind: String) -> bool:
	for job in skirmish.production.get_queue(team, "structures"):
		if job.info.kind == kind:
			return true
	for b in skirmish.get_team_buildings(team):
		if b.kind == kind and b.build_incomplete:
			return true
	return false

func _rebuild_lost_manufactories() -> void:
	for tier in MANUFACTORY_TIERS:
		if skirmish.has_factory_of_tier(team, tier):
			continue
		var kind = tier + "_manufactory"
		if _structure_pending(kind):
			continue
		var stats = BuildingScript.PREFAB_STATS[kind]
		skirmish.production.enqueue_structure(team, {"kind": kind, "cost_metal": stats.cost_metal, "cost_crystal": stats.cost_crystal})

func _build_power_plant_if_needed() -> void:
	if not skirmish.is_low_power(team):
		return
	if _structure_pending("power_plant"):
		return
	var stats = BuildingScript.PREFAB_STATS["power_plant"]
	skirmish.production.enqueue_structure(team, {"kind": "power_plant", "cost_metal": stats.cost_metal, "cost_crystal": stats.cost_crystal})

# RTS_CORE_ROADMAP.md 1.3, item 3: "place defenses near the HQ under
# attack" - checked once per STRUCTURE_CHECK_INTERVAL against the HQ's OWN hp
# delta since the last check (no separate damage-event signal exists on
# building.gd, and this is cheap and reliable enough at an 8s cadence: any
# real attack drops HQ hp measurably within one window). Placement reuses
# _find_ai_build_position()'s default anchor (the team's own HQ) with the
# defense's real 28m leash, so "near the HQ" falls straight out of the
# existing C3 adjacency rule with no special-casing.
func _defense_roster() -> Array:
	var list = []
	for entry in skirmish.enemy_roster:
		if not entry.is_defense: continue
		if not ModuleCatalog.validate_build_legality(entry.blueprint).valid: continue
		list.append(entry)
	return list

func _defend_hq_if_under_attack() -> void:
	var hq = skirmish._get_slot(team).get("hq")
	if not is_instance_valid(hq) or hq.is_dead:
		return
	if _last_hq_hp < 0.0:
		_last_hq_hp = hq.hp
		return
	var took_damage = hq.hp < _last_hq_hp - 0.01
	_last_hq_hp = hq.hp
	if not took_damage:
		return

	var live_defenses = 0
	for b in skirmish.get_team_buildings(team):
		if b.kind == "defense":
			live_defenses += 1
	if live_defenses >= MAX_AI_DEFENSES:
		return
	if _structure_pending("defense"):
		return

	var defenses = _defense_roster()
	if defenses.is_empty():
		return
	var cheapest = defenses[0]
	for e in defenses:
		if e.cost_metal + e.cost_crystal < cheapest.cost_metal + cheapest.cost_crystal:
			cheapest = e
	skirmish.production.enqueue_structure(team, {"kind": "defense", "blueprint": cheapest.blueprint, "cost_metal": cheapest.cost_metal, "cost_crystal": cheapest.cost_crystal})

func _launch_wave():
	wave_number += 1
	var units = skirmish.get_team_units(team, true)
	if units.is_empty(): return
	var target = skirmish.player_hq
	if not is_instance_valid(target) or target.is_dead:
		return
	for u in units:
		u.order_attack(target)
