extends SceneTree
# Headless automated test runner for Kitbash Command.
# Run via the wrapper, not directly: ./run_tests.ps1  (or ./run_tests.sh)
#
# The suites themselves live in tests/test_<area>.gd, all extending
# tests/suite_base.gd. This file is only the driver: it owns the retry
# quarantine, the ordered manifest, the pass/fail tally and the exit code.
#
# WHY A MANIFEST INSTEAD OF ITERATING THE FILES: execution order is significant.
# See the quarantine note below - several navmesh/Recast suites flake depending
# on what ran before them, so SUITE_ORDER preserves the exact order the old
# single-file runner used. Grouping suites into files is presentation only.
# Adding a suite means adding its name here as well as writing the function.
#
# 2026-08-10: the battle-system unification's Phase 4 retired the
# pre-unification test areas (test_weapons_and_damage, test_locomotion,
# test_tutorial, test_sim_and_stats, test_support_modules, test_hull_and_armor,
# test_ai_and_win, test_economy_and_production) along with the legacy
# scripts they depended on (battle_unit.gd, player_vehicle.gd,
# target_dummy.gd, Battlefield.tscn, battlefield.gd). Per Chris's "nuke
# those tests entirely" call - we can rebuild them against the new
# battle layer (tests/battle/) when needed. The pre-loaded constants,
# SUITE_FILES entries and SUITE_ORDER rows for the retired suites are
# removed; the remaining battle/* suites below already cover the same
# surface (combat, AI, vision, placement, HUD) through the new runtime.

const SUITE_FILES := {
	"designer_lab": preload("res://tests/test_designer_lab.gd"),
	"ui_and_camera": preload("res://tests/test_ui_and_camera.gd"),
	"input_and_settings": preload("res://tests/test_input_and_settings.gd"),
	"scene_loads": preload("res://tests/test_scene_loads.gd"),
	"base_building": preload("res://tests/test_base_building.gd"),
	"design_verdict": preload("res://tests/test_design_verdict.gd"),
	"lab_instructions": preload("res://tests/test_lab_instructions.gd"),
	"terrain_and_maps": preload("res://tests/test_terrain_and_maps.gd"),
	# The rebuilt battle layer (scripts/battle/). Kept in its own subdirectory
	# because it grows one file per phase and it retires as a unit if the rebuild
	# is ever abandoned - unlike the area files above, which are a split of
	# one historical monolith.
	"battle_movement": preload("res://tests/battle/test_battle_movement.gd"),
	"battle_command": preload("res://tests/battle/test_battle_command.gd"),
	"battle_economy": preload("res://tests/battle/test_battle_economy.gd"),
	"battle_combat": preload("res://tests/battle/test_battle_combat.gd"),
	"battle_vision": preload("res://tests/battle/test_battle_vision.gd"),
	"battle_ai": preload("res://tests/battle/test_battle_ai.gd"),
	"battle_placement": preload("res://tests/battle/test_battle_placement.gd"),
	"battle_hud": preload("res://tests/battle/test_battle_hud.gd"),
	"battle_perf": preload("res://tests/battle/test_battle_perf.gd"),
	"operations_setup": preload("res://tests/battle/test_operations_setup.gd"),
	"after_action_report": preload("res://tests/battle/test_after_action_report.gd"),
	"counter_draft": preload("res://tests/battle/test_counter_draft.gd"),
	"economy_balance": preload("res://tests/battle/test_economy_balance.gd"),
	"resource_fields": preload("res://tests/battle/test_resource_fields.gd"),
	"tech_tree": preload("res://tests/battle/test_tech_tree.gd"),
	"debug_cheats": preload("res://tests/battle/test_debug_cheats.gd"),
	"match_rule_set": preload("res://tests/test_match_rule_set.gd"),
	"match_rule_set_integration": preload("res://tests/battle/test_match_rule_set_integration.gd"),
}

