extends CharacterBody3D
class_name Ped
## Pooled pedestrian. role "ped" walks sidewalks; role "enemy" hunts the player.

signal died(ped: Ped)

const CORNERS := [Vector2(-30, -30), Vector2(30, -30), Vector2(30, 30), Vector2(-30, 30)]

var role := "ped"
var gx := 0
var gz := 0
var corner := 0
var dir := 1
var health := 30.0
var speed := 1.5
var state := "walk"
var flee_t := 0.0
var cd := 0.0
var dead_t := 0.0
var anim := 0.0
var skip := 0
var parts: Dictionary = {}
var model: Node3D
var bound_pos := Vector3.ZERO     # enemies: area they spawned in


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	add_to_group("chars")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)
	randomize_look()


func randomize_look() -> void:
	if model:
		model.queue_free()
	var shirt := Color.from_hsv(randf(), randf_range(0.2, 0.7), randf_range(0.4, 0.9))
	if role == "enemy":
		shirt = Color(0.55, 0.08, 0.08)
	var pants := Color(0.15, 0.17, 0.25) if randf() < 0.6 else Color(0.35, 0.3, 0.22)
	var skin: Color = [Color(0.9, 0.72, 0.58), Color(0.7, 0.5, 0.36), Color(0.45, 0.3, 0.22)][randi() % 3]
	parts = Gfx.make_human(shirt, pants, skin, Color(0.1, 0.08, 0.06))
	model = parts.root
	add_child(model)
	if role == "enemy":
		parts.gun.visible = true
		health = 60.0
		speed = 3.4
	else:
		health = 30.0
		speed = randf_range(1.3, 1.9)


func place_on_corner(bx: int, bz: int, c: int) -> void:
	gx = bx
	gz = bz
	corner = c
	dir = 1 if randf() < 0.5 else -1
	var cp := _corner_pos()
	global_position = cp + Vector3(randf_range(-2, 2), 0.1, randf_range(-2, 2))
	velocity = Vector3.ZERO
	revive()


func revive() -> void:
	state = "walk"
	dead_t = 0.0
	if model:
		model.rotation = Vector3.ZERO
		model.position = Vector3.ZERO
	health = 60.0 if role == "enemy" else 30.0
	collision_layer = 4


func _corner_pos() -> Vector3:
	var c: Vector2 = CORNERS[corner]
	return Vector3(gx * Game.C + c.x, global_position.y, gz * Game.C + c.y)


func _next_corner() -> void:
	var c: Vector2 = CORNERS[corner]
	if randf() < 0.3:
		var opts: Array = []
		var sx := int(signf(c.x))
		var sz := int(signf(c.y))
		if gx + sx >= 0 and gx + sx < Game.N:
			opts.append(Vector2i(sx, 0))
		if gz + sz >= 0 and gz + sz < Game.N:
			opts.append(Vector2i(0, sz))
		if not opts.is_empty():
			var o: Vector2i = opts[randi() % opts.size()]
			gx += o.x
			gz += o.y
			var nc := Vector2(-c.x if o.x != 0 else c.x, -c.y if o.y != 0 else c.y)
			corner = CORNERS.find(nc)
			return
	corner = (corner + dir + 4) % 4


func damage(amount: float, by_player := false) -> void:
	if state == "dead":
		return
	health -= amount
	if by_player and role == "ped":
		Game.add_heat(6.0)
	if health <= 0.0:
		state = "dead"
		dead_t = 0.0
		collision_layer = 0
		if model:
			model.rotation.x = -PI / 2.0
			model.position.y = 0.2
		if by_player and role == "ped":
			Game.add_heat(20.0)
		died.emit(self)
	elif role == "ped":
		state = "flee"
		flee_t = 4.0


func hit_by_vehicle(v: Vehicle, power: float) -> void:
	if state == "dead":
		return
	damage(power * 4.0, v.driver == "player")
	velocity += (global_position - v.global_position).normalized() * 6.0


func _physics_process(delta: float) -> void:
	var pl = Game.player
	if pl == null:
		return
	var d2 := global_position.distance_to(pl.global_position)
	if state != "dead" and d2 > 45.0:
		skip += 1
		if skip % 3 != 0:
			return
		delta *= 3.0
	cd = maxf(0.0, cd - delta)
	if state == "dead":
		dead_t += delta
		return
	var want := Vector3.ZERO
	var spd := speed
	if role == "enemy":
		var pp: Vector3 = pl.global_position
		var to := pp - global_position
		to.y = 0.0
		var dist := to.length()
		if dist < 60.0 and not pl.dead:
			state = "chase"
			var los := dist < 25.0 and _clear_line(pp)
			if dist < 2.0:
				want = Vector3.ZERO
				if cd <= 0.0:
					cd = 1.0
					pl.damage(8.0)
					Sfx.play3d(self, "punch", global_position)
			elif los and dist < 18.0:
				want = Vector3.ZERO
				if cd <= 0.0:
					cd = 1.3
					Sfx.play3d(self, "shot", global_position, -4.0)
					if randf() < 0.35:
						pl.damage(9.0)
			else:
				want = to.normalized()
				spd = speed
			if dist > 0.1:
				rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 8.0 * delta)
		else:
			state = "walk"
	if role == "ped" or state == "walk":
		if state == "flee":
			flee_t -= delta
			var away: Vector3 = global_position - pl.global_position
			away.y = 0.0
			want = away.normalized()
			spd = 4.2
			if flee_t <= 0.0:
				state = "walk"
		else:
			var to := _corner_pos() - global_position
			to.y = 0.0
			if to.length() < 1.2:
				_next_corner()
			else:
				want = to.normalized()
		if want.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(-want.x, -want.z), 8.0 * delta)
	if role == "ped" and state == "walk" and d2 < 14.0 and pl.in_vehicle and pl.vehicle != null and pl.vehicle.vel_h.length() > 9.0:
		state = "flee"
		flee_t = 3.0
	velocity.x = lerpf(velocity.x, want.x * spd, minf(1.0, 10.0 * delta))
	velocity.z = lerpf(velocity.z, want.z * spd, minf(1.0, 10.0 * delta))
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	var sp := Vector2(velocity.x, velocity.z).length()
	anim += delta * sp * 2.2
	var sw := sin(anim) * minf(sp / 3.0, 1.0) * 0.8
	parts.legL.rotation.x = sw
	parts.legR.rotation.x = -sw
	parts.armL.rotation.x = -sw
	if role == "enemy" and state == "chase":
		parts.armR.rotation.x = -1.4
	else:
		parts.armR.rotation.x = sw


func _clear_line(target: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.4, 0), target + Vector3(0, 1.2, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()
