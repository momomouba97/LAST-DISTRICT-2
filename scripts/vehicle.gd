extends CharacterBody3D
class_name Vehicle
## Arcade vehicle (CharacterBody3D). Each kind has its own handling config.
## driver: "" (empty) | "player" | "ai" (traffic) | "police" (pursuit) | "target" (mission chase)

const CFG := {
	"sedan": {"name": "Sedan", "size": Vector3(1.8, 0.6, 4.4), "cab": Vector3(1.55, 0.5, 2.1), "cab_z": 0.1, "accel": 9.0, "max": 31.0, "rev": 9.0, "steer": 1.9, "grip": 6.0, "brake": 24.0, "color": Color(0.55, 0.1, 0.12), "hp": 100.0},
	"hatchback": {"name": "Hatchback", "size": Vector3(1.7, 0.6, 3.8), "cab": Vector3(1.5, 0.55, 2.0), "cab_z": 0.3, "accel": 9.5, "max": 29.0, "rev": 8.0, "steer": 2.1, "grip": 6.5, "brake": 22.0, "color": Color(0.2, 0.45, 0.7), "hp": 90.0},
	"sports": {"name": "Sports car", "size": Vector3(1.9, 0.5, 4.3), "cab": Vector3(1.5, 0.4, 1.7), "cab_z": 0.3, "accel": 15.0, "max": 48.0, "rev": 10.0, "steer": 2.3, "grip": 7.5, "brake": 30.0, "color": Color(0.9, 0.7, 0.05), "hp": 80.0},
	"suv": {"name": "SUV", "size": Vector3(2.0, 0.8, 4.8), "cab": Vector3(1.8, 0.65, 2.7), "cab_z": 0.2, "accel": 8.0, "max": 33.0, "rev": 9.0, "steer": 1.7, "grip": 5.5, "brake": 24.0, "color": Color(0.15, 0.17, 0.2), "hp": 140.0},
	"pickup": {"name": "Pickup", "size": Vector3(2.0, 0.8, 5.0), "cab": Vector3(1.8, 0.6, 1.7), "cab_z": -0.8, "accel": 8.5, "max": 30.0, "rev": 8.0, "steer": 1.7, "grip": 5.2, "brake": 22.0, "color": Color(0.75, 0.75, 0.72), "hp": 130.0, "bed": true},
	"police": {"name": "Police cruiser", "size": Vector3(1.85, 0.6, 4.6), "cab": Vector3(1.6, 0.5, 2.1), "cab_z": 0.1, "accel": 12.0, "max": 40.0, "rev": 10.0, "steer": 2.1, "grip": 7.0, "brake": 28.0, "color": Color(0.92, 0.92, 0.95), "hp": 130.0, "bar": true},
	"motorcycle": {"name": "Motorcycle", "size": Vector3(0.55, 0.7, 2.0), "cab": Vector3(0.4, 0.5, 0.6), "cab_z": 0.1, "accel": 14.0, "max": 42.0, "rev": 4.0, "steer": 2.8, "grip": 8.0, "brake": 26.0, "color": Color(0.1, 0.1, 0.12), "hp": 60.0, "bike": true},
	"offroad": {"name": "Off-road", "size": Vector3(2.0, 0.9, 4.2), "cab": Vector3(1.8, 0.6, 2.0), "cab_z": 0.2, "accel": 9.0, "max": 32.0, "rev": 9.0, "steer": 2.0, "grip": 4.5, "brake": 22.0, "color": Color(0.3, 0.45, 0.2), "hp": 150.0, "lift": true},
}

