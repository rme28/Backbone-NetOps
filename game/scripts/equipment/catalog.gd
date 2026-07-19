class_name EquipmentCatalog
extends RefCounted
## Charge le catalogue d'equipements posables depuis resources/equipment/devices.json.
## Pour ajouter un nouveau materiel : ajouter une entree au JSON (id, label, pt_model),
## et si besoin son cablage dans scripts/network/interfaces.gd. Aucun code a toucher
## ailleurs pour un materiel deja gere par PTBuilder (modeles valides : voir bridge/README.md).

const PATH := "res://resources/equipment/devices.json"


static func load_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("[equipment] catalogue introuvable : %s" % PATH)
		return out
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) == TYPE_ARRAY:
		for entry in data:
			if typeof(entry) == TYPE_DICTIONARY:
				out.append(entry)
	return out
