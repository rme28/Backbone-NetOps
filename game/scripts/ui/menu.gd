extends Control

const GAME_SCENE := "res://scenes/world/server_room.tscn"

const ACCENT := Color("8bc6b5")
const ACCENT_DIM := Color("36545a")
const BG_PANEL := Color(0.045, 0.09, 0.12, 0.95)

var _name_edit: LineEdit
var _saves_list: ItemList
var _feedback: Label
var _settings: SettingsPanel
var _landing_view: Control
var _mission_view: Control

func _ready() -> void:
	theme = preload("res://scripts/ui/design_system.gd").get_theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_background()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_right", 90)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 50)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 26)
	margin.add_child(root)

	root.add_child(_build_header())
	root.add_child(_accent_separator())

	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(stack)

	_landing_view = _build_landing_view()
	_landing_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_landing_view)

	_mission_view = _build_mission_view()
	_mission_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mission_view.visible = false
	stack.add_child(_mission_view)

	_refresh_saves()
	if not OS.get_environment("BACKBONE_MENU_SCREENSHOT").is_empty(): _dev_menu_screenshot()


func _show_landing() -> void:
	_landing_view.visible = true
	_mission_view.visible = false


func _show_mission_select() -> void:
	_landing_view.visible = false
	_mission_view.visible = true


# --- Ecran d'accueil ---------------------------------------------------------

func _build_landing_view() -> Control:
	var center := HBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var buttons := VBoxContainer.new()
	buttons.custom_minimum_size = Vector2(360, 0)
	buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buttons.add_theme_constant_override("separation", 14)
	center.add_child(buttons)

	var play := _primary_button("JOUER")
	play.pressed.connect(_show_mission_select)
	buttons.add_child(play)


	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	buttons.add_child(spacer)

	var settings := _secondary_button("⚙  PARAMÈTRES")
	settings.pressed.connect(_open_settings)
	buttons.add_child(settings)

	var quit := _secondary_button("QUITTER", Color("ff8a80"))
	quit.pressed.connect(func(): get_tree().quit())
	buttons.add_child(quit)

	return center


# --- Ecran nouvelle mission / sauvegardes ------------------------------------

func _build_mission_view() -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 20)

	var back := _secondary_button("◂  RETOUR")
	back.custom_minimum_size = Vector2(140, 40)
	back.pressed.connect(_show_landing)
	root.add_child(back)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 30)
	root.add_child(columns)

	var new_card := _card("NOUVELLE INFRASTRUCTURE", "▹")
	new_card.custom_minimum_size = Vector2(500, 0)
	columns.add_child(new_card)
	var new_body := new_card.get_child(0)
	var new_hint := Label.new()
	new_hint.text = "Choisis un nom pour ta partie et démarre directement dans la salle serveur."
	new_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	new_hint.add_theme_color_override("font_color", Color("8ba7b5"))
	new_body.add_child(new_hint)
	_name_edit = _styled_line_edit("Nom de la partie")
	new_body.add_child(_name_edit)
	var new_button := _primary_button("DÉMARRER")
	new_button.pressed.connect(_on_new_game)
	new_body.add_child(new_button)

	var load_card := _card("PARTIES SAUVEGARDÉES", "▤")
	load_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(load_card)
	var load_body := load_card.get_child(0)
	_saves_list = _styled_item_list()
	_saves_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_saves_list.custom_minimum_size = Vector2(0, 230)
	_saves_list.item_activated.connect(_on_save_activated)
	load_body.add_child(_saves_list)
	var load_row := HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 10)
	load_body.add_child(load_row)
	var load := _secondary_button("CHARGER")
	load.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load.pressed.connect(_on_load_selected)
	load_row.add_child(load)
	var delete := _secondary_button("SUPPRIMER", Color("ff8a80"))
	delete.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete.pressed.connect(_on_delete_selected)
	load_row.add_child(delete)

	_feedback = Label.new()
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.add_theme_color_override("font_color", Color("ff7b72"))
	root.add_child(_feedback)

	return root


# --- Decor ----------------------------------------------------------------

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color("060d13")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if ResourceLoader.exists("res://assets/art/menu-background.png"):
		var picture := TextureRect.new()
		picture.texture = load("res://assets/art/menu-background.png")
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.set_anchors_preset(Control.PRESET_FULL_RECT)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(picture)
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.025,0.055,0.065,0.98))
	gradient.set_color(1, Color(0.025,0.055,0.065,0.25))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2(1,0)
	shade.texture = texture
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(shade)



