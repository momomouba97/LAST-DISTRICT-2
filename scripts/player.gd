extends CharacterBody3D
class_name Player

signal died

var health := 100.0
var dead := false
var in_vehicle := false
var vehicle: Vehicle = null
var yaw := 0.0
var pitch := -0.3
var cam_dist := 5.5
var cam_dist_goal := 5.5
var crouching := false
var anim := 0.0
var shoot_cd := 0.0
var melee_cd := 0.0
var reload_t := 0.0
var armed_t := 0.0
var regen_t := 0.0
var dead_t := 0.0
var fov := 65.0
var parts: Dictionary = {}
var model: Node3D
var cap: CapsuleShape3D
var step_t := 0.0
var interact_hint := ""

const WALK := 1.9
const RUN := 4.3
const SPRINT := 6.8


func _ready() -> void:
	add_to_group("chars")
	add_to_group("player")
	collision_layer = 4
	collision_mask = 3
	var cs := CollisionShape3D.new()
	cap = CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)
	parts = Gfx.make_human(Color(0.1, 0.35, 0.55), Color(0.12, 0.12, 0.14), Color(0.8, 0.6, 0.45), Color(0.06, 0.05, 0.05))
	model = parts.root
	add_child(model)
	health = Game.health


func damage(amount: float) -> void:
	if dead:
		return
	health -= amount
	regen_t = 10.0
	if health <= 0.0:
		health = 0.0
		dead = true
		dead_t = 0.0
		if in_vehicle:
			exit_vehicle(true)
		model.rotation.x = -PI / 2.0
		model.position.y = 0.2
		Game.say("WASTED")
		died.emit()


func respawn(at: Vector3) -> void:
	dead = false
	health = 100.0
	global_position = at
	velocity = Vector3.ZERO
	model.rotation = Vector3.ZERO
	model.position = Vector3.ZERO


func _physics_process(delta: float) -> void:
	shoot_cd = maxf(0.0, shoot_cd - delta)
	melee_cd = maxf(0.0, melee_cd - delta)
	armed_t = maxf(0.0, armed_t - delta)
	regen_t = maxf(0.0, regen_t - delta)
	if regen_t <= 0.0 and health < 100.0 and not dead:
		health = minf(100.0, health + 2.0 * delta)
	if dead:
		dead_t += delta
		return
	if Game.cutscene:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			var need := 12 - Game.ammo_mag
			var take := mini(need, Game.ammo_reserve)
			Game.ammo_mag += take
			Game.ammo_reserve -= take
	if Game.consume("interact"):
		_interact()
	if in_vehicle:
		return
	_on_foot(delta)


func _on_foot(delta: float) -> void:
	var mv := Game.get_move()
	var look := Game.take_look()
	yaw -= look.x * 0.0045 * Game.settings.look_sens
	pitch = clampf(pitch - look.y * 0.0035 * Game.settings.look_sens, -1.2, 0.35)
	if Game.consume("crouch"):
		crouching = not crouching
		cap.height = 1.1 if crouching else 1.7
		model.scale.y = 0.65 if crouching else 1.0
	var spd := RUN
	if mv.length() < 0.5:
		spd = WALK
	if Game.is_down("sprint") and not crouching:
		spd = SPRINT
	if crouching:
		spd = 1.3
	var dir := Vector3(mv.x, 0.0, mv.y).rotated(Vector3.UP, yaw)
	var aiming := Game.is_down("aim") or armed_t > 0.0
	var target_v := dir * spd * mv.length()
	velocity.x = lerpf(velocity.x, target_v.x, minf(1.0, 12.0 * delta))
	velocity.z = lerpf(velocity.z, target_v.z, minf(1.0, 12.0 * delta))
	if is_on_floor():
		velocity.y = -0.5
		if Game.consume("jump") and not crouching:
			velocity.y = 7.0
	else:
		velocity.y -= 22.0 * delta
	move_and_slide()
	if aiming:
		rotation.y = lerp_angle(rotation.y, yaw, 12.0 * delta)
	elif dir.length() > 0.1 and mv.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 10.0 * delta)
	_animate(delta, aiming)
	fov = lerpf(fov, 48.0 if Game.is_down("aim") else 65.0, 8.0 * delta)
	cam_dist_goal = 3.2 if Game.is_down("aim") else 5.5
	if Game.is_down("shoot"):
		_shoot()
	if Game.consume("melee"):
		_melee()
	if Game.consume("reload") and Game.ammo_mag < 12 and Game.ammo_reserve > 0 and reload_t <= 0.0:
		reload_t = 1.2
		Game.say("Reloading...")


func _animate(delta: float, aiming: bool) -> void:
	var sp := Vector2(velocity.x, velocity.z).length()
	anim += delta * sp * 2.0
	var sw := sin(anim) * minf(sp / 4.0, 1.0) * 0.9
	parts.legL.rotation.x = sw
	parts.legR.rotation.x = -sw
	parts.armL.rotation.x = -sw
	parts.gun.visible = aiming
	if aiming:
		parts.armR.rotation.x = -1.45
	else:
		parts.armR.rotation.x = sw
	if melee_cd > 0.3:
		parts.armR.rotation.x = -1.6
	parts.torso.position.y = sin(Time.get_ticks_msec() * 0.003) * 0.01
	if sp > 1.5 and is_on_floor():
		step_t += delta * sp
		if step_t > 2.2:
			step_t = 0.0
			Sfx.play3d(self, "step", global_position, -14.0)


func _cam_ray_origin() -> Vector3:
	return global_position + Vector3(0, 1.5, 0)


