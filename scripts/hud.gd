extends CanvasLayer
class_name HUD

signal quit_to_menu
signal _advance

const BUTTONS := {
	# name: [anchor, dx, dy, radius, label, mode]   mode: foot / veh / both
	"shoot": ["r", 110, 125, 58, "FIRE", "foot"],
	"jump": ["r", 255, 80, 42, "JUMP", "foot"],
	"melee": ["r", 270, 205, 38, "PUNCH", "foot"],
	"aim": ["r", 145, 255, 38, "AIM", "foot"],
	"reload": ["r", 395, 200, 34, "RELOAD", "foot"],
	"sprint": ["l", 95, 330, 40, "SPRINT", "foot"],
	"crouch": ["l", 225, 330, 34, "CROUCH", "foot"],
	"interact": ["r", 395, 95, 40, "USE", "both"],
	"gas": ["r", 120, 130, 62, "GAS", "veh"],
	"brake": ["r", 270, 100, 52, "BRAKE", "veh"],
	"handbrake": ["r", 150, 270, 42, "HAND", "veh"],
	"horn": ["r", 400, 215, 34, "HORN", "veh"],
	"left": ["l", 110, 120, 58, "<", "veh"],
	"right": ["l", 280, 120, 58, ">", "veh"],
	"pause": ["tr", 50, 50, 30, "II", "both"],
}

var touch: Control
var minimap: Control
var health_fill: ColorRect
var money_lbl: Label
var speed_lbl: Label
var ammo_lbl: Label
var obj_lbl: Label
var toast_lbl: Label
var diag_lbl: Label
var arrest_lbl: Label
var stars: Control
var bar_top: ColorRect
var bar_bot: ColorRect
var dialog_lbl: Label
var dialog_hint: Label
var result_panel: PanelContainer
var result_title: Label
var result_sub: Label
var result_btns: HBoxContainer
var pause_panel: PanelContainer
var settings_panel: SettingsPanel
var cutscene_active := false
var modal := false
var fingers := {}
var joy_idx := -1
var joy_origin := Vector2.ZERO
var joy_pos := Vector2.ZERO
var look_idx := -1
var toast_t := 0.0
var _diag_t := 0.0
var _map_t := 0.0
var _flash := 0.0
var _last_health := 100.0
var _retry_cb := Callable()


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.make()
	add_child(root)
	touch = TouchLayer.new()
	touch.hud = self
	touch.set_anchors_preset(Control.PRESET_FULL_RECT)
	touch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(touch)
	minimap = Minimap.new()
	minimap.position = Vector2(16, 16)
	minimap.size = Vector2(176, 176)
	minimap.custom_minimum_size = Vector2(176, 176)
	minimap.clip_contents = true
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(minimap)
	# health + money + wanted
	var hb := ColorRect.new()
	hb.color = Color(0, 0, 0, 0.55)
	hb.position = Vector2(206, 20)
	hb.size = Vector2(240, 22)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hb)
	health_fill = ColorRect.new()
	health_fill.color = Color(0.2, 0.8, 0.35)
	health_fill.position = Vector2(2, 2)
	health_fill.size = Vector2(236, 18)
	health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(health_fill)
	money_lbl = _label(root, Vector2(206, 46), 30)
	stars = Stars.new()
	stars.position = Vector2(206, 90)
	stars.size = Vector2(240, 36)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stars)
	arrest_lbl = _label(root, Vector2(206, 128), 22)
	obj_lbl = _label(root, Vector2(470, 16), 26)
	obj_lbl.custom_minimum_size = Vector2(520, 0)
	obj_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_lbl = _label(root, Vector2(470, 100), 30)
	toast_lbl.custom_minimum_size = Vector2(520, 0)
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	speed_lbl = _label(root, Vector2(0, 0), 40)
	ammo_lbl = _label(root, Vector2(0, 0), 28)
	diag_lbl = _label(root, Vector2(0, 0), 18)
	diag_lbl.add_theme_color_override("font_color", Color(0.5, 1, 0.6))
	# cutscene bars
	bar_top = ColorRect.new()
	bar_top.color = Color.BLACK
	bar_top.visible = false
	bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar_top)
	bar_bot = ColorRect.new()
	bar_bot.color = Color.BLACK
	bar_bot.visible = false
	bar_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar_bot)
	dialog_lbl = Label.new()
	dialog_lbl.add_theme_font_size_override("font_size", 30)
	dialog_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog_lbl.visible = false
	bar_bot.add_child(dialog_lbl)
	dialog_hint = Label.new()
	dialog_hint.text = "Tap to continue"
	dialog_hint.add_theme_font_size_override("font_size", 20)
	dialog_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	bar_bot.add_child(dialog_hint)
	# result panel
	result_panel = PanelContainer.new()
	result_panel.visible = false
	root.add_child(result_panel)
	var rv := VBoxContainer.new()
	result_panel.add_child(rv)
	result_title = Label.new()
	result_title.add_theme_font_size_override("font_size", 48)
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(result_title)
	result_sub = Label.new()
	result_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(result_sub)
	result_btns = HBoxContainer.new()
	result_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	rv.add_child(result_btns)
	# pause panel
	pause_panel = PanelContainer.new()
	pause_panel.visible = false
	root.add_child(pause_panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 12)
	pause_panel.add_child(pv)
	var pt := Label.new()
	pt.text = "PAUSED"
	pt.add_theme_font_size_override("font_size", 44)
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(pt)
	pv.add_child(UITheme.button("Resume", close_pause))
	pv.add_child(UITheme.button("Settings", _open_settings))
	pv.add_child(UITheme.button("Save game", func():
		Game.save_game()
		Game.say("Game saved")))
	pv.add_child(UITheme.button("Main menu", func():
		close_pause()
		quit_to_menu.emit()))
	root.resized.connect(_layout)
	Game.message.connect(_on_message)
	Game.money_changed.connect(_refresh_money)
	_refresh_money()
	_layout()


