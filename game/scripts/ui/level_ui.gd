extends RefCounted
## Level UI construction. Runtime state and callbacks remain on the scene;
## PC apps, settings and appliance command parsing live in their own modules.
var room: Node3D

func _init(host: Node3D) -> void:
	room = host

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	room._hud = layer

	room._help_label = Label.new()
	room._help_label.position = Vector2(16, 12)
	room._help_label.add_theme_font_size_override("font_size", 13)
	layer.add_child(room._help_label)

	room._status_label = Label.new()
	room._status_label.position = Vector2(16, 55)
	room._status_label.visible = false
	layer.add_child(room._status_label)

	room._feedback_label = Label.new()
	room._feedback_label.position = Vector2(16, 82)
	room._feedback_label.modulate = Color(0.5, 0.9, 0.5)
	layer.add_child(room._feedback_label)

	var crosshair := Label.new()
	crosshair.text = "·"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-5, -10)
	crosshair.add_theme_font_size_override("font_size", 20)
	crosshair.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0, 0.8))
	layer.add_child(crosshair)

	room._inspection_label = Label.new()
	room._inspection_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	room._inspection_label.position = Vector2(18, -155)
	room._inspection_label.custom_minimum_size = Vector2(360, 125)
	room._inspection_label.add_theme_font_override("font", room._terminal_font())
	room._inspection_label.add_theme_font_size_override("font_size", 13)
	room._inspection_label.add_theme_color_override("font_color", Color("d9f4ff"))
	var inspect_style := StyleBoxFlat.new()
	inspect_style.bg_color = Color(0.02, 0.05, 0.065, 0.88)
	inspect_style.border_color = Color("2d6275")
	inspect_style.set_border_width_all(1)
	inspect_style.content_margin_left = 12
	inspect_style.content_margin_top = 8
	inspect_style.content_margin_right = 12
	inspect_style.content_margin_bottom = 8
	room._inspection_label.add_theme_stylebox_override("normal", inspect_style)
	room._inspection_label.visible = false
	layer.add_child(room._inspection_label)

	# Indication contextuelle discrete, centree au-dessus du reticule.
	room._context_label = Label.new()
	room._context_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	room._context_label.position = Vector2(-260, -140)
	room._context_label.custom_minimum_size = Vector2(520, 0)
	room._context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room._context_label.add_theme_font_size_override("font_size", 15)
	room._context_label.add_theme_color_override("font_color", Color("dfebe5"))
	room._context_label.add_theme_constant_override("outline_size", 4)
	room._context_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	room._context_label.visible = false
	layer.add_child(room._context_label)

	room.add_child(layer)
	room._update_help_text()


## Applique les reglages qui concernent la scene 3D : echelle de rendu du
## viewport et visibilite de l'aide a l'ecran (parametre "show_help_overlay").

func _build_palette() -> void:
	room._palette_layer = CanvasLayer.new()
	room._palette_layer.visible = false
	room.add_child(room._palette_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.025, 0.035, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	room._palette_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	room._palette_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1050, 650)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("102229")
	style.border_color = Color("36545a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "INVENTAIRE TECHNICIEN"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 25)
	header.add_child(title)
	room._palette_bcoins = Label.new()
	room._palette_bcoins.add_theme_font_size_override("font_size", 19)
	room._palette_bcoins.add_theme_color_override("font_color", Color("ffd166"))
	header.add_child(room._palette_bcoins)
	vbox.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	vbox.add_child(body)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(210, 0)
	sidebar.add_theme_constant_override("separation", 8)
	body.add_child(sidebar)
	var sections := {
		"network": "RÉSEAU", "systems": "SYSTÈMES",
		"accessories": "ACCESSOIRES", "tools": "OUTILS",
	}
	for section in sections:
		var button := Button.new()
		button.text = sections[section]
		button.custom_minimum_size = Vector2(0, 52)
		button.pressed.connect(room._show_palette_section.bind(section))
		sidebar.add_child(button)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	body.add_child(right)
	room._palette_section_title = Label.new()
	room._palette_section_title.add_theme_font_size_override("font_size", 21)
	right.add_child(room._palette_section_title)
	room._palette_content = VBoxContainer.new()
	room._palette_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room._palette_content.add_theme_constant_override("separation", 8)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 400)
	scroll.add_child(room._palette_content)
	right.add_child(scroll)
	right.add_child(HSeparator.new())
	room._palette_description = Label.new()
	room._palette_description.custom_minimum_size = Vector2(0, 55)
	room._palette_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	room._palette_description.add_theme_color_override("font_color", Color("a8bfcc"))
	right.add_child(room._palette_description)
	var hint := Label.new()
	hint.text = "Cliquer pour sélectionner   •   TAB / Échap pour fermer"
	hint.add_theme_color_override("font_color", Color("688391"))
	vbox.add_child(hint)
	room._show_palette_section("network")



