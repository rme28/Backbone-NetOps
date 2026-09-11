class_name DeviceInterfaces
extends RefCounted
## Table des interfaces disponibles par categorie d'equipement, pour le cablage
## automatique (le jeu choisit la premiere interface libre de chaque cote, pas
## de selection manuelle d'interface pour rester simple). A completer si un
## nouveau modele de materiel est ajoute au catalogue (voir scripts/equipment/catalog.gd).

const BY_CATEGORY := {
	"wan": ["client"],
	"passive": ["wall", "patch"],
	"router": ["eth0", "eth1", "eth2"],
	"switch": ["eth0", "eth1", "eth2", "eth3", "eth4", "eth5"],
	"switch_l3": ["eth0", "eth1", "eth2", "eth3", "eth4", "eth5", "eth6", "eth7"],
	"wireless_router": ["eth0", "eth1", "eth2", "eth3"],
	"firewall": ["eth0", "eth1", "eth2", "eth3"],
	"access_point": ["eth0", "eth1"],
	"nas": ["eth0", "eth1"],
	"server": ["eth0", "eth1", "eth2", "eth3"],
	"pc": ["eth0"],
	"client_laptop": ["eth0"],
}


## Premiere interface non utilisee pour cette categorie, ou "" si toutes sont prises.
static func next_free(category: String, used: Array) -> String:
	var all: Array = BY_CATEGORY.get(category, [])
	for iface in all:
		if not (iface in used):
			return iface
	return ""
