extends Node
## Global game state, input hub, settings, save/load and wanted level.

signal wanted_changed
signal money_changed
signal message(text: String)
signal settings_changed

const C := 80.0                      # city cell size (metres)
const N := 10                        # blocks per side -> ~800 m city
const SAVE_PATH := "user://save.json"
const SETTINGS_PATH := "user://settings.json"
const VEHICLE_IDS := ["sedan", "hatchback", "sports", "suv", "pickup", "police", "motorcycle", "offroad"]
const GARAGE_POS := Vector3(100.0, 0.5, 520.0)
const START_POS := Vector3(40.0, 1.0, 520.0)

# h = render height at 100% scale; radius = streamed block radius
const PRESETS := [
	{"name": "Low", "h": 360, "min": 0.6, "radius": 2, "far": 170.0, "shadow": false, "shadow_dist": 0.0, "peds": 6, "cars": 4, "rain": 120, "fog": 0.006},
	{"name": "Balanced", "h": 540, "min": 0.55, "radius": 2, "far": 250.0, "shadow": true, "shadow_dist": 55.0, "peds": 9, "cars": 6, "rain": 220, "fog": 0.0035},
	{"name": "High", "h": 720, "min": 0.6, "radius": 3, "far": 340.0, "shadow": true, "shadow_dist": 100.0, "peds": 12, "cars": 8, "rain": 380, "fog": 0.0025},
]
const WEATHER_NAMES := ["Auto", "Clear", "Cloudy", "Light rain", "Heavy rain"]

var settings := {
	"preset": 1, "auto_res": true, "res_scale": 1.0, "master": 1.0, "music": 0.5, "sfx": 0.9,
	"btn_scale": 1.0, "btn_opacity": 0.75, "look_sens": 1.0, "weather": 0,
	"diag": false, "perf_mode": false, "fps_cap": 30,
}

# --- persistent progress ---
var money: int = 500
var health: float = 100.0
var player_pos: Vector3 = START_POS
var mission_done: Array = []
var side_done: Array = []
var unlocked: Array = ["sedan", "hatchback"]
var collected: Array = []
var time_of_day: float = 9.0

# --- runtime ---
var in_game := false
var cutscene := false
var wanted_heat := 0.0
var wanted := 0
var ammo_mag := 12
var ammo_reserve := 48
var world: Node = null
var hud: Node = null
var player: Node = null
var phase := 0                       # 0: x-axis traffic green, 1: z-axis green
var siren_on := false
var sfx_player: AudioStreamPlayer
var last_save_error := ""
var render_info := ""

var _touch_held := {}
var _key_held := {}
var _pressed := {}
var touch_move := Vector2.ZERO
var touch_look := Vector2.ZERO
var _phase_t := 0.0
var _siren_t := 0.0
var _autosave_t := 0.0

