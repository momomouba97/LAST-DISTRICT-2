class_name Gfx
## Procedural materials, textures and mesh helpers (no external art needed).

static var _mats := {}
static var _boxes := {}
static var _win_tex: ImageTexture
static var _win_emit: ImageTexture
static var night_mats: Array = []
static var lamp_mat: StandardMaterial3D
static var light_x: StandardMaterial3D
static var light_z: StandardMaterial3D
static var siren_a: StandardMaterial3D
static var siren_b: StandardMaterial3D
static var road_mat: StandardMaterial3D
static var zebra_mat: StandardMaterial3D
static var headlight_mat: StandardMaterial3D
static var brake_mat: StandardMaterial3D
static var night_factor := 0.0


static func _init_statics() -> void:
	if lamp_mat != null:
		return
	lamp_mat = _emissive(Color(1.0, 0.85, 0.55), 0.0)
	light_x = _emissive(Color(0.1, 1.0, 0.2), 2.0)
	light_z = _emissive(Color(1.0, 0.1, 0.1), 2.0)
	siren_a = _emissive(Color(1.0, 0.1, 0.1), 3.0)
	siren_b = _emissive(Color(0.15, 0.3, 1.0), 0.2)
	headlight_mat = _emissive(Color(1.0, 0.95, 0.8), 0.0)
	brake_mat = _emissive(Color(1.0, 0.05, 0.05), 0.3)
	road_mat = StandardMaterial3D.new()
	road_mat.albedo_texture = _noise_tex(0.20, 0.30, 5)
	road_mat.albedo_color = Color(1, 1, 1)
	road_mat.roughness = 0.9
	road_mat.uv1_triplanar = true
	road_mat.uv1_world_triplanar = true
	road_mat.uv1_scale = Vector3(0.2, 0.2, 0.2)
	zebra_mat = StandardMaterial3D.new()
	zebra_mat.albedo_texture = _zebra_tex()
	zebra_mat.roughness = 0.85
	zebra_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