func _shoot() -> void:
	if shoot_cd > 0.0 or reload_t > 0.0:
		return
	if Game.ammo_mag <= 0:
		if Game.ammo_reserve > 0:
			reload_t = 1.2
			Game.say("Reloading...")
		else:
			Game.say("Out of ammo")
			shoot_cd = 0.6
		return
	Game.ammo_mag -= 1
	shoot_cd = 0.32
	armed_t = 2.0
	Game.add_heat(1.5)
	var cam: Camera3D = Game.world.camera
	var from := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from + fwd * 2.5, from + fwd * 90.0, 7, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var muzzle := global_position + Vector3(0, 1.2, 0) + (-global_transform.basis.z) * 0.6
	var end := from + fwd * 90.0
	if not hit.is_empty():
		end = hit.position
		var col: Object = hit.collider
		if col is Ped:
			col.damage(25.0, true)
		elif col is Vehicle:
			col.damage(10.0)
			if col.driver == "police":
				Game.add_heat(10.0)
	Sfx.play3d(self, "shot", muzzle, -2.0)
	_tracer(muzzle, end)


func _tracer(a: Vector3, b: Vector3) -> void:
	var d := a.distance_to(b)
	if d < 0.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, d)
	mi.mesh = bm
	mi.material_override = Gfx.mat(Color(1, 0.9, 0.5), 1.0, 0.0, 3.0)
	Game.world.add_child(mi)
	mi.global_position = (a + b) * 0.5
	mi.look_at(b, Vector3.UP)
	get_tree().create_timer(0.05).timeout.connect(mi.queue_free)


func _melee() -> void:
	if melee_cd > 0.0:
		return
	melee_cd = 0.55
	var fwd := -global_transform.basis.z
	for c in get_tree().get_nodes_in_group("chars"):
		if c is Ped and c.state != "dead":
			var to: Vector3 = c.global_position - global_position
			to.y = 0.0
			if to.length() < 2.0 and to.normalized().dot(fwd) > 0.3:
				c.damage(18.0, true)
				Sfx.play3d(self, "punch", c.global_position)
				break


# ------------------------------------------------------------ interaction
func nearest_free_vehicle() -> Vehicle:
	var best: Vehicle = null
	var bd := 4.0
	for v in Game.world.all_vehicles():
		if v.dead or v.roadblock or v.driver == "player":
			continue
		var d: float = v.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = v
	return best


func _interact() -> void:
	if Game.world.missions.try_interact():
		return
	if in_vehicle:
		exit_vehicle(false)
		return
	if global_position.distance_to(Game.GARAGE_POS) < 6.0:
		Game.world.garage_spawn()
		return
	var v := nearest_free_vehicle()
	if v:
		enter_vehicle(v)


func enter_vehicle(v: Vehicle) -> void:
	if v.driver == "ai":
		Game.add_heat(14.0)
		Game.say("Carjacked!")
	elif v.driver == "police":
		Game.add_heat(40.0)
	v.driver = "player"
	v.siren_active = false
	v.owned = true
	v.parked = false
	v.ray.enabled = false
	Game.world.release_vehicle(v)
	vehicle = v
	in_vehicle = true
	model.visible = false
	collision_layer = 0
	collision_mask = 0
	cam_dist_goal = 8.0
	yaw = v.rotation.y
	pitch = -0.25
	Game.say(v.cfg.name)


func exit_vehicle(forced: bool) -> void:
	if vehicle == null:
		return
	var v := vehicle
	v.driver = ""
	v.throttle = 0.0
	v.steer = 0.0
	in_vehicle = false
	vehicle = null
	model.visible = true
	collision_layer = 4
	collision_mask = 3
	var side: Vector3 = v.global_transform.basis.x * (v.cfg.size.x * 0.5 + 1.0)
	global_position = v.global_position + side + Vector3(0, 0.3, 0)
	velocity = Vector3.ZERO
	cam_dist_goal = 5.5
	yaw = v.rotation.y
	if forced:
		velocity = Vector3(0, 3, 0)


# ------------------------------------------------------------ camera
func update_camera(delta: float, cam: Camera3D) -> void:
	var focus: Vector3
	var look := Vector2.ZERO
	if in_vehicle and vehicle:
		focus = vehicle.global_position + Vector3(0, 1.6, 0)
		look = Game.take_look()
		var heading := vehicle.rotation.y
		if vehicle.speed_f < -2.0:
			heading += PI
		if look.length() > 0.5:
			yaw -= look.x * 0.0045 * Game.settings.look_sens
			pitch = clampf(pitch - look.y * 0.0035 * Game.settings.look_sens, -0.9, 0.1)
		elif absf(vehicle.speed_f) > 1.5:
			yaw = lerp_angle(yaw, heading, 2.2 * delta)
		pitch = lerpf(pitch, -0.22, 1.0 * delta) if look.length() < 0.5 else pitch
		cam_dist_goal = 7.5 + clampf(absf(vehicle.speed_f) * 0.07, 0.0, 3.0)
		fov = lerpf(fov, 62.0 + clampf(absf(vehicle.speed_f) * 0.4, 0.0, 16.0), 3.0 * delta)
	else:
		focus = global_position + Vector3(0, 1.5 if not crouching else 1.0, 0)
	cam_dist = lerpf(cam_dist, cam_dist_goal, 4.0 * delta)
	var cb := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var shoulder := Vector3(0.6, 0, 0) if (not in_vehicle and Game.is_down("aim")) else Vector3.ZERO
	var desired := focus + cb * (Vector3(0, 0, cam_dist) + shoulder)
	var q := PhysicsRayQueryParameters3D.create(focus, desired, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		desired = hit.position + hit.normal * 0.35
	cam.global_position = cam.global_position.lerp(desired, minf(1.0, 14.0 * delta))
	cam.global_transform.basis = cb
	cam.fov = fov
