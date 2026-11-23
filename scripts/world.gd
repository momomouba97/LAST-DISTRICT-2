extends Node3D
class_name World
## Owns the 3D scene: streaming blocks, day/night, weather, NPC/traffic pools.

const HOSPITAL_POS := Vector3(120.0, 1.0, 120.0)
const POLICE_POS := Vector3(360.0, 1.0, 200.0)
const DAY_SECONDS := 1200.0

var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var player: Player
var missions: MissionManager
var police: PoliceManager
var tod := 9.0
var weather := 0                  # 0 clear 1 cloudy 2 light rain 3 heavy rain
var weather_t := 20.0
var cloud_f := 0.0
var wet := 0.0
var stream_radius := 2
var ped_target := 9
var car_target := 6
var blocks := {}
var build_queue: Array = []
var registry: Array = []          # every Vehicle
var peds: Array = []
var col_pos := {}
var col_keys: Array = []
var rain: CPUParticles3D
var rain_snd: AudioStreamPlayer
var garage_i := 0
var mem_mb := 0.0
var mem_reduced := false
var _t_stream := 0.0
var _t_pool := 0.0
var _t_slow := 0.0
var _t_col := 0.0
var _last_weather := -1
var _death_pending := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## Builds the scene. Awaits between steps so the loading screen can animate.
func build(progress: Callable) -> void:
	Gfx.set_night(0.0)
	Gfx.set_wet(0.0)
	tod = Game.time_of_day
	_make_environment()
	progress.call(0.05)
	await get_tree().process_frame
	_make_static_world()
	progress.call(0.15)
	await get_tree().process_frame
	camera = Camera3D.new()
	camera.far = 250.0
	camera.near = 0.2
	add_child(camera)
	camera.current = true
	player = Player.new()
	player.name = "Player"
	add_child(player)
	Game.world = self
	Game.player = player
	player.global_position = Game.player_pos
	if player.global_position.y < 0.5:
		player.global_position.y = 1.0
	player.died.connect(_on_player_died)
	_pick_collectibles()
	missions = MissionManager.new()
	missions.name = "Missions"
	add_child(missions)
	police = PoliceManager.new()
	police.name = "Police"
	add_child(police)
	_make_rain()
	apply_graphics()
	Game.settings_changed.connect(apply_graphics)
	_make_garage_marker()
	# initial streaming: build every block inside the radius, one per frame
	var want := _wanted_block_keys()
	var n := 0
	for k in want:
		_build_block(k)
		n += 1
		progress.call(0.2 + 0.6 * float(n) / float(want.size()))
		await get_tree().process_frame
	for i in range(Game.PRESETS[2].peds):
		var p := Ped.new()
		add_child(p)
		peds.append(p)
	for i in range(Game.PRESETS[2].cars):
		var v := Vehicle.new()
		v.pool = "traffic"
		add_child(v)
		v.setup(_random_kind())
		registry.append(v)
		v.process_mode = Node.PROCESS_MODE_INHERIT
	progress.call(0.9)
	await get_tree().process_frame
	_pool_tick(true)
	_start_audio()
	progress.call(1.0)
	await get_tree().process_frame
	update_camera_now()
	_update_sky(0.0)


func _start_audio() -> void:
	var music := AudioStreamPlayer.new()
	music.stream = Sfx.get_stream("music")
	music.bus = "Music"
	music.volume_db = -6.0
	add_child(music)
	music.play()
	var amb := AudioStreamPlayer.new()
	amb.stream = Sfx.get_stream("ambient")
	amb.bus = "SFX"
	amb.volume_db = -16.0
	add_child(amb)
	amb.play()
	rain_snd = AudioStreamPlayer.new()
	rain_snd.stream = Sfx.get_stream("rain")
	rain_snd.bus = "SFX"
	rain_snd.volume_db = -80.0
	add_child(rain_snd)
	rain_snd.play()


