import NetworkExtension
import Tun2SocksKit
import os

/// Green VPN iOS packet tunnel — mirrors the Android app's hev-socks5-tunnel path:
/// device packets -> this NEPacketTunnelProvider -> hev (Tun2SocksKit) -> SOCKS5
/// proxy at the relay (the location's socks_port) -> exit. The SOCKS5 host/port/
/// creds are passed from the Flutter app via the tunnel provider protocol.
class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = OSLog(subsystem: "com.oscar.greenvpn.PacketTunnel", category: "tunnel")

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // Config comes from the app through the provider protocol's providerConfiguration.
        let proto = self.protocolConfiguration as? NETunnelProviderProtocol
        let conf = proto?.providerConfiguration ?? [:]
        let host = (conf["host"] as? String) ?? (options?["host"] as? String) ?? ""
        let port = (conf["port"] as? Int) ?? (conf["port"] as? NSNumber)?.intValue ?? 0
        let user = (conf["username"] as? String) ?? ""
        let pass = (conf["password"] as? String) ?? ""

        os_log("startTunnel host=%{public}@ port=%d", log: log, type: .info, host, port)

        // 1. Virtual interface settings — route everything through the tunnel,
        //    BUT exclude the SOCKS5 relay's own IP so hev's connection out to the
        //    relay uses the real Wi-Fi/cellular interface instead of looping back
        //    into this tunnel (the iOS equivalent of Android's
        //    addDisallowedApplication(self)). Without this the tunnel comes up but
        //    no traffic ever flows.
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: host)
        let ipv4 = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        if isIPv4(host) {
            ipv4.excludedRoutes = [NEIPv4Route(destinationAddress: host,
                                               subnetMask: "255.255.255.255")]
        }
        settings.ipv4Settings = ipv4
        let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        settings.mtu = 1500

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                os_log("setTunnelNetworkSettings failed: %{public}@", log: self.log, type: .error, error.localizedDescription)
                completionHandler(error)
                return
            }

            // 2. hev-socks5-tunnel config (same shape as the Android tun2socks.yml).
            let yaml = """
            tunnel:
              mtu: 1500
            socks5:
              port: \(port)
              address: \(host)
              udp: 'udp'
              username: '\(user)'
              password: '\(pass)'
            misc:
              task-stack-size: 20480
              connect-timeout: 5000
              read-write-timeout: 60000
              log-level: warn
            """

            // 3. Start hev on the tunnel's file descriptor.
            Socks5Tunnel.run(withConfig: .string(content: yaml)) { code in
                os_log("Socks5Tunnel exited code=%d", log: self.log, type: .info, code)
            }
            completionHandler(nil)
        }
    }

    /// True if `s` is a plain IPv4 literal (so we can exclude it from the tunnel).
    private func isIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0).map { $0 >= 0 && $0 <= 255 } ?? false }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        os_log("stopTunnel reason=%d", log: log, type: .info, reason.rawValue)
        Socks5Tunnel.quit()
        completionHandler()
    }
}
