class_name LabDocument
extends Control
var telemetry_rail
var lab_toolbar
var tweak_callout_manager


const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const UIFlyoutScript = preload("res://scripts/ui_flyout.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")

# --- Rail structure (VISUAL/UI plan item 7) ---------------------------------
# The rail used to be a bare anchored `Panel` in UI_StatBlock.tscn carrying an
# embedded StyleBoxFlat sub-resource (PanelStyle_Stats). Both are gone: the
# surface is a UIDock built in _ready(), which brings the STEEL frame, the
# POWDERCOAT body, the three collapse states and width persistence with it.
#
# EVERY @onready BELOW STAYS VALID ACROSS THAT MOVE. `$Path` resolves once, at
# _ready(), and stores an object reference - reparenting the subtree afterwards
# does not invalidate a reference, only a re-resolved path. The nine places that
# re-resolved `$ScrollContainer/VBoxContainer` on every call are the ones that
# had to change; they use `_rail_vbox` now, captured before the move.
var stats_dock: Control = null
var _slot_hull_label: Label = null
var _slot_parts_label: Label = null
var _slot_cost_label: Label = null
var _rail_vbox: VBoxContainer = null

# The current design's headline stats, published by update_stats() for readers
# that want the numbers rather than the label text - fleet_comparison_panel.gd
# is the existing one. `drivetrain` is the whole Drivetrain.analyze() result
# (weight, capacity, load_ratio, top_speed, move_speed, is_overloaded, ...),
# so a new reader does not need a new field here for every figure it wants.
var total_hp: float = 0.0
var total_weight: float = 0.0
var total_dps: float = 0.0
var drivetrain: Dictionary = {}
var weapon_range: Dictionary = {}


@onready var hp_label = $ScrollContainer/VBoxContainer/HPLabel
@onready var weight_label = $ScrollContainer/VBoxContainer/WeightLabel
@onready var cost_label = $ScrollContainer/VBoxContainer/CostLabel
@onready var dps_label = $ScrollContainer/VBoxContainer/DPSLabel
@onready var mirror_checkbox = $ScrollContainer/VBoxContainer/MirrorCheckBox
@onready var delete_button = $ScrollContainer/VBoxContainer/DeleteButton
@onready var save_button = $ScrollContainer/VBoxContainer/SaveButton
@onready var test_button = $ScrollContainer/VBoxContainer/TestButton
@onready var blueprint_name_edit = $ScrollContainer/VBoxContainer/BlueprintNameEdit
@onready var library_button = $ScrollContainer/VBoxContainer/LibraryButton

@onready var locomotion_tweaks = $ScrollContainer/VBoxContainer/LocomotionTweaks
@onready var size_container = $ScrollContainer/VBoxContainer/LocomotionTweaks/SizeContainer
@onready var size_label = $ScrollContainer/VBoxContainer/LocomotionTweaks/SizeContainer/SizeLabel
@onready var size_slider = $ScrollContainer/VBoxContainer/LocomotionTweaks/SizeContainer/SizeSlider
@onready var count_container = $ScrollContainer/VBoxContainer/LocomotionTweaks/CountContainer
@onready var count_slider = $ScrollContainer/VBoxContainer/LocomotionTweaks/CountContainer/CountSlider
@onready var count_label = $ScrollContainer/VBoxContainer/LocomotionTweaks/CountContainer/CountLabel


const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
# Drivetrain and WeaponRange are no longer preloaded here: both are now called
# by design_stats.gd, which hands their results back in its return value, so this
# file has no direct use for either.
var current_selected_module: Node3D = null
var is_updating_sliders: bool = false
var _loco_slider_dragging: bool = false
var module_tweaks_container: VBoxContainer

# Which tweaks-dict key the shared "Size" slider writes, per locomotion
# type_id - used to route size_slider changes through
# update_locomotion_geometry_tweak() (no respawn) instead of the full
# update_locomotion() respawn _apply_tweaks() uses for count changes.
const LOCOMOTION_SIZE_KEY := {
	"wheels": "wheel_size",
	"tracked_treads": "tread_width",
	"helicopter_rotors": "blade_length",
	"legs": "leg_length",
	"hover_engine": "emv_level",
	"fixed_wing_engine": "turbine_compression",
	"screw_drive": "drum_diameter",
	"pontoon_wheels": "pontoon_size",
	"ornithopter_wing": "wingspan",
	"half_track": "tread_width",
	"rocker_bogie": "wheel_size",
	"air_cushion_skirt": "skirt_diameter",
	"anti_grav_plate": "field_strength",
}

const LOCOMOTION_SECONDARY_SIZE_KEY := {
	"helicopter_rotors": "blade_count",
	"buoyant_envelope": "blade_pitch",
	"screw_drive": "helix_depth",
	"ornithopter_wing": "wing_sweep",
	"half_track": "front_axle_size",
	"rocker_bogie": "arm_length",
	"air_cushion_skirt": "plenum_pressure",
}

# Floating Popup Window fields
var tweak_canvas: Control
var popup_name_label: Label
var popup_stats_label: Label
var popup_tweaks_container: VBoxContainer
var popup_rotate_btn: Button

