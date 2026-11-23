extends Node
## Headless test runner.  godot --headless res://tests/test_runner.tscn
## Exit code 0 = all passed. Prints a PASS/FAIL line per check.

var fails := 0
var passes := 0


func check(name: String, ok: bool, info := "") -> void:
	if ok:
		passes += 1
		print("PASS  ", name)
	else:
		fails += 1
		print("FAIL  ", name, "  ", info)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_scripts()
	_test_missions_data()
	_test_save()
	await _test_runtime()
	print("RESULT passed=%d failed=%d" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)


func _test_scripts() -> void:
	for f in DirAccess.get_files_at("res://scripts"):
		if f.ends_with(".gd"):
			var s = load("res://scripts/" + f)
			check("script loads: " + f, s != null and s.can_instantiate())
	for p in ["res://scenes/main.tscn", "res://assets/shaders/water.gdshader", "res://icon.svg"]:
		check("resource exists: " + p, ResourceLoader.exists(p))


func _test_missions_data() -> void:
	var defs := MissionManager.load_defs()
	check("missions parsed", defs.size() >= 13, str(defs.size()))
	var main_count := 0
	var ids := {}
	var valid_types := ["goto", "talk", "enter_vehicle", "kill", "escape", "chase"]
	for d in defs:
		var id := int(d.id)
		check("mission %d unique id" % id, not ids.has(id))
		ids[id] = true
		if not d.side:
			main_count += 1
		check("mission %d has objectives" % id, d.objs.size() > 0)
		check("mission %d start in range" % id, d.start[0] >= -1 and d.start[0] < Game.N and d.start[1] >= -1 and d.start[1] < Game.N)
		for o in d.objs:
			check("mission %d objective type %s" % [id, o.type], valid_types.has(o.type))
			if o.has("at"):
				check("mission %d objective pos" % id, o.at[0] >= -1 and o.at[0] < Game.N and o.at[1] >= -1 and o.at[1] < Game.N)
			if o.type == "enter_vehicle" or o.type == "chase":
				check("mission %d vehicle kind" % id, Vehicle.CFG.has(o.kind))
		if d.reward.has("unlock"):
			check("mission %d unlock valid" % id, Vehicle.CFG.has(d.reward.unlock))
	check("at least 10 story missions", main_count >= 10, str(main_count))
	check("8 vehicle configs", Vehicle.CFG.size() >= 8)


