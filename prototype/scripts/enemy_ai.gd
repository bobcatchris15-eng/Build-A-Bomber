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
var roster_index: int = 0
var wave_number: int = 0

const PRODUCE_INTERVAL: float = 14.0
const FIRST_WAVE_DELAY: float = 60.0
const WAVE_INTERVAL: float = 55.0

func setup(skirmish_node: Node3D):
	skirmish = skirmish_node
	wave_timer = WAVE_INTERVAL - FIRST_WAVE_DELAY # first wave after FIRST_WAVE_DELAY

func _physics_process(delta):
	if not skirmish or skirmish.game_over: return

	produce_timer += delta
	wave_timer += delta
	harvester_check_timer += delta

	if produce_timer >= PRODUCE_INTERVAL:
		produce_timer = 0.0
		_try_produce()

	if wave_timer >= WAVE_INTERVAL:
		wave_timer = 0.0
		_launch_wave()

	if harvester_check_timer >= 10.0:
		harvester_check_timer = 0.0
		_ensure_harvester()
		# Small pity trickle so the AI never fully stalls
		skirmish.add_resources(team, 10, 3)

const ModuleCatalog = preload("res://scripts/module_catalog.gd")

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

func _try_produce():
	var factory = skirmish.get_team_factory(team)
	if not factory or factory.production_queue.size() >= 2:
		return
	var combat = _combat_roster()
	if combat.is_empty(): return
	# Cycle through the roster; skip what we can't afford
	for i in range(combat.size()):
		var entry = combat[(roster_index + i) % combat.size()]
		if skirmish.can_afford(team, entry.cost_metal, entry.cost_crystal):
			skirmish.spend(team, entry.cost_metal, entry.cost_crystal)
			var build_time = skirmish.build_time_for_cost(Vector2i(entry.cost_metal, entry.cost_crystal))
			if skirmish.is_energy_deficit(team):
				build_time *= 1.5
			factory.queue_unit(entry.blueprint, build_time)
			roster_index = (roster_index + i + 1) % combat.size()
			return

func _ensure_harvester():
	for u in skirmish.get_team_units(team):
		if u.is_harvester:
			return
	var harv_bp = skirmish._find_harvester_blueprint(skirmish.enemy_roster)
	if harv_bp.is_empty(): return
	var cost = skirmish.blueprint_cost(harv_bp)
	var factory = skirmish.get_team_factory(team)
	if factory and skirmish.can_afford(team, cost.x, cost.y):
		skirmish.spend(team, cost.x, cost.y)
		factory.queue_unit(harv_bp, skirmish.build_time_for_cost(cost))

func _launch_wave():
	wave_number += 1
	var units = skirmish.get_team_units(team, true)
	if units.is_empty(): return
	var target = skirmish.player_hq
	if not is_instance_valid(target) or target.is_dead:
		return
	for u in units:
		u.order_attack(target)
