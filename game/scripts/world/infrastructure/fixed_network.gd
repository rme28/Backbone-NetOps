extends RefCounted
## Fixed building cabling. Each labelled socket is one independent passive run
## between the wall and the matching patch-panel jack, never a shared switch.
var room: Node3D
var count := 0
var directions: Dictionary = {}
var fixed: Dictionary = {}

func _init(host: Node3D) -> void:
	room = host

func outlet(pos: Vector3, yaw: float) -> void:
	if count == 0:
		var panel := Node3D.new()
		room.add_child(panel)
		panel.position = Vector3(-8.8625,1.34,-9.89)
		room._equipment_art.chassis(panel,Vector3.ZERO,Vector3(0.30,0.24,0.02),room._material(Color("273b43")),0.005)
		room._equipment_art.text(panel,"BRASSAGE / CAT 6",Vector3(0,0.1,0.012),0.00035)
	var plate := Node3D.new()
	room.add_child(plate)
	plate.position = pos
	plate.rotation.y = yaw
	room._equipment_art.chassis(plate,Vector3.ZERO,Vector3(0.086,0.086,0.008),room._material(Color("c7ceca")),0.002)
	for x in [-0.021,0.021]:
		count += 1
		var device := "PRISE-%02d" % count
		fixed[device] = true
		room._device_categories[device] = "passive"
		room._device_configs[device] = {"hostname":device,"category":"passive","interfaces":{"wall":{"shutdown":false},"patch":{"shutdown":false}}}
		port(plate,Vector3(x,0,0.006),device,"wall",str(count))
		var patch := Node3D.new()
		room.add_child(patch)
		patch.position = Vector3(-8.95 + ((count-1)%6)*0.035, 1.3 + ((count-1)/6)*0.08, -9.87)
		room._equipment_art.chassis(patch,Vector3(0,0,-0.005),Vector3(0.035,0.065,0.025),room._material(Color("273b43")),0.002)
		port(patch,Vector3(0,0,0.013),device,"patch",str(count))

func port(parent: Node3D, pos: Vector3, device: String, iface: String, label: String) -> void:
	var jack := StaticBody3D.new()
	parent.add_child(jack)
	jack.position = pos
	jack.set_meta("device_name",device)
	jack.set_meta("interface_name",iface)
	room._equipment_art.jack(jack)
	room._equipment_art.text(jack,label,Vector3(0,0.017,0.007),0.00025)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.023,0.025,0.02)
	col.shape = shape
	jack.add_child(col)
	var key := device+"|"+iface
	room._interface_positions[key] = jack.global_position
	directions[key] = jack.global_basis.z

func wan() -> void:
	var device := "WAN-ONT"
	fixed[device] = true
	room._device_categories[device] = "wan"
	room._device_configs[device] = {"category":"passive","hostname":device,"interfaces":{"client":{"shutdown":false},"uplink":{"shutdown":false}}}
	var body := StaticBody3D.new()
	room.add_child(body)
	body.position = Vector3(-14.285,1.35,12)
	body.rotation.y = PI/2
	body.set_meta("device_name",device)
	room._equipment_art.chassis(body,Vector3(0,0,0.045),Vector3(0.28,0.20,0.09),room._material(Color("c7ceca")),0.009)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.28,0.20,0.09)
	col.shape = shape
	col.position.z = 0.045
	body.add_child(col)
	port(body,Vector3(0,-0.035,0.099),device,"client","LAN")
	room._equipment_art.text(body,"ONT / FIBRE",Vector3(0,0.055,0.099),0.00045)
	room._add_signage(Vector3(-14.28,1.76,12),"DHCP / 203.0.113.0/24",Color("bfe4df"),PI/2)
	room._equipment_art.batch(body)