const TWEAK_SPECS = {
	"basic_cannon": [
		{"name": "caliber", "label": "Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_count", "label": "Barrel Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 1.0},
	],
	"heavy_machine_gun": [
		{"name": "caliber", "label": "Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "multi_barrel", "label": "Multi-Barrel Mode", "type": "bool", "default": false},
		{"name": "drum_size", "label": "Ammo Drum Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"rotary_cannon": [
		{"name": "caliber", "label": "Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_count", "label": "Barrel Count", "min": 3.0, "max": 9.0, "step": 1.0, "default": 6.0},
		{"name": "motor_size", "label": "Electric Motor Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"gauss_railgun": [
		{"name": "caliber", "label": "Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "rail_length", "label": "Electromagnetic Rail Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"artillery": [
		{"name": "caliber", "label": "Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_count", "label": "Barrel Count", "min": 1.0, "max": 2.0, "step": 1.0, "default": 1.0},
	],
	"mortar_array": [
		{"name": "caliber", "label": "Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Mortar Tube Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "tube_count", "label": "Mortar Tube Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 2.0},
	],
	"guided_missile": [
		{"name": "seeker_size", "label": "Missile Diameter", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "engine_length", "label": "Launch Tube Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_count", "label": "Launcher Tube Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 1.0},
	],
	"missile_pod": [
		{"name": "warhead_size", "label": "Rocket Warhead Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "motor_length", "label": "Rocket Motor Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "grid_size", "label": "Rocket Grid Size", "min": 2.0, "max": 6.0, "step": 1.0, "default": 4.0}
	],
	"cluster_dispenser": [
		{"name": "dispersion", "label": "Dispersion Spread Radius", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "payload_size", "label": "Canister Payload Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "tube_count", "label": "Projector Tube Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 2.0}
	],
	"flamethrower": [
		{"name": "nozzle_width", "label": "Emitter Nozzle Width", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "pressure_valve", "label": "Pressure Fuel Valve", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"heavy_laser": [
		{"name": "lens_aperture", "label": "Laser Lens Aperture", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Optical Telescope Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"plasma_lobber": [
		{"name": "containment", "label": "Plasma Chamber Diameter", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Accelerator Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"ciws": [
		{"name": "caliber", "label": "Rotary Gun Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Rotary Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "radar_dish", "label": "CIWS Tracking Radar Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"pd_laser": [
		{"name": "cooling_jacket", "label": "PD Laser Cooling Jacket", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Emitter Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"flak_cannon": [
		{"name": "caliber", "label": "Flak Cannon Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Flak Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_count", "label": "Flak Barrel Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 2.0},
		{"name": "fuse_setting", "label": "Proximity Fuse Setter", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	# --- Roster expansion ---
	# Every tweak name below is reused from the existing vocabulary
	# (ModuleCatalog.LINEAR_SCALE_WEAPON_TWEAKS / module_data.gd's scaling
	# lists) rather than invented, so weight/cost/dps/range/traverse
	# scaling all work for these weapons with no new plumbing.
	"mk19_grenade_launcher": [
		{"name": "caliber", "label": "Grenade Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "drum_size", "label": "Belt Box Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"recoilless_rifle": [
		{"name": "caliber", "label": "Bore Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Tube Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"coil_gun": [
		{"name": "caliber", "label": "Slug Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "rail_length", "label": "Accelerator Stage Count", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"autocannon": [
		{"name": "caliber", "label": "Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "drum_size", "label": "Ammo Drum Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	# Precision, not volume: no drum/ammo tweak at all, because "carry more
	# rounds" is not a question this weapon asks. optic_power is its
	# distinguishing slider (reach, at real crystal cost), and bipod_deploy
	# is the discrete capability trade - see auto_weapon's BIPOD_ constants.
	"anti_materiel_rifle": [
		{"name": "caliber", "label": "Calibre", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Barrel Length", "min": 0.6, "max": 2.2, "step": 0.1, "default": 1.0},
		{"name": "optic_power", "label": "Optic Power", "min": 0.7, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "bipod_deploy", "label": "Deploy Bipod", "min": 0.0, "max": 1.0, "step": 1.0, "default": 0.0},
	],
	"chaff_dispenser": [
		{"name": "tube_count", "label": "Cartridge Tubes", "min": 2.0, "max": 8.0, "step": 1.0, "default": 4.0},
	],
	"laser_dazzler": [
		{"name": "lens_aperture", "label": "Emitter Aperture", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
	],
	"aps_interceptor": [
		{"name": "fuse_setting", "label": "Intercept Fuse", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
	],
	"aa_autocannon": [
		{"name": "caliber", "label": "Calibre", "min": 0.6, "max": 1.6, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Barrel Length", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
	],
	"jammer_mast": [
		{"name": "mast_height", "label": "Mast Height", "min": 0.6, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"sentry_deployer": [
		{"name": "hangar_size", "label": "Sentries Carried", "min": 1.0, "max": 3.0, "step": 1.0, "default": 2.0},
	],
	"sensor_beacon_launcher": [
		{"name": "payload_size", "label": "Beacon Size", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
	],
	"decoy_projector": [
		{"name": "payload_size", "label": "Decoy Size", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
	],
	"spigot_mortar": [
		{"name": "rod_thickness", "label": "Spigot Rod", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
		{"name": "payload_size", "label": "Bomb Size", "min": 0.6, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"rocket_artillery": [
		{"name": "tube_count", "label": "Rail Count", "min": 2.0, "max": 8.0, "step": 1.0, "default": 4.0},
		{"name": "dispersion", "label": "Salvo Spread", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"hypervelocity_missile": [
		{"name": "tube_count", "label": "Canister Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 2.0},
		{"name": "seeker_size", "label": "Designator Power", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
	],
	"sam_launcher": [
		{"name": "tube_count", "label": "Rail Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 2.0},
		{"name": "radar_dish", "label": "Tracking Radar", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
	],
	"loitering_munition": [
		{"name": "tube_count", "label": "Tube Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 2.0},
		{"name": "seeker_size", "label": "Loiter Endurance", "min": 0.6, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"anti_radiation_missile": [
		{"name": "tube_count", "label": "Rail Count", "min": 1.0, "max": 3.0, "step": 1.0, "default": 2.0},
		{"name": "seeker_size", "label": "ESM Sensitivity", "min": 0.6, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"bunker_buster": [
		{"name": "warhead_size", "label": "Penetrator Mass", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
		{"name": "ascent_thruster", "label": "Top-Attack Climb", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
	],
	"cruise_missile": [
		{"name": "warhead_size", "label": "Warhead Size", "min": 0.6, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "motor_length", "label": "Fuel Load", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
	],
	"napalm_mortar": [
		{"name": "caliber", "label": "Canister Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Mortar Tube Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"mine_layer": [
		{"name": "tube_count", "label": "Mines Per Volley", "min": 1.0, "max": 4.0, "step": 1.0, "default": 1.0},
		{"name": "payload_size", "label": "Mine Charge Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"ballista": [
		{"name": "caliber", "label": "Bolt Thickness", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Draw Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	# Tube count is the discharger's one real handle: more tubes means more
	# canisters per volley and so a wider screen, at the usual weight/cost.
	"smoke_discharger": [
		{"name": "tube_count", "label": "Discharger Tube Count", "min": 2.0, "max": 6.0, "step": 1.0, "default": 4.0},
	],
	"resource_harvester": [
		{"name": "cutter_head", "label": "Drill Head Diameter", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "mount_extension", "label": "Mount Extension", "min": 0.6, "max": 1.5, "step": 0.1, "default": 1.0}
	],
	# Three levers, and they are deliberately not three flavours of the same one.
	# bay_volume is the stat that matters (cargo carried, and the weight paid for
	# it); hopper_depth and hatch_width are pure geometry, changing how the bay
	# reads on the hull and how much deck it eats without touching capacity - the
	# bay is a big part and where it fits is a real constraint on a crowded
	# harvester. Sizing tweaks with no stat behind them would normally be dead
	# tweaks, but these two change the module's own footprint, which is what
	# decides whether a third bay fits at all.
	"resource_bay": [
		{"name": "bay_volume", "label": "Bay Volume", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "hopper_depth", "label": "Hopper Depth", "min": 0.6, "max": 1.6, "step": 0.1, "default": 1.0},
		{"name": "hatch_width", "label": "Hatch Width", "min": 0.6, "max": 1.6, "step": 0.1, "default": 1.0}
	],
	"repair_array": [
		{"name": "welder_count", "label": "Welder Arm Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 2.0},
		{"name": "arm_reach", "label": "Manipulator Arm Reach", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"sensor_suite": [
		{"name": "mast_height", "label": "Radar Mast Height", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "dish_aperture", "label": "Radar Dish Diameter", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"energy_barrier_projector": [
		{"name": "projector_diameter", "label": "Array Diameter", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "coil_count", "label": "Capacitor Coil Count", "min": 2.0, "max": 6.0, "step": 1.0, "default": 4.0}
	],
	"laser_designator": [
		{"name": "optic_aperture", "label": "Optics Aperture", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "mast_extension", "label": "Targeting Mast Height", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"fire_control_radar": [
		{"name": "radar_size", "label": "Array Face Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "array_faces", "label": "Radar Panel Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 2.0}
	],
	"capacitor_bank": [
		{"name": "bank_capacity", "label": "Capacitor Cell Count", "min": 2.0, "max": 6.0, "step": 1.0, "default": 4.0},
		{"name": "busbar_gauge", "label": "Busbar Gauge", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"flywheel_storage": [
		{"name": "rotor_mass", "label": "Flywheel Rotor Mass", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "containment_armor", "label": "Containment Armor", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"solid_state_battery": [
		{"name": "cell_layers", "label": "Cell Pack Layers", "min": 2.0, "max": 6.0, "step": 1.0, "default": 4.0},
		{"name": "dielectric_thickness", "label": "Dielectric Density", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"fusion_generator": [
		{"name": "reactor_length", "label": "Reactor Core Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "cooling_radiator", "label": "Cooling Radiator Fins", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"diesel_generator": [
		{"name": "engine_displacement", "label": "Turbine Displacement", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "radiator_fins", "label": "Exhaust & Cooling Louvers", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"thermo_generator": [
		{"name": "core_diameter", "label": "Thermal Core Diameter", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "heatsink_fins", "label": "Heat Pipe Runners", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	# Previously documented in Arsenal_Weapons_List.md but missing from this
	# dict entirely - drone_carrier rendered zero tweak sliders in the
	# Design Lab (ENERGY_AND_BALANCE_SPEC.md #3).
	# drone_type is handled by a dedicated RadialAmmoSelector in
	# tweak_callout_manager.gd (see the drone_carrier branch in
	# _generate_custom_tweaks) and must NOT be included here — the
	# parametric loop only handles numeric and bool specs.
	"drone_carrier": [
		{"name": "hangar_size", "label": "Hangar Size (Drone Count)", "min": 1.0, "max": 5.0, "step": 1.0, "default": 2.0},
		{"name": "launch_catapult", "label": "Launch Catapult", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	# Energy weapons (ENERGY_AND_BALANCE_SPEC.md #5)
	"tesla_coil": [
		{"name": "caliber", "label": "Coil Charge Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	"arc_projector": [
		{"name": "containment", "label": "Arc Containment Field", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	# dish_aperture is the classic width-vs-reach trade made physical: a
	# bigger dish spreads the cone wider and shortens it, which the player can
	# predict from the model before touching the slider.
	"microwave_emitter": [
		{"name": "dish_aperture", "label": "Dish Aperture", "min": 0.6, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	# charge_time buys per-shot damage with exposure: a longer wind-up is more
	# time an alert enemy has to kill you before the shot lands. focal_length
	# scales the accelerator spine alone.
	"particle_lance": [
		{"name": "charge_time", "label": "Capacitor Charge", "min": 0.6, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "focal_length", "label": "Accelerator Length", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
	],
	"ion_cannon": [
		{"name": "lens_aperture", "label": "Ion Focusing Lens", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
	],
	# --- Propulsion modules (speed pass, 2026-08-08) ---
	# Every tweak name here is reused from LINEAR_SCALE_WEAPON_TWEAKS/
	# module_data.gd's scaling lists rather than invented, so weight/cost
	# scaling works with no new plumbing - the same convention the roster
	# expansion weapons above already follow.
	"turbocharger": [
		{"name": "turbine_compression", "label": "Turbine Compression", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "intake_size", "label": "Intake Size", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0}
	],
	"overdrive_gearbox": [
		{"name": "motor_size", "label": "Gearcase Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"hub_motor_array": [
		{"name": "motor_size", "label": "Hub Motor Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "coil_count", "label": "Stator Coil Count", "min": 2.0, "max": 8.0, "step": 1.0, "default": 4.0}
	],
	"nitrous_injector": [
		{"name": "drum_size", "label": "Coolant Bottle Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "pressure_valve", "label": "Feed Pressure", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"booster_rack": [
		{"name": "nozzle_count", "label": "Booster Tube Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 3.0},
		{"name": "motor_length", "label": "Booster Tube Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	]
}

var armor_mat_btn: OptionButton
var armor_thick_label: Label
var armor_thick_slider: HSlider

# --- Hull spec flyout (VISUAL/UI plan item 7) -------------------------------
# Armour material, faction and armour thickness used to be six controls parked
# permanently in the right rail, visible whether or not they applied to
# anything. They are hull-level settings a player touches a few times per
# design, so they now live behind one toolbar-style trigger.
#
# The controls themselves are created once and REUSED, never rebuilt per open,
# because every one of them is wired to an undo push and a stat recompute and
# rebuilding them would mean reconnecting all of that on each open. When the
# flyout closes they are reparented back into `hull_spec_stash` - the same
# stash-and-reparent idiom _add_callout() already uses for tweak widgets, for
# the same reason: a transient panel frees its children, and these must outlive
# it.
#
# The faction dropdown that used to live here is GONE. Faction is a battle-time
# property now, not a design-time one: reconstruct_vehicle()'s
# match_faction_override has always had the final word at spawn, so a Lab
# selector could only ever preview a livery that the match would overwrite -
# and it also tinted the Lab's own stat readout with that faction's passives,
# so the numbers a player tuned against were not the numbers the unit fielded
# under whichever faction they actually picked at match setup. The Lab now
# shows an unpainted design at its base stats, and both the paint and the
# passives are applied once, at battle time.
var hull_spec_stash: VBoxContainer
var _hull_spec_flyout: Node = null

# Wheels-only "dually" tweak (wheels_per_axle, 1-2): no scene node for this
# exists in UI_StatBlock.tscn (only the generic Size/Count sliders shared by
# every locomotion type), so it's built dynamically here rather than in the
# scene - added as a sibling of SizeContainer/CountContainer inside
# LocomotionTweaks so it reads as part of the same panel instead of a separate
# floating control.
var wheels_per_axle_container: HBoxContainer
var leg_type_container: VBoxContainer
var leg_type_button: OptionButton
var leg_type_desc: Label
var leg_width_container: HBoxContainer
var leg_width_label: Label
var leg_width_slider: HSlider
var wheels_per_axle_label: Label
var wheels_per_axle_slider: HSlider

# "Blade Count" tweak (blade_count, 2-8): same dynamic-widget pattern as
# wheels_per_axle above. Pure per-instance geometry (the ring in
# _build_helicopter_rotors()/_build_pylon_mounted_propeller()), no effect
# on collider or instance count, so it's always routed through
# update_locomotion_geometry_tweak(), never a respawn - same as
# tread_width. Originally helicopter_rotors-only; shared with naval_
# propeller/buoyant_envelope (Chris's ask, 2026-07-24) since all three now
# build a ring of blades the same way.
var blade_count_container: HBoxContainer
var blade_count_label: Label
var blade_count_slider: HSlider

# "Blade Pitch" tweak (blade_pitch, 0.5-1.5): buoyant_envelope originally
# (Chris's ask, 2026-07-24) - same dynamic-widget/geometry-tweak pattern as
# blade_count above. Now also reused (relabelled) by several other types'
# secondary slider - see the elif chain below.
var blade_pitch_container: HBoxContainer
var blade_pitch_label: Label
var blade_pitch_slider: HSlider

# "Helix Depth" tweak (helix_depth, 0.5-1.5): screw_drive only (Chris's
# ask, 2026-07-24) - same dynamic-widget pattern as blade_pitch above.
# Picks among 3 discrete authored drum variants in _build_screw_drive()
# rather than a continuous deformation, but the slider itself is a plain
# continuous 0.5-1.5 control like any other.
var helix_depth_container: HBoxContainer
var helix_depth_label: Label
var helix_depth_slider: HSlider

# helicopter_rotors-only "Ducted Shroud" tweak (duct, bool): same dynamic-
# widget pattern as above. Pure geometry (spawns/removes the duct ring in
# _build_helicopter_rotors()), routed through update_locomotion_geometry_
# tweak() like blade_count, not a respawn.
var duct_container: HBoxContainer
var duct_checkbox: CheckBox
# The checkbox is shared between helicopter_rotors' "Ducted Shroud" and
# pontoon_wheels' "Paddle Vanes" - which tweak key it writes and what its
# callout is titled are set per type in show_module_stats(), the same way the
# Blade Count slider is shared. Hardcoding the key is what silently no-opped
# that slider for two types before.
var bool_tweak_key := "duct"
var bool_tweak_title := "Ducted"

func _ready():
	add_to_group("stat_ui")

	# The Design Lab bed plus a workshop room tone. Deliberately the sparsest
	# track in the game (no kit, no hook, no melody) because the Lab is where a
	# player sits longest on one concentrated task - see tools/audio/tracks/lab.py.
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.play_music("lab")
		audio.play_ambience("ambience_lab")
	# Captured BEFORE _build_rail_dock() moves the subtree, because this one is
	# used as a parent for dynamically-added rows throughout the file.
	# Resolved here because the rest of _ready() adds rows to it. The dock itself
	# is built at the END of _ready() - see the call there for why the order
	# matters.
	_rail_vbox = $ScrollContainer/VBoxContainer
	telemetry_rail = preload("res://scripts/telemetry_rail.gd").new(self)
	lab_toolbar = preload("res://scripts/lab_toolbar.gd").new(self)
	tweak_callout_manager = preload("res://scripts/tweak_callout_manager.gd").new(self)
	
	var parts_menu = get_parent().get_node_or_null("UI_PartsMenu")
	if parts_menu:
		parts_menu.part_hovered.connect(_on_part_hovered)
		parts_menu.part_unhovered.connect(_on_part_unhovered)

	# Theme variations rather than four hand-picked fill colors.
	#
	# These used to be a saturated red, green, blue and purple slab stacked
	# in a column, which spent the loudest colors on screen on four buttons
	# that are not urgent, and left nothing to escalate to when something
	# actually goes wrong. It also meant the Design Lab's palette existed
	# nowhere else in the game.
	#
	# Now: Delete is the only destructive action here, so it is the only one
	# carrying alert red. Save is the commit action, so it takes the single
	# go-green. Test and Library are ordinary navigation and stay neutral -
	# they are reachable, not important.
	# The four blocks that used to sit here built a "plastic model kit sprue gate"
	# StyleBoxFlat per button - a green Save, an amber Test, a CYAN Library and a
	# red Delete, each with its own hover variant and font colour. They are gone,
	# and the paragraph above is now true instead of aspirational: the comment
	# already described theme variations as the intent while the code below it did
	# the exact opposite, so the design system could not reach the four loudest
	# controls in the Design Lab.
	#
	# Where the four states live now:
	#   Delete  -> DangerButton  (FIBERGLASS hazard placard) - set in the .tscn
	#   Save    -> PrimaryButton (CARBON, cast toward go-green) - set in the .tscn
	#   Test    -> plain Button  (MOULDED). Reclassified: it was marked
	#              DangerButton in UI_StatBlock.tscn, but running a test is not
	#              destructive, and spending alert red on it left nothing to
	#              escalate to. It is navigation.
	#   Library -> plain Button  (MOULDED). Its cyan appears nowhere in
	#              ui_tokens.gd; it was the last survivor of the old sci-fi accent.
	save_button.text = "SAVE BLUEPRINT"
	test_button.text = "TEST IN ARENA"
	test_button.theme_type_variation = ""
	library_button.text = "BLUEPRINT LIBRARY"
	delete_button.text = "DISCARD PART"

	lab_toolbar._build_mirror_icon()
	mirror_checkbox.toggled.connect(_on_mirror_toggled)
	delete_button.pressed.connect(_on_delete_pressed)
	save_button.pressed.connect(_on_save_pressed)
	test_button.pressed.connect(_on_test_pressed)
	library_button.pressed.connect(_on_library_pressed)
	blueprint_name_edit.text_changed.connect(_on_blueprint_name_changed)
	lab_toolbar._setup_name_roller()
	
	size_slider.value_changed.connect(_on_size_value_changed)
	size_slider.custom_minimum_size = Vector2(180, 0)
	count_slider.value_changed.connect(_on_count_value_changed)
	count_slider.custom_minimum_size = Vector2(180, 0)
	# Size never changes how many module instances exist for ANY locomotion
	# type (only Count does) - it's a purely cosmetic per-instance geometry
	# tweak, so it's routed through update_locomotion_geometry_tweak() (an
	# in-place mesh rebuild on every existing instance, same idea as a
	# weapon's rebuild_visual - see that function in module_placer.gd) on
	# EVERY value_changed tick, live and smooth, no debounce needed. Count IS
	# structural (adds/removes instances), so it still goes through the full
	# update_locomotion() respawn - but debounced to drag-END: applying that
	# full respawn on every tick during a drag reselects an arbitrary
	# instance each time, which relocates the floating popup (it tracks the
	# selected module's 3D->2D screen position every frame) and made a real
	# mouse drag land on the wrong final slider position relative to where
	# the panel had jumped to mid-drag - confirmed via a real simulated-
	# mouse-drag test, not just a direct function call.
	size_slider.drag_started.connect(_push_undo)
	count_slider.drag_started.connect(_on_loco_drag_started)
	count_slider.drag_ended.connect(_on_loco_drag_ended)

	# Dynamically build the wheels-only "Wheels Per Axle" slider (dually
	# tweak) and insert it right after CountContainer inside LocomotionTweaks.
	wheels_per_axle_container = HBoxContainer.new()
	wheels_per_axle_container.custom_minimum_size = Vector2(0, 24)
	wheels_per_axle_container.add_theme_constant_override("separation", 4)
	locomotion_tweaks.add_child(wheels_per_axle_container)
	locomotion_tweaks.move_child(wheels_per_axle_container, count_container.get_index() + 1)

	wheels_per_axle_label = Label.new()
	wheels_per_axle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wheels_per_axle_label.text = "Wheels Per Axle:"
	wheels_per_axle_container.add_child(wheels_per_axle_label)

	wheels_per_axle_slider = HSlider.new()
	wheels_per_axle_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wheels_per_axle_slider.size_flags_stretch_ratio = 2.0
	wheels_per_axle_slider.min_value = 1.0
	wheels_per_axle_slider.max_value = 2.0
	wheels_per_axle_slider.step = 1.0
	wheels_per_axle_slider.value = 1.0
	wheels_per_axle_slider.custom_minimum_size = Vector2(180, 0)
	wheels_per_axle_container.add_child(wheels_per_axle_slider)
	wheels_per_axle_slider.value_changed.connect(_on_wheels_per_axle_changed)
	wheels_per_axle_slider.drag_started.connect(_push_undo)
	wheels_per_axle_container.visible = false

	# Dynamically build the helicopter_rotors-only "Blade Count" slider.
	blade_count_container = HBoxContainer.new()
	blade_count_container.custom_minimum_size = Vector2(0, 24)
	blade_count_container.add_theme_constant_override("separation", 4)
	locomotion_tweaks.add_child(blade_count_container)
	locomotion_tweaks.move_child(blade_count_container, wheels_per_axle_container.get_index() + 1)

	blade_count_label = Label.new()
	blade_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blade_count_label.text = "Blade Count:"
	blade_count_container.add_child(blade_count_label)

	blade_count_slider = HSlider.new()
	blade_count_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blade_count_slider.size_flags_stretch_ratio = 2.0
	blade_count_slider.min_value = 2.0
	blade_count_slider.max_value = 8.0
	blade_count_slider.step = 1.0
	blade_count_slider.value = 4.0
	blade_count_slider.custom_minimum_size = Vector2(180, 0)
	blade_count_container.add_child(blade_count_slider)
	blade_count_slider.value_changed.connect(_on_blade_count_changed)
	blade_count_slider.drag_started.connect(_push_undo)
	blade_count_container.visible = false

	# Dynamically build the buoyant_envelope-only "Blade Pitch" slider
	# (Chris's ask, 2026-07-24).
	blade_pitch_container = HBoxContainer.new()
	blade_pitch_container.custom_minimum_size = Vector2(0, 24)
	blade_pitch_container.add_theme_constant_override("separation", 4)
	locomotion_tweaks.add_child(blade_pitch_container)
	locomotion_tweaks.move_child(blade_pitch_container, blade_count_container.get_index() + 1)

	blade_pitch_label = Label.new()
	blade_pitch_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blade_pitch_label.text = "Blade Pitch:"
	blade_pitch_container.add_child(blade_pitch_label)

	blade_pitch_slider = HSlider.new()
	blade_pitch_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blade_pitch_slider.size_flags_stretch_ratio = 2.0
	blade_pitch_slider.min_value = 0.5
	blade_pitch_slider.max_value = 1.5
	blade_pitch_slider.step = 0.1
	blade_pitch_slider.value = 1.0
	blade_pitch_slider.custom_minimum_size = Vector2(180, 0)
	blade_pitch_container.add_child(blade_pitch_slider)
	blade_pitch_slider.value_changed.connect(_on_blade_pitch_changed)
	blade_pitch_slider.drag_started.connect(_push_undo)
	blade_pitch_container.visible = false

	# Dynamically build the screw_drive-only "Helix Depth" slider.
	helix_depth_container = HBoxContainer.new()
	helix_depth_container.custom_minimum_size = Vector2(0, 24)
	helix_depth_container.add_theme_constant_override("separation", 4)
	locomotion_tweaks.add_child(helix_depth_container)
	locomotion_tweaks.move_child(helix_depth_container, blade_pitch_container.get_index() + 1)

	helix_depth_label = Label.new()
	helix_depth_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	helix_depth_label.text = "Helix Depth:"
	helix_depth_container.add_child(helix_depth_label)

	helix_depth_slider = HSlider.new()
	helix_depth_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	helix_depth_slider.size_flags_stretch_ratio = 2.0
	helix_depth_slider.min_value = 0.5
	helix_depth_slider.max_value = 1.5
	helix_depth_slider.step = 0.1
	helix_depth_slider.value = 1.0
	helix_depth_slider.custom_minimum_size = Vector2(180, 0)
	helix_depth_container.add_child(helix_depth_slider)
	helix_depth_slider.value_changed.connect(_on_helix_depth_changed)
	helix_depth_slider.drag_started.connect(_push_undo)
	helix_depth_container.visible = false

	# Dynamically build the helicopter_rotors-only "Ducted Shroud" checkbox.
	duct_container = HBoxContainer.new()
	duct_container.custom_minimum_size = Vector2(0, 24)
	duct_container.add_theme_constant_override("separation", 4)
	locomotion_tweaks.add_child(duct_container)
	locomotion_tweaks.move_child(duct_container, helix_depth_container.get_index() + 1)

	duct_checkbox = CheckBox.new()
	duct_checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duct_container.add_child(duct_checkbox)
	duct_checkbox.toggled.connect(_on_duct_toggled)
	duct_container.visible = false

	# The legs-only "Leg Width" slider. Its partner, Leg Length, rides the shared
	# Size slider via LOCOMOTION_SIZE_KEY; width needs its own because a type can
	# only claim one entry there.
	leg_width_container = HBoxContainer.new()
	leg_width_container.custom_minimum_size = Vector2(0, 24)
	leg_width_container.add_theme_constant_override("separation", 4)
	locomotion_tweaks.add_child(leg_width_container)
	locomotion_tweaks.move_child(leg_width_container, duct_container.get_index() + 1)

	leg_width_label = Label.new()
	leg_width_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leg_width_label.text = "Leg Width:"
	leg_width_container.add_child(leg_width_label)

	leg_width_slider = HSlider.new()
	leg_width_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leg_width_slider.size_flags_stretch_ratio = 2.0
	leg_width_slider.min_value = 0.5
	leg_width_slider.max_value = 2.0
	leg_width_slider.step = 0.05
	leg_width_slider.value = 1.0
	leg_width_slider.custom_minimum_size = Vector2(180, 0)
	leg_width_container.add_child(leg_width_slider)
	leg_width_slider.value_changed.connect(_on_leg_width_changed)
	leg_width_slider.drag_started.connect(_push_undo)
	leg_width_container.visible = false

	# The legs-only "Leg Set" picker. A dropdown plus a description line, which
	# is the same two-control shape the weapon ammo selector uses (see
	# _generate_custom_tweaks) - and deliberately so, because it is the same
	# kind of choice: one named variant out of a short list, changing real
	# stats, rather than a number to drag.
	leg_type_container = VBoxContainer.new()
	leg_type_container.add_theme_constant_override("separation", 2)
	locomotion_tweaks.add_child(leg_type_container)
	locomotion_tweaks.move_child(leg_type_container, duct_container.get_index() + 1)

	var leg_type_caption = Label.new()
	leg_type_caption.text = "Leg Set:"
	leg_type_container.add_child(leg_type_caption)

	leg_type_button = OptionButton.new()
	leg_type_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for leg_id in ModuleCatalog.get_leg_options():
		leg_type_button.add_item(ModuleCatalog.get_leg_profile(leg_id).label)
	leg_type_container.add_child(leg_type_button)

	leg_type_desc = Label.new()
	leg_type_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	leg_type_desc.custom_minimum_size.x = 220
	leg_type_desc.add_theme_font_size_override("font_size", 11)
	leg_type_desc.modulate = Color(1, 1, 1, 0.65)
	leg_type_container.add_child(leg_type_desc)

	leg_type_button.item_selected.connect(_on_leg_type_selected)
	leg_type_container.visible = false

	# The hull-spec controls. Built here, parked in an invisible stash, and
	# shown in a flyout off the trigger button below - see hull_spec_stash's
	# declaration for why they are reused rather than rebuilt per open.
	hull_spec_stash = VBoxContainer.new()
	hull_spec_stash.visible = false
	add_child(hull_spec_stash)

	var mat_cont = VBoxContainer.new()
	mat_cont.name = "ArmorMaterialContainer"
	var mat_label = Label.new()
	mat_label.text = "Armor Material:"
	mat_cont.add_child(mat_label)
	armor_mat_btn = OptionButton.new()
	armor_mat_btn.add_item("Hardened Steel")
	armor_mat_btn.add_item("Reactive Armor")
	armor_mat_btn.add_item("Ablative Ceramic")
	armor_mat_btn.add_item("Energy Shielding")
	armor_mat_btn.item_selected.connect(_on_armor_mat_selected)
	mat_cont.add_child(armor_mat_btn)
	hull_spec_stash.add_child(mat_cont)

	var thick_cont = VBoxContainer.new()
	thick_cont.name = "ArmorThicknessContainer"
	armor_thick_label = Label.new()
	armor_thick_label.text = "Armor Thickness: 1.0"
	thick_cont.add_child(armor_thick_label)
	armor_thick_slider = HSlider.new()
	armor_thick_slider.min_value = 0.5
	armor_thick_slider.max_value = 3.0
	armor_thick_slider.step = 0.1
	armor_thick_slider.value = 1.0
	armor_thick_slider.value_changed.connect(_on_armor_thick_changed)
	thick_cont.add_child(armor_thick_slider)
	hull_spec_stash.add_child(thick_cont)

	# The trigger. Sits in the rail for now; item 7's top toolbar is where it
	# belongs, and moving it there is a reparent of this one node.
	#
	# Deadpan procurement register per the plan's item 0 - this opens a hull's
	# specification, so it says so, and it carries no glyph.
	# (hull_spec_btn removed as it is no longer used)

	# Create Module Tweaks container
	module_tweaks_container = VBoxContainer.new()
	module_tweaks_container.name = "ModuleTweaksContainer"
	module_tweaks_container.add_theme_constant_override("separation", 8)
	_rail_vbox.add_child(module_tweaks_container)
	
	# Remove popup_panel and use tweak_canvas instead for infographic UI
	tweak_canvas = Control.new()
	tweak_canvas.name = "TweakCanvas"
	tweak_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tweak_canvas)
	
	# We still need popup_tweaks_container as a stash for persistent locomotion containers
	# when they aren't assigned to a TweakCallout.
	popup_tweaks_container = VBoxContainer.new()
	popup_tweaks_container.visible = false
	add_child(popup_tweaks_container)
	
	popup_name_label = Label.new()
	popup_name_label.text = "Module Customization"
	popup_name_label.add_theme_font_size_override("font_size", 16)
	popup_name_label.add_theme_color_override("font_color", Color.GOLD)
	popup_tweaks_container.add_child(popup_name_label)
	
	popup_stats_label = Label.new()
	popup_stats_label.text = ""
	popup_stats_label.add_theme_font_size_override("font_size", 12)
	popup_tweaks_container.add_child(popup_stats_label)
	
	popup_rotate_btn = Button.new()
	popup_rotate_btn.text = "Rotate 90° [R]"
	popup_rotate_btn.add_theme_font_size_override("font_size", 12)
	popup_rotate_btn.pressed.connect(func():
		var root = get_node_or_null("/root/MainLab")
		# NOTE: module_placer.gd is the script on the MainLab ROOT node, not a
		# child called "ModulePlacer" - check scenes/MainLab.tscn, where it is
		# ext_resource "1_placer" on the root. Three call sites here looked up a
		# child by that name, got null, and silently did nothing; the Rotate
		# button in the Design Lab has never worked. _on_delete_pressed() had it
		# right all along, calling root.delete_selected_module() directly.
		if root and root.has_method("rotate_selected_module"):
			root.rotate_selected_module()
	)
	popup_tweaks_container.add_child(popup_rotate_btn)
	
	# Undo/Redo used to be a two-button row stacked in this rail. Design_Lab_UI_UX
	# .md always specified them as a TOP-BAR pair, and VISUAL/UI plan item 7 says
	# the same thing ("Undo/redo belong on a toolbar, not stacked in a stat
	# column"), so they are built in _build_toolbar() now. Their behaviour is
	# unchanged and still mirrors the Ctrl+Z / Ctrl+Y bindings in module_placer.gd.

	# Navigation back to the main menu - captured in a holder, reparented into
	# the top toolbar by _build_toolbar(). It belongs with the document actions
	# (the rest of which moved into the DOCUMENT toolbox body), and it does not
	# belong stacked under the stat readouts - that was the old "everything
	# in the rail" pattern the new layout explicitly replaced.
	var menu_btn = Button.new()
	menu_btn.name = "MainMenuButton"
	menu_btn.text = "Main Menu"
	menu_btn.pressed.connect(lab_toolbar._return_to_menu)
	_rail_vbox.add_child(menu_btn)

	# Locomotion tweaks (Size/Count/Wheels-Per-Axle) move into the same
	# floating popup weapon/armor tweaks use, instead of living in the
	# right-hand sidebar - Chris's ask, "mirroring the weapon module
	# behavior" so every module type's tweaks appear in one consistent
	# place near the selected module. These are reused/reparented (not
	# rebuilt) each selection since on_module_selected()'s popup-clearing
	# sweep below explicitly skips them - see that guard.
	#
	# This is the STASH, not the display path - _add_callout() pulls a widget out
	# of here and into a floating callout when its locomotion type is selected,
	# and _clear_callouts() puts it back. A widget missing from this list still
	# works, because _add_callout() reparents whatever it is given; what it loses
	# is a well-defined home between selections.
	size_container.reparent(popup_tweaks_container)
	count_container.reparent(popup_tweaks_container)
	wheels_per_axle_container.reparent(popup_tweaks_container)
	blade_count_container.reparent(popup_tweaks_container)
	duct_container.reparent(popup_tweaks_container)
	leg_type_container.reparent(popup_tweaks_container)
	leg_width_container.reparent(popup_tweaks_container)
	locomotion_tweaks.visible = false

	# LAST, deliberately. _build_toolbar() reparents controls into the bar, and
	# hull_spec_btn is created partway through this function rather than being an
	# @onready node - building the dock any earlier caught it as null and silently
	# left the flyout trigger stranded in the rail with no error.
	_build_rail_dock()

	# Initial sync of armor UI
	call_deferred("_initial_sync")

const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")

func sync_hull_ui(hull: Node3D):
	# An unnamed design now shows an EMPTY field with a suggestion behind it,
	# not the literal string "Untitled Design". Writing the placeholder into
	# the field is what made it look like a name the player had already
	# supplied - they'd hit Save and get refused by something the UI had
	# filled in for them.
	if not hull:
		if blueprint_name_edit:
			blueprint_name_edit.text = ""
			lab_toolbar._reroll_name_suggestion()
		return
	is_updating_sliders = true
	if blueprint_name_edit:
		var bp_name = str(hull.get_meta("blueprint_name", "")).strip_edges()
		blueprint_name_edit.text = bp_name if BlueprintManagerScript.is_named(bp_name) else ""
		if blueprint_name_edit.text == "":
			lab_toolbar._reroll_name_suggestion()
	if armor_mat_btn:
		var mat = hull.get_meta("armor_material") if hull.has_meta("armor_material") else "hardened_steel"
		match mat:
			"hardened_steel": armor_mat_btn.selected = 0
			"reactive_armor": armor_mat_btn.selected = 1
			"ablative_ceramic": armor_mat_btn.selected = 2
			"energy_shielding": armor_mat_btn.selected = 3
	if armor_thick_slider:
		var thick = hull.get_meta("armor_thickness") if hull.has_meta("armor_thickness") else 1.0
		armor_thick_slider.value = thick
		if armor_thick_label:
			armor_thick_label.text = "Armor Thickness: %.1f" % thick
	# No faction sync: there is no faction control in the Lab any more. A
	# blueprint saved before this change still carries its "faction" key and
	# still deserializes, it simply has no effect until a match assigns one.
	is_updating_sliders = false
	update_stats(hull)

# One stylebox per load state, built on first use and reused - same idiom as
# skirmish.gd's _power_fill_style(). A ProgressBar fill is a STATE indicator,
# which is the documented exception to "no local styleboxes": there is no
# theme-side way to say "this bar is currently in its bad state", and the
# StyleBoxTexture material plates carry no colour channel to vary.
var _load_fill_styles: Dictionary = {}


var _alpha_rows: Array[Label] = []

# The regime column, as it is drawn. Two things carry the state, not one:
#
#   colour - CHIP is SIGNAL_ALERT (this design's shots are being stopped, which
#            is a failure state for the thing being measured), BRUTE is
#            SIGNAL_GO, and the ordinary through-regime keeps StatLabel's own
#            TEXT_SECONDARY so the two extremes are the only rows that pull the
#            eye. Same go/hazard/alert vocabulary the load bar uses for its
#            fill, applied to the same kind of question.
#   case   - the two extremes are SHOUTED and the middle is not. This is not
#            decoration: it is the redundant channel that keeps the regime
#            legible for a colour-blind player, and it survives a greyscale
#            screenshot, which the colour alone does not.
var _callout_dirs = [
	Vector2(0.8, -1.2), Vector2(-0.8, -1.2), # Top corners
	Vector2(1.2, -0.2), Vector2(-1.2, -0.2), # High sides
	Vector2(1.2, 0.6), Vector2(-1.2, 0.6),   # Low sides
	Vector2(0.8, 1.2), Vector2(-0.8, 1.2)    # Bottom corners
]
var _current_callout_idx = 0


# Opens the action ring on `module`.
#
# The ring carries the DISCRETE, mutually-exclusive verbs - rotate, mirror,
# discard - while the callouts carry the CONTINUOUS tweaks. That split is the
# whole reason there are two mechanisms rather than one: a pie slice cannot
# hold a slider, and a sidebar row is a bad place for a verb that applies to a
# thing you are looking at somewhere else.
func _build_rail_dock() -> void:
	var scroll: Node = get_node_or_null("ScrollContainer")
	if scroll == null:
		push_error("stat_calculator: no ScrollContainer to dock")
		return

	var UIDockScript = load("res://scripts/ui_dock.gd")
	stats_dock = UIDockScript.new()
	stats_dock.name = "StatsDock"
	stats_dock.dock_title = "TELEMETRY"
	stats_dock.dock_icon = "info"
	stats_dock.side = UIDockScript.Side.RIGHT
	stats_dock.expanded_size = 320.0
	stats_dock.auto_reveal = false
	stats_dock.default_state = UIDockScript.State.RAILED
	# Persisted separately from the parts catalogue so the two remember their own
	# widths - they are different panels holding different things.
	stats_dock.persist_key = "design_lab_stats"
	stats_dock.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	# Starts below the toolbar, which spans the full width above both docks.
	stats_dock.offset_top = Tokens.TOOLBAR_HEIGHT
	add_child(stats_dock)

	# The dock is added first and the scroll moved into it second, so the scroll
	# never spends a frame parentless (which would drop its scroll offset).
	scroll.reparent(stats_dock.body())
	# The rail's own anchoring came from the deleted Panel's layout; inside a dock
	# body the container drives width, so the offsets have to go or the scroll
	# keeps trying to sit 300px off the right edge of its new parent.
	if scroll is Control:
		var sc := scroll as Control
		sc.set_anchors_preset(Control.PRESET_FULL_RECT)
		sc.offset_left = 0.0
		sc.offset_top = 0.0
		sc.offset_right = 0.0
		sc.offset_bottom = 0.0
		sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_build_admin_toolbox()
	lab_toolbar._build_toolbar()


# --- The right-hand admin toolbox -------------------------------------------
# Chris's model: the right dock is a toolbox that expands into the document
# actions. Uses UIToolbox, the same widget backing the parts catalogue's four
# toolboxes on the opposite edge - it was built here first as a second copy and
# has since been extracted, so both sides are now one implementation.
#
# ADDITIVE ON PURPOSE. This inserts one tier at the TOP of the rail and moves
# nothing that was already there. The telemetry readouts below are positioned by
# INDEX - _build_drivetrain_readout() and _build_range_readout() both use
# _rail_vbox.move_child(x, at + n) to sit their labels directly after the row they
# explain - so re-homing the existing rail contents into tiers would silently
# reorder them. The stat rail is also the most heavily tested part of this screen.
# Restructuring it is a separate change with its own verification.
#
# The action buttons are NEW INSTANCES wired to the same handlers, not the rail's
# originals: those get reparented into the top toolbar by _build_toolbar(), and a
# node has exactly one parent. Chris asked for both, so both exist - the cost is
# that the copies must stay wired to the same methods, which is why they connect
# to _on_save_pressed etc. rather than duplicating any logic.
#
# The DELETE button is the one exception: the rail's original "Delete Selected
# Part" fires the same handler as the toolbox's "DISCARD PART", so showing
# both on screen at once reads as a duplicate rather than as a second entry
# point. The toolbox is the "official" home for document actions, so the
# rail's original is hidden below - the @onready var and its pressed signal
# stay wired, so the Delete keyboard binding keeps working.
func _build_admin_toolbox() -> void:
	if _rail_vbox == null:
		return

	var toolbox := UIToolbox.new()
	# Positive x: this dock is on the RIGHT edge, so content should unfold leftward
	# out of its header rather than in from off-screen.
	toolbox.stagger_from = Vector2(12, 0)
	# Single tier, so it opens with it already up - closing the only thing in the
	# toolbox by default would just hide it.
	var body := toolbox.add_tier("document", "DOCUMENT", true)

	var name_hint := Label.new()
	name_hint.text = "DESIGN NAME"
	name_hint.theme_type_variation = "HintLabel"
	body.add_child(name_hint)

	# The name field itself, moved rather than copied: a LineEdit holds the text
	# that Save reads, so two of them would be two different names.
	if blueprint_name_edit:
		blueprint_name_edit.reparent(body)

	# The Roll button that _setup_name_roller() built beside the name field
	# was originally a sibling of the LineEdit in a BlueprintNameRow in the
	# rail. That row is now orphaned (the LineEdit moved here), so the row
	# moves with the field - both live in the DOCUMENT section, and the
	# BlueprintNameRow's HBoxContainer layout still applies.
	var name_row := _rail_vbox.get_node_or_null("BlueprintNameRow")
	if name_row:
		name_row.reparent(body)
		# Reparent leaves the old FULL_RECT anchors on the row, which would
		# make it fill the body and cover the buttons below. Re-anchor it
		# to the top of the body so it sits between the name_hint label and
		# the action buttons.
		name_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
		name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_admin_action(body, "SAVE BLUEPRINT", _on_save_pressed, "confirm")
	_admin_action(body, "BLUEPRINT LIBRARY", _on_library_pressed, "default")
	_admin_action(body, "DISCARD PART", _on_delete_pressed, "danger")

	_rail_vbox.add_child(toolbox)
	_rail_vbox.move_child(toolbox, 0)

	# Hide the rail's original DeleteButton - the toolbox's DISCARD PART is
	# the visible home for this action. The @onready var and its pressed
	# signal stay wired so the Delete keyboard binding keeps working.
	if delete_button:
		delete_button.visible = false


# One transparent top-bar slot: a caption over a value, with a hairline rule on
# its trailing edge so the row reads as divided cells rather than as drifting text.
#
# Transparent deliberately - the slot is a REGION of the toolbar band, not a panel
# sitting on it. Giving each slot its own plate would stack two materials in a
# 64px strip and make the bar look like a row of buttons, which is the opposite of
# "static info". The only drawn ink is the divider.
func _info_slot(parent: Control, caption: String) -> Label:
	var slot := VBoxContainer.new()
	slot.add_theme_constant_override("separation", 0)
	slot.custom_minimum_size = Vector2(Tokens.SPACE_XL * 3, 0)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(slot)

	var cap := Label.new()
	cap.text = caption
	cap.theme_type_variation = "HintLabel"
	slot.add_child(cap)

	var value := Label.new()
	value.text = "-"
	# HUDValueLabel is the monospace readout variation, so a value changing width
	# does not shove the slots beside it sideways.
	value.theme_type_variation = "HUDValueLabel"
	slot.add_child(value)

	var rule := VSeparator.new()
	parent.add_child(rule)
	return value


# Refreshed from update_stats()' DesignStats result, so the bar and the rail can
# never show different numbers for the same design.
func _update_toolbar_info(hull: Node3D, stats: Dictionary) -> void:
	if _slot_hull_label:
		var hull_type := "-"
		if hull and hull.has_meta("type_id"):
			hull_type = _prettify_id(str(hull.get_meta("type_id")))
		_slot_hull_label.text = hull_type
	if _slot_parts_label:
		var n := 0
		if hull:
			for child in hull.get_children():
				if child.has_meta("module_data"):
					n += 1
		_slot_parts_label.text = str(n)
	if _slot_cost_label:
		# Read from the stats dict rather than recomputed, so the toolbar and the
		# telemetry rail's own Cost row are the same number by construction.
		_slot_cost_label.text = "%d cr" % int(stats.get("cost_credits", 0))


func _prettify_id(id: String) -> String:
	var out: Array = []
	for w in id.split("_"):
		if w.length() > 0:
			out.append(w[0].to_upper() + w.substr(1))
	return " ".join(PackedStringArray(out))


func _admin_action(parent: Control, label: String, handler: Callable, role: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
	if role == "danger":
		btn.theme_type_variation = "DangerButton"
	elif role == "confirm":
		btn.theme_type_variation = "PrimaryButton"
	btn.pressed.connect(handler)
	parent.add_child(btn)
	UIFeedbackScript.wire(btn, role)
	return btn


# The thin top toolbar. STEEL band via HeaderPanel, which already carries the
# hazard underline that separates chrome from viewport.
func _on_hull_spec_pressed() -> void:
	if is_instance_valid(_hull_spec_flyout):
		_hull_spec_flyout.close()
		return

	# Hosted on tweak_canvas, the same floating layer the callouts use.
	#
	# NOT the button's own ancestor: that is the rail's ScrollContainer, which
	# would clip a flyout wider than the rail - and wider than the rail is the
	# normal case, so clipping it there defeats the point of moving these
	# controls out of the rail at all.
	#
	# NOT get_tree().root either, which was the first version. A flyout parented
	# to the viewport outlives the Design Lab scene, so leaving the Lab with one
	# open leaked the panel AND the six reparented controls inside it - they are
	# no longer children of the scene by then, so freeing the scene does not take
	# them with it. tweak_canvas dies with the Lab and takes the flyout along.
	var flyout = UIFlyoutScript.create(tweak_canvas, "Hull Specification")
	_hull_spec_flyout = flyout

	for ctrl in _hull_spec_widgets():
		if is_instance_valid(ctrl):
			ctrl.reparent(flyout.body())

	# Reclaim the controls BEFORE the flyout frees itself. `closed` is emitted at
	# the top of close(), ahead of the queue_free, which is the only point where
	# reparenting is still safe.
	flyout.closed.connect(_on_hull_spec_closed)
	# (Flyout positioning removed since hull_spec_btn is gone)


func _on_hull_spec_closed() -> void:
	for ctrl in _hull_spec_widgets():
		if is_instance_valid(ctrl) and ctrl.get_parent() != hull_spec_stash:
			ctrl.reparent(hull_spec_stash)
	_hull_spec_flyout = null


# Declared in display order once, so open and close cannot disagree about which
# controls belong to the flyout - a mismatch would strand a widget in a freed
# panel and take the control with it.
func _on_armor_mat_selected(idx: int) -> void:
	if is_updating_sliders: return
	var root = get_node_or_null("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null
	if not hull: return
	_push_undo()
	var materials = ["hardened_steel", "reactive_armor", "ablative_ceramic", "energy_shielding"]
	var selected_mat = materials[clampi(idx, 0, materials.size() - 1)]
	hull.set_meta("armor_material", selected_mat)
	update_stats(hull)

func _on_armor_thick_changed(val: float) -> void:
	if is_updating_sliders: return
	var root = get_node_or_null("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null
	if not hull: return
	_push_undo()
	hull.set_meta("armor_thickness", val)
	if armor_thick_label:
		armor_thick_label.text = "Armor Thickness: %.1f" % val
	update_stats(hull)

func _hull_spec_widgets() -> Array:
	var out: Array = []
	if armor_mat_btn and is_instance_valid(armor_mat_btn):
		out.append(armor_mat_btn.get_parent())
	if armor_thick_slider and is_instance_valid(armor_thick_slider):
		out.append(armor_thick_slider.get_parent())
	return out

func _initial_sync():
	var root = get_node_or_null("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null
	if hull:
		if not hull.has_meta("blueprint_name"):
			hull.set_meta("blueprint_name", "Untitled Design")
		sync_hull_ui(hull)

func _process(delta):
	pass

func _on_part_hovered(type_id: String) -> void:
	var root = get_node_or_null("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null
	if hull == null or not is_instance_valid(hull):
		return
		
	var cat = ModuleCatalog.get_module_data(type_id).get("category", "")
	if cat == "hull":
		return # Cannot preview whole hull replacement cleanly
		
	var VisualBuilder = preload("res://scripts/visual_builder.gd")
	var ghost = VisualBuilder.build_module(type_id)
	var mirror = null
	
	if mirror_checkbox and mirror_checkbox.button_pressed:
		var is_symmetric = ModuleCatalog.get_module_data(type_id).get("is_symmetric", true)
		if not is_symmetric:
			mirror = VisualBuilder.build_module(type_id)
			
	# For locomotion, we want to simulate replacing the existing locomotion.
	# We achieve this by temporarily hiding existing locomotion modules from the hull
	# so they are skipped by DesignStatsScript.analyze, which recursively scans visible/valid children.
	var hidden_locomotion = []
	if cat == "locomotion":
		for child in hull.get_children():
			if child is Node3D and child.has_meta("type_id"):
				var child_cat = ModuleCatalog.get_module_data(child.get_meta("type_id")).get("category", "")
				if child_cat == "locomotion" and child.visible:
					child.visible = false
					hidden_locomotion.append(child)
					
	telemetry_rail.update_preview_stats(ghost, mirror)
	
	# Restore hidden locomotion
	for child in hidden_locomotion:
		if is_instance_valid(child):
			child.visible = true
			
	# Free the temporary preview nodes since TelemetryRail removes them from tree after analysis
	ghost.queue_free()
	if mirror:
		mirror.queue_free()

func _on_part_unhovered() -> void:
	telemetry_rail.clear_preview()


# Routed through SceneRouter so leaving this screen fades out rather than cutting.
# The get_node_or_null guard keeps the direct call as a fallback, matching the
# pattern the other router call sites in this file already use - a scene
# instantiated outside the running game (a test fixture) has no autoloads.

func update_stats(hull: Node3D): telemetry_rail.update_stats(hull)
func _push_undo(): lab_toolbar._push_undo()
func _on_delete_pressed(): lab_toolbar._on_delete_pressed()
func _on_save_pressed(): lab_toolbar._on_save_pressed()
func _on_test_pressed(): lab_toolbar._on_test_pressed()
func _on_mirror_toggled(button_pressed: bool): lab_toolbar._on_mirror_toggled(button_pressed)
func _on_library_pressed(): lab_toolbar._on_library_pressed()
func _on_blueprint_name_changed(new_text: String): lab_toolbar._on_blueprint_name_changed(new_text)
func _on_roll_name_pressed(): lab_toolbar._on_roll_name_pressed()

func on_module_selected(module: Node3D): tweak_callout_manager.on_module_selected(module)
func _on_size_value_changed(value: float): tweak_callout_manager._on_size_value_changed(value)
func _on_count_value_changed(value: float): tweak_callout_manager._on_count_value_changed(value)
func _on_wheels_per_axle_changed(value: float): tweak_callout_manager._on_wheels_per_axle_changed(value)
func _on_blade_count_changed(value: float): tweak_callout_manager._on_blade_count_changed(value)
func _on_blade_pitch_changed(value: float): tweak_callout_manager._on_blade_pitch_changed(value)
func _on_helix_depth_changed(value: float): tweak_callout_manager._on_helix_depth_changed(value)
func _on_leg_width_changed(value: float): tweak_callout_manager._on_leg_width_changed(value)
func _on_duct_toggled(pressed: bool): tweak_callout_manager._on_duct_toggled(pressed)
func _on_leg_type_selected(index: int): tweak_callout_manager._on_leg_type_selected(index)
func _on_loco_drag_started(): tweak_callout_manager._on_loco_drag_started()
func _on_loco_drag_ended(value_changed: bool): tweak_callout_manager._on_loco_drag_ended(value_changed)
