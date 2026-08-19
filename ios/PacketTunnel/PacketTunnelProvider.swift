import NetworkExtension
import Tun2SocksKit
import Network
import os

/// Green VPN iOS packet tunnel — mirrors the Android app's hev-socks5-tunnel path:
/// device packets -> this NEPacketTunnelProvider -> hev (Tun2SocksKit) -> SOCKS5
/// proxy at the relay (the location's socks_port) -> exit.
///
/// NOTE: diagnostics are logged at `.error` level with a "GVPNDBG" prefix so they
/// are visible in the plain device syslog (idevicesyslog); `.info`/`.debug` are
/// suppressed there. Grep the syslog for GVPNDBG to trace a connection.
class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = OSLog(subsystem: "com.oscar.greenvpn.PacketTunnel", category: "tunnel")
    private var probe: NWConnection?

    private func dbg(_ msg: String) {
        os_log("GVPNDBG %{public}@", log: log, type: .error, msg)
    }

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let proto = self.protocolConfiguration as? NETunnelProviderProtocol
        let conf = proto?.providerConfiguration ?? [:]
        let host = (conf["host"] as? String) ?? (options?["host"] as? String) ?? ""
        let port = (conf["port"] as? Int) ?? (conf["port"] as? NSNumber)?.intValue ?? 0
        let user = (conf["username"] as? String) ?? ""
        let pass = (conf["password"] as? String) ?? ""

        dbg("startTunnel host=\(host) port=\(port) user=\(user) passLen=\(pass.count)")

        // 1. Virtual interface: route everything through the tunnel, but exclude the
        //    relay IP so hev's own connection out to it uses the real interface
        //    (iOS equivalent of Android addDisallowedApplication(self)).
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: host.isEmpty ? "127.0.0.1" : host)
        let ipv4 = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        if isIPv4(host) {
            ipv4.excludedRoutes = [NEIPv4Route(destinationAddress: host, subnetMask: "255.255.255.255")]
            dbg("excludedRoute added for relay \(host)/32")
        }
        settings.ipv4Settings = ipv4
        // DNS points at hev's built-in mapdns listener (172.19.0.2). mapdns
        // answers queries locally with fake IPs and resolves the real domain
        // server-side over the SOCKS5 TCP connection — so DNS never has to travel
        // as UDP through the proxy. That UDP-through-proxy path works for the
        // direct Singapore exit but FAILS for the chained (uid-routed) locations,
        // which is why only Singapore had data before. Same as the Android app.
        let dns = NEDNSSettings(servers: ["172.19.0.2"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        // 8500 matches the Android app — a large tun MTU means iOS hands hev
        // fewer, bigger packets, which drastically cuts per-packet overhead and
        // raises throughput (1500 was a debugging value and throttled speed).
        settings.mtu = 8500

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.dbg("setTunnelNetworkSettings FAILED: \(error.localizedDescription)")
                completionHandler(error)
                return
            }
            self.dbg("setTunnelNetworkSettings OK")

            // 2. Probe: can we reach the relay's SOCKS port directly (outside the
            //    tunnel)? This isolates a routing/loop problem from a hev problem.
            self.runRelayProbe(host: host, port: port)

            // 3. hev-socks5-tunnel config (same shape as Android's tun2socks.yml).
            let yaml = """
            tunnel:
              mtu: 8500
              ipv4: 172.19.0.1
            socks5:
              port: \(port)
              address: \(host)
              udp: 'udp'
              username: '\(user)'
              password: '\(pass)'
            mapdns:
              address: 172.19.0.2
              port: 53
              network: 100.64.0.0
              netmask: 255.192.0.0
              cache-size: 10000
            misc:
              task-stack-size: 81920
              log-level: warn
            """
            self.dbg("starting hev...")
            Socks5Tunnel.run(withConfig: .string(content: yaml)) { code in
                self.dbg("hev EXITED code=\(code)")
            }
            completionHandler(nil)

            // 4. After 10s, report how many bytes hev moved (0 = nothing flowing).
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                let s = Socks5Tunnel.stats
                self.dbg("hev stats after 10s: up=\(s.up.bytes)B/\(s.up.packets)p down=\(s.down.bytes)B/\(s.down.packets)p")
            }
        }
    }

    /// Direct TCP probe to the relay SOCKS port. connected = routing is fine and the
    /// problem (if any) is inside hev; failed/timeout = the tunnel is swallowing the
    /// extension's own outbound connection (routing/loop).
    private func runRelayProbe(host: String, port: Int) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        self.probe = conn
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:   self?.dbg("relay-probe -> CONNECTED (routing OK, relay reachable)")
            case .waiting(let e): self?.dbg("relay-probe waiting: \(e)")
            case .failed(let e):  self?.dbg("relay-probe -> FAILED: \(e)")
            default: break
            }
        }
        conn.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + 8) { conn.cancel() }
    }

    private func isIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0).map { $0 >= 0 && $0 <= 255 } ?? false }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        dbg("stopTunnel reason=\(reason.rawValue)")
        Socks5Tunnel.quit()
        completionHandler()
    }
}