var pool := ""
var kind := "sedan"
var cfg: Dictionary = {}
var driver := ""
var vel_h := Vector3.ZERO
var health := 100.0
var dead := false
var steer := 0.0
var throttle := 0.0
var brake_in := 0.0
var hand := false
var speed_f := 0.0
var is_target := false
var parked := false
var owned := false
var roadblock := false
var ni := 0
var nj := 0
var dirv := Vector2i(1, 0)
var chase_pos := Vector3.ZERO
var target_speed := 11.0
var stuck_t := 0.0
var reverse_t := 0.0
var dmg_cd := 0.0
var model: Node3D
var body_mi: MeshInstance3D
var body_mat: StandardMaterial3D
var wheel_nodes: Array = []
var front_wheels: Array = []
var ray: RayCast3D
var engine_snd: AudioStreamPlayer3D
var siren_snd: AudioStreamPlayer3D
var smoke_t := 0.0
var siren_active := false
var _ray_hit := 99.0
var _last_player_hit := 0.0


func setup(k: String) -> void:
	kind = k
	cfg = CFG[k]
	health = cfg.hp
	dead = false
	if model:
		model.queue_free()
		model = null
	for c in get_children():
		if c is CollisionShape3D or c is RayCast3D:
			c.queue_free()
	collision_layer = 2
	collision_mask = 3
	var sz: Vector3 = cfg.size
	var h: float = sz.y + cfg.cab.y + 0.25
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(sz.x, h * 0.8, sz.z)
	cs.shape = bs
	cs.position = Vector3(0, h * 0.4 + 0.12, 0)
	add_child(cs)
	ray = RayCast3D.new()
	ray.position = Vector3(0, 0.6, -sz.z * 0.5)
	ray.target_position = Vector3(0, 0, -14)
	ray.collision_mask = 6
	ray.enabled = false
	add_child(ray)
	_build_model()
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50)


func _build_model() -> void:
	model = Node3D.new()
	add_child(model)
	wheel_nodes.clear()
	front_wheels.clear()
	var sz: Vector3 = cfg.size
	var cab: Vector3 = cfg.cab
	var lift := 0.3 if cfg.get("lift", false) else 0.0
	var wr := 0.34 + lift * 0.5
	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = cfg.color
	body_mat.metallic = 0.55
	body_mat.roughness = 0.28
	var glass := Gfx.mat(Color(0.12, 0.18, 0.25), 0.05, 0.3)
	var dark := Gfx.mat(Color(0.05, 0.05, 0.06), 0.8)
	if cfg.get("bike", false):
		body_mi = Gfx.box(model, Vector3(0, 0.6 + lift, 0), Vector3(0.3, 0.35, 1.2), body_mat)
		Gfx.box(model, Vector3(0, 0.95, 0.2), Vector3(0.35, 0.12, 0.6), dark)
		Gfx.box(model, Vector3(0, 1.05, -0.45), Vector3(0.7, 0.06, 0.06), dark)
		for z in [-0.75, 0.75]:
			var w := Gfx.cyl(model, Vector3(0, 0.33, z), 0.33, 0.14, dark, 0.0, Vector3(0, 0, PI / 2))
			wheel_nodes.append(w)
			if z < 0:
				front_wheels.append(w)
	else:
		body_mi = Gfx.box(model, Vector3(0, wr + sz.y * 0.5 + lift * 0.5, 0), sz, body_mat)
		Gfx.box(model, Vector3(0, wr + sz.y + cab.y * 0.5 + lift * 0.5, cfg.cab_z), cab, glass)
		var roof_mat := body_mat
		Gfx.box(model, Vector3(0, wr + sz.y + cab.y + lift * 0.5, cfg.cab_z), Vector3(cab.x, 0.06, cab.z * 0.9), roof_mat)
		if cfg.get("bed", false):
			Gfx.box(model, Vector3(0, wr + sz.y + 0.2, 1.4), Vector3(sz.x * 0.95, 0.35, 1.8), Gfx.mat(Color(0.3, 0.3, 0.32), 0.6, 0.3))
		if cfg.get("bar", false):
			Gfx.box(model, Vector3(-0.35, wr + sz.y + cab.y + 0.12, cfg.cab_z), Vector3(0.5, 0.12, 0.25), Gfx.siren_a)
			Gfx.box(model, Vector3(0.35, wr + sz.y + cab.y + 0.12, cfg.cab_z), Vector3(0.5, 0.12, 0.25), Gfx.siren_b)
			Gfx.box(model, Vector3(0, wr + sz.y * 0.5 + lift * 0.5, 0), Vector3(sz.x + 0.02, 0.18, sz.z * 0.5), Gfx.mat(Color(0.1, 0.12, 0.35), 0.4, 0.3))
		for sx in [-1, 1]:
			Gfx.box(model, Vector3(sx * sz.x * 0.35, wr + sz.y * 0.55 + lift * 0.5, -sz.z * 0.5), Vector3(0.35, 0.15, 0.06), Gfx.headlight_mat)
			Gfx.box(model, Vector3(sx * sz.x * 0.35, wr + sz.y * 0.55 + lift * 0.5, sz.z * 0.5), Vector3(0.35, 0.14, 0.06), Gfx.brake_mat)
		for sx in [-1, 1]:
			for sz_i in [-1, 1]:
				var w := Gfx.cyl(model, Vector3(sx * (sz.x * 0.5 - 0.05), wr, sz_i * sz.z * 0.32), wr, 0.26, dark, 0.0, Vector3(0, 0, PI / 2))
				wheel_nodes.append(w)
				if sz_i < 0:
					front_wheels.append(w)