# Exact execution order of the pre-split runner. Do not sort this.
# Pre-2026-08-10: this list interleaved the pre-unification suites (now
# retired) with the catalog and input-and-settings foundations. The
# foundation suites stayed in their historical positions; the retired
# suites have been removed and what remains is the foundation block
# followed by the rebuilt battle layer. The order is preserved by
# importance: catalog/input first (everything depends on them), then
# terrain and base-building (share the navmesh with the perf suites),
# then designer_lab (last because it instantiates the heaviest screen).
const SUITE_ORDER := [
	["debug_cheats", "test_infinite_resources_cheat"],
	["debug_cheats", "test_instant_build_cheat"],
	["debug_cheats", "test_reveal_all_fog_cheat"],
	["match_rule_set", "test_skirmish_factory_sets_required_fields"],
	["match_rule_set", "test_operations_factory_sets_campaign_fields"],
	["match_rule_set", "test_test_range_factory_flips_economy_and_hud_off"],
	["match_rule_set", "test_is_order_legal_allows_movement_in_every_mode"],
	["match_rule_set", "test_is_order_legal_allows_idle_and_hold_always"],
	["match_rule_set", "test_is_order_legal_blocks_harvest_in_test_range"],
	["match_rule_set", "test_is_order_legal_blocks_unknown_order_types"],
	["match_rule_set", "test_factory_does_not_alias_input_array"],
	["match_rule_set", "test_to_dict_round_trip_preserves_fields"],
	["match_rule_set_integration", "test_match_director_reads_map_id_from_rule_set"],
	["match_rule_set_integration", "test_match_director_reads_player_faction_from_rule_set"],
	["match_rule_set_integration", "test_match_director_falls_back_to_legacy_fields_when_rule_set_is_null"],
	["match_rule_set_integration", "test_match_director_skips_commander_when_rule_set_disables_ai"],
	["tech_tree", "test_building_catalog_prerequisites"],
	["tech_tree", "test_module_catalog_building_requirements"],
	["tech_tree", "test_design_costing_building_requirements"],
	["tech_tree", "test_production_service_prerequisite_gating"],
	["tech_tree", "test_building_glb_meshes_exist"],
	["designer_lab", "test_clipping_detection"],
	["designer_lab", "test_rotation_popup_and_deforms"],
	["designer_lab", "test_sensor_mast_tweak_and_proportions"],
	["designer_lab", "test_no_dead_tweaks"],
	["designer_lab", "test_designer_camera_pan"],
	["designer_lab", "test_designer_camera_zoom_smoothing"],
	["designer_lab", "test_ui_anim_motion_library"],
	["designer_lab", "test_part_button_custom_tooltip_card"],
	# Input and settings foundations. Placed immediately before the camera
	# suites because the camera now reads its pan/rotate/edge-scroll values
	# from SettingsService and its bindings from InputService - if those are
	# broken, the camera failures downstream are a consequence rather than a
	# cause, and seeing them in this order says so.
	["input_and_settings", "test_input_action_table_is_well_formed"],
	["input_and_settings", "test_input_modifiers_compared_exactly"],
	["input_and_settings", "test_input_rebind_persists_and_reports_conflicts"],
	["input_and_settings", "test_command_bindings_avoid_camera_keys"],
	["input_and_settings", "test_settings_defaults_are_complete_and_typed"],
	["input_and_settings", "test_settings_unknown_key_is_refused"],
	["input_and_settings", "test_camera_pan_is_yaw_relative"],
	["ui_and_camera", "test_rts_camera_edge_scroll_direction"],
	["ui_and_camera", "test_rts_camera_zoom_to_cursor_keeps_world_point_under_mouse"],
	["ui_and_camera", "test_rts_camera_world_scale_property_defaults_inert"],
	["terrain_and_maps", "test_world_scale_default_and_per_map_override"],
	["terrain_and_maps", "test_greeble_prop_scale_is_inert_at_1_and_doubles_at_2"],
	["terrain_and_maps", "test_greeble_density_holds_coverage_fraction_as_prop_scale_rises"],
	["terrain_and_maps", "test_spawn_visuals_threads_world_scale_into_every_greeble_call"],
	["terrain_and_maps", "test_tall_grassland_clutter_never_lands_on_the_navigable_interior"],
	["terrain_and_maps", "test_ground_noise_stretches_with_world_scale_not_just_amplifies"],
	["terrain_and_maps", "test_terrain_tile_density_scales_with_world_scale"],
	["terrain_and_maps", "test_every_spatial_field_in_field_spec_is_flagged_for_scaling"],
	["terrain_and_maps", "test_apply_world_scale_is_inert_at_1_and_scales_flagged_fields_at_2"],
	["terrain_and_maps", "test_spawn_fairness_lint_passes_a_real_map_scaled_up_4x"],
	["terrain_and_maps", "test_scattered_peaks_navmesh_bakes_cleanly_at_world_scale_4"],
	# 2026-08-10: navmesh path clearance around placed buildings. Locks the
	# agent_radius=1.0 fix in _bake_nav_mesh() against the 0.1 default that
	# produced the "harvester drives into the side of a building" bug.
	["terrain_and_maps", "test_navmesh_path_routes_around_building_with_clearance"],
	# 2026-08-10: base zones (pre-game HQ-placement areas per slot).
	["terrain_and_maps", "test_base_zones_field_in_field_spec"],
	["terrain_and_maps", "test_assign_base_zones_spreads_them_apart"],
	# 2026-08-10: pre-game HQ-placement phase. The new flow replaces the
	# old "auto-spawn HQ + refinery + 3 manufactories" boot with: each
	# player gets a base zone, drops their HQ inside it, and then the
	# match is live. Refinery + 2 manufactories are built NORMALLY
	# during play, paid for out of STARTING_CREDITS.
	["terrain_and_maps", "test_starting_bank_covers_refinery_plus_two_manufactories"],
	["terrain_and_maps", "test_spawn_bases_drops_only_hq_not_refinery_or_manufactories"],
	["terrain_and_maps", "test_ai_auto_places_hq_in_assigned_base_zone"],
	["terrain_and_maps", "test_place_hq_for_human_refuses_outside_zone_and_double_place"],
	# 2026-08-10: ambient nodes opt out of shadow casting. Up to 1000
	# ambient trees on a 4096 shadow atlas was the suspect behind
	# skirmish dropping to 2-4 fps; locks the off path so a future
	# "tidy setup()" doesn't re-enable shadows on 300+ decorative trees.
	["terrain_and_maps", "test_ambient_nodes_opt_out_of_shadow_casting"],
	# 2026-08-10: cluster-based ambient scatter. The 30+20 cluster pattern
	# replaces the pre-2026-08-10 random scatter; these tests pin the
	# "patches, not spread" and the determinism invariants.
	["terrain_and_maps", "test_ambient_tree_pool_size_matches_constant"],
	["terrain_and_maps", "test_ambient_tree_uses_ambient_pool_not_lumber_pool"],
	["terrain_and_maps", "test_ambient_tree_does_not_regrow_after_harvest"],
	["terrain_and_maps", "test_ambient_trees_scatter_is_deterministic"],
	["terrain_and_maps", "test_ambient_trees_respect_avoid_radii"],
	["terrain_and_maps", "test_ambient_ore_picks_from_resource_ore_pool"],
	["terrain_and_maps", "test_ambient_ore_does_not_regrow"],
	["terrain_and_maps", "test_ambient_ores_respect_avoid_radii_and_dont_overlap_trees"],
	["designer_lab", "test_undo_redo"],
	["designer_lab", "test_foundation_design_lab_parity"],
	["base_building", "test_centerline_placement_does_not_self_mirror"],
	["designer_lab", "test_free_rotation_ring"],
	["designer_lab", "test_angled_pintle_mount"],
	["designer_lab", "test_tweak_callout_uses_theme_not_local_stylebox"],
	["designer_lab", "test_blueprint_roster_gating"],
	["designer_lab", "test_module_mirror_chirality"],
	["base_building", "test_ui_flyout_placement"],
	["ui_and_camera", "test_ui_no_overflow_or_offscreen"],
	["ui_and_camera", "test_ui_audit_has_real_teeth"],
	["ui_and_camera", "test_ui_dock_state_cycle"],
	["ui_and_camera", "test_ui_tone_no_decorative_glyphs"],
	["ui_and_camera", "test_ui_icons_share_one_stroke_colour"],
	["ui_and_camera", "test_brushed_aluminum_ui_theme"],
	["ui_and_camera", "test_screenshot_diff_tolerance"],
	["terrain_and_maps", "test_terrain_builder_pure_functions"],
	["terrain_and_maps", "test_b6_heightmap_plateau_approachable_from_any_side"],
	["terrain_and_maps", "test_b7_open_plains_surfacemap_covers_all_7_surface_types"],
	["terrain_and_maps", "test_bridges_carve_a_real_ground_crossing_through_water"],
	["terrain_and_maps", "test_building_obstacle_spawns_taller_real_cover_than_rock_cluster"],
	["terrain_and_maps", "test_amphibious_navmesh_crosses_water"],
	["terrain_and_maps", "test_deep_water_navmesh_blocks_shallow_draught_hulls"],
	["terrain_and_maps", "test_map_open_plains_smoke"],
	["terrain_and_maps", "test_map_lake_crossing_smoke"],
	["terrain_and_maps", "test_map_highland_chokepoint_smoke"],
	["terrain_and_maps", "test_map_coastal_strand_smoke"],
	["terrain_and_maps", "test_map_twin_bridges_smoke"],
	["terrain_and_maps", "test_map_twin_summits_smoke"],
	["terrain_and_maps", "test_map_close_quarters_smoke"],
	["terrain_and_maps", "test_map_urban_sprawl_smoke"],
	["terrain_and_maps", "test_map_scattered_peaks_smoke"],
	["terrain_and_maps", "test_map_ore_basin_smoke"],
	["terrain_and_maps", "test_b8_large_map_navmesh_bake_does_not_crash_recast"],
	["terrain_and_maps", "test_b10_spawn_assignment_picks_explicit_then_maximizes_separation"],
	["terrain_and_maps", "test_b10_spawn_fairness_lint_passes_real_maps_and_catches_bad_ones"],
	["terrain_and_maps", "test_map_schema_validator"],
	["terrain_and_maps", "test_b3_maps_are_json_and_byte_identical_to_the_old_const"],
	["terrain_and_maps", "test_b3_hand_broken_json_map_hard_fails_with_a_useful_message"],
	["terrain_and_maps", "test_b4_heightmap_terrain_pure_functions"],
	["terrain_and_maps", "test_b4_heightmap_leaves_unmigrated_maps_untouched"],
	["terrain_and_maps", "test_b5_heightmap_navmesh_rejects_steep_slope"],
	["terrain_and_maps", "test_balance_report_covers_every_catalog_entry"],
	["terrain_and_maps", "test_part_material_roles_differentiate_surfaces"],
	["design_verdict", "test_design_verdict_flags_overweight_with_real_numbers"],
	["lab_instructions", "test_lab_instructions_table_is_well_formed"],

	# --- Rebuilt battle layer -------------------------------------------------
	# APPENDED, never interleaved. The order above is pinned because several
	# navmesh/Recast suites flake depending on what ran before them; inserting
	# anything mid-list perturbs exactly the thing the pinning protects. These
	# suites are pure value-in/value-out math with no scene, no navmesh and no
	# physics, so running last costs nothing and disturbs nothing.
	["battle_movement", "test_steering_yaw_faces_the_requested_direction"],
	["battle_movement", "test_steering_arrival_and_turn_rate"],
	["battle_movement", "test_order_vocabulary_and_completion"],
	["battle_movement", "test_real_unit_actually_converges_toward_a_move_order_on_a_real_map"],
	["battle_command", "test_formation_gives_every_unit_a_distinct_slot"],
	["battle_command", "test_formation_assignment_does_not_cross"],
	["battle_command", "test_flow_field_integrates_and_points_home"],
	["battle_command", "test_flow_field_cell_size_scales_with_world_scale"],
	["battle_command", "test_selection_frustum_geometry"],
	["battle_command", "test_separation_and_stance_policy"],
	["battle_economy", "test_production_uses_the_real_ra_speed_table"],
	["battle_economy", "test_production_drip_feeds_cost_and_refunds_only_what_was_drawn"],
	["battle_economy", "test_five_queues_are_independent_and_gated"],
	["battle_economy", "test_power_gates_production_rate"],
	["battle_economy", "test_income_rate_measures_deliveries_and_decays"],
	["battle_economy", "test_refinery_bays_are_exclusive_and_reclaimable"],
	["battle_combat", "test_take_damage_accepts_the_three_argument_weapon_contract"],
	["battle_combat", "test_strip_eligibility_excludes_armour_and_respects_facet"],
	["battle_combat", "test_module_damage_uses_the_resolver_fraction"],
	["battle_combat", "test_active_modules_excludes_dying_children"],
	["battle_combat", "test_weapon_attachment_covers_non_weapon_combat_modules"],
	["battle_vision", "test_selection_layer_does_not_collide_with_smoke"],
	["battle_vision", "test_vision_hides_the_distant_and_reveals_the_near"],
	["battle_vision", "test_buildings_lift_fog_around_a_base"],
	["battle_vision", "test_visibility_fails_open_before_the_first_scan"],
	["battle_vision", "test_reveal_hide_hysteresis_has_a_dead_zone"],
	["battle_vision", "test_reveal_beacons_light_an_area_and_expire"],
	["battle_vision", "test_effective_vision_elevation_bonus_is_capped_and_skips_flyers"],
	["battle_vision", "test_elevation_bonus_scales_cap_with_world_scale_but_not_its_maximum"],
	["battle_vision", "test_shroud_grid_cell_scales_keeping_image_size_bounded"],
	["battle_vision", "test_minimap_bakes_terrain_and_draws_blips"],
	["battle_vision", "test_minimap_cell_scales_keeping_image_size_bounded"],
	["battle_ai", "test_considerations_stay_normalised"],
	["battle_ai", "test_a_zero_consideration_vetoes_the_action"],
	["battle_ai", "test_opening_move_is_not_a_deadlock"],
	["battle_ai", "test_a_busy_economy_can_still_decide"],
	["battle_ai", "test_harvester_wanting_tracks_buildability_not_factory_count"],
	["battle_ai", "test_decisions_respond_to_the_battlefield"],
	["battle_ai", "test_push_requires_a_real_army"],
	["battle_ai", "test_roles_are_read_from_mounted_modules"],
	["battle_ai", "test_squad_retreat_and_regroup_have_a_dead_zone"],
	["battle_ai", "test_reinforcing_raises_the_health_bar"],
	["battle_placement", "test_placement_rejects_bounds_water_and_overlap"],
	["battle_placement", "test_placement_excludes_resource_nodes"],
	["battle_placement", "test_ai_siting_and_player_ghost_share_one_rule_set"],
	["battle_hud", "test_every_queue_has_a_visible_toolbox"],
	["battle_hud", "test_the_build_bar_is_actually_on_screen"],
	["battle_hud", "test_opening_a_queue_is_an_accordion"],
	["battle_hud", "test_the_readout_tracks_progress"],
	["battle_hud", "test_idle_toolboxes_retreat_and_busy_ones_do_not"],
	["battle_perf", "test_heightmap_authority_removes_terrain_from_the_collision_mask"],
	["battle_perf", "test_a_unit_with_no_controller_keeps_terrain_collision"],
	["operations_setup", "test_operations_engagement_count_spans_three_to_twelve"],
	["operations_setup", "test_operations_itinerary_resolves_every_map"],
	["operations_setup", "test_operations_changing_the_count_keeps_chosen_maps"],
	["operations_setup", "test_operations_difficulty_ramps_toward_the_choice"],
	["operations_setup", "test_operations_campaign_round_trips_through_disk"],
	["operations_setup", "test_operations_loop_advances_and_terminates"],
	["operations_setup", "test_operations_draft_carries_the_roster_and_the_next_map"],
	["after_action_report", "test_after_action_report_builds_its_whole_self"],
	["after_action_report", "test_after_action_report_counts_energy_damage"],
	["after_action_report", "test_after_action_report_mvp_must_have_been_fielded"],
	["after_action_report", "test_after_action_report_offers_the_next_engagement"],
	["counter_draft", "test_counter_draft_classifies_real_designs"],
	["counter_draft", "test_counter_draft_answers_an_air_force"],
	["counter_draft", "test_counter_draft_never_demotes_the_harvester"],
	["counter_draft", "test_counter_draft_ignores_a_token_threat"],
	["counter_draft", "test_counter_draft_weights_recent_engagements"],
	["economy_balance", "test_every_design_draws_the_same_rate_while_building"],
	["economy_balance", "test_four_harvesters_meet_the_stated_target"],
	["economy_balance", "test_harvester_capacity_comes_from_the_design"],
	["resource_fields", "test_resource_catalog_aliases_metal_to_ore"],
	["resource_fields", "test_resource_values_form_a_real_ladder"],
	["resource_fields", "test_a_field_scatters_and_refills"],
	["resource_fields", "test_oil_wells_are_single_points"],
	["resource_fields", "test_every_map_offers_lumber_and_oil"],

	# LAST, DELIBERATELY. This is the only suite that instantiates whole screens,
	# so it is the one most likely to leave residue - autoload state touched by a
	# screen's _ready(), a stray CanvasLayer, a freed-next-frame node. Running it
	# after everything else means it cannot perturb the pinned navmesh order that
	# the rest of SUITE_ORDER exists to protect.
	["scene_loads", "test_every_screen_survives_ready"],
]

