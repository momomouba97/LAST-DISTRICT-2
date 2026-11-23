extends Node
## Entry point. 3D is rendered in a SubViewport whose size is adaptive (dynamic
## resolution); the HUD is drawn on top at native resolution so it stays sharp.

var menu: MainMenu
var loading: Control
var bar: ProgressBar
var view: SubViewport
var display_layer: CanvasLayer
var display: TextureRect
var world: World
var hud: HUD
var res_scale := 1.0
var _fps_t := 0.0
var _frames := 0


func _ready() -> void:
	get_window().size_changed.connect(_apply_resolution)
	Game.settings_changed.connect(_apply_resolution)
	_show_menu()


func _show_menu() -> void:
	menu = MainMenu.new()
	var layer := CanvasLayer.new()
	layer.name = "MenuLayer"
	layer.add_child(menu)
	add_child(layer)
	menu.start_game.connect(_start)


func _start(new_game: bool) -> void:
	menu.get_parent().queue_free()
	menu = null
	_show_loading()
	if new_game:
		Game.new_game()
	elif not Game.load_game():
		Game.new_game()
	Game.clear_input()
	_make_view()
	world = World.new()
	view.add_child(world)
	await world.build(func(p: float): bar.value = p * 100.0)
	loading.get_parent().queue_free()
	hud = HUD.new()
	add_child(hud)
	Game.hud = hud
	hud.quit_to_menu.connect(_to_menu)
	Game.in_game = true
	get_tree().paused = false


func _show_loading() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	loading = Control.new()
	loading.theme = UITheme.make()
	loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(loading)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.add_child(bg)
	var l := Label.new()
	l.text = "LOADING SANTA LUCIA..."
	l.add_theme_font_size_override("font_size", 44)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(-300, -60)
	loading.add_child(l)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(600, 28)
	bar.set_anchors_preset(Control.PRESET_CENTER)
	bar.position = Vector2(-300, 20)
	bar.show_percentage = false
	loading.add_child(bar)
	loading.position = Vector2.ZERO


func _make_view() -> void:
	view = SubViewport.new()
	view.own_world_3d = true
	view.audio_listener_enable_3d = true
	view.msaa_3d = Viewport.MSAA_DISABLED
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.handle_input_locally = false
	add_child(view)
	display_layer = CanvasLayer.new()
	display_layer.layer = -1
	add_child(display_layer)
	display = TextureRect.new()
	display.texture = view.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_SCALE
	display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	display.set_anchors_preset(Control.PRESET_FULL_RECT)
	display_layer.add_child(display)
	res_scale = 1.0
	_apply_resolution()


func _apply_resolution() -> void:
	if view == null:
		return
	var win := get_window().size
	var p := Game.preset()
	var h := minf(float(p.h), float(win.y))
	var sc := res_scale if Game.settings.auto_res else float(Game.settings.res_scale)
	h = maxf(240.0, h * sc)
	var w := h * float(win.x) / float(maxi(win.y, 1))
	view.size = Vector2i(int(w), int(h))
	Game.render_info = "%dx%d (%.0f%%)" % [view.size.x, view.size.y, sc * 100.0]


func _process(delta: float) -> void:
	if view == null or not Game.in_game or get_tree().paused:
		return
	_frames += 1
	_fps_t += delta
	if _fps_t >= 1.5:
		var fps := _frames / _fps_t
		_frames = 0
		_fps_t = 0.0
		if Game.settings.auto_res:
			var lo: float = Game.preset().min
			var target := float(Game.settings.fps_cap)
			if fps < target * 0.85 and res_scale > lo:
				res_scale = maxf(lo, res_scale - 0.07)
				_apply_resolution()
			elif fps > target * 0.97 and res_scale < 1.0:
				res_scale = minf(1.0, res_scale + 0.04)
				_apply_resolution()


func _to_menu() -> void:
	Game.save_game()
	Game.in_game = false
	Game.world = null
	Game.player = null
	Game.hud = null
	Game.cutscene = false
	Game.clear_input()
	get_tree().paused = false
	if hud:
		hud.queue_free()
		hud = null
	if view:
		view.queue_free()
		view = null
	if display_layer:
		display_layer.queue_free()
		display_layer = null
	world = null
	_show_menu()
