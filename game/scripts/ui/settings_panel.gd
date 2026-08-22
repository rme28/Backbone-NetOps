class_name SettingsPanel
extends PanelContainer

signal closed

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.055, 0.075, 0.98)
	style.border_color = Color("34708e")
	style.set_border_width_all(2)
	style.content_margin_left = 50
	style.content_margin_right = 50
	style.content_margin_top = 35
	style.content_margin_bottom = 35
	add_theme_stylebox_override("panel", style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "PARAMÈTRES"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 28)
	header.add_child(title)
	var close := Button.new()
	close.text = "FERMER"
	close.pressed.connect(func(): closed.emit())
	header.add_child(close)
	root.add_child(HSeparator.new())

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 40)
	root.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)

	_add_section(left, "AUDIO")
	_add_slider(left, "Volume général", "master_volume", 0, 100, _apply_master_volume)
	_add_slider(left, "Musique", "music_volume", 0, 100)
	_add_slider(left, "Effets", "effects_volume", 0, 100)
	_add_section(left, "COMMANDES")
	_add_slider(left, "Sensibilité souris", "mouse_sensitivity", 10, 100)
	var controls := Label.new()
	controls.text = "ZQSD  Déplacement\nTAB  Inventaire\nE  Poser\nT  Interagir / Console\nClic  Câbler\nÉchap  Pause"
	controls.add_theme_color_override("font_color", Color("aac3d0"))
	left.add_child(controls)

	_add_section(right, "VIDÉO")
	_add_toggle(right, "Plein écran", "fullscreen", _apply_fullscreen)
	_add_toggle(right, "Synchronisation verticale", "vsync", _apply_vsync)
	_add_slider(right, "Échelle de rendu", "render_scale", 50, 120)
	_add_section(right, "INTERFACE")
	_add_slider(right, "Échelle UI", "ui_scale", 80, 130)
	var note := Label.new()
	note.text = "Les changements sont appliqués immédiatement.\nLa personnalisation des touches arrivera avec le système de profils."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("6f8996"))
	right.add_child(note)

func _add_section(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", Color("78d4ff"))
	parent.add_child(label)
	parent.add_child(HSeparator.new())

func _add_slider(parent: VBoxContainer, label_text: String, key: String, minimum: float, maximum: float, callback := Callable()) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(190, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.value = float(GameState.settings.get(key, maximum))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value := Label.new()
	value.text = "%d%%" % int(slider.value)
	value.custom_minimum_size = Vector2(55, 0)
	row.add_child(value)
	slider.value_changed.connect(func(new_value):
		GameState.settings[key] = new_value
		GameState.save_settings()
		value.text = "%d%%" % int(new_value)
		if callback.is_valid(): callback.call(new_value)
	)

func _add_toggle(parent: VBoxContainer, label_text: String, key: String, callback: Callable) -> void:
	var toggle := CheckButton.new()
	toggle.text = label_text
	toggle.button_pressed = bool(GameState.settings.get(key, false))
	toggle.toggled.connect(func(enabled):
		GameState.settings[key] = enabled
		GameState.save_settings()
		callback.call(enabled)
	)
	parent.add_child(toggle)

func _apply_master_volume(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(value / 100.0, 0.001)))

func _apply_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)

func _apply_vsync(enabled: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)
