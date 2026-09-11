extends CanvasLayer
signal closed
var service: RefCounted
var device := ""
var content: VBoxContainer
var title: Label
var clock_label: Label
var app := ""

func _ready() -> void:
	layer = 12
	var background := ColorRect.new()
	background.color = Color("10272f")
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,40)
	var root := VBoxContainer.new()
	margin.add_child(root)
	root.add_theme_constant_override("separation",24)
	var header := HBoxContainer.new()
	root.add_child(header)
	title = Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size",26)
	header.add_child(title)
	clock_label = Label.new()
	header.add_child(clock_label)
	button(header,"Quitter le PC",func(): closed.emit())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",30)
	root.add_child(body)
	var dock := VBoxContainer.new()
	dock.custom_minimum_size.x = 215
	body.add_child(dock)
	for item in ["Bureau","Réseau","Terminal","Navigateur","Informations système"]:
		button(dock,item,show_app.bind(item))
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",18)
	scroll.add_child(content)
	preload("res://scripts/ui/design_system.gd").apply(background)
	preload("res://scripts/ui/design_system.gd").apply(margin)
	visible = false

func _process(_delta: float) -> void:
	if visible: clock_label.text = Time.get_time_string_from_system().left(5)+"   "

func open_device(name_: String) -> void:
	device = name_
	title.text = "BACKBONE DESKTOP  /  "+device
	visible = true
	show_app("Bureau")

func button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(l)
	return l

func field(text: String, value: String) -> LineEdit:
	label(text)
	var edit := LineEdit.new()
	edit.text = value
	content.add_child(edit)
	return edit

func show_app(selected: String) -> void:
	app = selected
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	label(selected.to_upper()).add_theme_font_size_override("font_size",24)
	match selected:
		"Réseau": network_app()
		"Terminal": terminal_app()
		"Navigateur":
			label("Test de services du réseau simulé")
			var url := field("Adresse","https://connectivity.backbone.test")
			var result := label("")
			button(content,"Ouvrir",func(): result.text = service.browse(device,url.text))
		"Informations système": label("Backbone Desktop\nMachine : "+device+"\n"+service.network_info(device))
		_: label("Votre poste de travail\n\nConfigurez Ethernet dans Réseau, puis vérifiez une destination depuis le terminal ou le navigateur.")

func network_app() -> void:
	label(service.network_info(device))
	var config: Dictionary = service.configs[device]
	var selector := OptionButton.new()
	for name_ in config.interfaces: selector.add_item(name_)
	content.add_child(selector)
	var mode := CheckButton.new()
	mode.text = "Configuration automatique (DHCP)"
	content.add_child(mode)
	var address := field("Adresse IPv4","")
	var prefix := field("Préfixe CIDR","")
	var gateway := field("Passerelle","")
	var load_interface := func(_index: int):
		var cidr: String = config.interfaces[selector.get_item_text(selector.selected)].get("address","")
		mode.button_pressed = cidr == "dhcp"
		address.text = "" if cidr == "dhcp" else cidr.get_slice("/",0)
		prefix.text = cidr.get_slice("/",1) if "/" in cidr else "24"
		gateway.text = config.get("default_gateway","")
		for edit in [address,prefix,gateway]: edit.editable = not mode.button_pressed
	selector.item_selected.connect(load_interface)
	mode.toggled.connect(func(active):
		for edit in [address,prefix,gateway]: edit.editable = not active
	)
	load_interface.call(0)
	var status := label("")
	button(content,"Appliquer",func():
		status.text = service.configure(device,selector.get_item_text(selector.selected),mode.button_pressed,address.text.strip_edges(),prefix.text.strip_edges(),gateway.text.strip_edges())+"\n"+service.network_info(device)
	)

func terminal_app() -> void:
	var output := RichTextLabel.new()
	output.custom_minimum_size.y = 300
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.scroll_following = true
	output.text = "Backbone Desktop Terminal\nSaisir help pour les commandes.\n"
	content.add_child(output)
	var input := LineEdit.new()
	input.placeholder_text = device+" $"
	content.add_child(input)
	input.text_submitted.connect(func(command):
		if command.strip_edges() == "clear": output.text = ""
		else: output.append_text("\n$ "+command+"\n"+service.command(device,command)+"\n")
		input.clear()
	)
	input.grab_focus()
