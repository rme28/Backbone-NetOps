extends Control

const GAME_SCENE := "res://scenes/world/server_room.tscn"
var _name_edit: LineEdit
var _saves_list: ItemList
var _feedback: Label
var _settings: SettingsPanel

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = Color("071118")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Bandes décoratives rappelant une baie réseau.
	for index in 8:
		var line := ColorRect.new()
		line.color = Color(0.08, 0.20, 0.27, 0.22)
		line.position = Vector2(0, 90 + index * 105)
		line.size = Vector2(2200, 1)
		add_child(line)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 75)
	margin.add_theme_constant_override("margin_right", 75)
	margin.add_theme_constant_override("margin_top", 55)
	margin.add_theme_constant_override("margin_bottom", 55)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 22)
	margin.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var brand := VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(brand)
	var title := Label.new()
	title.text = "BACKBONE\nNETOPS"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color("e6f7ff"))
	brand.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "BUILD  •  CONFIGURE  •  TROUBLESHOOT"
	subtitle.add_theme_color_override("font_color", Color("63c8f5"))
	brand.add_child(subtitle)
	var version := Label.new()
	version.text = "ALPHA 0.3.0  /  ns-3 ENGINE"
	version.add_theme_color_override("font_color", Color("607987"))
	top.add_child(version)
	root.add_child(HSeparator.new())

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 28)
	root.add_child(columns)
	var new_card := _card("NOUVELLE MISSION")
	new_card.custom_minimum_size = Vector2(520, 0)
	columns.add_child(new_card)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Nom de la partie"
	_name_edit.custom_minimum_size = Vector2(0, 48)
	new_card.get_child(0).add_child(_name_edit)
	var new_button := Button.new()
	new_button.text = "DÉMARRER"
	new_button.custom_minimum_size = Vector2(0, 58)
	new_button.pressed.connect(_on_new_game)
	new_card.get_child(0).add_child(new_button)

	var load_card := _card("PARTIES SAUVEGARDÉES")
	load_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(load_card)
	_saves_list = ItemList.new()
	_saves_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_saves_list.custom_minimum_size = Vector2(0, 230)
	_saves_list.item_activated.connect(_on_save_activated)
	load_card.get_child(0).add_child(_saves_list)
	var load_row := HBoxContainer.new()
	load_card.get_child(0).add_child(load_row)
	var load := Button.new()
	load.text = "CHARGER"
	load.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load.pressed.connect(_on_load_selected)
	load_row.add_child(load)
	var delete := Button.new()
	delete.text = "SUPPRIMER"
	delete.pressed.connect(_on_delete_selected)
	load_row.add_child(delete)

	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	var settings := Button.new()
	settings.text = "PARAMÈTRES"
	settings.pressed.connect(_open_settings)
	bottom.add_child(settings)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var quit := Button.new()
	quit.text = "QUITTER"
	quit.pressed.connect(func(): get_tree().quit())
	bottom.add_child(quit)
	_feedback = Label.new()
	_feedback.add_theme_color_override("font_color", Color("ff7b72"))
	root.add_child(_feedback)
	_refresh_saves()

func _card(title_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.10, 0.135, 0.94)
	style.border_color = Color("24495d")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("7dd8ff"))
	content.add_child(title)
	content.add_child(HSeparator.new())
	return panel

func _open_settings() -> void:
	if _settings == null:
		_settings = SettingsPanel.new()
		_settings.closed.connect(func(): _settings.visible = false)
		add_child(_settings)
	_settings.visible = true

func _refresh_saves() -> void:
	_saves_list.clear()
	for save in GameState.list_saves(): _saves_list.add_item(save)

func _on_new_game() -> void:
	var game_name := _name_edit.text.strip_edges()
	if game_name.is_empty(): game_name = "Mission %s" % Time.get_datetime_string_from_system().replace(":", "-")
	if game_name in GameState.list_saves(): _feedback.text = "Cette partie existe déjà."; return
	GameState.new_game(game_name)
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_load_selected() -> void:
	var selected := _saves_list.get_selected_items()
	if selected.is_empty(): _feedback.text = "Sélectionne une partie."; return
	_load(_saves_list.get_item_text(selected[0]))

func _on_save_activated(index: int) -> void: _load(_saves_list.get_item_text(index))

func _load(save: String) -> void:
	if not GameState.load_from(save): _feedback.text = "Chargement impossible."; return
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_delete_selected() -> void:
	var selected := _saves_list.get_selected_items()
	if selected.is_empty(): return
	GameState.delete_save(_saves_list.get_item_text(selected[0]))
	_refresh_saves()