func _label(parent: Control, pos: Vector2, size_px: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size_px)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func screen() -> Vector2:
	return get_viewport().get_visible_rect().size


func _layout() -> void:
	var s := screen()
	obj_lbl.position.x = s.x * 0.5 - 150.0
	obj_lbl.custom_minimum_size.x = 420
	toast_lbl.position = Vector2(s.x * 0.5 - 260.0, 110)
	speed_lbl.position = Vector2(s.x * 0.5 - 100.0, s.y - 90.0)
	ammo_lbl.position = Vector2(s.x - 310.0, s.y - 400.0)
	diag_lbl.position = Vector2(s.x - 300.0, 90.0)
	bar_top.position = Vector2.ZERO
	bar_top.size = Vector2(s.x, 70)
	bar_bot.position = Vector2(0, s.y - 150.0)
	bar_bot.size = Vector2(s.x, 150)
	dialog_lbl.position = Vector2(80, 18)
	dialog_lbl.custom_minimum_size = Vector2(s.x - 160.0, 0)
	dialog_hint.position = Vector2(s.x - 250.0, 112)
	for p in [pause_panel, result_panel]:
		p.position = Vector2(s.x * 0.5 - 220.0, s.y * 0.5 - 200.0)
		p.custom_minimum_size = Vector2(440, 0)
	result_panel.position.y = s.y * 0.5 - 160.0
	if settings_panel:
		pass


func _refresh_money() -> void:
	money_lbl.text = "$ %d" % Game.money


func _on_message(t: String) -> void:
	toast_lbl.text = t
	toast_t = 2.6


func set_objective(text: String, t_left: float) -> void:
	if text == "":
		obj_lbl.text = ""
		return
	obj_lbl.text = text if t_left < 0.0 else "%s  [%d s]" % [text, int(ceil(t_left))]


