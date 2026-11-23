extends Node
class_name MissionManager
## Data-driven missions loaded from res://data/missions.json.
## Objective types: goto, talk, enter_vehicle, kill, escape, chase.

var defs: Array = []
var active: Dictionary = {}
var obj: Dictionary = {}
var obj_i := 0
var markers := {}
var beacon: Node3D
var enemies: Array = []
var spawned_cars: Array = []
var target_car: Vehicle = null
var time_left := -1.0
var escape_seen := false
var failed_def: Dictionary = {}
var away_t := 0.0
var busy := false


func _ready() -> void:
	defs = load_defs()
	call_deferred("_setup_markers")


static func load_defs() -> Array:
	var txt := FileAccess.get_file_as_string("res://data/missions.json")
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY or not data.has("missions"):
		push_error("missions.json invalid")
		return []
	return data.missions


static func pos_of(a: Array) -> Vector3:
	return Game.node_pos(int(a[0]), int(a[1]))


func _setup_markers() -> void:
	var w: Node3D = get_parent()
	for d in defs:
		var m := Node3D.new()
		var col := Color(0.2, 0.8, 1.0, 0.5) if d.side else Color(1.0, 0.55, 0.1, 0.5)
		var mat := Gfx.mat(col, 0.5, 0.0, 1.6)
		Gfx.cyl(m, Vector3(0, 0.1, 0), 2.6, 0.1, mat)
		Gfx.cyl(m, Vector3(0, 7.0, 0), 0.12, 14.0, mat)
		Gfx.label(m, ("%s: %s" % [d.giver, d.name]), Vector3(0, 3.2, 0), 0.015, 120.0)
		w.add_child(m)
		m.global_position = pos_of(d.start)
		markers[int(d.id)] = m
	beacon = Node3D.new()
	var bm := Gfx.mat(Color(1.0, 0.9, 0.2, 0.5), 0.5, 0.0, 2.0)
	Gfx.cyl(beacon, Vector3(0, 0.1, 0), 3.0, 0.1, bm)
	Gfx.cyl(beacon, Vector3(0, 9.0, 0), 0.15, 18.0, bm)
	w.add_child(beacon)
	beacon.visible = false
	_refresh_markers()


func available(d: Dictionary) -> bool:
	var id := int(d.id)
	if d.side:
		if Game.side_done.has(id):
			return false
	elif Game.mission_done.has(id):
		return false
	var req := int(d.req)
	return req == 0 or Game.mission_done.has(req)


func _refresh_markers() -> void:
	for d in defs:
		var m: Node3D = markers.get(int(d.id))
		if m:
			m.visible = active.is_empty() and available(d)


func map_points() -> Array:
	var out: Array = []
	if active.is_empty():
		for d in defs:
			if available(d):
				out.append({"pos": pos_of(d.start), "kind": "side" if d.side else "start"})
	elif beacon and beacon.visible:
		out.append({"pos": beacon.global_position, "kind": "obj"})
	for e in enemies:
		if is_instance_valid(e) and e.state != "dead":
			out.append({"pos": e.global_position, "kind": "enemy"})
	return out


# ----------------------------------------------------------------- flow
func start(d: Dictionary, skip_intro := false) -> void:
	if not active.is_empty() or busy:
		return
	active = d
	obj = {}
	for m in markers.values():
		m.visible = false
	Game.say("Mission: %s" % d.name)
	if not skip_intro and d.intro.size() > 0:
		busy = true
		await Game.hud.run_cutscene(d.intro)
		busy = false
		if active.is_empty():
			return
	_begin(0)


func _begin(i: int) -> void:
	if i >= active.objs.size():
		_complete()
		return
	obj_i = i
	obj = active.objs[i]
	time_left = float(obj.get("time", -1.0))
	escape_seen = false
	away_t = 0.0
	beacon.visible = false
	var w: World = Game.world
	match obj.type:
		"goto", "talk":
			beacon.global_position = pos_of(obj.at)
			beacon.visible = true
		"enter_vehicle":
			var sp := pos_of(obj.spawn) + Vector3(4, 0, 4)
			target_car = w.spawn_vehicle(obj.kind, sp, 0.0, "mission")
			spawned_cars.append(target_car)
			beacon.visible = true
		"kill":
			_spawn_enemies()
		"escape":
			Game.set_wanted_level(int(obj.level))
		"chase":
			var d := Vector2i(1, 0)
			var np := pos_of(obj.at)
			target_car = w.spawn_vehicle(obj.kind, np - Vector3(10, 0, 0) + Vector3(0, 0, 4), atan2(-1.0, 0.0), "mission", "ai")
			target_car.is_target = true
			target_car.start_lane(int(obj.at[0]), int(obj.at[1]), d)
			spawned_cars.append(target_car)
			beacon.visible = true
			Game.add_heat(0.0)
	Game.say(obj.text)


