extends RefCounted
# The tutorial script, as data.
#
# One entry per step. tutorial_manager.gd walks this array; tutorial_overlay.gd
# renders whichever entry is current. Nothing here knows how a step is drawn or
# how its condition is evaluated - that separation is what lets the copy be
# rewritten without touching the driver, and lets test_tutorial.gd validate the
# whole table without instantiating a single scene.
#
# FIELDS
#   scene    Which scene the step belongs to. The manager holds position while
#            the player is anywhere else, so a step never fires against a screen
#            it was not written for.
#   title    The card heading. Short.
#   body     The explanation. Autowrapped; write it as prose, not as a keymap.
#   target   What to spotlight. "" means a centred card with no cutout. See
#            tutorial_overlay._resolve_target() for the vocabulary.
#   advance  What has to become true before the step is done. See
#            tutorial_manager._condition_met() for the vocabulary.
#
# NO EMOJI OR DINGBATS in title or body - standing project rule, and
# test_tutorial_step_table_is_well_formed() enforces it here even though the
# scene-scanning UI tone suite cannot (this text lives in a script, not a .tscn).

const SCENE_LAB := "res://scenes/MainLab.tscn"
const SCENE_ARENA := "res://scenes/Battlefield.tscn"

const STEPS := [
	{
		"scene": SCENE_LAB,
		"title": "WELCOME TO THE DESIGN BUREAU",
		"body": "In Kitbash Command you do not pick units off a list - you build them. "
			+ "Everything you field in a battle is designed here first.\n\n"
			+ "Camera: hold right mouse to orbit, middle mouse to pan, wheel to zoom. "
			+ "Try it now, then continue.",
		"target": "",
		"advance": "next_button",
	},
	{
		"scene": SCENE_LAB,
		"title": "THE HARDWARE CATALOG",
		"body": "Every part you can bolt on lives in this catalog, filed under four "
			+ "toolboxes: Hulls, Weapons, Support and Drives. Open a toolbox, then a "
			+ "drawer inside it, to see the parts.\n\n"
			+ "The search box cuts across all four at once.",
		"target": "parts_dock",
		"advance": "next_button",
	},
	{
		"scene": SCENE_LAB,
		"title": "START WITH A CHASSIS",
		"body": "Every design starts with a hull. It sets your base structure, your "
			+ "weight before anything is fitted, and how much surface you have to "
			+ "mount things on.\n\n"
			+ "Drag the highlighted Medium Hull out of the catalog and drop it on the "
			+ "platform. Any hull works - this one is a reasonable place to start.",
		"target": "part_card:medium_hull",
		"advance": "hull_replaced",
	},
	{
		"scene": SCENE_LAB,
		"title": "GIVE IT SOMETHING TO RUN ON",
		"body": "A hull with no drive is a pillbox. Drag Wheels onto the chassis and "
			+ "the Lab works out where the axles sit for you.\n\n"
			+ "Drives carry a weight capacity. Overload it and the design still runs, "
			+ "just slower - the telemetry rail will tell you when that happens.",
		"target": "part_card:wheels",
		"advance": "locomotion_placed",
	},
	{
		"scene": SCENE_LAB,
		"title": "ARM IT",
		"body": "Drop the Basic Cannon onto the hull. Parts snap to whichever facet you "
			+ "drop them on, and a weapon can only shoot where its facet faces.\n\n"
			+ "Mirror mode is on by default - place something off the centreline and a "
			+ "matching part appears on the far side. Press M to toggle it.",
		"target": "part_card:basic_cannon",
		"advance": "weapon_placed",
	},
	{
		"scene": SCENE_LAB,
		"title": "PARTS ARE ADJUSTABLE",
		"body": "Click a part you have placed. It gets a set of gizmo handles: drag "
			+ "those to stretch a barrel or open up a calibre, and the stats update "
			+ "while you drag.\n\n"
			+ "Press R to rotate a selected part. Delete removes it.",
		"target": "hull",
		"advance": "module_selected",
	},
	{
		"scene": SCENE_LAB,
		"title": "READ THE TELEMETRY",
		"body": "This rail is the truth about your design: structure, weight, cost, and "
			+ "damage per second, all recomputed live as you build.\n\n"
			+ "Watch the drivetrain readout in particular. A design that is over its "
			+ "weight capacity will be outrun by everything on the field.",
		"target": "telemetry_dock",
		"advance": "next_button",
	},
	{
		"scene": SCENE_LAB,
		"title": "NAME IT",
		"body": "Type a name for this design. Saving refuses an unnamed blueprint on "
			+ "purpose - an unnamed roster is impossible to draft from later.\n\n"
			+ "There is a roll button beside the field if you would rather not think "
			+ "of one.",
		"target": "name_field",
		"advance": "design_named",
	},
	{
		"scene": SCENE_LAB,
		"title": "SAVE IT TO THE LIBRARY",
		"body": "Save writes the blueprint to your library. From there it can be drafted "
			+ "into a Skirmish or an Operation and produced from a factory like any "
			+ "other unit.\n\n"
			+ "If Save refuses, you have overlapping parts - the Lab will not let a "
			+ "clipping design out the door.",
		"target": "toolbar_save",
		"advance": "blueprint_saved",
	},
	{
		"scene": SCENE_LAB,
		"title": "NOW TEST IT",
		"body": "A design on paper tells you very little. Test in Arena drops this exact "
			+ "vehicle onto the proving ground so you can drive it and shoot it.\n\n"
			+ "Your work is not lost by leaving - the Lab restores it when you come back.",
		"target": "toolbar_test",
		"advance": "scene_is_arena",
	},
	{
		"scene": SCENE_ARENA,
		"title": "THE PROVING GROUND",
		"body": "Your design, live, against target dummies. Some of them shoot back.\n\n"
			+ "This is the same unit code that runs in a real battle - it acquires "
			+ "targets, manoeuvres to bring armour to bear, and fires on its own.",
		"target": "",
		"advance": "next_button",
	},
	{
		"scene": SCENE_ARENA,
		"title": "GIVE IT AN ORDER",
		"body": "Right-click somewhere on the ground. Your vehicle will drive there.\n\n"
			+ "How quickly it gets moving is your drive choice and your weight, exactly "
			+ "as the telemetry rail predicted back in the Lab.",
		"target": "",
		"advance": "arena_move_ordered",
	},
	{
		"scene": SCENE_ARENA,
		"title": "ENGAGE",
		"body": "Drive within range of a dummy. You do not need to give a fire order - "
			+ "the vehicle acquires and engages by itself.\n\n"
			+ "Watch what happens to your health readout while it does. Armour is "
			+ "directional: it only protects the facet the shot came from.",
		"target": "arena_dummy",
		"advance": "arena_dummy_destroyed",
	},
	{
		"scene": SCENE_ARENA,
		"title": "TAKE WHAT YOU LEARNED BACK",
		"body": "That is the whole point of the range - find the weakness here, where it "
			+ "costs nothing, rather than in an Operation.\n\n"
			+ "Head back to the Lab. Your design comes with you.",
		"target": "arena_return",
		"advance": "scene_is_lab",
	},
	{
		"scene": SCENE_LAB,
		"title": "THAT IS THE LOOP",
		"body": "Build, test, refine, repeat. Your design is in the Blueprint Library and "
			+ "ready to be drafted.\n\n"
			+ "From the main menu: Skirmish is a single battle, Operations is a run of "
			+ "three to twelve with a re-draft between each. Both field what you build "
			+ "here.",
		"target": "",
		"advance": "finish_button",
	},
]