# ------------------------------------------------------------- cutscene / results
func run_cutscene(lines: Array) -> void:
	cutscene_active = true
	Game.cutscene = true
	Game.clear_input()
	fingers.clear()
	bar_top.visible = true
	bar_bot.visible = true
	dialog_lbl.visible = true
	for l in lines:
		dialog_lbl.text = str(l)
		await _advance
	bar_top.visible = false
	bar_bot.visible = false
	dialog_lbl.visible = false
	cutscene_active = false
	Game.cutscene = false


func show_result(ok: bool, title: String, sub: String, retry: Callable) -> void:
	for c in result_btns.get_children():
		c.queue_free()
	result_title.text = ("MISSION PASSED" if ok else "MISSION FAILED")
	result_title.add_theme_color_override("font_color", Color(0.4, 1, 0.5) if ok else Color(1, 0.35, 0.3))
	result_sub.text = "%s\n%s" % [title, sub]
	result_panel.visible = true
	if ok:
		await get_tree().create_timer(3.5).timeout
		result_panel.visible = false
		return
	modal = true
	_retry_cb = retry
	result_btns.add_child(UITheme.button("Retry", func():
		result_panel.visible = false
		modal = false
		_retry_cb.call(), 180.0))
	result_btns.add_child(UITheme.button("Close", func():
		result_panel.visible = false
		modal = false, 180.0))


# ------------------------------------------------------------- pause
func open_pause() -> void:
	if get_tree().paused or not Game.in_game:
		return
	get_tree().paused = true
	Game.clear_input()
	fingers.clear()
	joy_idx = -1
	look_idx = -1
	modal = true
	pause_panel.visible = true


func close_pause() -> void:
	pause_panel.visible = false
	if settings_panel:
		settings_panel.queue_free()
		settings_panel = null
	modal = false
	get_tree().paused = false


func _open_settings() -> void:
	pause_panel.visible = false
	settings_panel = SettingsPanel.new()
	settings_panel.closed.connect(func():
		settings_panel.queue_free()
		settings_panel = null
		pause_panel.visible = true)
	pause_panel.get_parent().add_child(settings_panel)


# ------------------------------------------------------------- per-frame
func _process(delta: float) -> void:
	var pl: Player = Game.player
	if pl == null or not is_instance_valid(pl):
		return
	if Game.consume("pause") and not cutscene_active:
		open_pause()
	if cutscene_active and (Game.consume("interact") or Game.consume("jump")):
		_advance.emit()
	health_fill.size.x = 236.0 * clampf(pl.health / 100.0, 0.0, 1.0)
	health_fill.color = Color(0.2, 0.8, 0.35).lerp(Color(0.9, 0.15, 0.1), 1.0 - clampf(pl.health / 100.0, 0.0, 1.0))
	if pl.health < _last_health - 0.5:
		_flash = 0.5
	_last_health = pl.health
	toast_t -= delta
	toast_lbl.modulate.a = clampf(toast_t, 0.0, 1.0)
	stars.queue_redraw()
	var in_v := pl.in_vehicle and pl.vehicle != null
	speed_lbl.text = ("%d km/h" % int(absf(pl.vehicle.speed_f) * 3.6)) if in_v else ""
	ammo_lbl.text = "" if in_v else ("%d / %d" % [Game.ammo_mag, Game.ammo_reserve])
	var pol: PoliceManager = Game.world.police if Game.world else null
	arrest_lbl.text = ("ARRESTING %d%%" % int(pol.arrest_t / 3.0 * 100.0)) if (pol and pol.arrest_t > 0.1) else ""
	_map_t += delta
	if _map_t > 0.08:
		_map_t = 0.0
		minimap.queue_redraw()
	touch.queue_redraw()
	_diag_t += delta
	diag_lbl.visible = Game.settings.diag
	if Game.settings.diag and _diag_t > 0.5:
		_diag_t = 0.0
		var w: World = Game.world
		diag_lbl.text = "FPS %d\nRender %s\nMem %.0f MB\nDraws %d\nObjects %d\nBlocks %d  Veh %d\nWeather %d  Heat %.0f" % [
			Engine.get_frames_per_second(), Game.render_info,
			OS.get_static_memory_usage() / 1048576.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_COUNT),
			w.blocks.size() if w else 0, w.registry.size() if w else 0,
			w.weather if w else 0, Game.wanted_heat]