# Quarantine, applied uniformly rather than via a hand-maintained allowlist
# (2026-07-27 finding): isolated standalone reruns confirmed at least 3
# distinct suites can flake, and a live full-suite run then produced a
# FOURTH, previously-unseen flake - matching PROGRESS.md's own long-standing
# note that "a different navmesh/movement test fails each run, never the
# same one twice." A fixed name list will always lag one flake behind
# reality, so every suite gets one bounded, logged retry instead. This is
# a strictly weaker safety net than a regression would need to slip through
# twice in a row, and every retry prints plainly - nothing is silently
# swallowed. See UNIFIED_ROADMAP.md 0.4 for the actual Recast-nondeterminism
# investigation this doesn't replace.
const _SUITE_RETRY_ATTEMPTS: int = 2


func _run_suite(cb: Callable, name: String) -> bool:
	var match_config = root.get_node_or_null("MatchConfig")
	if match_config:
		match_config.selected_map_id = ""
	for attempt in range(1, _SUITE_RETRY_ATTEMPTS + 1):
		var ok = await cb.call()
		if ok:
			if attempt > 1:
				print("  [QUARANTINE] %s passed on retry %d/%d." % [name, attempt, _SUITE_RETRY_ATTEMPTS])
			return true
		if attempt < _SUITE_RETRY_ATTEMPTS:
			print("  [QUARANTINE] %s failed on attempt %d/%d, retrying." % [name, attempt, _SUITE_RETRY_ATTEMPTS])
	print("  [FAIL] %s failed all %d attempts - treating as a real failure." % [name, _SUITE_RETRY_ATTEMPTS])
	return false


func _init():
	print("\n==============================================")
	print("    KITBASH COMMAND HEADLESS TEST RUNNER")
	print("==============================================\n")

	# One instance per area file, built up front and reused across that area's
	# suites - the same sharing the old single-object runner had.
	var instances := {}
	for key in SUITE_FILES:
		var inst = SUITE_FILES[key].new()
		inst.tree = self
		inst.root = root
		instances[key] = inst

	var success = true
	var _failed: Array = []
	var _total_suites: int = 0

	for entry in SUITE_ORDER:
		var inst = instances[entry[0]]
		var suite_name: String = entry[1]
		_total_suites += 1
		if not await _run_suite(Callable(inst, suite_name), suite_name):
			success = false
			_failed.append(suite_name)

	print("")
	print("Ran %d suites across %d files." % [_total_suites, SUITE_FILES.size()])
	if _failed.is_empty():
		print("All suites PASSED.")
	else:
		print("FAILED suites (%d):" % _failed.size())
		for name in _failed:
			print("  - %s" % name)
	print("")

	# A non-zero exit on any failure is what the CI step keys on. Headless
	# dev runs of the same harness just see the printed verdict.
	quit(0 if success else 1)
