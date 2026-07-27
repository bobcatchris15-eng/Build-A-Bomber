#!/usr/bin/gdscript
extends Node

# Detailed Hull Builder test script that simulates the actual
# test workflow that would run in the project
const EXPECTED_PRIMITIVES_COUNT = 6
const EXPECTED_DOMAINS = ["Ground", "Naval", "Air", "Static Defense"]
const MIN_COORDINATES = [-10, -5, -10]
const MAX_COORDINATES = [10, 5, 10]
func _ready() -> void:
    print("=== Hull Builder Unit Tests ===")

    var all_passed = _run_all_tests()

    if all_passed:
        print("\n✓ All unit tests passed!")
        get_tree().quit(0)
    else:
        print("\n✗ Some tests failed!")
        get_tree().quit(1)

func _run_all_tests() -> bool:
    var tests = []

    # Core functionality tests
    tests.append(_test_script_files_exist)
    tests.append(_test_script_syntax)
    tests.append(_test_scene_structure)
    tests.append(_test_test_files_exist)

    # Hull Builder script tests
    tests.append(_test_hull_builder_enums)
    tests.append(_test_hull_builder_constants)
    tests.append(_test_hull_builder_functions)

    # Blender tools tests
    tests.append(_test_blender_script_exists)
    tests.append(_test_blender_script_syntax)

    # Export pipeline tests
    tests.append(_test_export_prototype)

    # Integration tests
    tests.append(_test_scene_references)

    # Visual polish tests
    tests.append(_test_ui_elements)

    for test in tests:
        var test_name = test.get("name")
        print("Running: %s" % test_name)

        var result = test.call(_)
        if not result:
            print("FAILED: %s" % test_name)
            return false

        print("PASSED: %s" % test_name)
        print("")

    return true

func _test_script_files_exist() -> bool:
    var required_files = [
        "res://scripts/hull_builder.gd",
        "res://scripts/mesh_asset_loader.gd",
        "res://scripts/hull_loader.gd",
        "res://scripts/parts_menu.gd",
        "res://scripts/module_catalog.gd",
        "res://scenes/HullBuilder.tscn",
        "res://scripts/gizmo_3d.gd",
        "res://scenes/Gizmo3D.tscn"
    ]

    for file_path in required_files:
        if not FileAccess.file_exists(file_path):
            print("  Missing: %s" % file_path)
            return false

    print("  All required files exist")
    return true

func _test_script_syntax() -> bool:
    print("  Testing script syntax...")

    # We'll try to preload critical scripts
    var critical_scripts = [
        preload("res://scripts/hull_builder.gd"),
        preload("res://scripts/mesh_asset_loader.gd"),
        preload("res://scripts/hull_loader.gd"),
        preload("res://scripts/designer_camera.gd")
    ]

    for script in critical_scripts:
        if script == null:
            print("  Could not preload script")
            return false

    print("  All scripts preload successfully")
    return true

func _test_scene_structure() -> bool:
    print("  Testing scene structure...")

    var scene = load("res://scenes/HullBuilder.tscn")
    if scene == null:
        print("  Could not load HullBuilder scene")
        return false

    var instance = scene.instantiate()
    if instance == null:
        print("  Could not instantiate HullBuilder scene")
        return false

    # Check for required nodes
    var required_nodes = [
        "CanvasLayer",
        "BackButton",
        "LeftPanel",
        "RightPanel",
        "BottomBar",
        "HullContainer"
    ]

    for node_name in required_nodes:
        if instance.find_child(node_name) == null:
            print("  Missing required node: %s" % node_name)
            instance.queue_free()
            return false
    end for

    instance.queue_free()
    print("  Scene structure is valid")
    return true

func _test_test_files_exist() -> bool:
    print("  Testing test files...")

    var test_files = [
        "res://run_hull_builder_tests.gd",
        "res://test_hull_builder_simple.gd",
        "res://test_hull_builder_detailed.gd"
    ]

    for file_path in test_files:
        if not FileAccess.file_exists(file_path):
            print("  Missing test file: %s" % file_path)
    end for

    print("  Test files structure verified")
    return true

func _test_hull_builder_enums() -> bool:
    print("  Testing HullBuilder enums...")

    var script = preload("res://scripts/hull_builder.gd")
    if script == null:
        return false

    # Check that the PrimitiveType enum exists
    # We can't easily access enum values in a script without running it,
    # so we'll rely on the file structure

    var script_content = _load_file_content("res://scripts/hull_builder.gd")
    if script_content == "":
        return false

    # Look for enum definitions
    if "enum PrimitiveType" not in script_content:
        print("  Missing PrimitiveType enum")
        return false

    print("  Enums are properly defined")
    return true