# ------------------------------------------------------------- touch input
func mode() -> String:
	var pl: Player = Game.player
	return "veh" if (pl and pl.in_vehicle) else "foot"


func button_pos(name: String) -> Vector2:
	var d: Array = BUTTONS[name]
	var s := screen()
	var sc: float = Game.settings.btn_scale
	match d[0]:
		"r": return Vector2(s.x - d[1] * sc, s.y - d[2] * sc)
		"l": return Vector2(d[1] * sc, s.y - d[2] * sc)
	return Vector2(s.x - d[1], d[2])


func button_radius(name: String) -> float:
	var d: Array = BUTTONS[name]
	return d[3] * (1.0 if d[0] == "tr" else float(Game.settings.btn_scale))


func button_visible(name: String) -> bool:
	var m: String = BUTTONS[name][5]
	return m == "both" or m == mode()


func _input(event: InputEvent) -> void:
	if modal:
		return
	if event is InputEventScreenTouch:
		if cutscene_active:
			if event.pressed:
				_advance.emit()
			return
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag and not cutscene_active:
		if event.index == joy_idx:
			var d: Vector2 = event.position - joy_origin
			joy_pos = joy_origin + d.limit_length(70.0)
			Game.touch_move = d.limit_length(70.0) / 70.0
		elif event.index == look_idx:
			Game.touch_look += event.relative


func _touch_down(idx: int, p: Vector2) -> void:
	for n in BUTTONS.keys():
		if button_visible(n) and p.distance_to(button_pos(n)) < button_radius(n) * 1.15:
			fingers[idx] = n
			if n == "pause":
				open_pause()
			else:
				Game.touch_press(n)
			return
	var s := screen()
	if joy_idx == -1 and p.x < s.x * 0.4 and p.y > s.y * 0.3:
		joy_idx = idx
		joy_origin = p
		joy_pos = p
		return
	if look_idx == -1:
		look_idx = idx


func _touch_up(idx: int) -> void:
	if fingers.has(idx):
		Game.touch_release(fingers[idx])
		fingers.erase(idx)
	if idx == joy_idx:
		joy_idx = -1
		Game.touch_move = Vector2.ZERO
	if idx == look_idx:
		look_idx = -1


# ------------------------------------------------------------- inner draw classes
class TouchLayer extends Control:
	var hud: HUD

	func _draw() -> void:
		if hud == null or not Game.in_game or Game.cutscene:
			return
		var font := ThemeDB.fallback_font
		var op: float = Game.settings.btn_opacity
		if hud.joy_idx != -1:
			draw_circle(hud.joy_origin, 72.0, Color(1, 1, 1, 0.12 * op))
			draw_arc(hud.joy_origin, 72.0, 0.0, TAU, 40, Color(1, 1, 1, 0.5 * op), 3.0)
			draw_circle(hud.joy_pos, 32.0, Color(1, 1, 1, 0.45 * op))
		for n in HUD.BUTTONS.keys():
			if not hud.button_visible(n):
				continue
			var c := hud.button_pos(n)
			var r := hud.button_radius(n)
			var down := Game.is_down(n)
			var col := Color(1.0, 0.42, 0.17) if down else Color(0.1, 0.13, 0.2)
			draw_circle(c, r, Color(col.r, col.g, col.b, op * (0.9 if down else 0.6)))
			draw_arc(c, r, 0.0, TAU, 32, Color(1, 1, 1, op), 3.0)
			var label: String = HUD.BUTTONS[n][4]
			if n == "interact":
				label = "EXIT" if hud.mode() == "veh" else ("ENTER" if (Game.player and Game.player.nearest_free_vehicle() != null) else "USE")
			var fs := int(clampf(r * 0.42, 14.0, 30.0))
			draw_string(font, c + Vector2(-r, fs * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color.WHITE)
		if hud._flash > 0.0:
			hud._flash -= 0.016
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0, 0, hud._flash * 0.4))