static func _emissive(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


static func update_lights(phase: int) -> void:
	light_x.albedo_color = Color(0.1, 1.0, 0.2) if phase == 0 else Color(1.0, 0.1, 0.1)
	light_x.emission = light_x.albedo_color
	light_z.albedo_color = Color(0.1, 1.0, 0.2) if phase == 1 else Color(1.0, 0.1, 0.1)
	light_z.emission = light_z.albedo_color


static func set_night(f: float) -> void:
	_init_statics()
	night_factor = f
	for m in night_mats:
		m.emission_energy_multiplier = f * 1.6
	lamp_mat.emission_energy_multiplier = f * 3.0
	headlight_mat.emission_energy_multiplier = f * 2.5 + 0.15


static func set_wet(w: float) -> void:
	_init_statics()
	road_mat.roughness = lerpf(0.9, 0.3, w)
	road_mat.albedo_color = Color(1, 1, 1).lerp(Color(0.55, 0.55, 0.6), w)


static func mat(c: Color, rough := 0.8, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	_init_statics()
	var key := "%s|%s|%s|%s" % [c.to_html(), rough, metal, emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	if c.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


static func building_mat(tint: Color) -> StandardMaterial3D:
	_init_statics()
	var key := "bld|" + tint.to_html()
	if _mats.has(key):
		return _mats[key]
	if _win_tex == null:
		_make_window_textures()
	var m := StandardMaterial3D.new()
	m.albedo_texture = _win_tex
	m.albedo_color = tint
	m.roughness = 0.75
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.0625, 0.0625, 0.0625)
	m.emission_enabled = true
	m.emission_texture = _win_emit
	m.emission_energy_multiplier = night_factor * 1.6
	night_mats.append(m)
	_mats[key] = m
	return m


static func _make_window_textures() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var em := Image.create(128, 128, false, Image.FORMAT_RGB8)
	img.fill(Color(0.92, 0.92, 0.92))
	em.fill(Color(0, 0, 0))
	for cy in range(4):
		for cx in range(4):
			var lit := rng.randf() < 0.55
			for y in range(7, 25):
				for x in range(7, 25):
					var px := cx * 32 + x
					var py := cy * 32 + y
					img.set_pixel(px, py, Color(0.18, 0.26, 0.35))
					if lit:
						em.set_pixel(px, py, Color(1.0, 0.78, 0.45))
	img.generate_mipmaps()
	em.generate_mipmaps()
	_win_tex = ImageTexture.create_from_image(img)
	_win_emit = ImageTexture.create_from_image(em)


static func _noise_tex(lo: float, hi: float, seed_v: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in range(128):
		for x in range(128):
			var v := rng.randf_range(lo, hi)
			img.set_pixel(x, y, Color(v, v, v * 1.02))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _zebra_tex() -> ImageTexture:
	var img := Image.create(64, 8, false, Image.FORMAT_RGB8)
	for x in range(64):
		var white := (x / 4) % 2 == 0
		for y in range(8):
			img.set_pixel(x, y, Color(0.9, 0.9, 0.9) if white else Color(0.24, 0.24, 0.25))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func sidewalk_mat() -> StandardMaterial3D:
	_init_statics()
	if _mats.has("sidewalk"):
		return _mats["sidewalk"]
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.62, 0.61, 0.58))
	for i in range(64):
		img.set_pixel(i, 0, Color(0.45, 0.45, 0.43))
		img.set_pixel(0, i, Color(0.45, 0.45, 0.43))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	m.roughness = 0.9
	_mats["sidewalk"] = m
	return m


# ------------------------------------------------------------ mesh helpers
static func _box_mesh(size: Vector3) -> BoxMesh:
	var key := str(size)
	if _boxes.has(key):
		return _boxes[key]
	var bm := BoxMesh.new()
	bm.size = size
	_boxes[key] = bm
	return bm


static func box(parent: Node, pos: Vector3, size: Vector3, m: Material, body: StaticBody3D = null, vis_end := 0.0) -> MeshInstance3D:
	_init_statics()
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.material_override = m
	mi.position = pos
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
	parent.add_child(mi)
	if body != null:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		body.add_child(cs)
	return mi


static func cyl(parent: Node, pos: Vector3, radius: float, height: float, m: Material, vis_end := 0.0, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
	parent.add_child(mi)
	return mi


static func sphere(parent: Node, pos: Vector3, radius: float, m: Material, scl := Vector3.ONE, vis_end := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	mi.scale = scl
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
	parent.add_child(mi)
	return mi


static func label(parent: Node, text: String, pos: Vector3, size := 0.02, vis_end := 160.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.pixel_size = size
	l.font_size = 96
	l.outline_size = 16
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.visibility_range_end = vis_end
	parent.add_child(l)
	return l


## Simple articulated humanoid. Returns {root, legL, legR, armL, armR, torso, gun}.
static func make_human(shirt: Color, pants: Color, skin: Color, hair: Color) -> Dictionary:
	var root := Node3D.new()
	var torso := Node3D.new()
	root.add_child(torso)
	box(torso, Vector3(0, 1.15, 0), Vector3(0.5, 0.65, 0.28), mat(shirt, 0.85))
	sphere(torso, Vector3(0, 1.62, 0), 0.15, mat(skin, 0.7))
	sphere(torso, Vector3(0, 1.68, 0.0), 0.16, mat(hair, 0.9), Vector3(1, 0.7, 1))
	var legL := Node3D.new()
	legL.position = Vector3(-0.14, 0.8, 0)
	root.add_child(legL)
	box(legL, Vector3(0, -0.4, 0), Vector3(0.2, 0.8, 0.22), mat(pants, 0.9))
	var legR := Node3D.new()
	legR.position = Vector3(0.14, 0.8, 0)
	root.add_child(legR)
	box(legR, Vector3(0, -0.4, 0), Vector3(0.2, 0.8, 0.22), mat(pants, 0.9))
	var armL := Node3D.new()
	armL.position = Vector3(-0.34, 1.42, 0)
	root.add_child(armL)
	box(armL, Vector3(0, -0.3, 0), Vector3(0.14, 0.6, 0.16), mat(shirt, 0.85))
	var armR := Node3D.new()
	armR.position = Vector3(0.34, 1.42, 0)
	root.add_child(armR)
	box(armR, Vector3(0, -0.3, 0), Vector3(0.14, 0.6, 0.16), mat(shirt, 0.85))
	var gun := box(armR, Vector3(0, -0.62, -0.12), Vector3(0.07, 0.12, 0.3), mat(Color(0.08, 0.08, 0.09), 0.4, 0.6))
	gun.visible = false
	return {"root": root, "legL": legL, "legR": legR, "armL": armL, "armR": armR, "torso": torso, "gun": gun}