func _build_terminal() -> void:
	room._terminal_layer = CanvasLayer.new()
	room._terminal_layer.visible = false
	room.add_child(room._terminal_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	room._terminal_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	room._terminal_layer.add_child(center)

	var terminal := PanelContainer.new()
	terminal.custom_minimum_size = Vector2(900, 560)
	var terminal_style := StyleBoxFlat.new()
	terminal_style.bg_color = Color("102229")
	terminal_style.border_color = Color("36545a")
	terminal_style.set_border_width_all(1)
	terminal_style.set_corner_radius_all(8)
	terminal_style.content_margin_left = 18
	terminal_style.content_margin_right = 18
	terminal_style.content_margin_top = 14
	terminal_style.content_margin_bottom = 14
	terminal.add_theme_stylebox_override("panel", terminal_style)
	center.add_child(terminal)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	terminal.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)
	room._terminal_title = Label.new()
	room._terminal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room._terminal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	room._terminal_title.add_theme_color_override("font_color", Color("eeeeee"))
	room._terminal_title.add_theme_font_size_override("font_size", 16)
	header.add_child(room._terminal_title)
	var live := Label.new()
	live.text = "●  SESSION LOCALE"
	live.add_theme_color_override("font_color", Color("80d890"))
	header.add_child(live)
	vbox.add_child(HSeparator.new())
	var tabs := Label.new()
	tabs.text = "CONSOLE  /  CONFIGURATION RÉSEAU"
	tabs.add_theme_color_override("font_color", Color("bdbdbd"))
	tabs.add_theme_font_size_override("font_size", 13)
	vbox.add_child(tabs)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(panel)
	var output_style := StyleBoxFlat.new()
	output_style.bg_color = Color("09171e")
	output_style.content_margin_left = 14
	output_style.content_margin_right = 14
	output_style.content_margin_top = 12
	output_style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", output_style)

	room._terminal_output = RichTextLabel.new()
	room._terminal_output.custom_minimum_size = Vector2(850, 400)
	room._terminal_output.scroll_following = true
	room._terminal_output.bbcode_enabled = false
	room._terminal_output.add_theme_color_override("default_color", Color("e8e8e8"))
	room._terminal_output.add_theme_font_size_override("normal_font_size", 14)
	room._terminal_output.add_theme_font_override("normal_font", room._terminal_font())
	panel.add_child(room._terminal_output)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 0)
	vbox.add_child(input_row)
	room._terminal_prompt = Label.new()
	room._terminal_prompt.add_theme_font_override("font", room._terminal_font())
	room._terminal_prompt.add_theme_font_size_override("font_size", 15)
	room._terminal_prompt.add_theme_color_override("font_color", Color("ffffff"))
	input_row.add_child(room._terminal_prompt)
	room._terminal_input = LineEdit.new()
	room._terminal_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room._terminal_input.placeholder_text = "commande..."
	room._terminal_input.keep_editing_on_text_submit = true
	room._terminal_input.add_theme_font_override("font", room._terminal_font())
	room._terminal_input.add_theme_font_size_override("font_size", 15)
	room._terminal_input.add_theme_color_override("font_color", Color("ffffff"))
	room._terminal_input.add_theme_color_override("caret_color", Color("ffffff"))
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color("09171e")
	input_style.border_color = Color("36545a")
	input_style.set_border_width_all(1)
	input_style.content_margin_left = 6
	input_style.content_margin_right = 6
	room._terminal_input.add_theme_stylebox_override("normal", input_style)
	room._terminal_input.add_theme_stylebox_override("focus", input_style)
	room._terminal_input.text_submitted.connect(room._on_terminal_command_submitted)
	room._terminal_input.text_changed.connect(room._on_terminal_text_changed)
	room._terminal_input.gui_input.connect(room._on_terminal_input_event)
	room._terminal_input.focus_exited.connect(room._keep_terminal_focus)
	# Empeche Tab de faire fuir le focus vers un autre controle de l'UI (comportement
	# de navigation par defaut de Godot et garde le focus dans la console.
	room._terminal_input.focus_mode = Control.FOCUS_ALL
	input_row.add_child(room._terminal_input)
	room._terminal_input.focus_next = room._terminal_input.get_path()
	room._terminal_input.focus_previous = room._terminal_input.get_path()

	room._terminal_suggestions = Label.new()
	room._terminal_suggestions.add_theme_font_override("font", room._terminal_font())
	room._terminal_suggestions.add_theme_font_size_override("font_size", 12)
	room._terminal_suggestions.add_theme_color_override("font_color", Color("799b88"))
	vbox.add_child(room._terminal_suggestions)
	var hint := Label.new()
	hint.text = "TAB completer   ↑↓ historique   ? aide   Echap fermer"
	hint.add_theme_color_override("font_color", Color("60786b"))
	vbox.add_child(hint)



