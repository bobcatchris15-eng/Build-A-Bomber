extends Control
const ModuleDataResource = preload("res://scripts/module_data.gd")


const FactionCatalog = preload("res://scripts/faction_catalog.gd")
const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const BlueprintNamerScript = preload("res://scripts/blueprint_namer.gd")
const UIFlyoutScript = preload("res://scripts/ui_flyout.gd")
const UIIconsScript = preload("res://scripts/ui_icons.gd")
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
var toolbar: Control = null
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
var _undo_btn: Button = null
var _redo_btn: Button = null

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
var _name_roll_button: Button = null

@onready var locomotion_tweaks = $ScrollContainer/VBoxContainer/LocomotionTweaks
@onready var size_container = $ScrollContainer/VBoxContainer/LocomotionTweaks/SizeContainer
@onready var size_label = $ScrollContainer/VBoxContainer/LocomotionTweaks/SizeContainer/SizeLabel
@onready var size_slider = $ScrollContainer/VBoxContainer/LocomotionTweaks/SizeContainer/SizeSlider
@onready var count_container = $ScrollContainer/VBoxContainer/LocomotionTweaks/CountContainer
@onready var count_slider = $ScrollContainer/VBoxContainer/LocomotionTweaks/CountContainer/CountSlider
@onready var count_label = $ScrollContainer/VBoxContainer/LocomotionTweaks/CountContainer/CountLabel

