// Prototype Backbone NetOps : PC1 -- R1 -- R2 -- PC2.
#include "ns3/core-module.h"
#include "ns3/internet-apps-module.h"
#include "ns3/internet-module.h"
#include "ns3/network-module.h"
#include "ns3/point-to-point-module.h"
#include <iostream>
using namespace ns3;

static uint32_t replies = 0;
static void OnReply(uint16_t seq, Time rtt) {
    ++replies;
    std::cout << "Reponse " << seq << " : " << rtt.GetMilliSeconds() << " ms\n";
}
static NetDeviceContainer Connect(Ptr<Node> a, Ptr<Node> b) {
    PointToPointHelper link;
    link.SetDeviceAttribute("DataRate", StringValue("1Gbps"));
    link.SetChannelAttribute("Delay", StringValue("2ms"));
    return link.Install(a, b);
}

int main(int argc, char** argv) {
    bool configureRoutes = true;
    CommandLine cmd(__FILE__);
    cmd.AddValue("configureRoutes", "Ajoute les routes statiques", configureRoutes);
    cmd.Parse(argc, argv);

    NodeContainer n;
    n.Create(4);
    InternetStackHelper().Install(n);
    auto d1 = Connect(n.Get(0), n.Get(1));
    auto d2 = Connect(n.Get(1), n.Get(2));
    auto d3 = Connect(n.Get(2), n.Get(3));
    Ipv4AddressHelper ip;
    ip.SetBase("10.0.1.0", "255.255.255.0"); auto a1 = ip.Assign(d1);
    ip.SetBase("10.0.2.0", "255.255.255.0"); auto a2 = ip.Assign(d2);
    ip.SetBase("10.0.3.0", "255.255.255.0"); auto a3 = ip.Assign(d3);

    std::cout << "PC1 " << a1.GetAddress(0) << " -- R1 " << a1.GetAddress(1)
              << " / " << a2.GetAddress(0) << " -- R2 " << a2.GetAddress(1)
              << " / " << a3.GetAddress(0) << " -- PC2 " << a3.GetAddress(1) << "\n";
    if (configureRoutes) {
        Ipv4StaticRoutingHelper h;
        h.GetStaticRouting(n.Get(0)->GetObject<Ipv4>())->SetDefaultRoute(a1.GetAddress(1), 1);
        h.GetStaticRouting(n.Get(1)->GetObject<Ipv4>())->AddNetworkRouteTo(
            Ipv4Address("10.0.3.0"), Ipv4Mask("255.255.255.0"), a2.GetAddress(1), 2);
        h.GetStaticRouting(n.Get(2)->GetObject<Ipv4>())->AddNetworkRouteTo(
            Ipv4Address("10.0.1.0"), Ipv4Mask("255.255.255.0"), a2.GetAddress(0), 1);
        h.GetStaticRouting(n.Get(3)->GetObject<Ipv4>())->SetDefaultRoute(a3.GetAddress(0), 1);
        std::cout << "Routes statiques : configurees\n";
    } else std::cout << "Routes statiques : absentes\n";

    PingHelper ping(a3.GetAddress(1));
    ping.SetAttribute("Count", UintegerValue(4));
    auto app = ping.Install(n.Get(0));
    app.Get(0)->TraceConnectWithoutContext("Rtt", MakeCallback(&OnReply));
    app.Start(Seconds(1)); app.Stop(Seconds(7));
    Simulator::Run(); Simulator::Destroy();
    std::cout << "Resultat : " << replies << "/4 - "
              << (replies == 4 ? "PING REUSSI" : "PING ECHEC") << "\n";
    return 0;
}
