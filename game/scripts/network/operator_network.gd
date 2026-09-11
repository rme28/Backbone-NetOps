extends RefCounted
## Tiny simulated operator. Documentation-only IPv4 ranges; no real network IO.
const SERVICE_IP := "198.51.100.10"
const GATEWAY_IP := "203.0.113.1"

static func configs() -> Dictionary:
	return {
		"ISP-GATEWAY":{"category":"router","interfaces":{
			"handoff":{"address":GATEWAY_IP+"/24","shutdown":false},
			"core":{"address":"198.51.100.1/24","shutdown":false}},
			"dhcp_pools":[{"network":"203.0.113.0/24","gateway":GATEWAY_IP}]},
		"INTERNET-TEST":{"category":"server","interfaces":{"eth0":{"address":SERVICE_IP+"/24","shutdown":false}},"default_gateway":"198.51.100.1"}}

static func links() -> Array:
	return [{"dev1":"WAN-ONT","iface1":"uplink","dev2":"ISP-GATEWAY","iface2":"handoff"},
		{"dev1":"ISP-GATEWAY","iface1":"core","dev2":"INTERNET-TEST","iface2":"eth0"}]
