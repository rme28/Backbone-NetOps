extends RefCounted
## Shared application theme. Local overrides are reserved for contextual accents.
static var shared: Theme
static func get_theme() -> Theme:
	if shared != null: return shared
	shared = Theme.new()
	shared.default_font_size = 15
	for kind in ["Label", "Button", "LineEdit", "CheckButton", "ItemList", "RichTextLabel"]:
		shared.set_color("font_color", kind, Color("dfebe5"))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := panel(Color("172b31"), Color("36545a"))
		if state == "hover": style.bg_color = Color("26454a")
		if state == "pressed": style.bg_color = Color("365e61")
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = Color("8bc6b5")
		shared.set_stylebox(state,"Button",style)
		shared.set_color("font_" + state + "_color","Button",Color("dfebe5"))
	shared.set_stylebox("panel","PanelContainer",panel(Color("102229"),Color("36545a")))
	shared.set_stylebox("normal","LineEdit",panel(Color("09171e"),Color("36545a")))
	shared.set_stylebox("focus","LineEdit",panel(Color("09171e"),Color("8bc6b5")))
	shared.set_color("caret_color","LineEdit",Color("8bc6b5"))
	shared.set_color("selection_color","LineEdit",Color("365e61"))
	shared.set_constant("outline_size","Label",0)
	return shared

static func panel(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func apply(root: Node) -> void:
	if root is Control: root.theme = get_theme()
	for child in root.get_children(): apply(child)