const KEYS := {
	KEY_SHIFT: "sprint", KEY_SPACE: "jump", KEY_E: "interact", KEY_ENTER: "shoot", KEY_F: "shoot",
	KEY_Q: "melee", KEY_R: "reload", KEY_C: "crouch", KEY_TAB: "aim", KEY_ESCAPE: "pause", KEY_H: "horn",
	KEY_W: "gas", KEY_UP: "gas", KEY_S: "brake", KEY_DOWN: "brake",
	KEY_A: "left", KEY_LEFT: "left", KEY_D: "right", KEY_RIGHT: "right",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	sfx_player = AudioStreamPlayer.new()
	sfx_player.bus = "SFX"
	add_child(sfx_player)
	load_settings()
	apply_audio()


# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if KEYS.has(key):
			var n: String = KEYS[key]
			_key_held[n] = event.pressed
			if event.pressed:
				_pressed[n] = true


func touch_press(n: String) -> void:
	_touch_held[n] = true
	_pressed[n] = true


func touch_release(n: String) -> void:
	_touch_held[n] = false


func is_down(n: String) -> bool:
	return _touch_held.get(n, false) or _key_held.get(n, false)


func consume(n: String) -> bool:
	if _pressed.get(n, false):
		_pressed[n] = false
		return true
	return false


func clear_input() -> void:
	_touch_held.clear()
	_key_held.clear()
	_pressed.clear()
	touch_move = Vector2.ZERO
	touch_look = Vector2.ZERO


## y < 0 means forward / up.
func get_move() -> Vector2:
	var v := touch_move
	if is_down("gas"):
		v.y -= 1.0
	if is_down("brake"):
		v.y += 1.0
	if is_down("left"):
		v.x -= 1.0
	if is_down("right"):
		v.x += 1.0
	return v.limit_length(1.0)


func take_look() -> Vector2:
	var l := touch_look
	touch_look = Vector2.ZERO
	return l


# ---------------------------------------------------------------- frame
func _process(delta: float) -> void:
	if not in_game or get_tree().paused:
		return
	_phase_t += delta
	if _phase_t > 14.0:
		_phase_t = 0.0
		phase = 1 - phase
	_siren_t += delta
	var a := fmod(_siren_t, 0.5) < 0.25
	Gfx.siren_a.emission_energy_multiplier = 3.0 if a else 0.2
	Gfx.siren_b.emission_energy_multiplier = 0.2 if a else 3.0
	Gfx.update_lights(phase)
	_autosave_t += delta
	if _autosave_t > 30.0:
		_autosave_t = 0.0
		save_game()


func axis_green(axis: int) -> bool:
	return axis == phase


func node_pos(i: int, j: int) -> Vector3:
	return Vector3((i + 0.5) * C, 0.0, (j + 0.5) * C)


func say(text: String) -> void:
	message.emit(text)


func add_money(v: int) -> void:
	money = maxi(0, money + v)
	money_changed.emit()


# ---------------------------------------------------------------- wanted
func add_heat(h: float) -> void:
	wanted_heat = clampf(wanted_heat + h, 0.0, 100.0)
	_update_wanted()


func clear_wanted() -> void:
	wanted_heat = 0.0
	_update_wanted()


func set_wanted_level(l: int) -> void:
	wanted_heat = maxf(wanted_heat, [0.0, 10.0, 30.0, 50.0, 70.0, 90.0][clampi(l, 0, 5)])
	_update_wanted()


func _update_wanted() -> void:
	var lvl := 0
	for t in [10.0, 30.0, 50.0, 70.0, 90.0]:
		if wanted_heat >= t:
			lvl += 1
	if lvl != wanted:
		wanted = lvl
		wanted_changed.emit()


# ---------------------------------------------------------------- graphics presets
func preset() -> Dictionary:
	if settings.perf_mode:
		return PRESETS[0]
	return PRESETS[clampi(int(settings.preset), 0, 2)]


func apply_audio() -> void:
	var map := {"Master": settings.master, "Music": settings.music, "SFX": settings.sfx}
	for b in map:
		var idx := AudioServer.get_bus_index(b)
		if idx >= 0:
			var v: float = clampf(float(map[b]), 0.0, 1.0)
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
			AudioServer.set_bus_mute(idx, v <= 0.001)
	Engine.max_fps = int(settings.fps_cap)


func settings_apply_and_save() -> void:
	apply_audio()
	save_settings()
	settings_changed.emit()


func click() -> void:
	var s := Sfx.get_stream("click")
	if s and sfx_player:
		sfx_player.stream = s
		sfx_player.play()


# ---------------------------------------------------------------- settings io
func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var txt := FileAccess.get_file_as_string(SETTINGS_PATH)
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return
	for k in settings.keys():
		if data.has(k) and typeof(data[k]) == typeof(settings[k]):
			settings[k] = data[k]
		elif data.has(k) and typeof(settings[k]) == TYPE_FLOAT and typeof(data[k]) == TYPE_INT:
			settings[k] = float(data[k])
	settings.preset = clampi(int(settings.preset), 0, 2)
	settings.fps_cap = 60 if int(settings.fps_cap) >= 60 else 30
	settings.weather = clampi(int(settings.weather), 0, 4)


# ---------------------------------------------------------------- progress save
func new_game() -> void:
	money = 500
	health = 100.0
	player_pos = START_POS
	mission_done = []
	side_done = []
	unlocked = ["sedan", "hatchback"]
	collected = []
	time_of_day = 9.0
	wanted_heat = 0.0
	wanted = 0
	ammo_mag = 12
	ammo_reserve = 48


func has_valid_save() -> bool:
	return _read_save().size() > 0


func save_game() -> void:
	if not in_game:
		return
	if player and is_instance_valid(player):
		player_pos = player.global_position
		health = player.health
	if world and is_instance_valid(world):
		time_of_day = world.tod
	var body := JSON.stringify({
		"v": 1, "money": money, "health": health,
		"pos": [player_pos.x, player_pos.y, player_pos.z],
		"missions": mission_done, "side": side_done, "unlocked": unlocked,
		"collected": collected, "tod": time_of_day,
	})
	var outer := JSON.stringify({"sum": body.hash(), "body": body})
	var f := FileAccess.open(SAVE_PATH + ".tmp", FileAccess.WRITE)
	if f == null:
		last_save_error = "cannot write save"
		return
	f.store_string(outer)
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH + ".tmp"), ProjectSettings.globalize_path(SAVE_PATH))


