class_name City
## Deterministic procedural generator for one city block (64 m square, 80 m grid).
## Blocks are created on demand by the World streamer and freed when far away.

const SPECIALS := {
	Vector2i(5, 2): "police", Vector2i(2, 2): "hospital", Vector2i(1, 7): "safehouse",
	Vector2i(0, 4): "gas", Vector2i(1, 5): "workshop", Vector2i(2, 4): "market", Vector2i(1, 3): "dealer",
}
const WALLS := [Color(0.95, 0.9, 0.8), Color(0.9, 0.77, 0.6), Color(0.93, 0.68, 0.52), Color(0.84, 0.86, 0.88), Color(0.78, 0.84, 0.9), Color(0.97, 0.95, 0.88)]
const GLASS := [Color(0.55, 0.72, 0.85), Color(0.6, 0.75, 0.8), Color(0.45, 0.6, 0.75), Color(0.7, 0.8, 0.9)]
const CONTAINER := [Color(0.75, 0.2, 0.15), Color(0.15, 0.4, 0.7), Color(0.85, 0.6, 0.1), Color(0.2, 0.5, 0.3), Color(0.6, 0.6, 0.62)]


static func district_of(gx: int, gz: int) -> String:
	if gz == Game.N - 1:
		return "coast"
	if gx >= 7 and gz <= 3:
		return "industrial"
	if gx >= 3 and gx <= 6 and gz >= 3 and gz <= 6:
		return "downtown"
	if gx <= 2 and gz >= 3 and gz <= 6:
		return "commercial"
	return "residential"


