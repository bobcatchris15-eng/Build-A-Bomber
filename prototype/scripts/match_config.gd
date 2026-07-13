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
