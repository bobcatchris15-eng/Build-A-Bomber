extends Node
# Autoload: sizes the game window to fit the screen it actually launches on.
#
# THE BUG: project.godot declares a fixed 1920x1080 window. On a 1920x1080
# display that is exactly the full screen resolution, so once the OS adds a
# title bar and reserves the taskbar strip, the bottom of the window is
# pushed off-screen and sits behind the taskbar. On anything smaller than
# 1080p it is worse; on anything larger the window is a small rectangle
# marooned in the middle of the display.
#
# THE FIX: screen_get_usable_rect() returns the work area - the screen
# MINUS the taskbar and any other reserved OS furniture - which is exactly
# the constraint the fixed size was ignoring. The window is fitted inside
# that and centred within it.
#
# Deliberately does NOT force fullscreen. Launching straight into exclusive
# fullscreen is hostile during development (and generally), and the point
# here is a window that behaves, not one that takes over.

# Fraction of the work area to occupy when the screen is large enough to
# have a choice. Slightly inset so the window reads as a window and the
# player can still grab the desktop behind it.
const FILL_FRACTION := 0.92

# Below this, fitting to a fraction produces a window too small to lay the
# three-column screens out in, so we take the whole work area instead.
const SMALL_SCREEN_THRESHOLD := Vector2i(1600, 900)

# NOTE: there is deliberately no maximum-size clamp here.
#
# A first pass capped the window at the 1920x1080 design size. On the
# development machine - a 2560x1080 ultrawide with a 2560x1040 work area -
# that cap reproduced half the original bug: 1920 is NARROWER than the
# screen, so the window stayed marooned in the middle horizontally. The
# stretch mode is "expand", so extra width is genuinely usable and the
# layouts are proportional rather than fixed-width. Fit the work area; don't
# second-guess it.


# Vsync is asserted HERE, in code, rather than in project.godot.
#
# It was first set there as `window/vsync/vsync_mode=1` - and Godot silently
# deleted the line, comments and all, the next time it loaded the project.
# Godot only persists project settings whose value DIFFERS from the built-in
# default, and Enabled (1) IS the default, so an explicit statement of the
# current behaviour is literally unpersistable in that file. (This also makes
# ProjectSettings.get_setting() useless for verifying it: the getter returns 1
# whether the key was set deliberately or is simply absent.)
#
# Why state it at all, when it changes nothing today: during the performance
# investigation the implicit default pinned every measurement to the 16.7ms
# vblank on a 60Hz display, which made an empty map and a full battle measure
# identically and manufactured a frame-time "floor" that did not exist. It
# also means any regression stays invisible until it exceeds 16.7ms. Having it
# written down as a decision, in a place that survives, is the point.
#
# Modes: 0 Disabled, 1 Enabled, 2 Adaptive, 3 Mailbox.
#
# Deliberately NOT Adaptive (Vulkan FIFO_RELAXED), though it would remove the
# judder cliff this scene currently falls off: with Enabled, a frame that
# misses the deadline waits a whole extra vblank, so ~17ms of work costs
# 33.3ms and jitter pushes some frames to 50ms. Adaptive presents late instead
# of waiting, but tears whenever a frame is late - and this scene measured
# 22-45fps at 1080p on an integrated GPU, i.e. MOST frames are late, so it
# would trade consistent pacing for near-constant tearing. The real fix is a
# cheaper frame (the ground shader and 4x MSAA dominate it), not a different
# way of presenting a slow one. Revisit once the frame fits in 16.7ms.
#
# The measurement harnesses (scratch/perf_matrix.gd, scratch/probe_world_cost.gd)
# override this at runtime, because there is no measurement resolution below
# the refresh period while it is on.
const VSYNC_MODE := DisplayServer.VSYNC_ENABLED


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(VSYNC_MODE)
	# Deferred: on some platforms the window is still being created during
	# autoload _ready(), and querying/setting geometry that early is either
	# ignored or reports the pre-creation values.
	call_deferred("fit_to_screen")


func fit_to_screen() -> void:
	var mode := DisplayServer.window_get_mode()
	# Respect a player who launched maximised or fullscreen - resizing out
	# from under them would be worse than the bug this fixes.
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN \
			or mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		return

	var screen := DisplayServer.window_get_current_screen()
	# The WORK AREA, not screen_get_size() - the difference between the two
	# is the taskbar, which is the entire problem.
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return

	var target: Vector2i
	if usable.size.x < SMALL_SCREEN_THRESHOLD.x or usable.size.y < SMALL_SCREEN_THRESHOLD.y:
		target = usable.size
	else:
		target = Vector2i(
			int(usable.size.x * FILL_FRACTION),
			int(usable.size.y * FILL_FRACTION))

	# Final clamp: whatever the arithmetic above produced, it must never
	# exceed the work area, or we reintroduce the offscreen bottom edge.
	target.x = mini(target.x, usable.size.x)
	target.y = mini(target.y, usable.size.y)

	DisplayServer.window_set_size(target)
	# Centre within the WORK AREA and offset by its position, so this is
	# correct on a multi-monitor desktop and on a taskbar docked to the top
	# or left (where usable.position is not the origin).
	DisplayServer.window_set_position(
		usable.position + (usable.size - target) / 2)