# ---------------------------------------------------------------- environment
func _make_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_blend_splits = false
	sun.light_angular_distance = 0.5
	add_child(sun)


func _make_static_world() -> void:
	var gb := StaticBody3D.new()
	gb.collision_layer = 1
	gb.collision_mask = 0
	add_child(gb)
	Gfx.box(self, Vector3(360, -0.5, 360), Vector3(824, 1, 824), Gfx.road_mat, gb)
	Gfx.box(self, Vector3(360, -0.6, 360), Vector3(8000, 1, 8000), Gfx.mat(Color(0.28, 0.36, 0.2), 1.0))
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8000, 3000)
	sea.mesh = pm
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/water.gdshader")
	sea.material_override = sm
	sea.position = Vector3(360, -0.08, 772 + 1500)
	add_child(sea)
	# invisible bounds
	for w in [[Vector3(-53, 20, 360), Vector3(2, 40, 830)], [Vector3(773, 20, 360), Vector3(2, 40, 830)],
			[Vector3(360, 20, -53), Vector3(830, 40, 2)], [Vector3(360, 20, 773), Vector3(830, 40, 2)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = w[1]
		cs.shape = bs
		cs.position = w[0]
		gb.add_child(cs)


func _make_garage_marker() -> void:
	var m := Gfx.mat(Color(0.2, 0.7, 1.0, 0.5), 0.5, 0.0, 1.5)
	Gfx.cyl(self, Game.GARAGE_POS + Vector3(0, 0.08, 0), 4.0, 0.1, m)
	Gfx.label(self, "GARAGE - tap USE to pick a vehicle", Game.GARAGE_POS + Vector3(0, 3.5, 0), 0.015, 80.0)
	var seat := Gfx.mat(Color(0.12, 0.13, 0.16), 0.7)
	Gfx.box(self, Game.GARAGE_POS + Vector3(0, 0.03, 0), Vector3(8, 0.02, 8), seat)


func _make_rain() -> void:
	rain = CPUParticles3D.new()
	rain.emitting = false
	rain.amount = 200
	rain.lifetime = 1.1
	rain.local_coords = false
	rain.fixed_fps = 30
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(22, 0.5, 22)
	rain.direction = Vector3(0, -1, 0)
	rain.spread = 2.0
	rain.gravity = Vector3(0, -14, 0)
	rain.initial_velocity_min = 9.0
	rain.initial_velocity_max = 12.0
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.5, 0.012)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.75, 0.82, 0.95, 0.4)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = rm
	rain.mesh = bm
	add_child(rain)


func apply_graphics() -> void:
	var p := Game.preset()
	camera.far = p.far
	sun.shadow_enabled = p.shadow
	sun.directional_shadow_max_distance = maxf(p.shadow_dist, 10.0)
	stream_radius = maxi(1, p.radius - (1 if mem_reduced else 0))
	ped_target = p.peds
	car_target = p.cars
	_apply_rain_amount()


func _apply_rain_amount() -> void:
	var base: int = Game.preset().rain
	rain.amount = base * (2 if weather == 3 else 1)
	rain.emitting = weather >= 2


# ---------------------------------------------------------------- streaming
func _wanted_block_keys() -> Array:
	var c := _focus_block()
	var out: Array = []
	for dx in range(-stream_radius, stream_radius + 1):
		for dz in range(-stream_radius, stream_radius + 1):
			var k := Vector2i(c.x + dx, c.y + dz)
			if k.x >= 0 and k.x < Game.N and k.y >= 0 and k.y < Game.N:
				out.append(k)
	out.sort_custom(func(a, b): return a.distance_squared_to(c) < b.distance_squared_to(c))
	return out


func _focus_block() -> Vector2i:
	var p := focus_pos()
	return Vector2i(clampi(roundi(p.x / Game.C), 0, Game.N - 1), clampi(roundi(p.z / Game.C), 0, Game.N - 1))


func focus_pos() -> Vector3:
	if player.in_vehicle and player.vehicle:
		return player.vehicle.global_position
	return player.global_position


