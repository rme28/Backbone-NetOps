extends Control
## Menu principal : Nouvelle partie / Charger / Quitter.
## Construit entierement par code (aucune manip souris dans l'editeur).

const GAME_SCENE := "res://scenes/world/server_room.tscn"

var _name_edit: LineEdit
var _saves_list: ItemList
var _feedback: Label


func _ready() -> void:
	# Toujours rendre la souris visible dans le menu (au cas ou on arrive depuis le jeu).
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.10, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	vbox.add_theme_constant_override("separation", 10)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "BACKBONE NETOPS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Le simulateur ultime d'ingenieur reseau"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.6, 0.65, 0.7)
	vbox.add_child(subtitle)

	vbox.add_child(_spacer(16))

	# --- Nouvelle partie ---
	var new_label := Label.new()
	new_label.text = "Nouvelle partie"
	vbox.add_child(new_label)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Nom de la partie"
	vbox.add_child(_name_edit)

	var new_btn := Button.new()
	new_btn.text = "Demarrer une nouvelle partie"
	new_btn.pressed.connect(_on_new_game)
	vbox.add_child(new_btn)

	vbox.add_child(_spacer(16))

	# --- Charger ---
	var load_label := Label.new()
	load_label.text = "Charger une partie"
	vbox.add_child(load_label)

	_saves_list = ItemList.new()
	_saves_list.custom_minimum_size = Vector2(0, 140)
	_saves_list.item_activated.connect(_on_save_activated)
	vbox.add_child(_saves_list)

	var load_row := HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 8)
	vbox.add_child(load_row)

	var load_btn := Button.new()
	load_btn.text = "Charger"
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_btn.pressed.connect(_on_load_selected)
	load_row.add_child(load_btn)

	var delete_btn := Button.new()
	delete_btn.text = "Supprimer"
	delete_btn.pressed.connect(_on_delete_selected)
	load_row.add_child(delete_btn)

	vbox.add_child(_spacer(16))

	# --- Quitter ---
	var quit_btn := Button.new()
	quit_btn.text = "Quitter"
	quit_btn.pressed.connect(func(): get_tree().quit())
	vbox.add_child(quit_btn)

	_feedback = Label.new()
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.modulate = Color(0.95, 0.4, 0.4)
	vbox.add_child(_feedback)

	_refresh_saves()


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _refresh_saves() -> void:
	_saves_list.clear()
	for save in GameState.list_saves():
		_saves_list.add_item(save)


func _on_new_game() -> void:
	var game_name := _name_edit.text.strip_edges()
	if game_name.is_empty():
		game_name = "Partie %s" % Time.get_datetime_string_from_system().replace(":", "-")
	if game_name in GameState.list_saves():
		_feedback.text = "Une partie nommee \"%s\" existe deja." % game_name
		return
	GameState.new_game(game_name)
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_load_selected() -> void:
	var selected := _saves_list.get_selected_items()
	if selected.is_empty():
		_feedback.text = "Selectionne une partie a charger."
		return
	_load(_saves_list.get_item_text(selected[0]))


func _on_save_activated(index: int) -> void:
	_load(_saves_list.get_item_text(index))


func _load(save: String) -> void:
	if not GameState.load_from(save):
		_feedback.text = "Impossible de charger \"%s\"." % save
		return
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_delete_selected() -> void:
	var selected := _saves_list.get_selected_items()
	if selected.is_empty():
		return
	GameState.delete_save(_saves_list.get_item_text(selected[0]))
	_refresh_saves()