# Locomotion Size/Count sliders previously showed only a static base label
# ("Wheel Size:") with no live numeric readout, unlike every other slider
# in the Design Lab (armor thickness, weapon tweaks) which all show the
# current value - a real, noticed inconsistency. These track the base
# name so _refresh_locomotion_labels() can append the live value on top
# of whatever branch in on_module_selected() set it.
var size_label_base: String = "Size"
var count_label_base: String = "Count"

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const DamageResolverScript = preload("res://scripts/damage_resolver.gd")
const DesignStatsScript = preload("res://scripts/design_stats.gd")
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
	"legs": "knee_height",
	"hover_engine": "emv_level",
	"fixed_wing_engine": "turbine_compression",
	"screw_drive": "drum_diameter",
	"pontoon_wheels": "pontoon_size",
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
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 4.0, "step": 1.0, "default": 0.0}
	],
	"heavy_machine_gun": [
		{"name": "caliber", "label": "Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "multi_barrel", "label": "Multi-Barrel Mode", "type": "bool", "default": false},
		{"name": "drum_size", "label": "Ammo Drum Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 4.0, "step": 1.0, "default": 0.0}
	],
	"rotary_cannon": [
		{"name": "caliber", "label": "Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_count", "label": "Barrel Count", "min": 3.0, "max": 9.0, "step": 1.0, "default": 6.0},
		{"name": "motor_size", "label": "Electric Motor Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 4.0, "step": 1.0, "default": 0.0}
	],
	"gauss_railgun": [
		{"name": "caliber", "label": "Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "rail_length", "label": "Electromagnetic Rail Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 4.0, "step": 1.0, "default": 0.0}
	],
	"artillery": [
		{"name": "caliber", "label": "Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_count", "label": "Barrel Count", "min": 1.0, "max": 2.0, "step": 1.0, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 3.0, "step": 1.0, "default": 0.0}
	],
	"mortar_array": [
		{"name": "caliber", "label": "Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Mortar Tube Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "tube_count", "label": "Mortar Tube Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 2.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 3.0, "step": 1.0, "default": 0.0}
	],
	"guided_missile": [
		{"name": "seeker_size", "label": "Missile Diameter", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "engine_length", "label": "Launch Tube Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_count", "label": "Launcher Tube Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 4.0, "step": 1.0, "default": 0.0}
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
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 2.0, "step": 1.0, "default": 0.0}
	],
	"heavy_laser": [
		{"name": "lens_aperture", "label": "Laser Lens Aperture", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Optical Telescope Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 4.0, "step": 1.0, "default": 0.0}
	],
	"plasma_lobber": [
		{"name": "containment", "label": "Plasma Chamber Diameter", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Accelerator Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 3.0, "step": 1.0, "default": 0.0}
	],
	"ciws": [
		{"name": "caliber", "label": "Rotary Gun Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Rotary Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "radar_dish", "label": "CIWS Tracking Radar Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 2.0, "step": 1.0, "default": 0.0}
	],
	"pd_laser": [
		{"name": "cooling_jacket", "label": "PD Laser Cooling Jacket", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Emitter Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 2.0, "step": 1.0, "default": 0.0}
	],
	"flak_cannon": [
		{"name": "caliber", "label": "Flak Cannon Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Flak Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_count", "label": "Flak Barrel Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 2.0},
		{"name": "fuse_setting", "label": "Proximity Fuse Setter", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 4.0, "step": 1.0, "default": 0.0}
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
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 3.0, "step": 1.0, "default": 0.0}
	],
	"recoilless_rifle": [
		{"name": "caliber", "label": "Bore Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Tube Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 2.0, "step": 1.0, "default": 0.0}
	],
	"coil_gun": [
		{"name": "caliber", "label": "Slug Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "rail_length", "label": "Accelerator Stage Count", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 4.0, "step": 1.0, "default": 0.0}
	],
	"autocannon": [
		{"name": "caliber", "label": "Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "drum_size", "label": "Ammo Drum Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 3.0, "step": 1.0, "default": 0.0}
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
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 2.0, "step": 1.0, "default": 0.0}
	],
	"chaff_dispenser": [
		{"name": "tube_count", "label": "Cartridge Tubes", "min": 2.0, "max": 8.0, "step": 1.0, "default": 4.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 2.0, "step": 1.0, "default": 0.0}
	],
	"laser_dazzler": [
		{"name": "lens_aperture", "label": "Emitter Aperture", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 3.0, "step": 1.0, "default": 0.0}
	],
	"aps_interceptor": [
		{"name": "fuse_setting", "label": "Intercept Fuse", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 3.0, "step": 1.0, "default": 0.0}
	],
	"aa_autocannon": [
		{"name": "caliber", "label": "Calibre", "min": 0.6, "max": 1.6, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Barrel Length", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 3.0, "step": 1.0, "default": 0.0}
	],
	"jammer_mast": [
		{"name": "mast_height", "label": "Mast Height", "min": 0.6, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 2.0, "step": 1.0, "default": 0.0}
	],
	"sentry_deployer": [
		{"name": "hangar_size", "label": "Sentries Carried", "min": 1.0, "max": 3.0, "step": 1.0, "default": 2.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 2.0, "step": 1.0, "default": 0.0}
	],
	"sensor_beacon_launcher": [
		{"name": "payload_size", "label": "Beacon Size", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 2.0, "step": 1.0, "default": 0.0}
	],
	"decoy_projector": [
		{"name": "payload_size", "label": "Decoy Size", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 2.0, "step": 1.0, "default": 0.0}
	],
	"spigot_mortar": [
		{"name": "rod_thickness", "label": "Spigot Rod", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
		{"name": "payload_size", "label": "Bomb Size", "min": 0.6, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 2.0, "step": 1.0, "default": 0.0}
	],
	"rocket_artillery": [
		{"name": "tube_count", "label": "Rail Count", "min": 2.0, "max": 8.0, "step": 1.0, "default": 4.0},
		{"name": "dispersion", "label": "Salvo Spread", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 2.0, "step": 1.0, "default": 0.0}
	],
	"hypervelocity_missile": [
		{"name": "tube_count", "label": "Canister Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 2.0},
		{"name": "seeker_size", "label": "Designator Power", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 3.0, "step": 1.0, "default": 0.0}
	],
	"sam_launcher": [
		{"name": "tube_count", "label": "Rail Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 2.0},
		{"name": "radar_dish", "label": "Tracking Radar", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 3.0, "step": 1.0, "default": 0.0}
	],
	"loitering_munition": [
		{"name": "tube_count", "label": "Tube Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 2.0},
		{"name": "seeker_size", "label": "Loiter Endurance", "min": 0.6, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 2.0, "step": 1.0, "default": 0.0}
	],
	"anti_radiation_missile": [
		{"name": "tube_count", "label": "Rail Count", "min": 1.0, "max": 3.0, "step": 1.0, "default": 2.0},
		{"name": "seeker_size", "label": "ESM Sensitivity", "min": 0.6, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 3.0, "step": 1.0, "default": 0.0}
	],
	"bunker_buster": [
		{"name": "warhead_size", "label": "Penetrator Mass", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
		{"name": "ascent_thruster", "label": "Top-Attack Climb", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 3.0, "step": 1.0, "default": 0.0}
	],
	"cruise_missile": [
		{"name": "warhead_size", "label": "Warhead Size", "min": 0.6, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "motor_length", "label": "Fuel Load", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 2.0, "step": 1.0, "default": 0.0}
	],
	"napalm_mortar": [
		{"name": "caliber", "label": "Canister Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Mortar Tube Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 2.0, "step": 1.0, "default": 0.0}
	],
	"mine_layer": [
		{"name": "tube_count", "label": "Mines Per Volley", "min": 1.0, "max": 4.0, "step": 1.0, "default": 1.0},
		{"name": "payload_size", "label": "Mine Charge Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 2.0, "step": 1.0, "default": 0.0}
	],
	"ballista": [
		{"name": "caliber", "label": "Bolt Thickness", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Draw Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 3.0, "step": 1.0, "default": 0.0}
	],
	# Tube count is the discharger's one real handle: more tubes means more
	# canisters per volley and so a wider screen, at the usual weight/cost.
	"smoke_discharger": [
		{"name": "tube_count", "label": "Discharger Tube Count", "min": 2.0, "max": 6.0, "step": 1.0, "default": 4.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 2.0, "step": 1.0, "default": 0.0}
	],
	"resource_harvester": [
		{"name": "extractor_size", "label": "Extractor Arm Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"repair_array": [
		{"name": "welder_count", "label": "Welder Arm Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 2.0}
	],
	"sensor_suite": [
		{"name": "mast_height", "label": "Radar Mast Height", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	# Previously documented in Arsenal_Weapons_List.md but missing from this
	# dict entirely - drone_carrier rendered zero tweak sliders in the
	# Design Lab (ENERGY_AND_BALANCE_SPEC.md #3).
	"drone_carrier": [
		{"name": "hangar_size", "label": "Hangar Size (Drone Count)", "min": 1.0, "max": 5.0, "step": 1.0, "default": 2.0},
		{"name": "launch_catapult", "label": "Launch Catapult", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	# Energy weapons (ENERGY_AND_BALANCE_SPEC.md #5)
	"tesla_coil": [
		{"name": "caliber", "label": "Coil Charge Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 4.0, "step": 1.0, "default": 0.0}
	],
	"arc_projector": [
		{"name": "containment", "label": "Arc Containment Field", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 4.0, "step": 1.0, "default": 0.0}
	],
	# dish_aperture is the classic width-vs-reach trade made physical: a
	# bigger dish spreads the cone wider and shortens it, which the player can
	# predict from the model before touching the slider.
	"microwave_emitter": [
		{"name": "dish_aperture", "label": "Dish Aperture", "min": 0.6, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 3.0, "step": 1.0, "default": 0.0}
	],
	# charge_time buys per-shot damage with exposure: a longer wind-up is more
	# time an alert enemy has to kill you before the shot lands. focal_length
	# scales the accelerator spine alone.
	"particle_lance": [
		{"name": "charge_time", "label": "Capacitor Charge", "min": 0.6, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "focal_length", "label": "Accelerator Length", "min": 0.6, "max": 1.8, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 3.0, "step": 1.0, "default": 0.0}
	],
	"ion_cannon": [
		{"name": "lens_aperture", "label": "Ion Focusing Lens", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "protectedness", "label": "Armor Level", "min": 0.0, "max": 4.0, "step": 1.0, "default": 0.0}
	]
}

var armor_mat_label: Label
var armor_mat_btn: OptionButton
var armor_thick_label: Label
var armor_thick_slider: HSlider
var armor_threshold_label: Label

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
var faction_label: Label
var faction_btn: OptionButton
var hull_spec_btn: Button
var hull_spec_stash: VBoxContainer
var _hull_spec_flyout: Node = null
var energy_label: Label

# Wheels-only "dually" tweak (wheels_per_axle, 1-2): no scene node for this
# exists in UI_StatBlock.tscn (only the generic Size/Count sliders shared by
# every locomotion type), so it's built dynamically here rather than in the
# scene - added as a sibling of SizeContainer/CountContainer inside
# LocomotionTweaks so it reads as part of the same panel instead of a separate
# floating control.
var wheels_per_axle_container: HBoxContainer
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

# "Blade Pitch" tweak (blade_pitch, 0.5-1.5): naval_propeller/
# buoyant_envelope only (Chris's ask, 2026-07-24) - same dynamic-widget/
# geometry-tweak pattern as blade_count above.
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
	# Captured BEFORE _build_rail_dock() moves the subtree, because this one is
	# used as a parent for dynamically-added rows throughout the file.
	# Resolved here because the rest of _ready() adds rows to it. The dock itself
	# is built at the END of _ready() - see the call there for why the order
	# matters.
	_rail_vbox = $ScrollContainer/VBoxContainer
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
	#   Test    -> plain Button  (BAKELITE). Reclassified: it was marked
	#              DangerButton in UI_StatBlock.tscn, but running a test is not
	#              destructive, and spending alert red on it left nothing to
	#              escalate to. It is navigation.
	#   Library -> plain Button  (BAKELITE). Its cyan appears nowhere in
	#              ui_tokens.gd; it was the last survivor of the old sci-fi accent.
	save_button.text = "SAVE BLUEPRINT"
	test_button.text = "TEST IN ARENA"
	test_button.theme_type_variation = ""
	library_button.text = "BLUEPRINT LIBRARY"
	delete_button.text = "DISCARD PART"

	mirror_checkbox.toggled.connect(_on_mirror_toggled)
	delete_button.pressed.connect(_on_delete_pressed)
	save_button.pressed.connect(_on_save_pressed)
	test_button.pressed.connect(_on_test_pressed)
	library_button.pressed.connect(_on_library_pressed)
	blueprint_name_edit.text_changed.connect(_on_blueprint_name_changed)
	_setup_name_roller()
	
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

	# Dynamically build the naval_propeller/buoyant_envelope-only "Blade
	# Pitch" slider (Chris's ask, 2026-07-24).
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

	# The hull-spec controls. Built here, parked in an invisible stash, and
	# shown in a flyout off the trigger button below - see hull_spec_stash's
	# declaration for why they are reused rather than rebuilt per open.
	hull_spec_stash = VBoxContainer.new()
	hull_spec_stash.visible = false
	add_child(hull_spec_stash)

	armor_mat_label = Label.new()
	armor_mat_label.text = "Armor Material"
	hull_spec_stash.add_child(armor_mat_label)

	armor_mat_btn = OptionButton.new()
	armor_mat_btn.add_item("Hardened Steel")
	armor_mat_btn.add_item("Reactive Armor")
	armor_mat_btn.add_item("Ablative Ceramic")
	armor_mat_btn.add_item("Energy Shielding")
	hull_spec_stash.add_child(armor_mat_btn)
	armor_mat_btn.item_selected.connect(_on_armor_material_selected)

	faction_label = Label.new()
	faction_label.text = "Faction Selection"
	hull_spec_stash.add_child(faction_label)

	faction_btn = OptionButton.new()
	# clip_text - the roster grew from 3 factions to 10, some with longer
	# names ("The Aerodrome Cartel") than any of the old 3 - without this,
	# OptionButton auto-sizes to fit its longest item and was just barely
	# pushing the whole sidebar past its fixed width (caught by the UI
	# overflow audit test, not just eyeballing it). Still true inside a flyout,
	# which sizes to its contents just as readily.
	faction_btn.clip_text = true
	for fac_id in FactionCatalog.get_ids():
		faction_btn.add_item(FactionCatalog.get_faction_name(fac_id))
	faction_btn.name = "FactionDropdown"
	hull_spec_stash.add_child(faction_btn)
	faction_btn.item_selected.connect(_on_faction_selected)

	armor_thick_label = Label.new()
	armor_thick_label.text = "Armor Thickness"
	hull_spec_stash.add_child(armor_thick_label)

	armor_thick_slider = HSlider.new()
	armor_thick_slider.min_value = 0.5
	armor_thick_slider.max_value = 3.0
	armor_thick_slider.step = 0.1
	armor_thick_slider.value = 1.0
	hull_spec_stash.add_child(armor_thick_slider)
	armor_thick_slider.value_changed.connect(_on_armor_thickness_changed)
	armor_thick_slider.drag_started.connect(_push_undo)

	# The trigger. Sits in the rail for now; item 7's top toolbar is where it
	# belongs, and moving it there is a reparent of this one node.
	#
	# Deadpan procurement register per the plan's item 0 - this opens a hull's
	# specification, so it says so, and it carries no glyph.
	hull_spec_btn = Button.new()
	hull_spec_btn.text = "HULL SPECIFICATION"
	hull_spec_btn.tooltip_text = "Armor material, thickness and faction marking"
	_rail_vbox.add_child(hull_spec_btn)
	hull_spec_btn.pressed.connect(_on_hull_spec_pressed)

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

	# Navigation back to the main menu
	var menu_btn = Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.pressed.connect(_return_to_menu)
	_rail_vbox.add_child(menu_btn)

	# Locomotion tweaks (Size/Count/Wheels-Per-Axle) move into the same
	# floating popup weapon/armor tweaks use, instead of living in the
	# right-hand sidebar - Chris's ask, "mirroring the weapon module
	# behavior" so every module type's tweaks appear in one consistent
	# place near the selected module. These are reused/reparented (not
	# rebuilt) each selection since on_module_selected()'s popup-clearing
	# sweep below explicitly skips them - see that guard.
	size_container.reparent(popup_tweaks_container)
	count_container.reparent(popup_tweaks_container)
	wheels_per_axle_container.reparent(popup_tweaks_container)
	blade_count_container.reparent(popup_tweaks_container)
	duct_container.reparent(popup_tweaks_container)
	locomotion_tweaks.visible = false

	# LAST, deliberately. _build_toolbar() reparents controls into the bar, and
	# hull_spec_btn is created partway through this function rather than being an
	# @onready node - building the dock any earlier caught it as null and silently
	# left the flyout trigger stranded in the rail with no error.
	_build_rail_dock()

	# Initial sync of armor UI
	call_deferred("_initial_sync")

func _push_undo():
	var root = get_node_or_null("/root/MainLab")
	if root and root.has_method("push_undo_snapshot"):
		root.push_undo_snapshot()

const UIStampScript = preload("res://scripts/ui_stamp.gd")

func _on_delete_pressed():
	var root = get_node_or_null("/root/MainLab")
	if root and root.has_method("delete_selected_module"):
		UIStampScript.spawn_stamp(get_tree().root, "DECOMMISSIONED / DISCARDED", "alert")
		root.delete_selected_module()
		
func _on_save_pressed():
	var root = get_node("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null
	if hull:
		var name_text = blueprint_name_edit.text.strip_edges()
		hull.set_meta("blueprint_name", name_text)
	var blueprint_manager = root.get_node_or_null("BlueprintManager")
	if blueprint_manager:
		if blueprint_manager.save_blueprint():
			UIStampScript.spawn_stamp(get_tree().root, "APPROVED FOR FIELD TEST", "go")
		else:
			blueprint_name_edit.grab_focus()

# Adds a "Roll" button beside the name field that fills in a generated
# designation ("GoatHauler Mk VI", "Type 17 IronDung").
#
# Built in code rather than added to UI_StatBlock.tscn so the LineEdit keeps
# its existing path - stat_calculator.gd reaches it via an @onready node
# path, and reparenting it into a new HBox in the scene would break that
# reference (and every other script that walks the same path).
func _setup_name_roller() -> void:
	if not blueprint_name_edit:
		return
	var parent := blueprint_name_edit.get_parent()
	var idx := blueprint_name_edit.get_index()

	var row := HBoxContainer.new()
	row.name = "BlueprintNameRow"
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	parent.move_child(row, idx)

	# reparent() preserves the node itself, so $ScrollContainer/VBoxContainer/
	# BlueprintNameEdit becomes .../BlueprintNameRow/BlueprintNameEdit. The
	# @onready var already resolved at _ready(), so the reference stays valid.
	blueprint_name_edit.reparent(row)
	blueprint_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_name_roll_button = Button.new()
	_name_roll_button.text = "Roll"
	_name_roll_button.tooltip_text = "Suggest a designation"
	_name_roll_button.pressed.connect(_on_roll_name_pressed)
	row.add_child(_name_roll_button)

	_reroll_name_suggestion()

func _reroll_name_suggestion() -> void:
	# Shown as placeholder text only. A suggestion the player never looked at
	# is not a name they chose, so it must not count as one - it stays out of
	# the field (and therefore out of the save) until Roll is pressed.
	if blueprint_name_edit:
		blueprint_name_edit.placeholder_text = BlueprintNamerScript.generate()

func _on_roll_name_pressed() -> void:
	if not blueprint_name_edit:
		return
	var rolled: String = BlueprintNamerScript.generate()
	blueprint_name_edit.text = rolled
	_on_blueprint_name_changed(rolled)
	_reroll_name_suggestion()

func _on_blueprint_name_changed(new_text: String):
	var root = get_node_or_null("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null
	if hull:
		hull.set_meta("blueprint_name", new_text)

func _on_library_pressed():
	var root = get_node_or_null("/root/MainLab")
	if not root: return
	var router = get_node_or_null("/root/SceneRouter")
	if router:
		# Pass the lab as context so the library knows to return here
		router.goto("res://scenes/BlueprintLibrary.tscn", "res://scenes/MainLab.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/BlueprintLibrary.tscn")

func sync_hull_ui(hull: Node3D):
	# An unnamed design now shows an EMPTY field with a suggestion behind it,
	# not the literal string "Untitled Design". Writing the placeholder into
	# the field is what made it look like a name the player had already
	# supplied - they'd hit Save and get refused by something the UI had
	# filled in for them.
	if not hull:
		if blueprint_name_edit:
			blueprint_name_edit.text = ""
			_reroll_name_suggestion()
		return
	is_updating_sliders = true
	if blueprint_name_edit:
		var bp_name = str(hull.get_meta("blueprint_name", "")).strip_edges()
		blueprint_name_edit.text = bp_name if BlueprintManagerScript.is_named(bp_name) else ""
		if blueprint_name_edit.text == "":
			_reroll_name_suggestion()
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
	# Held as a member rather than looked up by node path. The old
	# `$ScrollContainer/VBoxContainer.get_node_or_null("FactionDropdown")` broke
	# the moment this control moved into the hull-spec flyout, and broke
	# SILENTLY - get_node_or_null returns null, the `if` skips, and a loaded
	# blueprint just quietly shows the wrong faction in the dropdown with no
	# error anywhere. The dropdown now moves between stash and flyout on every
	# open, so a path-based lookup could never be right again.
	if faction_btn:
		var fac = hull.get_meta("faction") if hull.has_meta("faction") else "industrialists"
		var idx = FactionCatalog.get_ids().find(fac)
		if idx >= 0:
			faction_btn.selected = idx
	is_updating_sliders = false
	update_stats(hull)

func _on_test_pressed():
	var root = get_node("/root/MainLab")
	var blueprint_manager = root.get_node_or_null("BlueprintManager")
	if blueprint_manager:
		var success = blueprint_manager.save_scratch()
		if success:
			UIStampScript.spawn_stamp(get_tree().root, "DESTRUCTIVE TEST PERMIT", "hazard")
			get_tree().create_timer(0.35).timeout.connect(func():
				get_tree().change_scene_to_file("res://scenes/Battlefield.tscn")
			)
		else:
			var ui = get_tree().get_first_node_in_group("stat_ui")
			if ui and ui.has_node("ScrollContainer/VBoxContainer/Title"):
				ui.get_node("ScrollContainer/VBoxContainer/Title").text = "TEST BLOCKED: Resolve Clipping!"
				get_tree().create_timer(3.0).timeout.connect(func():
					if is_instance_valid(ui) and ui.has_node("ScrollContainer/VBoxContainer/Title"):
						ui.get_node("ScrollContainer/VBoxContainer/Title").text = "Blueprint Stats"
				)
	else:
		get_tree().change_scene_to_file("res://scenes/Battlefield.tscn")

func _on_mirror_toggled(button_pressed: bool):
	var root = get_node("/root/MainLab")
	if root and root.has_method("set_mirror_enabled"):
		root.set_mirror_enabled(button_pressed)

func set_mirror_toggle(enabled: bool):
	if mirror_checkbox:
		# Set without triggering the signal to avoid infinite loops
		mirror_checkbox.set_pressed_no_signal(enabled)

func update_stats(hull: Node3D):
	# The faction re-tint that used to happen here is gone with the `Panel` node
	# it painted (VISUAL/UI plan items 2 and 7). ui_material.gdshader's contract is
	# explicit that chrome stays neutral and the faction accent is "a low-strength
	# identity wash for the faction preview swatch only, never general chrome" -
	# and repainting the whole 320px rail in the faction's colour on every stat
	# recompute is about as far from that as the codebase got. The rail is
	# POWDERCOAT from the dock now, the same in every faction; faction identity is
	# carried by the units on the stage, which is where the player is looking.
	# The whole summation this function used to do inline now lives in
	# DesignStats.analyze(), so the roster cards and the fleet comparison panel
	# can read the same figures instead of only this sidebar being able to.
	# Nothing about WHAT is computed changed - see design_stats.gd's header. The
	# locals below are kept as locals so the label code further down reads
	# unchanged.
	var stats: Dictionary = DesignStatsScript.analyze(hull)
	var total_cost_metal = stats["cost_metal"]
	var total_cost_crystal = stats["cost_crystal"]
	var total_dps = stats["dps"]
	var total_energy_capacity = stats["energy_capacity"]
	# Weight, load capacity, thrust and top speed all come from
	# Drivetrain.analyze() - the SAME call battle_unit.gd makes when it spawns
	# the unit for real, so every number this sidebar shows is a number combat
	# will actually run. DesignStats.analyze() made that call above and hands the
	# result back, so it happens once per recompute rather than twice.
	#
	# This replaces a local re-derivation that carried its own comment saying
	# it only needed to be "close enough to warn". It was not: it knew about
	# wheels, treads, rotors and legs, and nothing about hover pads, Electron
	# Megavoltage, turbine compression, or any of the eleven expansion
	# locomotors - so on most of the roster the capacity figure could not move
	# when the player dragged the very tweaks that change it. See the header
	# comment in drivetrain.gd for why the two copies are now one.
	var dt: Dictionary = stats["drivetrain"]
	# No total_weight_capacity local: it was assigned and never read (already dead
	# at HEAD, not made dead by this refactor). _update_drivetrain_readout() takes
	# the whole dt and reads capacity from it directly.

	var armor_material = "hardened_steel"
	var armor_thickness = 1.0
	var faction = "industrialists"

	if hull:
		if hull.has_meta("armor_material"):
			armor_material = hull.get_meta("armor_material")
		if hull.has_meta("armor_thickness"):
			armor_thickness = hull.get_meta("armor_thickness")
		if hull.has_meta("faction"):
			faction = hull.get_meta("faction")

	# FABLE_REVIEW.md 2.6 fix: this sidebar used to show numbers combat never
	# used - "Total HP" was the MODULE hp sum scaled by material/thickness
	# (an empty hull showed 0.0 but fielded at 400), and "Total Weight"
	# applied material multipliers the combat weight sum didn't. Both now
	# come from the same shared ModuleCatalog.compute_hull_* functions
	# battle_unit.gd/building.gd/blueprint_cost() read, so what you see in
	# the Design Lab is what the simulation runs.
	#
	# Hull HP, the module pool and the weight all arrive from
	# DesignStats.analyze(), which makes exactly those shared calls. The hull cost
	# it computes is already folded into cost_metal/cost_crystal above, so there
	# is no separate hull_cost addition here any more.
	var module_hp_pool = stats["module_hp_pool"]
	var total_hp = stats["hull_hp"]
	var total_weight = stats["weight"]

	# Read straight from DamageResolver.ARMOR_TABLE (single source of truth,
	# same as combat) instead of a second hardcoded k_base/t_base/e_base
	# table - the two had drifted: "E:" here used to be a copy-paste of the
	# EXPLOSIVE threshold mislabeled as Energy (damage_resolver.gd had no
	# real "energy" row at all until this pass). Found while scoping the
	# energy-weapon damage_class reclassification work.
	var k_thresh = DamageResolverScript.get_material_threshold(armor_material, "kinetic", armor_thickness).x
	var t_thresh = DamageResolverScript.get_material_threshold(armor_material, "thermal", armor_thickness).x
	var e_thresh = DamageResolverScript.get_material_threshold(armor_material, "energy", armor_thickness).x

	# Stat rounding: total_hp/total_weight/total_dps are sums of
	# module_data.gd getters that already round to the nearest 0.5 at the
	# point they're computed (GlobalConfig.round_to_half), so what's shown
	# here is exactly what combat uses - this %.1f is just consistent
	# formatting (a sum of clean .5-stepped numbers is itself clean), not a
	# second, independent rounding pass. Previously these 4 labels were the
	# one place in this file using bare str() on a float, which is why they
	# alone showed raw float precision (e.g. "14.723891...") while every
	# other label here was already %.1f/%.2f/%d formatted.
	hp_label.text = "Hull HP: %.1f (modules +%.1f)" % [total_hp, module_hp_pool]
	hp_label.tooltip_text = "Hull HP is the unit's real health pool in combat.\nModule HP is each mounted part's own pool - parts get shot off (subsystem stripping) without draining hull HP."
	cost_label.text = "Cost: %d Metal, %d Crystal" % [total_cost_metal, total_cost_crystal]
	dps_label.text = "Total DPS: %.1f" % total_dps

	weight_label.text = "Total Weight: %.1f kg" % total_weight

	# Publish the figures for anything that reads this design's stats rather
	# than the labels. fleet_comparison_panel.gd has always tried to
	# (`stat_calc.total_weight if "total_weight" in stat_calc`), but these were
	# LOCALS of this function, so that guard never passed and the WIP column of
	# the comparison panel silently showed 0 HP / 0 kg / 0 DPS against a real
	# saved design. Assigning them here is what makes the guard true.
	# Assigned through `self` deliberately: the locals above shadow these
	# members, so a bare `total_weight = total_weight` would be a self-
	# assignment of the local and publish nothing.
	self.total_hp = total_hp
	self.total_weight = total_weight
	self.total_dps = total_dps
	self.drivetrain = dt
	# Already analysed inside DesignStats.analyze() above; taken from there rather
	# than walking every module's range tweaks a second time per recompute.
	var wr: Dictionary = stats["weapon_range"]
	self.weapon_range = wr

	# The manufactory-tier note stays tooltip-only. Manufactory tier is
	# determined entirely by the hull TYPE (see ModuleCatalog.
	# get_hull_size_tier(), the same function skirmish.gd's
	# _queue_player_unit() uses) - a player could previously only discover
	# which manufactory they'd need via a failed build attempt mid-match.
	var tier = ModuleCatalog.get_hull_size_tier(hull.get_meta("type_id", "medium_hull")) if hull and hull.has_meta("type_id") else ""
	var tooltip_parts: Array = []
	if tier != "":
		tooltip_parts.append("Needs a %s Manufactory to build this design." % tier.capitalize())
	weight_label.tooltip_text = "\n".join(tooltip_parts)
	# The overweight state is no longer said by tinting this label. It has its
	# own bar, its own speed readout and its own warning panel below - a label
	# turning orange was the entire previous treatment, and it neither said
	# what the limit was nor what exceeding it cost.
	weight_label.modulate = Color(1, 1, 1)

	_update_drivetrain_readout(dt)
	_update_range_readout(wr)

	if not energy_label:
		energy_label = Label.new()
		_rail_vbox.add_child(energy_label)
	energy_label.text = "Energy Capacity: +%.1f" % total_energy_capacity
	energy_label.visible = total_energy_capacity > 0.0

	if not armor_threshold_label:
		armor_threshold_label = Label.new()
		# Found by the new headless UI-overflow audit: this label's natural
		# single-line width (305px, "Armor Thresholds: K: 15.0, T: 5.0,
		# E: 10.0") exceeds the sidebar's fixed 210px width - it was
		# silently clipping/spilling past the panel edge (visible in
		# several of today's own verification screenshots as a stray
		# trailing character, never flagged as a bug until now). Word-wrap
		# instead of a hardcoded width, since threshold values can grow to
		# more digits than today's baseline numbers.
		armor_threshold_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rail_vbox.add_child(armor_threshold_label)
	armor_threshold_label.text = "Armor Thresholds: K: %.1f, T: %.1f, E: %.1f" % [k_thresh, t_thresh, e_thresh]

# --- Drivetrain readout (load bar + top speed + overweight warning) ---------
#
# WHY THIS IS VISIBLE CHROME AND NOT A TOOLTIP. The overweight state used to be
# communicated by tinting the weight label orange and putting a sentence in its
# tooltip. The comment justifying that said the sidebar "has zero
# vertical/horizontal layout slack left", and at the time it was right - it was
# a fixed 210px-wide strip, and the project's own overflow test had rejected
# three attempts at a persistent label.
#
# That constraint no longer exists. The TELEMETRY dock is a 320px UIDock whose
# body is a ScrollContainer (see _build_rail_dock()), so it can hold real rows
# and scroll them. A tooltip is also the wrong instrument for this specific
# job: the player is DRAGGING a tweak slider and needs to watch the number
# respond, and a tooltip is not on screen while the mouse is on the slider.
#
# Chris's ask was that exceeding capacity "light up a warning notification" and
# that the player "be aware of the flaw and what they are trading" - so the
# panel names the cost in the same units as the stat it is spending (speed),
# rather than saying "overweight" and leaving the player to infer the rest.
# Nothing here blocks saving or testing: an overloaded design is a legal,
# fieldable design, per that same ask.
var _load_bar: ProgressBar = null
var _load_label: Label = null
var _speed_label: Label = null
var _overweight_panel: PanelContainer = null
var _overweight_title: Label = null
var _overweight_detail: Label = null
# One stylebox per load state, built on first use and reused - same idiom as
# skirmish.gd's _power_fill_style(). A ProgressBar fill is a STATE indicator,
# which is the documented exception to "no local styleboxes": there is no
# theme-side way to say "this bar is currently in its bad state", and the
# StyleBoxTexture material plates carry no colour channel to vary.
var _load_fill_styles: Dictionary = {}

func _load_fill_style(state: String) -> StyleBoxFlat:
	if not _load_fill_styles.has(state):
		var sb := StyleBoxFlat.new()
		match state:
			"go": sb.bg_color = Tokens.SIGNAL_GO
			"hazard": sb.bg_color = Tokens.SIGNAL_HAZARD
			_: sb.bg_color = Tokens.SIGNAL_ALERT
		sb.corner_radius_top_left = Tokens.RADIUS_CONTROL
		sb.corner_radius_top_right = Tokens.RADIUS_CONTROL
		sb.corner_radius_bottom_left = Tokens.RADIUS_CONTROL
		sb.corner_radius_bottom_right = Tokens.RADIUS_CONTROL
		_load_fill_styles[state] = sb
	return _load_fill_styles[state]

func _build_drivetrain_readout() -> void:
	# Built once, lazily, then reused - matches how energy_label and
	# armor_threshold_label are handled in update_stats(). Ordered directly
	# after the weight row it explains, via move_child: lazily-added children
	# otherwise land at the end of the rail, which would put the load bar
	# below the save/test buttons.
	_speed_label = Label.new()
	_speed_label.theme_type_variation = "StatLabel"
	_rail_vbox.add_child(_speed_label)

	_load_label = Label.new()
	_load_label.theme_type_variation = "StatLabel"
	_rail_vbox.add_child(_load_label)

	_load_bar = ProgressBar.new()
	_load_bar.show_percentage = false
	_load_bar.min_value = 0.0
	# Deliberately 0-125 rather than 0-100: a bar that pins at full the moment
	# a design crosses capacity cannot show HOW far over it is, and "how far
	# over" is the whole quantity the player is trading against. Past 125% it
	# does pin, and the warning panel carries the exact figure.
	_load_bar.max_value = 125.0
	_load_bar.custom_minimum_size = Vector2(0, 6)
	_rail_vbox.add_child(_load_bar)

	# The warning notification. HAZARD, not ALERT: an overweight design is a
	# flaw the player is choosing to accept, not a failure or a destructive
	# action - see ui_tokens.gd's role comments on the signal colours.
	_overweight_panel = PanelContainer.new()
	var pair := Tokens.signal_pair("hazard")
	var warn_style := StyleBoxFlat.new()
	warn_style.bg_color = pair["fill"]
	warn_style.border_color = pair["edge"]
	warn_style.border_width_left = Tokens.BORDER_EMPHASIS
	warn_style.content_margin_left = Tokens.SPACE_SM
	warn_style.content_margin_right = Tokens.SPACE_SM
	warn_style.content_margin_top = Tokens.SPACE_XS
	warn_style.content_margin_bottom = Tokens.SPACE_XS
	_overweight_panel.add_theme_stylebox_override("panel", warn_style)
	_overweight_panel.visible = false
	var warn_box := VBoxContainer.new()
	warn_box.add_theme_constant_override("separation", Tokens.SPACE_XS)
	_overweight_panel.add_child(warn_box)
	_overweight_title = Label.new()
	_overweight_title.theme_type_variation = "HeadingLabel"
	_overweight_title.add_theme_color_override("font_color", pair["edge"])
	warn_box.add_child(_overweight_title)
	_overweight_detail = Label.new()
	_overweight_detail.theme_type_variation = "HintLabel"
	# These lines run past the rail's width; without a wrap the panel would
	# stretch the whole dock. Same fix as armor_threshold_label above.
	_overweight_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn_box.add_child(_overweight_detail)
	_rail_vbox.add_child(_overweight_panel)

	if weight_label and weight_label.get_parent() == _rail_vbox:
		var at := weight_label.get_index()
		_rail_vbox.move_child(_speed_label, at + 1)
		_rail_vbox.move_child(_load_label, at + 2)
		_rail_vbox.move_child(_load_bar, at + 3)
		_rail_vbox.move_child(_overweight_panel, at + 4)

func _update_drivetrain_readout(dt: Dictionary) -> void:
	if _load_bar == null:
		_build_drivetrain_readout()

	# A design with no running gear yet has no speed and no capacity to be
	# over. Showing "Top Speed 0.0" and a full-red load bar on a hull the
	# player has only just spawned would read as a fault in the design rather
	# than as an unfinished one.
	if not dt["has_locomotion"]:
		_speed_label.text = "Top Speed: - (no locomotion)"
		_load_label.visible = false
		_load_bar.visible = false
		_overweight_panel.visible = false
		return
	_load_label.visible = true
	_load_bar.visible = true

	var top_speed: float = dt["top_speed"]
	var move_speed: float = dt["move_speed"]
	var load_pct: float = dt["load_ratio"] * 100.0

	# Two different figures when overloaded, and the gap between them IS the
	# trade. When not overloaded there is only one, so only one is shown -
	# printing "9.7 (of 9.7)" would imply a penalty that isn't there.
	#
	# The gap is also suppressed when it rounds away. A design a fraction of a
	# percent over capacity has a real but sub-0.05 penalty, and rendering that
	# as "Top Speed: 5.0 (was 5.0)" reads as a broken label rather than as a
	# negligible cost - caught in the 100%-load capture, not by the suite,
	# which asserts the text only at 130% where the gap is wide.
	if dt["is_overloaded"] and absf(top_speed - move_speed) >= 0.05:
		_speed_label.text = "Top Speed: %.1f  (was %.1f)" % [move_speed, top_speed]
	else:
		_speed_label.text = "Top Speed: %.1f" % move_speed
	# Says WHICH limit is binding, because the two have opposite fixes: a
	# chassis-limited design needs different locomotion, a power-limited one
	# needs more thrust or less mass. Without this the player has no way to
	# tell why adding engines stopped helping.
	if dt["capacity_limited"] and not dt["is_overloaded"]:
		_speed_label.tooltip_text = "This chassis is rated for %.1f and is already there - more thrust will not make it faster. A different locomotion type will." % dt["chassis_top_speed"]
	else:
		_speed_label.tooltip_text = "Chassis rated %.1f; this design's power/weight allows %.1f." % [dt["chassis_top_speed"], dt["power_top_speed"]]

	_load_label.text = "Load: %.0f / %.0f kg  (%.0f%%)" % [dt["weight"], dt["capacity"], load_pct]
	_load_bar.value = minf(load_pct, _load_bar.max_value)
	# HAZARD from 90% - the point of a warning is to arrive BEFORE the cliff,
	# and a design at 95% is one armor plate away from the penalty.
	var state := "go"
	if dt["is_overloaded"]:
		state = "alert"
	elif load_pct >= 90.0:
		state = "hazard"
	_load_bar.add_theme_stylebox_override("fill", _load_fill_style(state))

	_overweight_panel.visible = dt["is_overloaded"]
	if dt["is_overloaded"]:
		_overweight_title.text = "OVERWEIGHT - %.0f%% OF CAPACITY" % load_pct
		# Same rounding guard as the speed row above: at a fraction of a
		# percent over, "Top speed 5.0 instead of 5.0" reads as a broken
		# label, so the cost is stated as a percentage alone until the two
		# figures actually differ on screen.
		var cost_pct: float = (1.0 - dt["overload_multiplier"]) * 100.0
		var cost: String
		if absf(top_speed - move_speed) >= 0.05:
			cost = "Top speed %.1f instead of %.1f (-%.0f%%)." % [move_speed, top_speed, cost_pct]
		else:
			cost = "Top speed down %.1f%% so far, and falling steeply from here." % cost_pct
		_overweight_detail.text = "%.0f kg over what this locomotion is rated to carry. %s Buildable and fieldable as-is - add locomotion, shed mass, or accept the loss." % [
			dt["weight"] - dt["capacity"], cost]
	_load_label.tooltip_text = "What this design's locomotion is rated to carry, tweaks included.\nOver capacity, top speed falls steeply - see the warning below."

# --- Range readout ---------------------------------------------------------
# The sidebar showed no range at all before this, which made a whole axis of
# the design invisible: the player could drag barrel_length - the single
# biggest lever on reach - and see the weight and cost move while the stat it
# was actually buying stayed off-screen entirely.
#
# It reports three things, because the range retune (ModuleCatalog.RANGE_TIERS)
# made them separable for the first time:
#   - the reach span across the design's real weapons, and which tier the
#     longest one lands in;
#   - the design's own vision, since that is the line between "this weapon can
#     find its own targets" and "this weapon needs somebody else to look";
#   - a warning naming any weapon that reaches past that line, and what it
#     costs. Exactly like the overweight panel, it does not block anything: a
#     spotter-dependent design is a legitimate and often very strong design,
#     it just isn't one you want to field by accident with no scout.
var _range_label: Label = null
var _vision_label: Label = null
var _spotter_panel: PanelContainer = null
var _spotter_title: Label = null
var _spotter_detail: Label = null

func _build_range_readout() -> void:
	_range_label = Label.new()
	_range_label.theme_type_variation = "StatLabel"
	_rail_vbox.add_child(_range_label)

	_vision_label = Label.new()
	_vision_label.theme_type_variation = "StatLabel"
	_rail_vbox.add_child(_vision_label)

	# HAZARD, matching the overweight panel: a trade the player is choosing,
	# not a failure. See ui_tokens.gd's role comments on the signal colours.
	_spotter_panel = PanelContainer.new()
	var pair := Tokens.signal_pair("hazard")
	var warn_style := StyleBoxFlat.new()
	warn_style.bg_color = pair["fill"]
	warn_style.border_color = pair["edge"]
	warn_style.border_width_left = Tokens.BORDER_EMPHASIS
	warn_style.content_margin_left = Tokens.SPACE_SM
	warn_style.content_margin_right = Tokens.SPACE_SM
	warn_style.content_margin_top = Tokens.SPACE_XS
	warn_style.content_margin_bottom = Tokens.SPACE_XS
	_spotter_panel.add_theme_stylebox_override("panel", warn_style)
	_spotter_panel.visible = false
	var warn_box := VBoxContainer.new()
	warn_box.add_theme_constant_override("separation", Tokens.SPACE_XS)
	_spotter_panel.add_child(warn_box)
	_spotter_title = Label.new()
	_spotter_title.theme_type_variation = "HeadingLabel"
	_spotter_title.add_theme_color_override("font_color", pair["edge"])
	warn_box.add_child(_spotter_title)
	_spotter_detail = Label.new()
	_spotter_detail.theme_type_variation = "HintLabel"
	_spotter_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn_box.add_child(_spotter_detail)
	_rail_vbox.add_child(_spotter_panel)

	# Sits directly after the DPS row it belongs with, rather than at the end
	# of the rail where lazily-added children otherwise land (which would put
	# it below the save/test buttons). Same move_child idiom as the drivetrain
	# rows above.
	if dps_label and dps_label.get_parent() == _rail_vbox:
		var at := dps_label.get_index()
		_rail_vbox.move_child(_range_label, at + 1)
		_rail_vbox.move_child(_vision_label, at + 2)
		_rail_vbox.move_child(_spotter_panel, at + 3)

func _update_range_readout(wr: Dictionary) -> void:
	if _range_label == null:
		_build_range_readout()

	# A hull with no armed modules yet has no range to report. Showing
	# "Range: 0.0" on a design the player has only started reads as a fault
	# rather than as an unfinished build - same reasoning as the drivetrain
	# readout's no-locomotion case.
	if not wr.get("has_weapons", false):
		_range_label.text = "Range: - (no weapons)"
		_vision_label.visible = false
		_spotter_panel.visible = false
		return
	_vision_label.visible = true

	var shortest: float = wr["shortest"]
	var longest: float = wr["longest"]
	var vision: float = wr["vision"]

	# One figure when every weapon reaches the same distance, a span otherwise -
	# printing "Range: 38 - 38" implies a spread that isn't there.
	if absf(longest - shortest) >= 0.5:
		_range_label.text = "Range: %.0f - %.0f  (%s)" % [shortest, longest, wr["tier_label"]]
	else:
		_range_label.text = "Range: %.0f  (%s)" % [longest, wr["tier_label"]]
	_range_label.tooltip_text = "Reach of this design's armed modules, tweaks included.\nBarrel length is the biggest lever: a longer barrel reaches further and throws faster, but traverses slower."

	_vision_label.text = "Vision: %.0f" % vision
	_vision_label.tooltip_text = "How far this design can see for itself.\nWeapons reaching past this can only fire that far at targets another unit on your team is looking at."

	var required: Array = wr["spotter_required"]
	var assisted: Array = wr["spotter_assisted"]
	_spotter_panel.visible = not required.is_empty() or not assisted.is_empty()
	if not _spotter_panel.visible:
		return

	# The stronger claim first. A weapon past 2x vision cannot meaningfully
	# self-acquire at range at all, which is a different and much more
	# consequential fact than "reaches a bit past its own eyes".
	if not required.is_empty():
		_spotter_title.text = "NEEDS A SPOTTER"
		var names: Array = []
		for w in required:
			names.append("%s (%.0f)" % [w["name"], w["reach"]])
		_spotter_detail.text = "%s %s far past this design's own %.0f vision. Without another unit of yours watching the target, it can only shoot as far as it can see - roughly %.0f%% of its reach. Pair it with a scout or a radar mast and it works at full range." % [
			", ".join(names),
			"reaches" if names.size() == 1 else "reach",
			vision,
			(vision / longest) * 100.0]
	else:
		_spotter_title.text = "OUT-REACHES ITS OWN VISION"
		var names: Array = []
		for w in assisted:
			names.append("%s (%.0f)" % [w["name"], w["reach"]])
		_spotter_detail.text = "%s can shoot further than this design can see (%.0f). Usable as-is, but a spotting unit or a radar mast is what unlocks the last %.0f units of that reach." % [
			", ".join(names), vision, longest - vision]

# Radial positions for infographic lines (prioritize a ring around the module).
#
# These are ORDERED BY PREFERENCE, not by angle: top corners first, then high
# sides, then low sides, then bottom corners. A module usually has fewer tweaks
# than there are slots, so the early entries are the ones that get used, and
# they are the positions that read best - above and outboard of the part, where
# a leader line has clear air and nothing is hidden behind the callout.
# tweak_callout.gd may flip a direction horizontally to keep its line on the
# same side as the geometry it points at; the vertical spread here is what stops
# same-side callouts from piling up.
var _callout_dirs = [
	Vector2(0.8, -1.2), Vector2(-0.8, -1.2), # Top corners
	Vector2(1.2, -0.2), Vector2(-1.2, -0.2), # High sides
	Vector2(1.2, 0.6), Vector2(-1.2, 0.6),   # Low sides
	Vector2(0.8, 1.2), Vector2(-0.8, 1.2)    # Bottom corners
]
var _current_callout_idx = 0

# The radial action ring (scripts/ui_radial_menu.gd). One at a time; opening a
# new one on a fresh selection closes the old.
var _action_ring: UIRadialMenu = null


# Opens the action ring on `module`.
#
# The ring carries the DISCRETE, mutually-exclusive verbs - rotate, mirror,
# discard - while the callouts carry the CONTINUOUS tweaks. That split is the
# whole reason there are two mechanisms rather than one: a pie slice cannot
# hold a slider, and a sidebar row is a bad place for a verb that applies to a
# thing you are looking at somewhere else.
func _open_action_ring(module: Node3D, designation: String) -> void:
	_close_action_ring()
	if tweak_canvas == null or module == null:
		return

	var ring = UIRadialMenu.new()
	ring.target_node = module
	ring.subject_label = designation
	# TEXT LEGENDS, NOT ICONS, deliberately.
	#
	# The icons in scripts/ui_icons.gd carry their stroke colour baked into the
	# SVG - rotate_right is cyan, close is red, and so on. draw_texture_rect's
	# modulate MULTIPLIES, so there is no way to force a coloured icon to the
	# ring's own tint; the first version put saturated cyan and red clip-art on
	# a warm neutral dial and it fought the palette badly. Stencilled words are
	# also simply more correct for this object: real equipment legends are
	# words. A monochrome icon set would let icons back in here later.
	ring.add_action("rotate", "Rotate", "", _module_can_rotate(module))
	ring.add_action("mirror", "Mirror")
	ring.add_action("arc", "Arc")
	ring.add_action("discard", "Discard")
	ring.action_invoked.connect(_on_ring_action)
	tweak_canvas.add_child(ring)

	var camera = get_viewport().get_camera_3d()
	var at = Vector2.ZERO
	if camera and not camera.is_position_behind(module.global_position):
		at = camera.unproject_position(module.global_position)
	ring.open_at(at)
	_action_ring = ring


# The Gizmo3D instance parented to the currently selected module, if any.
# module_placer.gd names it "Gizmo3D" when it attaches it.
func _selected_gizmo() -> Node:
	if not is_instance_valid(current_selected_module):
		return null
	return current_selected_module.get_node_or_null("Gizmo3D")


# Whether the rotation ring exists for this part. module_placer.gd frees
# HandleRotate outright for locomotion, armor and structural categories (armor
# is facet-fitted, structural stays flush - see MOUNTING_AND_ARMOR_SPEC.md), so
# offering Rotate on those would be a button that does nothing.
func _module_can_rotate(module: Node3D) -> bool:
	if module == null or not module.has_meta("module_data"):
		return false
	var data = module.get_meta("module_data")
	var cat = data.get("category") if "category" in data else "module"
	return cat == "weapon" or cat == "module"


func _close_action_ring() -> void:
	if is_instance_valid(_action_ring):
		_action_ring.close()
	_action_ring = null


func _on_ring_action(action_id: String) -> void:
	match action_id:
		"rotate":
			# Summons the rotation RING rather than stepping 90 degrees.
			#
			# Chris's note: the fixed-step button sitting next to a permanently
			# visible grab-handle ring was clunky - two ways to rotate, both on
			# screen at once, neither obviously the main one. Now Rotate is the
			# way IN to free rotation: the gizmo swaps its stretch handles for
			# the ring (gizmo_3d.set_rotate_mode), and the ring is restyled to
			# match this menu so the two read as one mechanism.
			var giz = _selected_gizmo()
			if giz and giz.has_method("set_rotate_mode"):
				giz.set_rotate_mode(true)
		"mirror":
			# Reuses the existing global mirror toggle rather than introducing a
			# second, per-module notion of mirroring that would then have to be
			# kept in sync with the checkbox.
			if mirror_checkbox:
				mirror_checkbox.button_pressed = not mirror_checkbox.button_pressed
		"arc":
			var root = get_node_or_null("/root/MainLab")
			if root and root.has_method("toggle_firing_arc"):
				root.toggle_firing_arc()
		"discard":
			_on_delete_pressed()

func _add_callout(module: Node3D, title: String, control: Control):
	if control.get_parent():
		control.reparent(tweak_canvas) # Temporarily avoid issues if it's already in the tree somewhere
	var dir = _callout_dirs[_current_callout_idx % _callout_dirs.size()]
	var dist = 100.0 + (_current_callout_idx / _callout_dirs.size()) * 70.0
	var callout = load("res://scripts/tweak_callout.gd").new(title, control, dir, dist)
	callout.target_node = module
	callout.stash = popup_tweaks_container
	tweak_canvas.add_child(callout)
	_current_callout_idx += 1

# The persistent locomotion widgets. These are REUSED across selections rather
# than rebuilt, so they must be rescued out of a dying callout instead of freed
# with it. Everything else a callout holds is built fresh per selection and
# should go when the callout goes.
func _persistent_tweak_widgets() -> Array:
	return [size_container, count_container, wheels_per_axle_container,
		blade_count_container, blade_pitch_container, helix_depth_container,
		duct_container, popup_name_label, popup_stats_label, popup_rotate_btn]

func _clear_callouts():
	if not tweak_canvas: return

	# STEP 1: reclaim every callout's control into the invisible stash BEFORE
	# anything is freed.
	#
	# Doing this here, rather than leaving it to each callout's own _process,
	# is what actually fixes the orphaned widgets: a callout only ran its
	# hand-back path when its TARGET went invalid, so a plain deselect (target
	# still alive, callout freed by the sweep below) never handed anything back
	# at all. Reparenting into popup_tweaks_container is safe for both kinds of
	# control because that container is invisible; step 3 then throws away the
	# ones that were single-use.
	for child in tweak_canvas.get_children():
		if child is TweakCallout:
			var ctrl = (child as TweakCallout).control_node
			if is_instance_valid(ctrl) and ctrl.get_parent() != popup_tweaks_container:
				ctrl.reparent(popup_tweaks_container)

	# STEP 2: make sure the persistent widgets are in the stash and parented.
	var persistent_items = _persistent_tweak_widgets()
	for c in persistent_items:
		if is_instance_valid(c) and c.get_parent() != popup_tweaks_container:
			if c.get_parent() != null:
				c.reparent(popup_tweaks_container)
			else:
				popup_tweaks_container.add_child(c)

	# STEP 3: purge the single-use controls that step 1 just swept in.
	# Without this the stash grows by a few nodes on every selection for the
	# whole session - invisible, so it would never be noticed, but it is still
	# an unbounded leak.
	for child in popup_tweaks_container.get_children():
		if child not in persistent_items:
			child.queue_free()


	# The ring is a child of tweak_canvas too, so the sweep below would free it
	# out from under _action_ring and leave a dangling reference. Drop it
	# explicitly first.
	_close_action_ring()

	for child in tweak_canvas.get_children():
		child.queue_free()
	_current_callout_idx = 0

func on_module_selected(module: Node3D):
	if module and not is_instance_valid(module):
		module = null
	current_selected_module = module

	_clear_callouts()

	# Default every locomotion tweak widget to hidden
	size_container.visible = false
	count_container.visible = false
	wheels_per_axle_container.visible = false
	blade_count_container.visible = false
	blade_pitch_container.visible = false
	helix_depth_container.visible = false
	duct_container.visible = false

	var root = get_node_or_null("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null

	if hull and (module == null or module == hull or module.name == "Hull"):
		sync_hull_ui(hull)

	if not locomotion_tweaks: return

	if not module or not module.has_meta("module_data"):
		return

	var data = module.get_meta("module_data")

	# We no longer use a single popup_panel. Instead we will create a callout for the stats
	# We can just use the popup_name_label and popup_stats_label but add them to a callout.
	
	# Actually, to avoid breaking, let's keep the name and stat label but put them in a dedicated callout
	var stats_container = VBoxContainer.new()
	if popup_name_label.get_parent(): popup_name_label.reparent(stats_container)
	else: stats_container.add_child(popup_name_label)
	
	if popup_stats_label.get_parent(): popup_stats_label.reparent(stats_container)
	else: stats_container.add_child(popup_stats_label)
		
	if popup_rotate_btn.get_parent(): popup_rotate_btn.reparent(stats_container)
	else: stats_container.add_child(popup_rotate_btn)
		
	popup_name_label.text = data.module_name.to_upper()

	# The action ring opens with the callouts, on the part itself.
	_open_action_ring(module, data.module_name.to_upper())

	var hp = data.get_hp()
	var wt = data.get_weight()
	var cost = data.get_cost()
	var dps = data.get_dps()
	var heal = data.get_heal_rate()
	var last_line = "Heal Rate: %.1f/s" % heal if heal > 0.0 else "DPS: %.1f" % dps
	var mount_line = _mount_style_line(module.get_meta("mount_style", ""))
	popup_stats_label.text = "HP: %.1f | Weight: %.1f kg\nCost: %d Metal, %d Crystal\n%s%s" % [hp, wt, cost.x, cost.y, last_line, mount_line]
	
	_add_callout(module, "Module Stats", stats_container)

	if data.category != "locomotion":
		_generate_custom_tweaks(module, data)
		return

	root = get_node("/root/MainLab")
	hull = root.get_node_or_null("Hull")
	if not hull:
		return

	var type_id = data.type_id
	var settings = {}
	if hull.has_meta("locomotion_settings"):
		settings = hull.get_meta("locomotion_settings")

	is_updating_sliders = true
	size_container.visible = true
	count_slider.min_value = 2.0
	count_slider.max_value = 8.0
	count_slider.step = 2.0
	# blade_count_container is now shared between helicopter_rotors and
	# naval_propeller/buoyant_envelope (Chris's ask, 2026-07-24) - reset
	# unconditionally so it doesn't stay visible after switching away from
	# whichever of those types last showed it (only helicopter_rotors used
	# it before, so this never came up).
	blade_count_container.visible = false
	blade_pitch_container.visible = false
	count_label_base = "Count"
	bool_tweak_key = "duct"
	bool_tweak_title = "Ducted"

	if type_id == "wheels":
		size_label_base = "Wheel Size"
		count_container.visible = true
		size_slider.min_value = 0.5
		size_slider.max_value = 2.5
		size_slider.value = settings.get("wheel_size", settings.get("size", 1.0))
		count_slider.min_value = 4.0
		count_slider.value = settings.get("num_axles", settings.get("count", 4))
		wheels_per_axle_container.visible = true
		wheels_per_axle_slider.value = settings.get("wheels_per_axle", 1.0)
	elif type_id == "tracked_treads":
		size_label_base = "Tread Width"
		count_container.visible = false
		size_slider.min_value = 0.5
		size_slider.max_value = 2.5
		size_slider.value = settings.get("tread_width", settings.get("width", 1.0))
	elif type_id == "helicopter_rotors":
		size_label_base = "Rotor Size"
		count_container.visible = true
		size_slider.min_value = 0.5
		size_slider.max_value = 2.5
		size_slider.value = settings.get("size", 1.0)
		count_slider.value = settings.get("count", 4)
		blade_count_container.visible = true
		blade_count_slider.value = settings.get("blade_count", 4.0)
		duct_container.visible = true
		duct_checkbox.tooltip_text = "Ducted Shroud"
		duct_checkbox.button_pressed = settings.get("duct", false)
	elif type_id == "legs":
		size_label_base = "Knee Height"
		count_container.visible = true
		size_slider.min_value = -0.5
		size_slider.max_value = 1.5
		size_slider.value = settings.get("knee_height", 0.375)
		count_slider.value = settings.get("count", 4)
	elif type_id == "hover_engine":
		size_label_base = "Electron Megavoltage"
		count_container.visible = true
		size_slider.min_value = 0.5
		size_slider.max_value = 2.5
		size_slider.value = settings.get("emv_level", 1.0)
		count_slider.min_value = 4.0
		count_slider.step = 1.0
		count_slider.value = settings.get("pad_count", 4)
	elif type_id == "fixed_wing_engine":
		size_label_base = "Turbine Compression"
		count_container.visible = true
		size_slider.min_value = 0.5
		size_slider.max_value = 2.0
		size_slider.value = settings.get("turbine_compression", 1.0)
		count_slider.min_value = 2.0
		count_slider.max_value = 6.0
		count_slider.step = 1.0
		count_slider.value = settings.get("engine_count", 2)
	elif type_id in ["naval_propeller", "buoyant_envelope"]:
		# Pylon-mounted rebuild (Chris's ask, 2026-07-24): no Size tweak at
		# all for either type - Count doubles as Propeller Count (1-5),
		# plus the shared Blade Count slider (reused from helicopter_rotors
		# above) and a new Blade Pitch slider.
		size_container.visible = false
		count_container.visible = true
		count_slider.min_value = 1.0
		# 6, not 5: buoyant_envelope's pod progression runs to three per side
		# (Chris). naval_propeller shares this branch and is unaffected - its
		# own layout still clamps at 5.
		count_slider.max_value = 6.0
		count_slider.step = 1.0
		count_slider.value = settings.get("prop_count", settings.get("count", 2))
		count_label_base = "Propeller Count"
		blade_count_container.visible = true
		blade_count_slider.value = settings.get("blade_count", 3.0)
		blade_pitch_container.visible = true
		blade_pitch_slider.value = settings.get("blade_pitch", 1.0)
	elif type_id == "screw_drive":
		# Rebuilt (Chris's ask, 2026-07-24): no Count at all - always one
		# drum per side, like tracked_treads. Size doubles as Drum Diameter
		# (see LOCOMOTION_SIZE_KEY), plus a new Helix Depth slider.
		size_label_base = "Drum Diameter"
		count_container.visible = false
		size_slider.min_value = 0.5
		size_slider.max_value = 2.0
		size_slider.value = settings.get("drum_diameter", settings.get("drum_width", 1.0))
		helix_depth_container.visible = true
		helix_depth_slider.value = settings.get("helix_depth", 1.0)
	elif type_id == "pontoon_wheels":
		# module_catalog.gd has declared these three since the type was added,
		# but no UI branch ever read them, so the type came up with no
		# tweakables at all (Chris's report, 2026-08-02) - it fell through to
		# the else below and hid the Size slider.
		size_label_base = "Pontoon Size"
		size_slider.min_value = 0.6
		size_slider.max_value = 1.8
		size_slider.value = settings.get("pontoon_size", 1.0)
		count_container.visible = true
		count_slider.min_value = 2.0
		count_slider.max_value = 6.0
		count_slider.step = 2.0
		count_slider.value = settings.get("axle_count", 4)
		count_label_base = "Axle Count"
		bool_tweak_key = "paddle_vanes"
		bool_tweak_title = "Paddle Vanes"
		duct_container.visible = true
		duct_checkbox.tooltip_text = "Paddle Vanes"
		duct_checkbox.button_pressed = settings.get("paddle_vanes", true)
	else:
		size_container.visible = false

	_refresh_locomotion_labels()
	
	if size_container.visible: _add_callout(module, "Size", size_container)
	if count_container.visible: _add_callout(module, "Count", count_container)
	if wheels_per_axle_container.visible: _add_callout(module, "Wheels Per Axle", wheels_per_axle_container)
	if blade_count_container.visible: _add_callout(module, "Blade Count", blade_count_container)
	if blade_pitch_container.visible: _add_callout(module, "Blade Pitch", blade_pitch_container)
	if helix_depth_container.visible: _add_callout(module, "Helix Depth", helix_depth_container)
	if duct_container.visible: _add_callout(module, bool_tweak_title, duct_container)
	
	is_updating_sliders = false

func _refresh_locomotion_labels():
	if size_label_base == "Knee Height":
		size_label.text = "%s: %+.2fm" % [size_label_base, size_slider.value]
	else:
		size_label.text = "%s: %.2fx" % [size_label_base, size_slider.value]
	if count_container.visible:
		count_label.text = "%s: %d" % [count_label_base, int(count_slider.value)]
	if wheels_per_axle_container.visible:
		var dually = int(wheels_per_axle_slider.value) >= 2
		wheels_per_axle_label.text = "Wheels Per Axle: %d%s" % [int(wheels_per_axle_slider.value), " (dually)" if dually else ""]
	if blade_count_container.visible:
		blade_count_label.text = "Blade Count: %d" % int(blade_count_slider.value)
	if blade_pitch_container.visible:
		blade_pitch_label.text = "Blade Pitch: %.2fx" % blade_pitch_slider.value
	if helix_depth_container.visible:
		helix_depth_label.text = "Helix Depth: %.2fx" % helix_depth_slider.value

func _on_size_value_changed(value: float):
	_refresh_locomotion_labels()
	if is_updating_sliders or not current_selected_module or not is_instance_valid(current_selected_module): return
	var root = get_node_or_null("/root/MainLab")
	if not root or not root.has_method("update_locomotion_geometry_tweak"): return
	var data = current_selected_module.get_meta("module_data")
	var type_id = data.type_id
	var key = LOCOMOTION_SIZE_KEY.get(type_id, "size")
	root.update_locomotion_geometry_tweak(type_id, key, value)

func _on_count_value_changed(value: float):
	_refresh_locomotion_labels()
	if is_updating_sliders or not current_selected_module or _loco_slider_dragging: return
	_apply_tweaks()

func _on_wheels_per_axle_changed(value: float):
	_refresh_locomotion_labels()
	if is_updating_sliders or not current_selected_module or not is_instance_valid(current_selected_module): return
	var root = get_node_or_null("/root/MainLab")
	if not root or not root.has_method("update_locomotion_geometry_tweak"): return
	root.update_locomotion_geometry_tweak("wheels", "wheels_per_axle", int(value))

func _on_blade_count_changed(value: float):
	_refresh_locomotion_labels()
	if is_updating_sliders or not current_selected_module or not is_instance_valid(current_selected_module): return
	var root = get_node_or_null("/root/MainLab")
	if not root or not root.has_method("update_locomotion_geometry_tweak"): return
	# Shared between helicopter_rotors and naval_propeller/buoyant_envelope
	# (Chris's ask, 2026-07-24) - was hardcoded to "helicopter_rotors",
	# which silently no-opped this slider for the other two types (their
	# module_data.tweaks never actually get a "blade_count" key written,
	# since update_locomotion_geometry_tweak() matches children by type_id).
	var data = current_selected_module.get_meta("module_data")
	root.update_locomotion_geometry_tweak(data.type_id, "blade_count", int(value))

func _on_blade_pitch_changed(value: float):
	_refresh_locomotion_labels()
	if is_updating_sliders or not current_selected_module or not is_instance_valid(current_selected_module): return
	var root = get_node_or_null("/root/MainLab")
	if not root or not root.has_method("update_locomotion_geometry_tweak"): return
	var data = current_selected_module.get_meta("module_data")
	root.update_locomotion_geometry_tweak(data.type_id, "blade_pitch", value)

func _on_helix_depth_changed(value: float):
	_refresh_locomotion_labels()
	if is_updating_sliders or not current_selected_module or not is_instance_valid(current_selected_module): return
	var root = get_node_or_null("/root/MainLab")
	if not root or not root.has_method("update_locomotion_geometry_tweak"): return
	var data = current_selected_module.get_meta("module_data")
	root.update_locomotion_geometry_tweak(data.type_id, "helix_depth", value)

func _on_duct_toggled(pressed: bool):
	if is_updating_sliders or not current_selected_module or not is_instance_valid(current_selected_module): return
	_push_undo()
	var root = get_node_or_null("/root/MainLab")
	if not root or not root.has_method("update_locomotion_geometry_tweak"): return
	var data = current_selected_module.get_meta("module_data")
	root.update_locomotion_geometry_tweak(data.type_id, bool_tweak_key, pressed)

func _on_loco_drag_started():
	_loco_slider_dragging = true
	_push_undo()

# Fires once when the mouse releases the slider grabber - this is where the
# actual (expensive, full-respawn) update_locomotion() call happens, not on
# every intermediate value_changed tick during the drag. See the comment on
# the drag_started/drag_ended connections in _ready() for why.
func _on_loco_drag_ended(value_changed: bool):
	_loco_slider_dragging = false
	if is_updating_sliders or not current_selected_module: return
	if value_changed:
		_apply_tweaks()

func _apply_tweaks():
	var root = get_node("/root/MainLab")
	var hull = root.get_node_or_null("Hull")
	if not root or not hull or not current_selected_module: return
	
	var data = current_selected_module.get_meta("module_data")
	var type_id = data.type_id
	var new_settings = {}
	
	if type_id == "wheels":
		new_settings = {
			"wheel_size": size_slider.value,
			"num_axles": int(count_slider.value),
			"wheels_per_axle": int(wheels_per_axle_slider.value)
		}
	elif type_id == "tracked_treads":
		new_settings = {
			"tread_width": size_slider.value
		}
	elif type_id == "helicopter_rotors":
		new_settings = {
			"size": size_slider.value,
			"count": int(count_slider.value),
			"blade_count": int(blade_count_slider.value),
			"duct": duct_checkbox.button_pressed
		}
	elif type_id == "legs":
		new_settings = {
			"knee_height": size_slider.value,
			"count": int(count_slider.value)
		}
	elif type_id == "pontoon_wheels":
		# paddle_vanes rides along for the same reason blade_count does below:
		# an Axle Count change respawns every instance, so a tweak left out of
		# this dict silently resets to its default on the next Count drag.
		new_settings = {
			"pontoon_size": size_slider.value,
			"axle_count": int(count_slider.value),
			"paddle_vanes": duct_checkbox.button_pressed
		}
	elif type_id == "hover_engine":
		new_settings = {
			"emv_level": size_slider.value,
			"pad_count": int(count_slider.value)
		}
	elif type_id == "fixed_wing_engine":
		new_settings = {
			"turbine_compression": size_slider.value,
			"engine_count": int(count_slider.value)
		}
	elif type_id in ["naval_propeller", "buoyant_envelope"]:
		# Count (Propeller Count) is structural here too - changing it
		# respawns every prop instance, so blade_count/blade_pitch have to
		# ride along in the same settings dict or they'd silently reset to
		# their defaults on the very next Count drag.
		new_settings = {
			"prop_count": int(count_slider.value),
			"blade_count": int(blade_count_slider.value),
			"blade_pitch": blade_pitch_slider.value
		}
	elif type_id == "screw_drive":
		new_settings = {
			"drum_diameter": size_slider.value,
			"helix_depth": helix_depth_slider.value
		}

	if root.has_method("update_locomotion"):
		# Update positions/scales immediately
		root.update_locomotion(type_id, new_settings)
		# Reselect the new node counterpart to keep selection and UI visible
		var new_selected = null
		for child in hull.get_children():
			# update_locomotion() just queue_free()'d every OLD instance of
			# this type before spawning the new ones - queue_free() doesn't
			# remove a node from its parent immediately, so the doomed old
			# instances are still in get_children() (and, since they were
			# added earlier, sorted BEFORE the fresh replacements) at this
			# exact point. Without this check, "first match" reliably picked
			# a soon-to-be-freed old instance instead of a live new one; by
			# the time the deferred _select_module below actually ran, that
			# instance had already been freed, and on_module_selected()
			# calling .has_meta() on it threw - which left
			# current_selected_module corrupted (pointing at a freed
			# object) for every tweak afterward, until the player manually
			# reselected. Confirmed via a real drag-up-then-drag-down test:
			# the second (down) drag silently no-op'd because of exactly
			# this.
			if child.is_queued_for_deletion(): continue
			if child.has_meta("module_data"):
				var m_data = child.get_meta("module_data")
				if m_data and m_data.type_id == type_id:
					new_selected = child
					break
		if new_selected:
			root.call_deferred("_select_module", new_selected)

# --- Rail dock + top toolbar (VISUAL/UI plan item 7) ------------------------

# Wraps the telemetry rail in a UIDock and lifts its action controls into a thin
# STEEL toolbar across the top of the Lab.
#
# WHY THE TOOLBAR EXISTS. Undo, Redo, Mirror, Save, Test, Library and the
# hull-spec trigger were seven rows stacked in a 320px column, present whether or
# not they applied to anything - and Undo/Redo in particular are document-level
# actions that belong on a toolbar, not buried under a stat readout. Lifting them
# out is also what lets the dock rail away to 40px and still be useful: what is
# left in the rail is genuinely just the blueprint's identity and its headline
# numbers, which is the only part worth reading continuously.
#
# DEFAULT STATE IS RAILED. The plan's whole complaint about the Design Lab is
# that the 3D model - the actual subject - got the leftover middle. Both docks
# start collapsed so the viewport has the screen until the player asks for a
# panel. `auto_reveal` stays OFF: a dock that vanishes on mouse-out is a nuisance
# in an editor and a defect in combat, and this primitive is shared with the HUD.
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

	_build_toolbar()


# The thin top toolbar. STEEL band via HeaderPanel, which already carries the
# hazard underline that separates chrome from viewport.
func _build_toolbar() -> void:
	var bar = PanelContainer.new()
	bar.name = "Toolbar"
	bar.theme_type_variation = "HeaderPanel"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	bar.offset_top = 0.0
	# Tall enough to clear Tokens.HIT_TARGET_MIN with the band's own padding. Both
	# docks inset their top by this same token so nothing is drawn over the bar.
	bar.offset_bottom = Tokens.TOOLBAR_HEIGHT
	add_child(bar)
	toolbar = bar

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.SPACE_SM)
	bar.add_child(row)

	# Undo/Redo first: they act on the document, and reading order should match
	# the fact that they are the two most-used controls in the Lab.
	_undo_btn = _toolbar_button(row, "UNDO", "undo", func(): _toolbar_undo())
	_redo_btn = _toolbar_button(row, "REDO", "redo", func(): _toolbar_redo())

	row.add_child(VSeparator.new())

	# Mirror is a mode, so it stays a checkbox rather than becoming a button -
	# a latched state needs to look latched.
	if mirror_checkbox:
		mirror_checkbox.reparent(row)

	row.add_child(VSeparator.new())

	# The flyout trigger, and then the document actions. Save last-but-one and
	# Test last, so the two that leave or commit the screen sit furthest from
	# Undo/Redo and cannot be hit by accident on the way to them.
	if hull_spec_btn:
		hull_spec_btn.reparent(row)
	if library_button:
		library_button.reparent(row)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	if save_button:
		save_button.reparent(row)
	if test_button:
		test_button.reparent(row)


func _toolbar_undo() -> void:
	var root = get_node_or_null("/root/MainLab")
	if root and root.has_method("undo"):
		root.undo()


func _toolbar_redo() -> void:
	var root = get_node_or_null("/root/MainLab")
	if root and root.has_method("redo"):
		root.redo()


func _toolbar_button(parent: Container, label: String, icon_name: String, cb: Callable) -> Button:
	var b = Button.new()
	b.text = label
	if UIIconsScript.has_icon(icon_name):
		b.icon = UIIconsScript.get_icon(icon_name)
	b.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# --- Hull spec flyout -------------------------------------------------------

# Opens the hull-spec flyout, or closes it if it is already up so the trigger
# toggles rather than stacking a second copy on every press.
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
	flyout.open_from(hull_spec_btn, UIFlyoutScript.Align.LEFT_OF)


func _on_hull_spec_closed() -> void:
	for ctrl in _hull_spec_widgets():
		if is_instance_valid(ctrl) and ctrl.get_parent() != hull_spec_stash:
			ctrl.reparent(hull_spec_stash)
	_hull_spec_flyout = null


# Declared in display order once, so open and close cannot disagree about which
# controls belong to the flyout - a mismatch would strand a widget in a freed
# panel and take the control with it.
func _hull_spec_widgets() -> Array:
	return [
		armor_mat_label, armor_mat_btn,
		faction_label, faction_btn,
		armor_thick_label, armor_thick_slider,
	]


func _on_armor_material_selected(index: int):
	if is_updating_sliders: return
	var root = get_node_or_null("/root/MainLab")
	if not root: return
	var hull = root.get_node_or_null("Hull")
	if not hull: return
	_push_undo()

	var mat_name = "hardened_steel"
	match index:
		0: mat_name = "hardened_steel"
		1: mat_name = "reactive_armor"
		2: mat_name = "ablative_ceramic"
		3: mat_name = "energy_shielding"
		
	hull.set_meta("armor_material", mat_name)
	if root.has_method("update_hull_appearance"):
		root.update_hull_appearance()
	update_stats(hull)

func _on_armor_thickness_changed(value: float):
	if is_updating_sliders: return
	var root = get_node_or_null("/root/MainLab")
	if not root: return
	var hull = root.get_node_or_null("Hull")
	if not hull: return
	
	hull.set_meta("armor_thickness", value)
	if armor_thick_label:
		armor_thick_label.text = "Armor Thickness: %.1f" % value
	if root.has_method("update_hull_appearance"):
		root.update_hull_appearance()
	update_stats(hull)

func _on_faction_selected(index: int):
	if is_updating_sliders: return
	var root = get_node_or_null("/root/MainLab")
	if not root: return
	var hull = root.get_node_or_null("Hull")
	if not hull: return
	_push_undo()

	var ids = FactionCatalog.get_ids()
	var fac_name = ids[index] if index >= 0 and index < ids.size() else FactionCatalog.DEFAULT_FACTION

	hull.set_meta("faction", fac_name)
	if root.has_method("update_hull_appearance"):
		root.update_hull_appearance()
	update_stats(hull)

func _initial_sync():
	var root = get_node_or_null("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null
	if hull:
		if not hull.has_meta("blueprint_name"):
			hull.set_meta("blueprint_name", "Untitled Design")
		sync_hull_ui(hull)

func _on_tweak_changed():
	if current_selected_module and is_instance_valid(current_selected_module):
		var primary_data = current_selected_module.get_meta("module_data") if current_selected_module.has_meta("module_data") else null
		VisualBuilder.rebuild_visual(current_selected_module)
		if current_selected_module.has_meta("mirrored_counterpart"):
			var mirror = current_selected_module.get_meta("mirrored_counterpart")
			if mirror and is_instance_valid(mirror):
				# Sync tweaks directly to the mirror so symmetric edits work correctly
				var mirror_data = mirror.get_meta("module_data") if mirror.has_meta("module_data") else null
				if primary_data and mirror_data:
					mirror_data.tweaks = primary_data.tweaks.duplicate()
				VisualBuilder.rebuild_visual(mirror)
				
	var root = get_node_or_null("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null
	if hull:
		update_stats(hull)
		# Update popup stats label text too
		if current_selected_module and is_instance_valid(current_selected_module) and current_selected_module.has_meta("module_data"):
			var data = current_selected_module.get_meta("module_data")
			if popup_stats_label:
				var hp = data.get_hp()
				var wt = data.get_weight()
				var cost = data.get_cost()
				var dps = data.get_dps()
				var heal = data.get_heal_rate()
				var last_line = "Heal Rate: %.1f/s" % heal if heal > 0.0 else "DPS: %.1f" % dps
				var mount_line = _mount_style_line(current_selected_module.get_meta("mount_style", ""))
				popup_stats_label.text = "HP: %.1f | Weight: %.1f kg\nCost: %d Metal, %d Crystal\n%s%s" % [hp, wt, cost.x, cost.y, last_line, mount_line]
		# Same root-not-child correction as the rotate sites above.
		if root and root.has_method("check_all_clipping"):
			root.check_all_clipping()

# mount_style (module_placer.gd/module_catalog.gd) drives real combat
# behavior (whether the weapon independently traverses or the whole
# vehicle aims instead) but was never named or explained anywhere in the
# UI - a player just saw the result with no indication these are distinct
# categories with different rules. Appended to the floating module popup
# (not the fixed sidebar, which has zero layout slack left - see the
# manufactory-tier tooltip judgment call above) since this only applies to
# weapons, not every module. Visual placement (flush-mounted to whatever
# facet it's on) is the same for all three styles now - only traverse
# differs, so the wording below describes traverse, not mount geometry.
func _mount_style_line(style: String) -> String:
	var desc = ""
	match style:
		"turret": desc = "Turret mount (full traverse)"
		"frame_built": desc = "Frame-built (fixed - whole vehicle aims)"
		"pintle": desc = "Pintle mount (full traverse)"
	return "\n%s" % desc if desc != "" else ""

const ARMOR_MATERIALS = ["hardened_steel", "reactive_armor", "ablative_ceramic", "energy_shielding"]
const ARMOR_MATERIAL_LABELS = ["Hardened Steel", "Reactive Armor", "Ablative Ceramic", "Energy Shielding"]

func _generate_custom_tweaks(module: Node3D, data: ModuleDataResource):
	var type_id = data.type_id

	if data.category == "armor":
		var mat_container = VBoxContainer.new()
		mat_container.add_theme_constant_override("separation", 2)

		var current_mat = data.tweaks.get("material", "hardened_steel")
		var current_idx = ARMOR_MATERIALS.find(current_mat)
		if current_idx < 0: current_idx = 0

		var mat_btn = OptionButton.new()
		for lbl in ARMOR_MATERIAL_LABELS:
			mat_btn.add_item(lbl)
		mat_btn.selected = current_idx
		mat_container.add_child(mat_btn)
		mat_btn.item_selected.connect(func(index: int):
			_push_undo()
			data.tweaks["material"] = ARMOR_MATERIALS[index]
			_on_tweak_changed()
		)
		_add_callout(module, "Plate Material", mat_container)

	if ModuleCatalog.is_ammo_capable(type_id):
		var ammo_options = ModuleCatalog.get_ammo_options(type_id)
		var current_ammo = ModuleCatalog.get_ammo(type_id, data.tweaks)
		var ammo_idx = max(ammo_options.find(current_ammo), 0)

		var ammo_container = VBoxContainer.new()
		ammo_container.add_theme_constant_override("separation", 2)

		var ammo_btn = OptionButton.new()
		for a in ammo_options:
			ammo_btn.add_item(ModuleCatalog.get_ammo_profile(a).label)
		ammo_btn.selected = ammo_idx
		ammo_container.add_child(ammo_btn)

		var ammo_desc = Label.new()
		ammo_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ammo_desc.custom_minimum_size.x = 220
		ammo_desc.add_theme_font_size_override("font_size", 11)
		ammo_desc.modulate = Color(1, 1, 1, 0.65)
		ammo_desc.text = ModuleCatalog.get_ammo_profile(ammo_options[ammo_idx]).desc
		ammo_container.add_child(ammo_desc)

		ammo_btn.item_selected.connect(func(index: int):
			_push_undo()
			var picked = ammo_options[index]
			data.tweaks[ModuleCatalog.AMMO_TWEAK_KEY] = picked
			var profile = ModuleCatalog.get_ammo_profile(picked)
			ammo_desc.text = profile.desc
			_on_tweak_changed()
		)
		_add_callout(module, "Loaded Ammo", ammo_container)

	if not TWEAK_SPECS.has(type_id): return

	var specs = TWEAK_SPECS[type_id]
	for spec in specs:
		if spec.get("type", "") == "bool":
			var check = CheckBox.new()
			check.button_pressed = data.tweaks.get(spec.name, spec.default)
			check.tooltip_text = spec.label
			
			check.toggled.connect(func(pressed):
				_push_undo()
				data.tweaks[spec.name] = pressed
				_on_tweak_changed()
			)
			_add_callout(module, spec.label, check)
		else:
			var container = VBoxContainer.new()
			container.add_theme_constant_override("separation", 0)
			
			var label = Label.new()
			container.add_child(label)

			var slider = HSlider.new()
			slider.min_value = spec.min
			slider.max_value = spec.max
			slider.step = spec.step
			slider.value = data.tweaks.get(spec.name, spec.default)
			slider.custom_minimum_size = Vector2(180, 0)
			container.add_child(slider)

			if spec.step == 1.0:
				label.text = "%d" % int(slider.value)
			else:
				label.text = "%.2fx" % slider.value

			slider.drag_started.connect(_push_undo)
			slider.value_changed.connect(func(val):
				data.tweaks[spec.name] = val
				if spec.step == 1.0:
					label.text = "%d" % int(val)
				else:
					label.text = "%.2fx" % val
				_on_tweak_changed()
			)
			_add_callout(module, spec.label, container)

func _process(delta):
	pass


# Routed through SceneRouter so leaving this screen fades out rather than cutting.
# The get_node_or_null guard keeps the direct call as a fallback, matching the
# pattern the other router call sites in this file already use - a scene
# instantiated outside the running game (a test fixture) has no autoloads.
func _return_to_menu() -> void:
	var router = get_node_or_null("/root/SceneRouter")
	if router:
		router.goto("res://scenes/MainMenu.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