func _build_block(k: Vector2i) -> void:
	if blocks.has(k):
		return
	var key := "%d_%d" % [k.x, k.y]
	var col_here := col_keys.has(key) and not Game.collected.has(key)
	var b := City.build_block(k.x, k.y, col_here)
	add_child(b)
	blocks[k] = b
	if b.has_meta("col_pos"):
		col_pos[key] = b.get_meta("col_pos")


func _stream_tick() -> void:
	var want := _wanted_block_keys()
	var c := _focus_block()
	for k in want:
		if not blocks.has(k) and not build_queue.has(k):
			build_queue.append(k)
	for k in blocks.keys():
		if maxi(absi(k.x - c.x), absi(k.y - c.y)) > stream_radius + 1:
			var key := "%d_%d" % [k.x, k.y]
			col_pos.erase(key)
			blocks[k].queue_free()
			blocks.erase(k)


func _pick_collectibles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260101
	var all: Array = []
	for x in range(Game.N):
		for z in range(Game.N):
			all.append("%d_%d" % [x, z])
	for i in range(all.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = all[i]
		all[i] = all[j]
		all[j] = t
	col_keys = all.slice(0, 20)


func _collect_tick() -> void:
	var pp := player.global_position
	for key in col_pos.keys():
		if Game.collected.has(key):
			continue
		if pp.distance_to(col_pos[key]) < 3.0:
			Game.collected.append(key)
			Game.add_money(100)
			Game.say("Collectible %d/20  +$100" % Game.collected.size())
			Sfx.play3d(self, "pickup", pp)
			var parts: PackedStringArray = str(key).split("_")
			var k := Vector2i(int(parts[0]), int(parts[1]))
			if blocks.has(k):
				for n in blocks[k].get_meta("col_nodes", []):
					if is_instance_valid(n):
						n.queue_free()
			col_pos.erase(key)


# ---------------------------------------------------------------- vehicles & pools
func all_vehicles() -> Array:
	registry = registry.filter(func(v): return is_instance_valid(v))
	return registry


func release_vehicle(v: Vehicle) -> void:
	v.pool = "owned"


func register_vehicle(v: Vehicle) -> void:
	registry.append(v)


func spawn_vehicle(kind: String, pos: Vector3, yaw: float, pool: String, driver := "") -> Vehicle:
	var v := Vehicle.new()
	v.pool = pool
	add_child(v)
	v.setup(kind)
	v.global_position = pos + Vector3(0, 0.3, 0)
	v.rotation.y = yaw
	v.driver = driver
	registry.append(v)
	return v


func garage_spawn() -> void:
	var owned := registry.filter(func(v): return is_instance_valid(v) and v.pool == "owned" and v.driver == "")
	while owned.size() >= 3:
		var old: Vehicle = owned.pop_front()
		registry.erase(old)
		old.queue_free()
	garage_i = (garage_i + 1) % Game.unlocked.size()
	var kind: String = Game.unlocked[garage_i]
	var v := spawn_vehicle(kind, Game.GARAGE_POS + Vector3(0, 0.5, 0), PI / 2.0, "owned")
	v.owned = true
	Game.say("Garage: %s" % v.cfg.name)


func _random_kind() -> String:
	var r := randf()
	if r < 0.08:
		return "police"
	return ["sedan", "hatchback", "sports", "suv", "pickup", "motorcycle", "offroad"][randi() % 7]


func _pool_tick(force := false) -> void:
	var pp := focus_pos()
	var node_i := roundi(pp.x / Game.C - 0.5)
	var node_j := roundi(pp.z / Game.C - 0.5)
	# pedestrians
	for i in range(peds.size()):
		var p: Ped = peds[i]
		var active := i < ped_target
		p.visible = active
		p.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		if not active or p.role != "ped":
			continue
		if force or p.global_position.distance_to(pp) > 100.0 or (p.state == "dead" and p.dead_t > 6.0):
			for attempt in range(6):
				var bx := clampi(roundi(pp.x / Game.C) + randi_range(-2, 2), 0, Game.N - 1)
				var bz := clampi(roundi(pp.z / Game.C) + randi_range(-2, 2), 0, Game.N - 1)
				p.place_on_corner(bx, bz, randi() % 4)
				if p.global_position.distance_to(pp) > 18.0:
					break
	# traffic
	var traffic: Array = []
	for v in all_vehicles():
		if v.pool == "traffic":
			traffic.append(v)
	for i in range(traffic.size()):
		var v: Vehicle = traffic[i]
		var active := i < car_target
		v.visible = active
		v.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		if not active:
			continue
		if force or v.global_position.distance_to(pp) > 170.0 or v.dead:
			_place_traffic(v, node_i, node_j, pp)
	# free owned vehicles that were left far away
	for v in all_vehicles():
		if v.pool == "owned" and v.driver == "" and v.global_position.distance_to(pp) > 320.0:
			registry.erase(v)
			v.queue_free()


func _place_traffic(v: Vehicle, ci: int, cj: int, pp: Vector3) -> void:
	for attempt in range(10):
		var ti := clampi(ci + randi_range(-2, 2), -1, Game.N - 1)
		var tj := clampi(cj + randi_range(-2, 2), -1, Game.N - 1)
		var d: Vector2i = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][randi() % 4]
		var pos := Game.node_pos(ti, tj) - Vector3(d.x, 0, d.y) * 32.0 + Vector3(-d.y * 4.0, 0.0, d.x * 4.0)
		if pos.x < -45.0 or pos.x > 765.0 or pos.z < -45.0 or pos.z > 765.0:
			continue
		var dist := pos.distance_to(pp)
		if dist < 50.0 or dist > 150.0:
			continue
		var clear := true
		for o in all_vehicles():
			if o != v and o.global_position.distance_to(pos) < 9.0:
				clear = false
				break
		if not clear:
			continue
		if v.dead or randf() < 0.4:
			v.setup(_random_kind())
		v.global_position = pos + Vector3(0, 0.3, 0)
		v.rotation.y = atan2(-d.x, -d.y)
		v.start_lane(ti, tj, d)
		v.driver = "ai"
		v.target_speed = randf_range(9.0, 13.0)
		v.vel_h = Vector3(d.x, 0, d.y) * 8.0
		v.speed_f = 8.0
		v.steer = 0.0
		return
	# no free slot: park it far away (inactive) until next tick
	v.global_position = Vector3(360, -50, 360)
	v.vel_h = Vector3.ZERO


