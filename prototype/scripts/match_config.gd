extends Node
# Autoload singleton: carries the player's map choice from MapSelect.tscn
# across the scene change into Skirmish.tscn. Godot's change_scene_to_file()
# doesn't give the caller a handle to configure the new scene before it
# enters the tree, so a tiny autoload is the standard way to pass this kind
# of "next scene's setup" data - simpler than manually managing the scene
# tree swap just to inject one field.
#
# skirmish.gd reads this defensively (get_node_or_null("/root/MatchConfig"),
# duck-typed check for the field) rather than assuming it exists, so every
# headless test that instantiates Skirmish.tscn directly - with no autoload
# registered at all in that boot path - keeps working unchanged, falling
# back to MapCatalog.DEFAULT_MAP_ID.

var selected_map_id: String = ""

# Pre-match settings (map variety batch, part 2): set by MatchSetup.tscn
# after map selection, read defensively by skirmish.gd the same way
# selected_map_id already is - every field here has an "unset" sentinel
# ("" for strings, [] for the blueprint list, -1 for resource amounts) so
# any headless test/direct-instantiation path that never touches this
# autoload keeps getting Skirmish's own hardcoded defaults, unchanged.
var player_faction: String = "" # "" = derive from roster[0], old behavior
var enemy_faction: String = "" # "" = derive from enemy_roster[0], old behavior
var selected_blueprint_paths: Array = [] # [] = automatic top-8-newest-saved, old behavior
var ai_difficulty: String = "normal" # "easy" / "normal" / "hard"
var starting_metal: int = -1 # -1 = Skirmish's own default (450)
var starting_crystal: int = -1 # -1 = Skirmish's own default (150)
