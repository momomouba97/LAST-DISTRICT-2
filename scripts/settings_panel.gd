extends PanelContainer
class_name SettingsPanel

signal closed

var box: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 80
	offset_right = -80
	offset_top = 30
	offset_bottom = -30
	var outer := VBoxContainer.new()
	add_child(outer)
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 38)
	outer.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	_head("Graphics")
	_cycle("Preset", "preset", ["Low", "Balanced", "High"])
	_toggle("Automatic resolution scaling", "auto_res")
	_slider("Manual resolution scale", "res_scale", 0.4, 1.0, 0.05)
	_cycle("FPS cap", "fps_cap", [30, 60], true)
	_toggle("Performance mode (lowest detail)", "perf_mode")
	_cycle("Weather", "weather", Game.WEATHER_NAMES)
	_toggle("Developer diagnostics overlay", "diag")
	_head("Audio")
	_slider("Master volume", "master", 0.0, 1.0, 0.05)
	_slider("Music volume", "music", 0.0, 1.0, 0.05)
	_slider("Effects volume", "sfx", 0.0, 1.0, 0.05)
	_head("Controls")
	_slider("Button size", "btn_scale", 0.7, 1.4, 0.05)
	_slider("Button opacity", "btn_opacity", 0.3, 1.0, 0.05)
	_slider("Camera sensitivity", "look_sens", 0.4, 2.0, 0.1)
	outer.add_child(UITheme.button("Back", func(): closed.emit(), 240.0))


func _head(t: String) -> void:
	var l := Label.new()
	l.text = t.to_upper()
	l.add_theme_color_override("font_color", UITheme.ACCENT)
	l.add_theme_font_size_override("font_size", 30)
	box.add_child(l)


func _slider(label: String, key: String, lo: float, hi: float, step: float) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(430, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Game.settings[key])
	s.custom_minimum_size = Vector2(360, 44)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v: float):
		Game.settings[key] = v
		Game.settings_apply_and_save())
	row.add_child(s)
	box.add_child(row)


func _toggle(label: String, key: String) -> void:
	var c := CheckButton.new()
	c.text = label
	c.button_pressed = bool(Game.settings[key])
	c.toggled.connect(func(on: bool):
		Game.settings[key] = on
		Game.settings_apply_and_save())
	box.add_child(c)


func _cycle(label: String, key: String, options: Array, by_value := false) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 60)
	var refresh := func():
		var idx: int = int(Game.settings[key])
		if by_value:
			idx = maxi(0, options.find(Game.settings[key]))
		b.text = "%s: %s" % [label, str(options[idx])]
	b.pressed.connect(func():
		Game.click()
		var idx: int = int(Game.settings[key])
		if by_value:
			idx = maxi(0, options.find(Game.settings[key]))
		idx = (idx + 1) % options.size()
		Game.settings[key] = options[idx] if by_value else idx
		Game.settings_apply_and_save()
		refresh.call())
	refresh.call()
	box.add_child(b)