# Every `advance` value the table is allowed to use. tutorial_manager.gd
# switches on exactly this set, and test_tutorial.gd asserts the two agree - a
# typo'd condition would otherwise strand the player on a step forever, which is
# the single worst failure this feature has.
const ADVANCE_IDS := [
	"next_button",
	"finish_button",
	"hull_replaced",
	"locomotion_placed",
	"weapon_placed",
	"module_selected",
	"design_named",
	"blueprint_saved",
	"scene_is_arena",
	"scene_is_lab",
	"arena_move_ordered",
	"arena_dummy_destroyed",
]


# Every `target` value, minus the "part_card:<type_id>" family which is checked
# by prefix. Same contract as ADVANCE_IDS: the overlay resolves exactly these.
const TARGET_IDS := [
	"",
	"parts_dock",
	"telemetry_dock",
	"name_field",
	"toolbar_save",
	"toolbar_test",
	"hull",
	"arena_dummy",
	"arena_return",
]

const PART_CARD_PREFIX := "part_card:"


static func count() -> int:
	return STEPS.size()


static func step(index: int) -> Dictionary:
	if index < 0 or index >= STEPS.size():
		return {}
	return STEPS[index]


# True when the step wants a button on the card rather than a game action. Both
# ids mean "the player has read this"; they differ only in the button's label,
# because "NEXT" on the final card would be a lie about what happens.
static func is_button_step(advance: String) -> bool:
	return advance == "next_button" or advance == "finish_button"
