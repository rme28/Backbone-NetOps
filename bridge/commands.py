"""
Traduction des commandes de haut niveau (JSON envoyé par le jeu) en code JS
PTBuilder. Pour ajouter une nouvelle action : ajouter un cas ici, et côté jeu
un appel correspondant dans scripts/network/bridge_client.gd.
"""

from packettracer import js_string


def build_action_code(cmd):
    """Traduit une commande de haut niveau en code JS PTBuilder qui pose `result`."""
    action = cmd.get("action")

    if action == "addDevice":
        return "addDevice({name},{model},{x},{y}); result=true;".format(
            name=js_string(cmd["name"]),
            model=js_string(cmd["model"]),
            x=js_string(cmd.get("x", 0)),
            y=js_string(cmd.get("y", 0)),
        )

    if action == "addLink":
        return "addLink({d1},{i1},{d2},{i2},{cable}); result=true;".format(
            d1=js_string(cmd["dev1"]), i1=js_string(cmd["iface1"]),
            d2=js_string(cmd["dev2"]), i2=js_string(cmd["iface2"]),
            cable=js_string(cmd.get("cable", "straight")),
        )

    if action == "configureIos":
        ios = "\n".join(cmd["commands"])
        return "configureIosDevice({name},{ios}); result=true;".format(
            name=js_string(cmd["name"]), ios=js_string(ios),
        )

    if action == "configurePcIp":
        return "configurePcIp({name},{dhcp},{ip},{mask},{gw}); result=true;".format(
            name=js_string(cmd["name"]), dhcp=js_string(cmd.get("dhcp", False)),
            ip=js_string(cmd.get("ip", "")), mask=js_string(cmd.get("mask", "")),
            gw=js_string(cmd.get("gateway", "")),
        )

    if action == "getDevices":
        return "result = getDevices();"

    if action == "getDeviceCatalog":
        # Catalogue complet des modeles PT, groupes par categorie : {"router": ["2911", ...], ...}.
        # Calcule a la volee depuis les objets globaux deviceTypes (categorie -> id) et
        # allDeviceTypes (modele -> id de categorie), plutot que maintenu a la main cote jeu.
        return (
            "var idToName={};for(var k in deviceTypes){idToName[deviceTypes[k]]=k;}"
            "var byCat={};"
            "for(var model in allDeviceTypes){"
            "var cat=idToName[allDeviceTypes[model]]||String(allDeviceTypes[model]);"
            "if(!byCat[cat])byCat[cat]=[];"
            "byCat[cat].push(model);"
            "}"
            "result=byCat;"
        )

    if action == "clearTopology":
        # Vide le canvas PT (équivalent File > New). L'argument false = ne pas
        # demander de sauvegarder. Validé empiriquement sur PT 9.0.0.
        return "ipc.appWindow().fileNew(false); result = true;"

    if action == "raw":
        # Échappatoire : code JS PTBuilder brut fourni tel quel (doit poser `result`).
        return cmd["code"]

    raise ValueError("action inconnue: {}".format(action))
