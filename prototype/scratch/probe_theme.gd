extends SceneTree
# Scratch probe: ask Godot what it ACTUALLY resolves for our theme
# variations, rather than inferring it from the saved .tres. The .tres can
# be perfectly correct and still not reach the control.

func _init():
	var theme = load("res://resources/bomber_theme.tres") as Theme
	print("theme loaded: ", theme != null)
	print("project theme: ", ProjectSettings.get_setting("gui/theme/custom"))
	print("--- variation bases registered in the resource ---")
	for v in ["TitleLabel", "DisplayLabel", "CardPanel", "PrimaryButton"]:
		print("  %-14s base=%s  has_font=%s" % [
			v, theme.get_type_variation_base(v), theme.has_font("font", v)])

	print("--- what a live Label resolves ---")
	var probe = Label.new()
	probe.theme_type_variation = "TitleLabel"
	root.add_child(probe)
	await process_frame
	var f = probe.get_theme_font("font")
	print("  resolved font: ", f.get_font_name() if f else "<null>")
	print("  resolved size: ", probe.get_theme_font_size("font_size"))

	var probe2 = Label.new()
	root.add_child(probe2)
	await process_frame
	var f2 = probe2.get_theme_font("font")
	print("  plain Label font: ", f2.get_font_name() if f2 else "<null>")
	quit(0)
