extends Node
class_name PoliceManager
## Wanted-level response. L1: one unit, L2: 3, L3: 4 (faster), L4: 5 + roadblocks, L5: 6 (aggressive).

const UNITS_PER_LEVEL := [0, 1, 3, 4, 5, 6]

var units: Array = []
var roadblocks: Array = []
var arrest_t := 0.0
var last_seen := Vector3.ZERO
var unseen_t := 0.0
var _spawn_t := 0.0
var _chase_t := 0.0
var _block_t := 0.0
var _shoot_t := 0.0


func reset() -> void:
	for u in units:
		_free(u)
	for b in roadblocks:
		_free(b)
	units.clear()
	roadblocks.clear()
	arrest_t = 0.0
	unseen_t = 0.0


func _free(v) -> void:
	if is_instance_valid(v):
		Game.world.registry.erase(v)
		v.queue_free()


func _process(delta: float) -> void:
	var w: World = Game.world
	if w == null or w.player == null or Game.cutscene and false:
		return
	units = units.filter(func(u): return is_instance_valid(u) and not u.dead)
	var pl: Player = w.player
	var pp := w.focus_pos()
	var level := Game.wanted
	if level == 0:
		if not units.is_empty() or not roadblocks.is_empty():
			reset()
		arrest_t = 0.0
		return

	# ---- spawning
	_spawn_t -= delta
	if units.size() < UNITS_PER_LEVEL[level] and _spawn_t <= 0.0:
		_spawn_t = 3.0
		_spawn_unit(pp)
	# ---- decay when escaped
	var nearest := 9999.0
	for u in units:
		nearest = minf(nearest, u.global_position.distance_to(pp))
	if nearest < 110.0:
		unseen_t = 0.0
		last_seen = pp
	else:
		unseen_t += delta
	if unseen_t > 10.0:
		Game.add_heat(-3.0 * delta)
	elif nearest > 40.0 and pl.velocity.length() < 1.0 and not pl.in_vehicle:
		Game.add_heat(-1.5 * delta)
	# ---- steering targets for units
	_chase_t -= delta
	if _chase_t <= 0.0:
		_chase_t = 0.25
		var pvel := Vector3.ZERO
		if pl.in_vehicle and pl.vehicle:
			pvel = pl.vehicle.vel_h
		var aim := pp + pvel * 0.6
		for u in units:
			u.chase_pos = aim if unseen_t < 10.0 else last_seen
			u.siren_active = true
			if u.global_position.distance_to(pp) > 260.0:
				_respawn_far(u, pp)
	# ---- arrest
	var pspeed := pl.vehicle.vel_h.length() if (pl.in_vehicle and pl.vehicle) else pl.velocity.length()
	var close := false
	for u in units:
		if u.global_position.distance_to(pp) < 7.0:
			close = true
	if close and pspeed < 4.0 and not pl.dead:
		arrest_t += delta
		if arrest_t > 3.0:
			arrest_t = 0.0
			w.busted()
			return
	else:
		arrest_t = maxf(0.0, arrest_t - delta)
	# ---- officers fire at an on-foot player from level 3
	_shoot_t -= delta
	if level >= 3 and not pl.in_vehicle and _shoot_t <= 0.0:
		_shoot_t = 1.1
		for u in units:
			if u.global_position.distance_to(pp) < 28.0 and randf() < 0.3:
				Sfx.play3d(u, "shot", u.global_position, -4.0)
				pl.damage(7.0)
				break
	# ---- roadblocks
	roadblocks = roadblocks.filter(func(b): return is_instance_valid(b))
	if level >= 4:
		_block_t -= delta
		if _block_t <= 0.0:
			_block_t = 25.0
			_place_roadblock(pl, pp)
		for b in roadblocks.duplicate():
			if b.global_position.distance_to(pp) > 230.0:
				roadblocks.erase(b)
				_free(b)
	elif not roadblocks.is_empty():
		for b in roadblocks:
			_free(b)
		roadblocks.clear()


func _spawn_unit(pp: Vector3) -> void:
	var w: World = Game.world
	for attempt in range(10):
		var ci := roundi(pp.x / Game.C - 0.5) + randi_range(-3, 3)
		var cj := roundi(pp.z / Game.C - 0.5) + randi_range(-3, 3)
		ci = clampi(ci, -1, Game.N - 1)
		cj = clampi(cj, -1, Game.N - 1)
		var pos := Game.node_pos(ci, cj) + Vector3(4, 0, 4)
		var d := pos.distance_to(pp)
		if d < 60.0 or d > 110.0:
			continue
		var u := w.spawn_vehicle("police", pos, randf() * TAU, "police", "police")
		u.siren_active = true
		u.ray.enabled = true
		units.append(u)
		return


func _respawn_far(u: Vehicle, pp: Vector3) -> void:
	for attempt in range(8):
		var ci := clampi(roundi(pp.x / Game.C - 0.5) + randi_range(-3, 3), -1, Game.N - 1)
		var cj := clampi(roundi(pp.z / Game.C - 0.5) + randi_range(-3, 3), -1, Game.N - 1)
		var pos := Game.node_pos(ci, cj) + Vector3(4, 0.3, 4)
		var d := pos.distance_to(pp)
		if d > 70.0 and d < 150.0:
			u.global_position = pos
			u.vel_h = Vector3.ZERO
			return


func _place_roadblock(pl: Player, pp: Vector3) -> void:
	for b in roadblocks:
		_free(b)
	roadblocks.clear()
	var fwd := Vector3.ZERO
	if pl.in_vehicle and pl.vehicle:
		fwd = pl.vehicle.vel_h
	else:
		fwd = -pl.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 1.0:
		fwd = Vector3(1, 0, 0)
	fwd = fwd.normalized()
	var ahead := pp + fwd * 120.0
	var along_x := absf(fwd.x) > absf(fwd.z)
	var w: World = Game.world
	if along_x:
		var zc := (roundi(pp.z / Game.C - 0.5) + 0.5) * Game.C
		for dz in [-5.0, 0.0, 5.0]:
			var pos := Vector3(clampf(ahead.x, -30.0, 750.0), 0.3, clampf(zc + dz, -35.0, 755.0))
			_block_car(w, pos, 0.0)
	else:
		var xc := (roundi(pp.x / Game.C - 0.5) + 0.5) * Game.C
		for dx in [-5.0, 0.0, 5.0]:
			var pos := Vector3(clampf(xc + dx, -35.0, 755.0), 0.3, clampf(ahead.z, -30.0, 750.0))
			_block_car(w, pos, PI / 2.0)
	Game.say("Roadblock ahead!")


func _block_car(w: World, pos: Vector3, yaw: float) -> void:
	var b := w.spawn_vehicle("police", pos, yaw, "police", "")
	b.roadblock = true
	b.parked = true
	b.siren_active = true
	roadblocks.append(b)