# ---------------------------------------------------------------- frame
func _process(delta: float) -> void:
	if player == null:
		return
	tod = fmod(tod + delta * 24.0 / DAY_SECONDS, 24.0)
	_update_weather(delta)
	_update_sky(delta)
	player.update_camera(delta, camera)
	var focus := focus_pos()
	rain.global_position = camera.global_position + Vector3(0, 14, 0)
	if rain_snd:
		var tgt := -80.0
		if weather >= 2:
			tgt = -14.0 if weather == 2 else -8.0
		rain_snd.volume_db = lerpf(rain_snd.volume_db, tgt, 0.5 * delta)
	# at most one new block per frame to avoid hitches
	if not build_queue.is_empty():
		var k: Vector2i = build_queue.pop_front()
		if maxi(absi(k.x - _focus_block().x), absi(k.y - _focus_block().y)) <= stream_radius:
			_build_block(k)
	_t_stream += delta
	if _t_stream > 0.4:
		_t_stream = 0.0
		_stream_tick()
	_t_pool += delta
	if _t_pool > 1.0:
		_t_pool = 0.0
		_pool_tick()
	_t_col += delta
	if _t_col > 0.25:
		_t_col = 0.0
		_collect_tick()
	_t_slow += delta
	if _t_slow > 5.0:
		_t_slow = 0.0
		_memory_check()
	if focus.y < -5.0:
		player.global_position = Game.START_POS


