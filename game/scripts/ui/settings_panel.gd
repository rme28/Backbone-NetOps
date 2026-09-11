class_name SettingsPanel
extends Control

signal closed

func _ready() -> void:
	theme = preload("res://scripts/ui/design_system.gd").get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.025, 0.03, 0.94)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(960, 0)
	center.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.055, 0.075, 0.98)
	style.border_color = Color("36545a")
	style.set_border_width_all(2)
	style.content_margin_left = 50
	style.content_margin_right = 50
	style.content_margin_top = 35
	style.content_margin_bottom = 35
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
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
	_add_slider(left, "Volume général", "master_volume", 0, 100)
	_add_slider(left, "Musique", "music_volume", 0, 100)
	_add_slider(left, "Effets", "effects_volume", 0, 100)
	_add_section(left, "COMMANDES")
	_add_slider(left, "Sensibilité souris", "mouse_sensitivity", 10, 100)
	var keybinds := GridContainer.new()
	keybinds.columns = 2
	keybinds.add_theme_constant_override("h_separation", 12)
	keybinds.add_theme_constant_override("v_separation", 8)
	left.add_child(keybinds)
	for bind in [
		["ZQSD", "Déplacement"], ["SOURIS", "Regarder"], ["TAB", "Inventaire"],
		["E", "Poser l'équipement"], ["T", "Interagir / Console"],
		["CLIC G.", "Câbler un port"], ["CLIC D.", "Vue de précision (maintenir)"],
		["ÉCHAP", "Pause"],
	]:
		_add_keybind_row(keybinds, bind[0], bind[1])

	_add_section(right, "VIDÉO")
	_add_toggle(right, "Plein écran", "fullscreen")
	_add_toggle(right, "Synchronisation verticale", "vsync")
	_add_slider(right, "Échelle de rendu", "render_scale", 50, 120)
	_add_section(right, "INTERFACE")
	_add_slider(right, "Échelle UI", "ui_scale", 80, 130)
	_add_toggle(right, "Afficher l'aide à l'écran", "show_help_overlay")
	var note := Label.new()
	note.text = "Les changements sont appliqués immédiatement."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("6f8996"))
	right.add_child(note)

func _add_section(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", Color("8bc6b5"))
	parent.add_child(label)
	parent.add_child(HSeparator.new())

func _add_slider(parent: VBoxContainer, label_text: String, key: String, minimum: float, maximum: float) -> void:
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
		GameState.apply_all_settings()
	)

func _add_toggle(parent: VBoxContainer, label_text: String, key: String) -> void:
	var toggle := CheckButton.new()
	toggle.text = label_text
	toggle.button_pressed = bool(GameState.settings.get(key, false))
	toggle.toggled.connect(func(enabled):
		GameState.settings[key] = enabled
		GameState.save_settings()
		GameState.apply_all_settings()
	)
	parent.add_child(toggle)


## Affiche une "touche" (rectangle style clavier) + l'action associee.
func _add_keybind_row(parent: GridContainer, key_text: String, action_text: String) -> void:
	var key := PanelContainer.new()
	var key_style := StyleBoxFlat.new()
	key_style.bg_color = Color(0.06, 0.12, 0.15, 1.0)
	key_style.border_color = Color("3a6a80")
	key_style.set_border_width_all(1)
	key_style.set_corner_radius_all(4)
	key_style.content_margin_left = 10
	key_style.content_margin_right = 10
	key_style.content_margin_top = 5
	key_style.content_margin_bottom = 5
	key.add_theme_stylebox_override("panel", key_style)
	key.custom_minimum_size = Vector2(78, 0)
	var key_label := Label.new()
	key_label.text = key_text
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.add_theme_font_size_override("font_size", 13)
	key_label.add_theme_color_override("font_color", Color("aee3ff"))
	key.add_child(key_label)
	parent.add_child(key)

	var action := Label.new()
	action.text = action_text
	action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action.add_theme_color_override("font_color", Color("cfe3ec"))
	parent.add_child(action)