class Stars extends Control:
	func _draw() -> void:
		for i in range(5):
			var on: bool = i < Game.wanted
			var c := Vector2(18.0 + i * 40.0, 18.0)
			var pts := PackedVector2Array()
			for k in range(10):
				var r := 16.0 if k % 2 == 0 else 7.0
				var a := -PI / 2.0 + k * PI / 5.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			var col := Color(1.0, 0.85, 0.15) if on else Color(0.2, 0.2, 0.25, 0.7)
			if on and Game.wanted > 0 and int(Time.get_ticks_msec() / 300) % 2 == 0 and Game.world and Game.world.police.unseen_t < 10.0:
				col = Color(1.0, 0.35, 0.3)
			draw_colored_polygon(pts, col)


class Minimap extends Control:
	const SC := 0.5

	func _draw() -> void:
		var w: World = Game.world
		if w == null or w.player == null:
			return
		var c := size * 0.5
		var pp := w.focus_pos()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.16, 0.1, 0.85))
		var water_y := c.y + (772.0 - pp.z) * SC
		if water_y < size.y:
			draw_rect(Rect2(0, water_y, size.x, size.y - water_y), Color(0.1, 0.3, 0.45, 0.9))
		for i in range(-1, Game.N):
			var x := (i + 0.5) * Game.C
			var sx := c.x + (x - pp.x) * SC
			if sx > -6.0 and sx < size.x + 6.0:
				draw_line(Vector2(sx, 0), Vector2(sx, size.y), Color(0.55, 0.55, 0.6), 6.0)
			var sy := c.y + (x - pp.z) * SC
			if sy > -6.0 and sy < size.y + 6.0:
				draw_line(Vector2(0, sy), Vector2(size.x, sy), Color(0.55, 0.55, 0.6), 6.0)
		for key in w.col_pos.keys():
			if not Game.collected.has(key):
				var v: Vector3 = w.col_pos[key]
				draw_circle(c + Vector2(v.x - pp.x, v.z - pp.z) * SC, 3.0, Color(1, 0.85, 0.1))
		for v in w.registry:
			if is_instance_valid(v) and v.pool == "police" and not v.roadblock:
				draw_circle(c + Vector2(v.global_position.x - pp.x, v.global_position.z - pp.z) * SC, 4.0, Color(1, 0.2, 0.2))
		for m in w.missions.map_points():
			var off := Vector2(m.pos.x - pp.x, m.pos.z - pp.z) * SC
			var col := Color(1, 0.6, 0.1)
			if m.kind == "side":
				col = Color(0.3, 0.8, 1)
			elif m.kind == "obj":
				col = Color(1, 0.95, 0.2)
			elif m.kind == "enemy":
				col = Color(1, 0.1, 0.1)
			var lim := size * 0.5 - Vector2(8, 8)
			draw_circle(c + off.clamp(-lim, lim), 6.0 if m.kind != "enemy" else 3.5, col)
		var yaw: float = w.player.vehicle.rotation.y if (w.player.in_vehicle and w.player.vehicle) else w.player.rotation.y
		var f := Vector2(-sin(yaw), -cos(yaw))
		var rt := Vector2(-f.y, f.x)
		draw_colored_polygon(PackedVector2Array([c + f * 10.0, c - f * 6.0 + rt * 6.0, c - f * 6.0 - rt * 6.0]), Color.WHITE)
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.8), false, 3.0)
