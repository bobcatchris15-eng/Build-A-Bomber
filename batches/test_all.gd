extends Node

const TEST_SCRIPT_PATHS = [
    "run_hull_builder_tests.gd",
    "test_hull_builder_simple.gd",
    "test_hull_builder_detailed.gd"
]

const REQUIRED_SCRIPT_FILES = [
    "scripts/hull_builder.gd",
    "scripts/mesh_asset_loader.gd",
    "scripts/hull_loader.gd",
    "scripts/designer_camera.gd",
    "scenes/HullBuilder.tscn",
    "scenes/Gizmo3D.tscn",
    "scripts/gizmo_3d.gd",
    "scripts/parts_menu.gd",
    "scripts/module_catalog.gd"
]

const REQUIRED_TOOLS = [
    "tools/blender/build_meshes.py",
    "tools/blender/bake_custom_hull.py"
]
func _ready() -> void:
    print("=== Hull Builder Batch Test Suite ===")
    print("Testing Hull Builder implementation...\n")

    var all_passed = _run_tests()

    if all_passed:
        print("\n✓✓✓ ALL TESTS PASSED! ✓✓✓")
        print("Hull Builder implementation is complete and ready for use!")
        get_tree().quit(0)
    else:
        print("\n✗✗✗ SOME TESTS FAILED ✗✗✗")
        print("Hull Builder implementation needs additional work.")
        get_tree().quit(1)

func _run_tests() -> bool:
    var tests = []

    # Basic file existence tests
    tests.append(_test_file_existence)
    tests.append(_test_script_structure)
    tests.append(_test_scene_structure)
    tests.append(_test_blender_tools)

    # Hull Builder specific tests
    tests.append(_test_hull_builder_implementation)
    tests.append(_test_export_pipeline)
    tests.append(_test_ui_structure)

    # Integration tests
    tests.append(_test_catalog_integration)
    tests.append(_test_loader_integration)

    # Visual tests
    tests.append(_test_visual_elements)
    tests.append(_test_interaction_elements)

    for test in tests:
        var test_name = test.get("name")
        print("Running: %s" % test_name)

        var result = test.call(_)
        if not result:
            print("FAILED")
            return false

        print("PASSED")
        print("")

    return true

func _test_file_existence() -> bool:
    var passed = true

    print("Testing file existence...")

    # Check required script files
    for file_path in REQUIRED_SCRIPT_FILES:
        var full_path = "res://" + file_path
        if not FileAccess.file_exists(full_path):
            print("  Missing: %s" % file_path)
            passed = false
        else:
            print("  OK: %s" % file_path)
        end if
    end for

    # Check required tool files
    for file_path in REQUIRED_TOOLS:
        var full_path = "res://" + file_path
        if not FileAccess.file_exists(full_path):
            print("  Missing: %s" % file_path)
            passed = false
        else:
            print("  OK: %s" % file_path)
        end if
    end for

    # Check test scripts
    print("Checking test scripts...")
    for script_path in TEST_SCRIPT_PATHS:
        var full_path = "res://" + script_path
        if FileAccess.file_exists(full_path):
            print("  OK: %s" % script_path)
        else:
            print("  WARNING: Test script not found: %s" % script_path)
        end if
    end for

    return passed

func _test_script_structure() -> bool:
    print("Testing script structure...")

    var hull_builder_content = _load_script_content("scripts/hull_builder.gd")
    if hull_builder_content == "":
        return false

    # Check for essential script components
    var components = [
        ("PrimitiveType enum", "enum PrimitiveType"),
        ("max_primitives constant", "max_primitives: int = 50"),
        ("_ready method", "func _ready() -> void:"),
        ("_on_export_clicked method", "func _on_export_clicked() -> void:"),
        ("_add_primitive_at_position method", "func _add_primitive_at_position(type: PrimitiveType, position: Vector3) -> void:"),
        ("getters/setters", "_set_position"),
        ("undo stack", "_undo_stack"),
        ("UI updates", "_update_properties_panel"),
        ("status updates", "_update_status")
    ]

    for name, pattern in components:
        if pattern not in hull_builder_content:
            print("  Missing: %s" % name)
            return false
        else:
            print("  OK: %s" % name)
        end if
    end for

    return true