func _test_save() -> void:
	Game.new_game()
	Game.in_game = true
	Game.money = 1234
	Game.mission_done = [1, 2]
	Game.unlocked = ["sedan", "hatchback", "sports"]
	Game.collected = ["1_1"]
	Game.save_game()
	Game.money = 1
	Game.mission_done = []
	check("save loads", Game.load_game())
	check("save restores money", Game.money == 1234)
	check("save restores missions", Game.mission_done == [1, 2])
	var f := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{this is not valid json")
	f.close()
	check("corrupt save rejected", not Game.load_game())
	check("corrupt save set aside", not FileAccess.file_exists(Game.SAVE_PATH))
	var body := JSON.stringify({"v": 1, "money": -5})
	var g := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	g.store_string(JSON.stringify({"sum": 1, "body": body}))
	g.close()
	check("tampered save rejected", not Game.has_valid_save())
	Game.in_game = false


func m_reset(w: World) -> void:
	if not w.missions.active.is_empty():
		w.missions.fail("test reset")
	Game.hud.modal = false
	Game.hud.result_panel.visible = false
	w.missions.failed_def = {}


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _test_runtime() -> void:
	Game.new_game()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(2)
	main._start(true)
	var t := 0
	while not Game.in_game and t < 900:
		await get_tree().process_frame
		t += 1
	check("world builds and game starts", Game.in_game, "frames=%d" % t)
	if not Game.in_game:
		return
	var w: World = Game.world
	var pl: Player = Game.player
	await _frames(30)
	check("blocks streamed", w.blocks.size() >= 9, str(w.blocks.size()))
	check("camera exists", w.camera != null and w.camera.current)
	check("peds pooled", w.peds.size() > 0)
	var cars := 0
	for v in w.registry:
		if v.pool == "traffic":
			cars += 1
	check("traffic pooled", cars > 0, str(cars))
	# dismiss the opening cutscene (mission 1 triggers at the spawn point)
	for i in range(6):
		Game.hud._advance.emit()
		await _frames(3)
	check("opening cutscene dismissible", not Game.cutscene)
	# character moves
	var p0 := pl.global_position
	Game.touch_move = Vector2(0, -1)
	await _frames(90)
	Game.touch_move = Vector2.ZERO
	check("character moves", pl.global_position.distance_to(p0) > 1.0, str(pl.global_position.distance_to(p0)))
	# vehicle enter / drive / exit
	var v := w.spawn_vehicle("sports", pl.global_position + Vector3(3, 0, 0), 0.0, "owned")
	await _frames(10)
	pl.enter_vehicle(v)
	check("enter vehicle", pl.in_vehicle and v.driver == "player")
	var vp := v.global_position
	Game.touch_move = Vector2(0, -1)
	await _frames(120)
	Game.touch_move = Vector2.ZERO
	check("vehicle drives", v.global_position.distance_to(vp) > 5.0, str(v.global_position.distance_to(vp)))
	pl.exit_vehicle(false)
	check("exit vehicle", not pl.in_vehicle and v.driver == "")
	# every vehicle config builds
	for k in Vehicle.CFG.keys():
		var tv := w.spawn_vehicle(k, Vector3(60, 0, 60), 0.0, "owned")
		check("vehicle builds: " + k, tv.model != null and tv.wheel_nodes.size() >= 2)
		w.registry.erase(tv)
		tv.queue_free()
	# traffic and pedestrians actually move
	var moved := 0
	var starts := {}
	for ve in w.registry:
		if ve.pool == "traffic" and ve.driver == "ai":
			starts[ve] = ve.global_position
	await _frames(180)
	for ve in starts.keys():
		if is_instance_valid(ve) and ve.global_position.distance_to(starts[ve]) > 3.0:
			moved += 1
	check("traffic moves", moved > 0, "%d/%d" % [moved, starts.size()])
	# wanted level spawns police
	Game.set_wanted_level(2)
	check("wanted level set", Game.wanted == 2, str(Game.wanted))
	var max_units := 0
	for i in range(400):
		await get_tree().process_frame
		max_units = maxi(max_units, w.police.units.size())
	check("police units spawn", max_units > 0, str(max_units))
	Game.clear_wanted()
	await _frames(5)
	check("police cleared", w.police.units.is_empty())
	# the player may have been arrested/killed in the test; reset state
	Game.hud.modal = false
	Game.hud.result_panel.visible = false
	if not pl.dead:
		pl.health = 100.0
	m_reset(w)
	# missions
	var m := w.missions
	while pl.dead:
		await get_tree().process_frame
	check("mission markers", m.markers.size() >= 13)
	pl.global_position = Game.node_pos(0, 6)
	await _frames(20)
	check("mission starts at marker", not m.active.is_empty() or m.busy)
	Game.hud._advance.emit()
	Game.hud._advance.emit()
	await _frames(10)
	check("mission objective begins", not m.obj.is_empty(), str(m.obj))
	m.fail("test")
	check("mission fail handled", m.active.is_empty() and not m.failed_def.is_empty())
	Game.hud.modal = false
	# collectibles
	check("collectibles placed", w.col_keys.size() == 20)
	# time of day / weather
	var t0 := w.tod
	await _frames(30)
	check("time advances", w.tod != t0)
	Game.settings.weather = 4
	await _frames(5)
	check("heavy rain available", w.weather == 3)
	Game.settings.weather = 0
	# graphics presets
	for i in range(3):
		Game.settings.preset = i
		Game.settings_changed.emit()
		await _frames(3)
		check("preset %d applies" % i, w.camera.far == Game.PRESETS[i].far)
	# save in-game
	Game.save_game()
	check("in-game save valid", Game.has_valid_save())
	main._to_menu()
	await _frames(3)
	check("returns to menu", not Game.in_game)
	main.queue_free()