func update_camera_now() -> void:
	player.update_camera(1.0, camera)


func _memory_check() -> void:
	mem_mb = OS.get_static_memory_usage() / 1048576.0
	if mem_mb > 1100.0 and not mem_reduced:
		mem_reduced = true
		apply_graphics()
		Game.say("Memory pressure: detail reduced")
	elif mem_mb < 800.0 and mem_reduced:
		mem_reduced = false
		apply_graphics()


func _update_weather(delta: float) -> void:
	var s := int(Game.settings.weather)
	if s == 0:
		weather_t -= delta
		if weather_t <= 0.0:
			weather_t = randf_range(150.0, 360.0)
			weather = [0, 0, 1, 1, 2][randi() % 5]
	else:
		weather = s - 1
	if weather != _last_weather:
		_last_weather = weather
		_apply_rain_amount()
	var goal: float = [0.0, 0.5, 0.8, 1.0][weather]
	cloud_f = move_toward(cloud_f, goal, delta * 0.05)
	wet = move_toward(wet, 1.0 if weather >= 2 else 0.0, delta * 0.04)
	Gfx.set_wet(wet)


func _update_sky(delta: float) -> void:
	var ang := (tod - 6.0) / 24.0 * TAU
	var sh := sin(ang)
	var day := smoothstep(-0.08, 0.3, sh)
	var dusk := clampf(1.0 - absf(sh) / 0.35, 0.0, 1.0) * (1.0 - cloud_f * 0.5)
	var elev := maxf(absf(asin(clampf(sh, -1.0, 1.0))), 0.12)
	sun.rotation = Vector3(-elev, 0.7, 0.0)
	sun.light_energy = lerpf(0.14, 1.2, day) * (1.0 - cloud_f * 0.5)
	sun.light_color = Color(0.45, 0.55, 0.95).lerp(Color(1.0, 0.96, 0.88), day).lerp(Color(1.0, 0.62, 0.38), dusk * 0.8)
	var top := Color(0.02, 0.03, 0.09).lerp(Color(0.22, 0.46, 0.85), day).lerp(Color(0.28, 0.3, 0.55), dusk * 0.6)
	var hor := Color(0.05, 0.07, 0.14).lerp(Color(0.66, 0.79, 0.92), day).lerp(Color(0.98, 0.56, 0.34), dusk)
	var grey := Color(0.45, 0.48, 0.52) * lerpf(0.15, 1.0, day)
	top = top.lerp(grey, cloud_f * 0.8)
	hor = hor.lerp(grey * 1.15, cloud_f * 0.85)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = hor * 0.5
	env.fog_light_color = hor
	var p := Game.preset()
	env.fog_density = p.fog * (1.0 + cloud_f * 1.2 + wet * 0.8)
	env.ambient_light_color = Color(0.1, 0.12, 0.22).lerp(Color(0.62, 0.66, 0.74), day).lerp(Color(0.8, 0.6, 0.5), dusk * 0.25)
	env.ambient_light_energy = 1.0 - cloud_f * 0.1
	Gfx.set_night(1.0 - smoothstep(-0.05, 0.2, sh))


# ---------------------------------------------------------------- player events
func _on_player_died() -> void:
	if _death_pending:
		return
	_death_pending = true
	missions.fail("You were wasted")
	await get_tree().create_timer(3.0).timeout
	_death_pending = false
	Game.add_money(-mini(Game.money / 10, 500))
	Game.clear_wanted()
	police.reset()
	player.respawn(HOSPITAL_POS)
	Game.say("Treated at Santa Lucia Hospital")


func busted() -> void:
	Game.say("BUSTED")
	Game.add_money(-mini(Game.money / 8, 400))
	Game.clear_wanted()
	police.reset()
	if player.in_vehicle:
		player.exit_vehicle(true)
	player.global_position = POLICE_POS
	player.health = 100.0
	missions.fail("You were arrested")