func _ensure_audio() -> void:
	if engine_snd == null:
		var st := Sfx.get_stream("engine")
		if st == null:
			return
		engine_snd = AudioStreamPlayer3D.new()
		engine_snd.stream = st
		engine_snd.bus = "SFX"
		engine_snd.unit_size = 10.0
		engine_snd.max_distance = 50.0
		engine_snd.volume_db = -6.0
		add_child(engine_snd)
	if siren_snd == null and cfg.get("bar", false):
		siren_snd = AudioStreamPlayer3D.new()
		siren_snd.stream = Sfx.get_stream("siren")
		siren_snd.bus = "SFX"
		siren_snd.unit_size = 14.0
		siren_snd.max_distance = 80.0
		siren_snd.volume_db = -8.0
		add_child(siren_snd)


func damage(amount: float, source := "") -> void:
	if dead or amount <= 0.0:
		return
	health -= amount
	if health < cfg.hp * 0.5:
		body_mat.albedo_color = cfg.color.lerp(Color(0.1, 0.1, 0.1), 0.6)
	if health <= 0.0:
		_wreck()


func _wreck() -> void:
	dead = true
	body_mat.albedo_color = Color(0.05, 0.05, 0.05)
	body_mat.metallic = 0.0
	siren_active = false
	if driver == "player" and Game.player:
		Game.player.exit_vehicle(true)
	driver = ""
	Sfx.play3d(self, "crash", global_position, 3.0)


func _physics_process(delta: float) -> void:
	dmg_cd = maxf(0.0, dmg_cd - delta)
	if dead:
		throttle = 0.0
	elif driver == "player":
		_player_input(delta)
	elif driver != "":
		_ai(delta)
	else:
		throttle = 0.0
		brake_in = 0.3
	_integrate(delta)
	_visuals(delta)


func _player_input(delta: float) -> void:
	var mv := Game.get_move()
	throttle = clampf(-mv.y, 0.0, 1.0)
	brake_in = clampf(mv.y, 0.0, 1.0)
	hand = Game.is_down("jump") or Game.is_down("handbrake")
	steer = move_toward(steer, mv.x, 5.0 * delta)
	if Game.consume("horn"):
		Sfx.play3d(self, "horn", global_position)