## Returns validated dictionary or {} when missing/corrupt.
func _read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var outer: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(outer) != TYPE_DICTIONARY or not outer.has("body") or not outer.has("sum"):
		return _corrupt()
	var body: Variant = outer["body"]
	if typeof(body) != TYPE_STRING or int(outer["sum"]) != body.hash():
		return _corrupt()
	var d: Variant = JSON.parse_string(body)
	if typeof(d) != TYPE_DICTIONARY:
		return _corrupt()
	for k in ["money", "health", "pos", "missions", "side", "unlocked", "collected", "tod"]:
		if not d.has(k):
			return _corrupt()
	if typeof(d.pos) != TYPE_ARRAY or d.pos.size() != 3:
		return _corrupt()
	for p in d.pos:
		if typeof(p) != TYPE_FLOAT or is_nan(p) or absf(p) > 5000.0:
			return _corrupt()
	for k in ["missions", "side", "unlocked", "collected"]:
		if typeof(d[k]) != TYPE_ARRAY:
			return _corrupt()
	for u in d.unlocked:
		if not VEHICLE_IDS.has(u):
			return _corrupt()
	if typeof(d.money) != TYPE_FLOAT or d.money < 0 or d.money > 99999999:
		return _corrupt()
	if typeof(d.health) != TYPE_FLOAT or d.health <= 0 or d.health > 100:
		return _corrupt()
	return d


func _corrupt() -> Dictionary:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(SAVE_PATH + ".corrupt"))
	last_save_error = "Save file was corrupted and has been set aside."
	return {}


func load_game() -> bool:
	var d := _read_save()
	if d.is_empty():
		return false
	new_game()
	money = int(d.money)
	health = float(d.health)
	player_pos = Vector3(d.pos[0], d.pos[1], d.pos[2])
	mission_done = d.missions.map(func(x): return int(x))
	side_done = d.side.map(func(x): return int(x))
	unlocked = d.unlocked.duplicate()
	for v in ["sedan", "hatchback"]:
		if not unlocked.has(v):
			unlocked.append(v)
	collected = d.collected.map(func(x): return str(x))
	time_of_day = clampf(float(d.tod), 0.0, 24.0)
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if in_game:
			save_game()
			if what == NOTIFICATION_APPLICATION_PAUSED and hud and hud.has_method("open_pause"):
				hud.open_pause()
