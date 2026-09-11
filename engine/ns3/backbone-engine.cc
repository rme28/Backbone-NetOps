// Moteur dynamique Backbone NetOps. Lit un scenario TSV genere par le pont Python.
#include "ns3/bridge-module.h"
#include "ns3/core-module.h"
#include "ns3/csma-module.h"
#include "ns3/internet-apps-module.h"
#include "ns3/internet-module.h"
#include "ns3/network-module.h"

#include <fstream>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

using namespace ns3;

struct InterfaceConfig { std::string address; bool up{false}; };
struct RouteConfig { std::string network; std::string nextHop; };
struct Device {
    std::string category;
    Ptr<Node> node;
    std::map<std::string, InterfaceConfig> interfaces;
    std::map<std::string, Ptr<NetDevice>> ports;
    std::vector<RouteConfig> routes;
};
struct Link { std::string a, ifA, b, ifB; };

static uint32_t replies = 0;
static void OnReply(uint16_t seq, Time rtt) {
    ++replies;
}
static std::vector<std::string> Split(const std::string& line) {
    std::vector<std::string> values;
    std::stringstream stream(line);
    std::string value;
    while (std::getline(stream, value, '\t')) values.push_back(value);
    return values;
}
static std::pair<std::string, uint32_t> Cidr(const std::string& value) {
    auto slash = value.find('/');
    if (slash == std::string::npos) return {value, 32};
    return {value.substr(0, slash), static_cast<uint32_t>(std::stoul(value.substr(slash + 1)))};
}
static Ipv4Mask Mask(uint32_t prefix) {
    return Ipv4Mask(prefix == 0 ? 0 : (0xffffffffu << (32 - prefix)));
}
static uint32_t FindOutputInterface(Ptr<Ipv4> ipv4, Ipv4Address nextHop) {
    for (uint32_t index = 1; index < ipv4->GetNInterfaces(); ++index) {
        for (uint32_t a = 0; a < ipv4->GetNAddresses(index); ++a) {
            auto local = ipv4->GetAddress(index, a);
            if (local.GetLocal().CombineMask(local.GetMask()) == nextHop.CombineMask(local.GetMask())) return index;
        }
    }
    return 0;
}

int main(int argc, char** argv) {
    std::string scenario;
    CommandLine cmd(__FILE__);
    cmd.AddValue("scenario", "Fichier TSV de topologie", scenario);
    cmd.Parse(argc, argv);
    if (scenario.empty()) { std::cerr << "ERROR: scenario missing\n"; return 2; }

    std::map<std::string, Device> devices;
    std::vector<Link> links;
    std::string pingSource, pingDestination, line;
    std::ifstream input(scenario);
    while (std::getline(input, line)) {
        auto v = Split(line);
        if (v.empty() || v[0].empty()) continue;
        if (v[0] == "DEVICE" && v.size() >= 3) devices[v[1]].category = v[2];
        else if (v[0] == "IFACE" && v.size() >= 5) devices[v[1]].interfaces[v[2]] = {v[3], v[4] == "up"};
        else if (v[0] == "LINK" && v.size() >= 5) links.push_back({v[1], v[2], v[3], v[4]});
        else if (v[0] == "ROUTE" && v.size() >= 4) devices[v[1]].routes.push_back({v[2], v[3]});
        else if (v[0] == "PING" && v.size() >= 3) { pingSource = v[1]; pingDestination = v[2]; }
    }
    if (!devices.count(pingSource)) { std::cerr << "ERROR: unknown source " << pingSource << "\n"; return 2; }

    NodeContainer allNodes;
    for (auto& [name, device] : devices) { device.node = CreateObject<Node>(); allNodes.Add(device.node); }
    InternetStackHelper().Install(allNodes);

    CsmaHelper ethernet;
    ethernet.SetChannelAttribute("DataRate", StringValue("1Gbps"));
    ethernet.SetChannelAttribute("Delay", TimeValue(MilliSeconds(1)));
    for (const auto& link : links) {
        if (!devices.count(link.a) || !devices.count(link.b)) continue;
        auto ends = ethernet.Install(NodeContainer(devices[link.a].node, devices[link.b].node));
        devices[link.a].ports[link.ifA] = ends.Get(0);
        devices[link.b].ports[link.ifB] = ends.Get(1);
    }

    for (auto& [name, device] : devices) {
        if (device.category == "switch" || device.category == "access_point") {
            NetDeviceContainer ports;
            for (auto& [iface, port] : device.ports) {
                if (device.interfaces.count(iface) && device.interfaces[iface].up) ports.Add(port);
            }
            if (ports.GetN() >= 2) BridgeHelper().Install(device.node, ports);
            continue;
        }
        auto ipv4 = device.node->GetObject<Ipv4>();
        for (auto& [iface, config] : device.interfaces) {
            if (!device.ports.count(iface) || config.address.empty()) continue;
            auto parsed = Cidr(config.address);
            uint32_t index = ipv4->AddInterface(device.ports[iface]);
            ipv4->AddAddress(index, Ipv4InterfaceAddress(Ipv4Address(parsed.first.c_str()), Mask(parsed.second)));
            if (config.up) ipv4->SetUp(index); else ipv4->SetDown(index);
        }
    }

    Ipv4StaticRoutingHelper routingHelper;
    for (auto& [name, device] : devices) {
        if (device.category == "switch") continue;
        auto ipv4 = device.node->GetObject<Ipv4>();
        auto routing = routingHelper.GetStaticRouting(ipv4);
        for (const auto& route : device.routes) {
            auto network = Cidr(route.network);
            Ipv4Address nextHop(route.nextHop.c_str());
            uint32_t output = FindOutputInterface(ipv4, nextHop);
            if (output == 0) { std::cout << "% Route ignored on " << name << ": next-hop unreachable\n"; continue; }
            if (network.second == 0) routing->SetDefaultRoute(nextHop, output);
            else routing->AddNetworkRouteTo(Ipv4Address(network.first.c_str()), Mask(network.second), nextHop, output);
        }
    }

    std::cout << "PING " << pingDestination << " from " << pingSource << "\n";
    PingHelper ping{Ipv4Address(pingDestination.c_str())};
    ping.SetAttribute("Count", UintegerValue(4));
    ping.SetAttribute("Interval", TimeValue(Seconds(1)));
    auto app = ping.Install(devices[pingSource].node);
    app.Get(0)->TraceConnectWithoutContext("Rtt", MakeCallback(&OnReply));
    app.Start(Seconds(1)); app.Stop(Seconds(7));
    Simulator::Run(); Simulator::Destroy();
    std::cout << "Resultat : " << replies << "/4 - " << (replies == 4 ? "PING REUSSI" : "PING ECHEC") << "\n";
    return 0;
}