func _integrate(delta: float) -> void:
	var spd_prev := vel_h.length()
	# steering rotates the body first so sideways slip is measured afterwards
	var fwd0 := -global_transform.basis.z
	var vf0 := vel_h.dot(fwd0)
	var sf := clampf(vf0 / 6.0, -1.0, 1.0)
	var yaw: float = -steer * cfg.steer * sf * (1.0 - 0.45 * clampf(absf(vf0) / cfg.max, 0.0, 1.0)) * (1.5 if hand else 1.0)
	rotation.y += yaw * delta
	var fwd := -global_transform.basis.z
	var right := global_transform.basis.x
	var vf := vel_h.dot(fwd)
	var vs := vel_h.dot(right)
	if throttle > 0.0:
		if vf < -0.5:
			vf += cfg.brake * delta
		else:
			vf += cfg.accel * throttle * delta * (1.0 - clampf(vf / cfg.max, 0.0, 1.0)) + 0.6 * delta
	elif brake_in > 0.0:
		if vf > 0.5:
			vf -= cfg.brake * brake_in * delta
		else:
			vf = maxf(vf - cfg.accel * 0.6 * brake_in * delta, -cfg.rev)
	else:
		vf = move_toward(vf, 0.0, 3.0 * delta)
	if hand:
		vf = move_toward(vf, 0.0, 9.0 * delta)
	var g: float = cfg.grip * (0.25 if (hand and absf(vf) > 5.0) else 1.0)
	vs = lerpf(vs, 0.0, 1.0 - exp(-g * delta))
	vel_h = fwd * vf + right * vs
	speed_f = vf
	velocity.x = vel_h.x
	velocity.z = vel_h.z
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 25.0 * delta
	move_and_slide()
	var nh := Vector3(velocity.x, 0.0, velocity.z)
	var impact := (vel_h - nh).length()
	var pre := vel_h
	vel_h = nh
	if impact > 7.0 and dmg_cd <= 0.0:
		dmg_cd = 0.4
		damage(impact * 1.6)
		Sfx.play3d(self, "crash", global_position, clampf(impact * 0.2 - 4.0, -6.0, 4.0))
		if driver == "player":
			Game.player.damage(impact * 0.25)
	for i in range(get_slide_collision_count()):
		var col := get_slide_collision(i).get_collider()
		if col is Vehicle and dmg_cd > 0.3:
			col.damage(impact * 1.3)
			col.vel_h += pre * 0.25
			if driver == "player" and col.driver != "police" and Time.get_ticks_msec() - _last_player_hit > 1500:
				_last_player_hit = Time.get_ticks_msec()
				Game.add_heat(4.0)
			if col.driver == "police" and driver == "player":
				Game.add_heat(10.0)
	if spd_prev > 5.0 and (driver == "player" or driver == "police" or driver == "target"):
		_run_over(spd_prev)


func _run_over(spd: float) -> void:
	var fwd := -global_transform.basis.z
	for c in get_tree().get_nodes_in_group("chars"):
		if c == self or (c is Player and driver == "player"):
			continue
		var to: Vector3 = c.global_position - global_position
		to.y = 0.0
		if to.length() < 2.4 and to.normalized().dot(fwd) > 0.3:
			if c is Ped:
				c.hit_by_vehicle(self, spd * 0.3)
			elif c is Player and driver != "player":
				c.damage(spd * 1.2)