func _build_technician_hub() -> void:
	room._technician_hub = CanvasLayer.new()
	room._technician_hub.visible = false
	room.add_child(room._technician_hub)
	var dim := ColorRect.new()
	dim.color = Color(0.005, 0.015, 0.025, 0.96)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	room._technician_hub.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	room._technician_hub.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1120, 690)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0d1821")
	style.border_color = Color("36545a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(7)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var brand := Label.new()
	brand.text = "BACKBONE OS  /  TECHNICIAN HUB"
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_font_size_override("font_size", 23)
	header.add_child(brand)
	room._hub_bcoins = Label.new()
	room._hub_bcoins.add_theme_font_size_override("font_size", 19)
	room._hub_bcoins.add_theme_color_override("font_color", Color("ffd166"))
	header.add_child(room._hub_bcoins)
	root.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	root.add_child(body)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(220, 0)
	sidebar.add_theme_constant_override("separation", 9)
	body.add_child(sidebar)
	for tab in [["dashboard","TABLEAU DE BORD"], ["mail","MESSAGERIE"], ["jobs","JOBS"], ["shop","BOUTIQUE"], ["settings","PARAMÈTRES"]]:
		var button := Button.new()
		button.text = tab[1]
		button.custom_minimum_size = Vector2(0, 52)
		button.pressed.connect(room._show_hub_tab.bind(tab[0]))
		sidebar.add_child(button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(spacer)
	var close := Button.new()
	close.text = "FERMER"
	close.pressed.connect(room._close_technician_hub)
	sidebar.add_child(close)
	room._hub_content = RichTextLabel.new()
	room._hub_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room._hub_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room._hub_content.bbcode_enabled = true
	room._hub_content.add_theme_font_size_override("normal_font_size", 16)
	body.add_child(room._hub_content)
	room._show_hub_tab("dashboard")



func _build_objectives_panel() -> void:
	var layer := CanvasLayer.new()
	room.add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-260, 12)
	panel.custom_minimum_size = Vector2(240, 0)
	panel.visible = false
	layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	room._score_label = Label.new()
	room._score_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(room._score_label)

	vbox.add_child(HSeparator.new())

	room._objectives_list = VBoxContainer.new()
	room._objectives_list.add_theme_constant_override("separation", 2)
	vbox.add_child(room._objectives_list)



func _build_pause_menu() -> void:
	room._pause_menu = CanvasLayer.new()
	room._pause_menu.visible = false
	room.add_child(room._pause_menu)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	room._pause_menu.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	room._pause_menu.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(390,0)
	center.add_child(card)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(350,0)
	vbox.add_theme_constant_override("separation",14)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var resume_btn := Button.new()
	resume_btn.text = "Reprendre"
	resume_btn.pressed.connect(room._toggle_pause)
	vbox.add_child(resume_btn)

	var save_btn := Button.new()
	save_btn.text = "Sauvegarder"
	save_btn.pressed.connect(room._on_save_pressed)
	vbox.add_child(save_btn)

	var settings_btn := Button.new()
	settings_btn.text = "Paramètres"
	settings_btn.pressed.connect(room._open_game_settings)
	vbox.add_child(settings_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Menu principal"
	menu_btn.pressed.connect(room._on_quit_to_menu)
	vbox.add_child(menu_btn)

	room._settings_overlay = SettingsPanel.new()
	room._settings_overlay.visible = false
	room._settings_overlay.closed.connect(room._close_game_settings)
	room._pause_menu.add_child(room._settings_overlay)