func _build_header() -> Control:
	var top := HBoxContainer.new()
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 2)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(brand)
	var title := Label.new()
	title.text = "BACKBONE NETOPS"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color("f0fbff"))
	title.add_theme_constant_override("outline_size", 0)
	brand.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "CONSTRUIRE. CONNECTER. COMPRENDRE."
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", ACCENT)
	subtitle.add_theme_constant_override("outline_size", 0)
	brand.add_child(subtitle)

	var badge := PanelContainer.new()
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.12)
	badge_style.border_color = ACCENT_DIM
	badge_style.set_border_width_all(1)
	badge_style.set_corner_radius_all(4)
	badge_style.content_margin_left = 14
	badge_style.content_margin_right = 14
	badge_style.content_margin_top = 7
	badge_style.content_margin_bottom = 7
	badge.add_theme_stylebox_override("panel", badge_style)
	var version := Label.new()
	version.text = "ALPHA 0.5.0"
	version.add_theme_font_size_override("font_size", 13)
	version.add_theme_color_override("font_color", Color("9fd4ee"))
	badge.add_child(version)
	top.add_child(badge)
	return top


func _accent_separator() -> Control:
	var box := VBoxContainer.new()
	var line := ColorRect.new()
	line.color = ACCENT_DIM
	line.custom_minimum_size = Vector2(0, 1)
	box.add_child(line)
	return box


func _card(title_text: String, icon: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = BG_PANEL
	style.border_color = ACCENT_DIM
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)
	var title := Label.new()
	title.text = "%s  %s" % [icon, title_text]
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", ACCENT)
	content.add_child(title)
	var sep := ColorRect.new()
	sep.color = Color(ACCENT_DIM.r, ACCENT_DIM.g, ACCENT_DIM.b, 0.6)
	sep.custom_minimum_size = Vector2(0, 1)
	content.add_child(sep)
	return panel


# --- Styled controls --------------------------------------------------------

func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _primary_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 56)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color("04141c"))
	button.add_theme_color_override("font_hover_color", Color("04141c"))
	button.add_theme_color_override("font_pressed_color", Color("04141c"))
	button.add_theme_stylebox_override("normal", _button_style(ACCENT, ACCENT))
	button.add_theme_stylebox_override("hover", _button_style(Color("aed9c9"), Color("aed9c9")))
	button.add_theme_stylebox_override("pressed", _button_style(Color("73ad9d"), Color("73ad9d")))
	button.add_theme_stylebox_override("focus", _button_style(ACCENT, Color("f0fbff")))
	return button


func _secondary_button(text: String, accent: Color = ACCENT) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 46)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", accent)
	button.add_theme_color_override("font_hover_color", Color("f0fbff"))
	var dim_border := Color(accent.r, accent.g, accent.b, 0.5)
	button.add_theme_stylebox_override("normal", _button_style(Color(0, 0, 0, 0.2), dim_border))
	button.add_theme_stylebox_override("hover", _button_style(Color(accent.r, accent.g, accent.b, 0.16), accent))
	button.add_theme_stylebox_override("pressed", _button_style(Color(accent.r, accent.g, accent.b, 0.3), accent))
	button.add_theme_stylebox_override("focus", _button_style(Color(0, 0, 0, 0.2), Color("f0fbff")))
	return button


## Bouton non-cliquable pour une fonctionnalite pas encore disponible
## (ex. multijoueur). Style attenue, sans etats hover/pressed.
func _disabled_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = true
	button.custom_minimum_size = Vector2(0, 46)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_disabled_color", Color("4c6875"))
	button.add_theme_stylebox_override("disabled", _button_style(Color(0, 0, 0, 0.15), Color(0.15, 0.24, 0.29, 0.5)))
	return button


func _styled_line_edit(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 48)
	edit.add_theme_font_size_override("font_size", 15)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.35)
	style.border_color = ACCENT_DIM
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	edit.add_theme_stylebox_override("normal", style)
	var focus_style := style.duplicate()
	focus_style.border_color = ACCENT
	edit.add_theme_stylebox_override("focus", focus_style)
	return edit


func _styled_item_list() -> ItemList:
	var list := ItemList.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.3)
	style.border_color = ACCENT_DIM
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_top = 6
	list.add_theme_stylebox_override("panel", style)
	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.22)
	selected_style.set_corner_radius_all(3)
	list.add_theme_stylebox_override("selected", selected_style)
	list.add_theme_stylebox_override("selected_focus", selected_style)
	return list


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


func _dev_menu_screenshot() -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("BACKBONE_MENU_SCREENSHOT"))
	get_tree().quit()