func _spawn_enemies() -> void:
	enemies.clear()
	var c := pos_of(obj.at)
	for i in range(int(obj.count)):
		var p := Ped.new()
		p.role = "enemy"
		Game.world.add_child(p)
		p.global_position = c + Vector3(randf_range(-6, 6), 0.5, randf_range(-6, 6))
		enemies.append(p)
	beacon.global_position = c
	beacon.visible = true


func _process(delta: float) -> void:
	if Game.world == null or Game.player == null or beacon == null or Game.hud == null:
		return
	var pl: Player = Game.player
	var pp: Vector3 = Game.world.focus_pos()
	if active.is_empty():
		if not busy and not Game.cutscene:
			for d in defs:
				var m: Node3D = markers.get(int(d.id))
				if m and m.visible and not pl.dead and pp.distance_to(m.global_position) < 3.5:
					start(d)
					break
		return
	if obj.is_empty() or pl.dead or Game.cutscene:
		return
	if time_left > 0.0:
		time_left -= delta
		if time_left <= 0.0:
			fail("Out of time")
			return
	match obj.type:
		"goto":
			var target := pos_of(obj.at)
			var need_v: bool = obj.get("vehicle", false)
			var r := 7.0 if pl.in_vehicle else 3.5
			if _flat(pp, target) < r and (not need_v or pl.in_vehicle) and not obj.get("interact", false):
				_next()
		"enter_vehicle":
			if target_car == null or not is_instance_valid(target_car) or target_car.dead:
				fail("Vehicle destroyed")
				return
			beacon.global_position = target_car.global_position
			if pl.in_vehicle and pl.vehicle == target_car:
				_next()
		"kill":
			var left := 0
			for e in enemies:
				if is_instance_valid(e) and e.state != "dead":
					left += 1
			if left == 0:
				_next()
		"escape":
			if Game.wanted > 0:
				escape_seen = true
			elif escape_seen:
				_next()
		"chase":
			if target_car == null or not is_instance_valid(target_car):
				fail("Target lost")
				return
			beacon.global_position = target_car.global_position
			if target_car.dead:
				_next()
			elif pp.distance_to(target_car.global_position) > 280.0:
				away_t += delta
				if away_t > 8.0:
					fail("The target got away")
			else:
				away_t = 0.0
	_update_hud()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _update_hud() -> void:
	if Game.hud == null:
		return
	var t: String = obj.get("text", "")
	if obj.get("type") == "kill":
		var left := 0
		for e in enemies:
			if is_instance_valid(e) and e.state != "dead":
				left += 1
		t += "  (%d left)" % left
	Game.hud.set_objective(t, time_left)


func _next() -> void:
	_cleanup_objective()
	Game.say("Objective complete")
	_begin(obj_i + 1)


func _cleanup_objective() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	beacon.visible = false


func _cleanup_all() -> void:
	_cleanup_objective()
	for c in spawned_cars:
		if is_instance_valid(c):
			if c.driver == "player":
				c.pool = "owned"
				c.owned = true
			else:
				Game.world.registry.erase(c)
				c.queue_free()
	spawned_cars.clear()
	target_car = null
	if Game.hud:
		Game.hud.set_objective("", -1.0)


func _complete() -> void:
	var d := active
	var rw: Dictionary = d.reward
	Game.add_money(int(rw.get("money", 0)))
	var sub := "+$%d" % int(rw.get("money", 0))
	if rw.has("unlock") and not Game.unlocked.has(rw.unlock):
		Game.unlocked.append(rw.unlock)
		sub += "   Unlocked: " + Vehicle.CFG[rw.unlock].name
	if d.side:
		Game.side_done.append(int(d.id))
	else:
		Game.mission_done.append(int(d.id))
	_cleanup_all()
	active = {}
	obj = {}
	Game.save_game()
	_refresh_markers()
	Game.hud.show_result(true, d.name, sub, Callable())
	Sfx.play3d(Game.world, "pickup", Game.player.global_position)
	if d.outro.size() > 0:
		busy = true
		await Game.hud.run_cutscene(d.outro)
		busy = false


func fail(reason: String) -> void:
	if active.is_empty():
		return
	failed_def = active
	_cleanup_all()
	active = {}
	obj = {}
	_refresh_markers()
	Game.hud.show_result(false, failed_def.name, reason, Callable(self, "retry"))


func retry() -> void:
	if failed_def.is_empty():
		return
	var d := failed_def
	failed_def = {}
	start(d, true)


## Called by the player when INTERACT is pressed. Returns true if consumed.
func try_interact() -> bool:
	if active.is_empty() or obj.is_empty() or busy:
		return false
	var pp: Vector3 = Game.world.focus_pos()
	match obj.type:
		"goto":
			if obj.get("interact", false) and _flat(pp, pos_of(obj.at)) < 6.0:
				Sfx.play3d(Game.world, "pickup", pp)
				_next()
				return true
		"talk":
			if _flat(pp, pos_of(obj.at)) < 6.0:
				_do_talk()
				return true
	return false


func _do_talk() -> void:
	busy = true
	await Game.hud.run_cutscene(obj.lines)
	busy = false
	if not active.is_empty():
		_next()
