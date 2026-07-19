class_name DeviceInterfaces
extends RefCounted
## Table des interfaces disponibles par categorie d'equipement, pour le cablage
## automatique (le jeu choisit la premiere interface libre de chaque cote, pas
## de selection manuelle d'interface pour rester simple). A completer si un
## nouveau modele de materiel est ajoute au catalogue (voir scripts/equipment/catalog.gd).

const BY_CATEGORY := {
	"router": ["GigabitEthernet0/0", "GigabitEthernet0/1", "GigabitEthernet0/2"],
	"switch": ["GigabitEthernet0/1", "GigabitEthernet0/2", "GigabitEthernet0/3", "GigabitEthernet0/4", "GigabitEthernet0/5"],
	"pc": ["FastEthernet0"],
}


## Premiere interface non utilisee pour cette categorie, ou "" si toutes sont prises.
static func next_free(category: String, used: Array) -> String:
	var all: Array = BY_CATEGORY.get(category, [])
	for iface in all:
		if not (iface in used):
			return iface
	return ""