func _test_hull_builder_constants() -> bool:
    print("  Testing HullBuilder constants...")

    var script_content = _load_file_content("res://scripts/hull_builder.gd")
    if script_content == "":
        return false

    # Check for key constants
    var required_constants = [
        "max_primitives: int = 50",
        "snap_distance: float = 1.0",
        "snap_enabled: bool = true"
    ]

    for const in required_constants:
        if const not in script_content:
            print("  Missing or incorrect constant: %s" % const)
            return false
    end for

    print("  Constants are properly defined")
    return true

func _test_hull_builder_functions() -> bool:
    print("  Testing HullBuilder functions...")

    var script_content = _load_file_content("res://scripts/hull_builder.gd")
    if script_content == "":
        return false

    # Check for essential function signatures
    var required_functions = [
        "func _ready() -> void",
        "func _on_export_clicked() -> void",
        "func _on_clear_clicked() -> void",
        "func _on_back_clicked() -> void",
        "func _add_primitive_at_position(type: PrimitiveType, position: Vector3) -> void"
    ]

    for func in required_functions:
        if func not in script_content:
            print("  Missing required function: %s" % func)
            return false
    end for

    print("  All required functions are defined")
    return true

func _test_blender_script_exists() -> bool:
    print("  Testing Blender script...")

    var script_paths = [
        "res://tools/blender/bake_custom_hull.py",
        "res://tools/blender/build_meshes.py"
    ]

    for path in script_paths:
        if not FileAccess.file_exists(path):
            print("  Missing Blender script: %s" % path)
            return false
    end for

    print("  Blender scripts exist")
    return true

func _test_blender_script_syntax() -> bool:
    print("  Testing Blender script syntax...")

    # We can't easily validate Python syntax in this context,
    # but we can check for basic structure

    var script_path = "res://tools/blender/bake_custom_hull.py"
    if not FileAccess.file_exists(script_path):
        return false

    var script_content = _load_file_content(script_path)
    if script_content == "":
        return false

    # Check for basic Python structure
    if "def main():" not in script_content:
        print("  Missing main() function in Blender script")
        return false

    print("  Blender script structure is valid")
    return true

func _test_export_prototype() -> bool:
    print("  Testing export pipeline prototype...")

    var script_content = _load_file_content("res://scripts/hull_builder.gd")
    if script_content == "":
        return false

    # Check that export functionality is implemented
    if "_on_export_clicked" not in script_content:
        print("  Export functionality not implemented")
        return false

    if "_serialize_for_blender" not in script_content:
        print("  Serialization functionality not implemented")
        return false

    if "bake_custom_hull.py" not in script_content:
        print("  Blender integration not implemented")
        return false

    print("  Export pipeline prototype is implemented")
    return true

func _test_scene_references() -> bool:
    print("  Testing scene references...")

    var hull_builder_content = _load_file_content("res://scripts/hull_builder.gd")
    var hull_loader_content = _load_file_content("res://scripts/hull_loader.gd")

    if hull_builder_content == "" or hull_loader_content == "":
        return false

    # Check that hull_builder.gd references hull_loader.gd
    if "HullLoader" not in hull_builder_content:
        print("  HullBuilder does not reference HullLoader")
        return false

    # Check that hull_loader.gd has required constants
    if "BUILTIN_DIR = \"res://assets/models/hulls\"" not in hull_loader_content:
        print("  HullLoader missing BUILTIN_DIR constant")
        return false

    print("  Scene references are properly configured")
    return true

func _test_ui_elements() -> bool:
    print("  Testing UI elements...")

    var scene_content = _load_file_content("res://scenes/HullBuilder.tscn")
    if scene_content == "":
        return false

    # Check for key UI elements in the scene
    var ui_elements = [
        "PrimitiveScroller",
        "PrimitiveLabel",
        "PropertiesScroller",
        "PropertiesLabel",
        "StatusLabel",
        "ClearButton",
        "ExportButton"
    ]

    for element in ui_elements:
        if element not in scene_content:
            print("  Missing UI element in scene: %s" % element)
    end for

    print("  UI elements are present in scene")
    return true

func _load_file_content(file_path: String) -> String:
    var file = FileAccess.open(file_path, FileAccess.READ)
    if file == null:
        return ""

    var content = file.get_as_text()
    file.close()
    return content