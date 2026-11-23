extends Control
class_name MainMenu

signal start_game(new_game: bool)

var settings_panel: SettingsPanel
var buildings: Array = []
var vbox: VBoxContainer


func _ready() -> void:
	theme = UITheme.make()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var x := 0.0
	while x < 1800.0:
		var w := rng.randf_range(50, 130)
		buildings.append(Rect2(x, 0, w, rng.randf_range(120, 420)))
		x += w + 4.0
	vbox = VBoxContainer.new()
	vbox.position = Vector2(90, 120)
	vbox.add_theme_constant_override("separation", 14)
	add_child(vbox)
	var title := Label.new()
	title.text = "LAST DISTRICT"
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color(1, 0.95, 0.9))
	title.add_theme_color_override("font_outline_color", UITheme.ACCENT)
	title.add_theme_constant_override("outline_size", 10)
	vbox.add_child(title)
	var sub := Label.new()
	sub.text = "SANTA LUCIA  -  an original open-world story"
	sub.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	vbox.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(gap)
	var cont := UITheme.button("Continue", func(): start_game.emit(false))
	cont.disabled = not Game.has_valid_save()
	vbox.add_child(cont)
	vbox.add_child(UITheme.button("New Game", func(): start_game.emit(true)))
	vbox.add_child(UITheme.button("Settings", _open_settings))
	vbox.add_child(UITheme.button("Quit", func(): get_tree().quit()))
	if Game.last_save_error != "":
		var warn := Label.new()
		warn.text = Game.last_save_error
		warn.add_theme_color_override("font_color", Color(1, 0.6, 0.4))
		vbox.add_child(warn)
		Game.last_save_error = ""


func _open_settings() -> void:
	vbox.visible = false
	settings_panel = SettingsPanel.new()
	settings_panel.closed.connect(func():
		settings_panel.queue_free()
		vbox.visible = true)
	add_child(settings_panel)


func _draw() -> void:
	var s := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.06, 0.09, 0.16))
	draw_rect(Rect2(0, s.y * 0.55, s.x, s.y * 0.45), Color(0.1, 0.16, 0.26))
	draw_circle(Vector2(s.x * 0.78, s.y * 0.38), 90.0, Color(1.0, 0.5, 0.2, 0.9))
	for b in buildings:
		draw_rect(Rect2(b.position.x, s.y - b.size.y, b.size.x, b.size.y), Color(0.08, 0.12, 0.2))
		for wy in range(int(b.size.y / 30.0)):
			if (wy * 7 + int(b.position.x)) % 3 == 0:
				draw_rect(Rect2(b.position.x + 10, s.y - b.size.y + 12 + wy * 30, 10, 14), Color(1, 0.8, 0.45, 0.7))