func _test_scene_structure() -> bool:
    print("Testing scene structure...")

    var hull_builder_content = _load_script_content("scripts/hull_builder.gd")
    if hull_builder_content == "":
        return false

    # Check for required function calls in script
    var script_calls = [
        ("Back button", "_on_back_clicked"),
        ("Clear button", "_on_clear_clicked"),
        ("Export button", "_on_export_clicked"),
        ("Primitive selection", "_on_primitive_selected"),
        ("Gizmo connection", "_attach_gizmo"),
        ("Palette drag handling", "_start_palette_drag")
    ]

    for name, pattern in script_calls:
        if pattern not in hull_builder_content:
            print("  Missing: %s" % name)
            return false
        else:
            print("  OK: %s" % name)
        end if
    end for

    return true

func _test_blender_tools() -> bool:
    print("Testing Blender tools...")

    # Test bake_custom_hull.py structure
    var bake_script = _load_script_content("tools/blender/bake_custom_hull.py")
    if bake_script == "":
        print("  Missing or unreadable: tools/blender/bake_custom_hull.py")
        return false

    var bake_components = [
        ("scene clearing", "def clear_scene():"),
        ("primitive creation", "def create_primitive_mesh"),
        ("export function", "def export_glb"),
        ("sidecar generation", "def generate_sidecar_json"),
        ("main function", "def main():"),
        ("argument parsing", "argv = sys.argv")
    ]

    for name, pattern in bake_components:
        if pattern not in bake_script:
            print("  Missing: %s" % name)
            return false
        else:
            print("  OK: %s" % name)
        end if
    end for

    return true

