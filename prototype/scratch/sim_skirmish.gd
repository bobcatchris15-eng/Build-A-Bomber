extends SceneTree
# Scratch probe: run the Skirmish scene headless for ~100s of sim time and
# report economy/unit/AI activity so we can confirm the game actually plays out.
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --fixed-fps 60 --script scratch/sim_skirmish.gd

func _init():
	var skirmish = load("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await process_frame

	print("[SIM] Player roster: ", skirmish.roster.size(), " | Enemy roster: ", skirmish.enemy_roster.size())
	print("[SIM] Player faction: ", skirmish.player_faction, " | Enemy faction: ", skirmish.enemy_faction)

	var frames = 0
	while frames < 6600: # ~110s at 60fps
		await physics_frame
		frames += 1
		if frames % 1200 == 0:
			var t = frames / 60
			print("[SIM t=%ds] P units: %d (harv %d) | E units: %d | P eco: %dM/%dC | E eco: %dM/%dC | P HQ: %d | E HQ: %d" % [
				t,
				skirmish.get_team_units(0).size(),
				skirmish.get_team_units(0).filter(func(u): return u.is_harvester).size(),
				skirmish.get_team_units(1).size(),
				skirmish.economy[0].metal, skirmish.economy[0].crystal,
				skirmish.economy[1].metal, skirmish.economy[1].crystal,
				int(skirmish.player_hq.hp) if is_instance_valid(skirmish.player_hq) else -1,
				int(skirmish.enemy_hq.hp) if is_instance_valid(skirmish.enemy_hq) else -1,
			])
	var ai = skirmish.get_node("EnemyAI")
	print("[SIM] Enemy waves launched: ", ai.wave_number)
	print("[SIM] Game over: ", skirmish.game_over)
	quit(0)