func _visuals(delta: float) -> void:
	var sp := speed_f
	for w in wheel_nodes:
		w.rotation.x += sp * delta * 2.5
	for w in front_wheels:
		w.rotation.y = -steer * 0.4
	if model:
		var lean := -steer * clampf(absf(sp) / cfg.max, 0.0, 1.0)
		model.rotation.z = lerpf(model.rotation.z, lean * (0.45 if cfg.get("bike", false) else 0.04), 6.0 * delta)
		model.rotation.x = lerpf(model.rotation.x, clampf(-(throttle - brake_in) * 0.02, -0.03, 0.03), 4.0 * delta)
	var cam_d := 999.0
	if Game.world and Game.world.camera:
		cam_d = global_position.distance_to(Game.world.camera.global_position)
	var want_audio := cam_d < 45.0 and (driver != "" or absf(sp) > 1.0) and not dead
	if want_audio:
		_ensure_audio()
	if engine_snd:
		if want_audio and not engine_snd.playing:
			engine_snd.play()
		elif not want_audio and engine_snd.playing:
			engine_snd.stop()
		engine_snd.pitch_scale = 0.7 + clampf(absf(sp) / cfg.max, 0.0, 1.0) * 1.8 + throttle * 0.2
	if siren_snd:
		var on := siren_active and cam_d < 90.0 and not dead
		if on and not siren_snd.playing:
			siren_snd.play()
		elif not on and siren_snd.playing:
			siren_snd.stop()


# --------------------------------------------------------------------- AI
func start_lane(i: int, j: int, d: Vector2i) -> void:
	ni = i
	nj = j
	dirv = d


func _lane_target() -> Vector3:
	var np := Game.node_pos(ni, nj)
	return np + Vector3(-dirv.y * 4.0, 0.0, dirv.x * 4.0)


func _choose_dir() -> void:
	var d := dirv
	var left := Vector2i(d.y, -d.x)
	var right := Vector2i(-d.y, d.x)
	var opts: Array = [d, d, d, left, right]
	opts.shuffle()
	for o in opts:
		var ti: int = ni + o.x
		var tj: int = nj + o.y
		if ti >= -1 and ti <= Game.N - 1 and tj >= -1 and tj <= Game.N - 1:
			ni = ti
			nj = tj
			dirv = o
			return
	dirv = Vector2i(-d.x, -d.y)
	ni += dirv.x
	nj += dirv.y


func _ai(delta: float) -> void:
	ray.enabled = true
	var goal: Vector3
	var tspeed := target_speed
	if driver == "police":
		goal = chase_pos
		tspeed = cfg.max * 0.85 * (1.15 if Game.wanted >= 3 else 1.0)
	else:
		goal = _lane_target()
		if is_target:
			tspeed = 17.0
		if global_position.distance_to(goal) < 11.0:
			_choose_dir()
			goal = _lane_target()
		# traffic lights
		var np := Game.node_pos(ni, nj)
		var dc := global_position.distance_to(np)
		var axis := 0 if dirv.x != 0 else 1
		if dc < 26.0 and dc > 9.0 and not Game.axis_green(axis):
			if (np - global_position).normalized().dot(Vector3(dirv.x, 0, dirv.y)) > 0.5:
				tspeed = 0.0
	var to := goal - global_position
	to.y = 0.0
	var local := global_transform.basis.inverse() * to
	var ang := atan2(local.x, -local.z)
	var st := clampf(ang * 2.0, -1.0, 1.0)
	var obstacle := 99.0
	if ray.is_colliding():
		var col := ray.get_collider()
		if not (driver == "police" and col is Vehicle and col.driver == "player"):
			obstacle = global_position.distance_to(ray.get_collision_point())
	if obstacle < 22.0:
		tspeed = minf(tspeed, maxf(0.0, (obstacle - 6.0) * 1.2))
	tspeed *= lerpf(1.0, 0.45, clampf(absf(ang) / 1.2, 0.0, 1.0))
	var vf := speed_f
	var thr := clampf((tspeed - vf) / 3.0, -1.0, 1.0)
	if reverse_t > 0.0:
		reverse_t -= delta
		throttle = 0.0
		brake_in = 1.0
		st = -st
	else:
		throttle = maxf(thr, 0.0)
		brake_in = maxf(-thr, 0.0)
		if tspeed > 2.0 and absf(vf) < 0.6:
			stuck_t += delta
			if stuck_t > 2.5:
				stuck_t = 0.0
				reverse_t = 1.3
		else:
			stuck_t = 0.0
	steer = move_toward(steer, st, 4.0 * delta)
	hand = false