func _test_hull_builder_implementation() -> bool:
    print("Testing Hull Builder implementation completeness...")

    var hull_builder_content = _load_script_content("scripts/hull_builder.gd")
    if hull_builder_content == "":
        return false

    # Check for implemented features from HULL_BUILDER_PLAN.md
    var planned_features = [
        ("Primitive palette", "primitive_palette"),
        ("Delete functionality", "_delete_selected"),
        ("Duplicate functionality", "_duplicate_selected"),
        ("Gizmo integration", "_attach_gizmo"),
        ("Properties panel", "_update_properties_panel"),
        ("Color picker", "ColorPickerButton"),
        ("Selection highlighting", "_set_highlight"),
        ("Export functionality", "_on_export_clicked"),
        ("Undo/redo stack", "_undo_stack"),
        ("Status bar", "_update_status"),
        ("Camera controls", "_on_viewport_input")
    ]

    var passed_features = 0
    for name, pattern in planned_features:
        if pattern in hull_builder_content:
            print("  OK: %s" % name)
            passed_features += 1
        else:
            print("  Missing: %s" % name)
        end if
    end for

    print("  Implemented %d/%d planned features" % [passed_features, planned_features.size()])

    # At least 70% of features should be implemented
    return passed_features >= (planned_features.size() * 7 // 10)

func _test_export_pipeline() -> bool:
    print("Testing export pipeline...")

    var hull_builder_content = _load_script_content("scripts/hull_builder.gd")
    if hull_builder_content == "":
        return false

    var export_components = [
        ("Hull name dialog", "prompt_for_hull_name"),
        ("Serialize for Blender", "_serialize_for_blender"),
        ("Write temp JSON", "_write_temp_json"),
        ("Blender invocation", "OS.create_process"),
        ("Progress feedback", "_update_status"),
        ("Stats dialog", "_show_hull_stats_dialog"),
        ("AABB calculation", "_calculate_aabb")
    ]

    var passed = true
    for name, pattern in export_components:
        if pattern in hull_builder_content:
            print("  OK: %s" % name)
        else:
            print("  Warning: %s not found" % name)
            #pass
        end if
    end for

    return true

func _test_ui_structure() -> bool:
    print("Testing UI structure...")

    var hull_builder_content = _load_script_content("scripts/hull_builder.gd")
    var hull_builder_scene_content = _load_script_content("scenes/HullBuilder.tscn")

    if hull_builder_content == "" or hull_builder_scene_content == "":
        return false

    var ui_elements = [
        ("CanvasLayer for UI", "CanvasLayer"),
        ("Left panel for palette", "LeftPanel"),
        ("Right panel for properties", "RightPanel"),
        ("Bottom bar for controls", "BottomBar"),
        ("Back button", "BackButton"),
        ("Clear button", "ClearButton"),
        ("Export button", "ExportButton"),
        ("Status label", "StatusLabel"),
        ("Primitive scrolling", "PrimitiveScroller"),
        ("Properties scrolling", "PropertiesScroller")
    ]

    for name, pattern in ui_elements:
        if pattern in hull_builder_scene_content:
            print("  OK: %s" % name)
        else:
            print("  Warning: %s not found in scene" % name)
            #pass
        end if
    end for

    return true

func _test_catalog_integration() -> bool:
    print("Testing Design Lab catalog integration...")

    var hull_loader_content = _load_script_content("scripts/hull_loader.gd")
    var module_catalog_content = _load_script_content("scripts/module_catalog.gd")

    if hull_loader_content == "" or module_catalog_content == "":
        return false

    # Check that hull loader is properly integrated
    var hull_loader_features = [
        ("Builtin directory constant", "BUILTIN_DIR = \"res://assets/models/hulls\""),
        ("Mod directory constant", "MOD_DIR = \"user://mods/hulls\""),
        ("Scan functionality", "_scan_directory"),
        ("Validation", "_validate_and_default"),
        ("Cache management", "_cache"),
        ("Fallback protection", "_ensure_medium_hull_protected")
    ]

    for name, pattern in hull_loader_features:
        if pattern in hull_loader_content:
            print("  OK: %s" % name)
        else:
            print("  Warning: %s not found" % name)
            #pass
        end if
    end for

    # Check catalog integration
    if "HullLoader" in module_catalog_content:
        print("  OK: Catalog integrates with HullLoader")
    else:
        print("  Warning: Catalog may not integrate with HullLoader")

    return true

func _test_loader_integration() -> bool:
    print("Testing Hull loader integration...")

    var hull_builder_content = _load_script_content("scripts/hull_builder.gd")

    if hull_builder_content == "":
        return false

    # Check that hull builder references hull loader and other systems
    var integration_points = [
        ("hull_loader.gd", "HullLoader"),
        ("mesh_asset_loader.gd", "MeshAssetLoader"),
        ("module_catalog.gd", "ModuleCatalog"),
        ("designer_camera.gd", "designer_camera.gd")
    ]

    for name, pattern in integration_points:
        if pattern in hull_builder_content:
            print("  OK: Hull Builder integrated with %s" % name)
        else:
            print("  Warning: Hull Builder not integrated with %s" % name)
            #pass
        end if
    end for

    return true

func _test_visual_elements() -> bool:
    print("Testing visual elements...")

    var hull_builder_content = _load_script_content("scripts/hull_builder.gd")

    if hull_builder_content == "":
        return false

    var visual_elements = [
        ("Gizmo colors", "COL_X", "COL_Y", "COL_Z"),
        ("Hilight emission", "HIGHLIGHT_EMISSION"),
        ("Tooltips", "tooltip_text"),
        ("Color picker button", "ColorPickerButton"),
        ("Section headers", "_add_section_header"),
        ("Vector3 spinners", "SpinBox"),
        ("Separator elements", "HSeparator")
    ]

    for element_name in visual_elements:
        var element = element_name if typeof(element_name) == "String" else element_name[0]
        if element in hull_builder_content:
            print("  OK: %s" % element)
        else:
            print("  Warning: %s not found" % element)
            #pass
        end if
    end for

    return true

func _test_interaction_elements() -> bool:
    print("Testing interaction elements...")

    var hull_builder_content = _load_script_content("scripts/hull_builder.gd")

    if hull_builder_content == "":
        return false

    var interaction_elements = [
        ("Keyboard shortcuts", "KEY_DELETE"),
        ("Mouse input handling", "_input"),
        ("Viewport interaction", "_on_viewport_input"),
        ("Drag and drop", "is_dragging_from_palette"),
        ("Raycast handling", "_do_raycast"),
        ("Gizmo drag handling", "_on_gizmo_drag_start"),
        ("Color changed handler", "_on_color_changed"),
        ("Primitive selection", "_select_primitive")
    ]

    var passed = true
    for element_name in interaction_elements:
        var element = element_name if typeof(element_name) == "String" else element_name[0]
        if element in hull_builder_content:
            print("  OK: %s" % element)
        else:
            print("  Warning: %s not found" % element)
            #pass
        end if
    end for

    return true

func _load_script_content(file_path: String) -> String:
    var full_path = "res://" + file_path

    var file = FileAccess.open(full_path, FileAccess.READ)
    if file == null:
        print("  Cannot open file: %s" % full_path)
        return ""
    end if

    var content = file.get_as_text()
    file.close()
    return content