static func build_block(gx: int, gz: int, with_collectible: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "B%d_%d" % [gx, gz]
	root.position = Vector3(gx * Game.C, 0.0, gz * Game.C)
	var rng := RandomNumberGenerator.new()
	rng.seed = gx * 7919 + gz * 104729 + 17
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var dist := district_of(gx, gz)
	var special: String = SPECIALS.get(Vector2i(gx, gz), "")
	var beach := dist == "coast" and gx <= 5
	var marina := dist == "coast" and gx >= 6
	var slab: Material = Gfx.sidewalk_mat()
	if beach:
		slab = Gfx.mat(Color(0.86, 0.79, 0.6), 1.0)
	elif marina:
		slab = Gfx.mat(Color(0.5, 0.5, 0.52), 0.9)
	Gfx.box(root, Vector3(0, 0.04, 0), Vector3(64, 0.08, 64), slab)
	# road markings and crosswalks (shared meshes/materials)
	var yellow := Gfx.mat(Color(0.9, 0.75, 0.1), 0.8)
	Gfx.box(root, Vector3(40, 0.03, 0), Vector3(0.3, 0.02, 64), yellow, null, 130.0)
	Gfx.box(root, Vector3(0, 0.03, 40), Vector3(64, 0.02, 0.3), yellow, null, 130.0)
	_plane(root, Vector3(40, 0.045, 30), Vector2(16, 3), Gfx.zebra_mat, 0.0)
	_plane(root, Vector3(30, 0.045, 40), Vector2(16, 3), Gfx.zebra_mat, PI / 2.0)
	_street_props(root, rng, beach)

	if special != "":
		_special(root, body, rng, special)
	else:
		match dist:
			"residential": _residential(root, body, rng)
			"downtown": _downtown(root, body, rng)
			"commercial": _commercial(root, body, rng)
			"industrial": _industrial(root, body, rng)
			"coast":
				if beach:
					_beach(root, body, rng)
				else:
					_marina(root, body, rng, gx)
	if with_collectible:
		var cp := _ring_point(rng) + Vector3(0, 1.0, 0)
		var m := Gfx.mat(Color(1.0, 0.85, 0.1), 0.3, 0.5, 2.0)
		var s1 := Gfx.sphere(root, cp, 0.5, m, Vector3.ONE, 140.0)
		var s2 := Gfx.cyl(root, cp + Vector3(0, 4, 0), 0.08, 8.0, m, 140.0)
		root.set_meta("col_nodes", [s1, s2])
		root.set_meta("col_pos", root.position + cp)
	return root


static func _plane(parent: Node, pos: Vector3, size: Vector2, m: Material, rot_y: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = m
	mi.position = pos
	mi.rotation.y = rot_y
	mi.visibility_range_end = 130.0
	parent.add_child(mi)


static func _ring_point(rng: RandomNumberGenerator) -> Vector3:
	var t := rng.randf_range(-24.0, 24.0)
	match rng.randi() % 4:
		0: return Vector3(t, 0, -30.5)
		1: return Vector3(t, 0, 30.5)
		2: return Vector3(-30.5, 0, t)
	return Vector3(30.5, 0, t)


static func _street_props(root: Node3D, rng: RandomNumberGenerator, beach: bool) -> void:
	var dark := Gfx.mat(Color(0.12, 0.13, 0.15), 0.6, 0.5)
	for p in [Vector2(-31, 31), Vector2(31, -31)]:
		Gfx.cyl(root, Vector3(p.x, 3.0, p.y), 0.08, 6.0, dark, 110.0)
		Gfx.box(root, Vector3(p.x, 6.1, p.y), Vector3(0.7, 0.15, 0.3), Gfx.lamp_mat, null, 110.0)
		Gfx.box(root, Vector3(p.x, 4.3, p.y), Vector3(0.9, 0.35, 0.05), Gfx.mat(Color(0.1, 0.5, 0.3), 0.6), null, 80.0)
	# traffic light post at the +x/+z corner
	Gfx.cyl(root, Vector3(31, 2.5, 31), 0.08, 5.0, dark, 110.0)
	Gfx.box(root, Vector3(31.3, 4.7, 31), Vector3(0.3, 0.8, 0.3), Gfx.light_x, null, 110.0)
	Gfx.box(root, Vector3(31, 4.7, 31.3), Vector3(0.3, 0.8, 0.3), Gfx.light_z, null, 110.0)
	var trunk := Gfx.mat(Color(0.4, 0.28, 0.18), 1.0)
	var leaf := Gfx.mat(Color(0.14, 0.4, 0.15), 0.9)
	var frond := Gfx.mat(Color(0.2, 0.5, 0.18), 0.9)
	var count := 6 if beach else 3
	for i in range(count):
		var p := _ring_point(rng)
		if rng.randf() < 0.6:
			var h := rng.randf_range(5.5, 8.0)
			Gfx.cyl(root, p + Vector3(0, h * 0.5, 0), 0.22, h, trunk, 120.0)
			Gfx.sphere(root, p + Vector3(0, h, 0), 1.9, frond, Vector3(1.0, 0.35, 1.0), 120.0)
			Gfx.sphere(root, p + Vector3(0.3, h + 0.5, 0), 1.2, frond, Vector3(1.0, 0.4, 1.0), 120.0)
		else:
			Gfx.cyl(root, p + Vector3(0, 1.4, 0), 0.25, 2.8, trunk, 100.0)
			Gfx.sphere(root, p + Vector3(0, 3.8, 0), 1.8, leaf, Vector3.ONE, 100.0)
	for i in range(2):
		var p := _ring_point(rng)
		Gfx.box(root, p + Vector3(0, 0.3, 0), Vector3(1.6, 0.1, 0.5), trunk, null, 70.0)
		Gfx.box(root, p + Vector3(0, 0.55, 0.2), Vector3(1.6, 0.4, 0.08), trunk, null, 70.0)


static func _lot(root: Node3D, body: StaticBody3D, rng: RandomNumberGenerator, c: Vector3, size: Vector3, tint: Color, roof: Color, shop := false) -> void:
	var m := Gfx.building_mat(tint)
	Gfx.box(root, Vector3(c.x, 0.08 + size.y * 0.5, c.z), size, m, body)
	Gfx.box(root, Vector3(c.x, 0.08 + size.y + 0.2, c.z), Vector3(size.x + 0.6, 0.4, size.z + 0.6), Gfx.mat(roof, 0.9), null, 140.0)
	if rng.randf() < 0.6:
		Gfx.box(root, Vector3(c.x + rng.randf_range(-size.x * 0.3, size.x * 0.3), 0.08 + size.y + 1.0, c.z + rng.randf_range(-size.z * 0.3, size.z * 0.3)), Vector3(2.0, 1.2, 1.6), Gfx.mat(Color(0.6, 0.6, 0.62), 0.5, 0.4), null, 100.0)
	if shop:
		var aw := Gfx.mat(Color.from_hsv(rng.randf(), 0.6, 0.8), 0.9)
		Gfx.box(root, Vector3(c.x, 3.4, c.z + size.z * 0.5 + 0.9), Vector3(size.x * 0.7, 0.2, 1.8), aw, null, 100.0)


static func _residential(root: Node3D, body: StaticBody3D, rng: RandomNumberGenerator) -> void:
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var cx: float = sx * 16.0 + rng.randf_range(-1.5, 1.5)
			var cz: float = sz * 16.0 + rng.randf_range(-1.5, 1.5)
			var tint: Color = WALLS[rng.randi() % WALLS.size()]
			if rng.randf() < 0.45:
				_lot(root, body, rng, Vector3(cx, 0, cz), Vector3(rng.randf_range(13, 19), rng.randf_range(5.5, 7.5), rng.randf_range(12, 18)), tint, Color(0.7, 0.32, 0.2))
			else:
				_lot(root, body, rng, Vector3(cx, 0, cz), Vector3(rng.randf_range(19, 24), rng.randf_range(12, 19), rng.randf_range(17, 22)), tint, Color(0.5, 0.5, 0.52))


static func _downtown(root: Node3D, body: StaticBody3D, rng: RandomNumberGenerator) -> void:
	if rng.randf() < 0.35:
		var h := rng.randf_range(45, 70)
		_lot(root, body, rng, Vector3(0, 0, 0), Vector3(36, h, 36), GLASS[rng.randi() % GLASS.size()], Color(0.35, 0.36, 0.4))
		_lot(root, body, rng, Vector3(0, 0, 0), Vector3(50, 6, 50), WALLS[rng.randi() % WALLS.size()], Color(0.4, 0.4, 0.42), true)
		return
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var c := Vector3(sx * 16.0, 0, sz * 16.0)
			var tint: Color = GLASS[rng.randi() % GLASS.size()] if rng.randf() < 0.6 else WALLS[rng.randi() % WALLS.size()]
			_lot(root, body, rng, c, Vector3(24, rng.randf_range(20, 52), 24), tint, Color(0.35, 0.36, 0.4), true)


static func _commercial(root: Node3D, body: StaticBody3D, rng: RandomNumberGenerator) -> void:
	for sz in [-1, 1]:
		var tint: Color = WALLS[rng.randi() % WALLS.size()]
		_lot(root, body, rng, Vector3(0, 0, sz * 16.0), Vector3(rng.randf_range(40, 52), rng.randf_range(8, 12), 24), tint, Color(0.5, 0.5, 0.52), true)


static func _industrial(root: Node3D, body: StaticBody3D, rng: RandomNumberGenerator) -> void:
	var tint := Color(0.7, 0.74, 0.78)
	_lot(root, body, rng, Vector3(-8, 0, -14), Vector3(40, rng.randf_range(9, 12), 26), tint, Color(0.45, 0.47, 0.5))
	if rng.randf() < 0.5:
		Gfx.cyl(root, Vector3(14, 12, -14), 2.4, 24.0, Gfx.mat(Color(0.5, 0.45, 0.42), 0.9), 150.0)
	for i in range(rng.randi_range(4, 7)):
		var p := Vector3(rng.randf_range(-26, 26), 1.3, rng.randf_range(10, 26))
		Gfx.box(root, p, Vector3(6, 2.6, 2.4), Gfx.mat(CONTAINER[rng.randi() % CONTAINER.size()], 0.6, 0.3), body)
		if rng.randf() < 0.4:
			Gfx.box(root, p + Vector3(0, 2.6, 0), Vector3(6, 2.6, 2.4), Gfx.mat(CONTAINER[rng.randi() % CONTAINER.size()], 0.6, 0.3), body)


static func _beach(root: Node3D, body: StaticBody3D, rng: RandomNumberGenerator) -> void:
	for i in range(2):
		var tint := Color.from_hsv(rng.randf_range(0.0, 0.15), 0.35, 0.95)
		_lot(root, body, rng, Vector3(-16 + i * 32, 0, -18), Vector3(12, 4.5, 10), tint, Color(0.6, 0.4, 0.3), true)
	var pole := Gfx.mat(Color(0.9, 0.9, 0.9), 0.8)
	for i in range(6):
		var p := Vector3(rng.randf_range(-24, 24), 0, rng.randf_range(-4, 22))
		Gfx.cyl(root, p + Vector3(0, 1.2, 0), 0.04, 2.4, pole, 90.0)
		Gfx.sphere(root, p + Vector3(0, 2.4, 0), 1.3, Gfx.mat(Color.from_hsv(rng.randf(), 0.7, 0.9), 0.9), Vector3(1, 0.3, 1), 90.0)


static func _marina(root: Node3D, body: StaticBody3D, rng: RandomNumberGenerator, gx: int) -> void:
	var wood := Gfx.mat(Color(0.45, 0.32, 0.2), 0.95)
	var white := Gfx.mat(Color(0.95, 0.95, 0.97), 0.3, 0.2)
	_lot(root, body, rng, Vector3(0, 0, -18), Vector3(34, 7, 16), Color(0.75, 0.78, 0.8), Color(0.4, 0.42, 0.45))
	for i in range(3):
		var x := -20.0 + i * 20.0
		Gfx.box(root, Vector3(x, 0.15, 14), Vector3(2.2, 0.3, 28), wood, null, 130.0)
		if rng.randf() < 0.8:
			Gfx.box(root, Vector3(x + 3.2, 0.5, 14 + rng.randf_range(-8, 8)), Vector3(2.4, 0.9, 7), white, null, 130.0)
			Gfx.box(root, Vector3(x + 3.2, 1.3, 14.5), Vector3(1.8, 0.8, 3), Gfx.mat(Color(0.15, 0.25, 0.4), 0.2, 0.3), null, 130.0)
	if gx == 9:
		var orange := Gfx.mat(Color(0.9, 0.45, 0.1), 0.6, 0.3)
		Gfx.box(root, Vector3(24, 10, -4), Vector3(1.2, 20, 1.2), orange, body)
		Gfx.box(root, Vector3(14, 19.5, -4), Vector3(22, 1.0, 1.0), orange, null, 150.0)


static func _special(root: Node3D, body: StaticBody3D, rng: RandomNumberGenerator, kind: String) -> void:
	match kind:
		"police":
			_lot(root, body, rng, Vector3(0, 0, -6), Vector3(38, 14, 26), Color(0.7, 0.78, 0.9), Color(0.2, 0.25, 0.4))
			Gfx.box(root, Vector3(0, 8, 7.2), Vector3(30, 1.0, 0.3), Gfx.mat(Color(0.1, 0.2, 0.7), 0.5, 0.0, 0.6))
			Gfx.label(root, "POLICE", Vector3(0, 19, 7))
		"hospital":
			_lot(root, body, rng, Vector3(0, 0, -6), Vector3(42, 20, 28), Color(0.96, 0.96, 0.98), Color(0.7, 0.7, 0.72))
			var red := Gfx.mat(Color(0.85, 0.1, 0.1), 0.5, 0.0, 0.5)
			Gfx.box(root, Vector3(0, 15, 8.2), Vector3(8, 2.0, 0.3), red)
			Gfx.box(root, Vector3(0, 15, 8.2), Vector3(2.0, 8, 0.3), red)
			Gfx.label(root, "HOSPITAL", Vector3(0, 26, 8))
		"safehouse":
			_lot(root, body, rng, Vector3(-12, 0, -10), Vector3(20, 8, 16), Color(0.92, 0.62, 0.4), Color(0.6, 0.3, 0.2))
			_lot(root, body, rng, Vector3(14, 0, -10), Vector3(14, 5, 14), Color(0.65, 0.68, 0.7), Color(0.4, 0.4, 0.42))
			Gfx.label(root, "SAFEHOUSE", Vector3(-12, 13, -10))
			Gfx.label(root, "GARAGE", Vector3(14, 10, -10))
			Gfx.box(root, Vector3(14, 2.4, -2.8), Vector3(8, 4.6, 0.3), Gfx.mat(Color(0.3, 0.35, 0.4), 0.5, 0.5))
		"gas":
			var steel := Gfx.mat(Color(0.8, 0.82, 0.85), 0.4, 0.5)
			Gfx.box(root, Vector3(0, 5, 8), Vector3(22, 0.6, 14), Gfx.mat(Color(0.9, 0.15, 0.15), 0.5), null, 140.0)
			for sx in [-1, 1]:
				for sz in [-1, 1]:
					Gfx.box(root, Vector3(sx * 9, 2.5, 8 + sz * 5), Vector3(0.5, 5, 0.5), steel, body)
			for i in range(3):
				Gfx.box(root, Vector3(-6 + i * 6, 0.9, 8), Vector3(0.8, 1.8, 1.2), Gfx.mat(Color(0.9, 0.9, 0.2), 0.5), body)
			_lot(root, body, rng, Vector3(0, 0, -16), Vector3(16, 4.5, 10), Color(0.95, 0.9, 0.8), Color(0.8, 0.15, 0.15), true)
			Gfx.label(root, "GAS STATION", Vector3(0, 9, 8))
		"workshop":
			_lot(root, body, rng, Vector3(0, 0, -8), Vector3(26, 7, 20), Color(0.6, 0.62, 0.65), Color(0.35, 0.35, 0.38))
			Gfx.box(root, Vector3(0, 2.2, 2.2), Vector3(7, 4.2, 0.3), Gfx.mat(Color(0.9, 0.5, 0.1), 0.6))
			Gfx.label(root, "REPAIR WORKSHOP", Vector3(0, 12, 2))
		"market":
			_lot(root, body, rng, Vector3(0, 0, -10), Vector3(42, 8, 30), Color(0.95, 0.95, 0.9), Color(0.3, 0.5, 0.3), true)
			Gfx.label(root, "SUPERMARKET", Vector3(0, 13, 6))
		"dealer":
			_lot(root, body, rng, Vector3(0, 0, -12), Vector3(30, 6, 18), Color(0.7, 0.85, 0.95), Color(0.3, 0.3, 0.35))
			for i in range(3):
				var cm := Gfx.mat(Color.from_hsv(rng.randf(), 0.8, 0.8), 0.25, 0.5)
				Gfx.box(root, Vector3(-9 + i * 9, 0.7, 12), Vector3(1.8, 0.8, 4.2), cm, body)
				Gfx.box(root, Vector3(-9 + i * 9, 1.3, 12), Vector3(1.5, 0.5, 2.0), Gfx.mat(Color(0.1, 0.15, 0.2), 0.1, 0.3))
			Gfx.label(root, "CAR DEALERSHIP", Vector3(0, 11, 0))
