import Flutter
import NetworkExtension

/// App-side bridge between Flutter (`com.oscar.greenvpn/vpn`) and the
/// NEPacketTunnelProvider extension. Mirrors the Android VpnService flow:
/// Flutter calls `connect` with the SOCKS5 host/port/creds -> we save & start
/// an NETunnelProviderManager pointing at the PacketTunnel extension -> status
/// changes stream back on `com.oscar.greenvpn/vpn_status`.
class VpnChannel: NSObject, FlutterStreamHandler {

    private let extensionBundleId = "com.oscar.greenvpn.PacketTunnel"
    private var eventSink: FlutterEventSink?
    private var manager: NETunnelProviderManager?

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = VpnChannel()
        let method = FlutterMethodChannel(name: "com.oscar.greenvpn/vpn",
                                          binaryMessenger: registrar.messenger())
        method.setMethodCallHandler(instance.handle)
        let status = FlutterEventChannel(name: "com.oscar.greenvpn/vpn_status",
                                         binaryMessenger: registrar.messenger())
        status.setStreamHandler(instance)
        NotificationCenter.default.addObserver(
            instance, selector: #selector(instance.statusChanged(_:)),
            name: .NEVPNStatusDidChange, object: nil)
    }

    // MARK: - MethodChannel

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "connect":
            guard let args = call.arguments as? [String: Any],
                  let host = args["host"] as? String,
                  let port = args["port"] as? Int else {
                result(FlutterError(code: "bad_args", message: "host/port missing", details: nil))
                return
            }
            let user = args["username"] as? String ?? ""
            let pass = args["password"] as? String ?? ""
            emit("connecting")
            connect(host: host, port: port, user: user, pass: pass, result: result)
        case "disconnect":
            disconnect(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func connect(host: String, port: Int, user: String, pass: String,
                         result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }
            if let error = error {
                self.emit("error")
                result(FlutterError(code: "load_failed", message: error.localizedDescription, details: nil))
                return
            }
            let mgr = managers?.first ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = self.extensionBundleId
            // serverAddress is display-only for the Settings VPN row.
            proto.serverAddress = host
            proto.providerConfiguration = [
                "host": host,
                "port": port,
                "username": user,
                "password": pass,
            ]
            mgr.protocolConfiguration = proto
            mgr.localizedDescription = "Green VPN"
            mgr.isEnabled = true
            mgr.saveToPreferences { saveErr in
                if let saveErr = saveErr {
                    self.emit("error")
                    result(FlutterError(code: "save_failed", message: saveErr.localizedDescription, details: nil))
                    return
                }
                // Reload so the connection object is valid after a fresh save.
                mgr.loadFromPreferences { _ in
                    self.manager = mgr
                    do {
                        try mgr.connection.startVPNTunnel()
                        result(nil)
                    } catch {
                        self.emit("error")
                        result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    }

    private func disconnect(result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            managers?.first?.connection.stopVPNTunnel()
            self?.emit("disconnected")
            result(nil)
        }
    }

    // MARK: - Status

    @objc private func statusChanged(_ note: Notification) {
        guard let conn = note.object as? NEVPNConnection else { return }
        switch conn.status {
        case .connected:    emit("connected")
        case .connecting, .reasserting: emit("connecting")
        case .disconnecting: emit("connecting")
        case .disconnected, .invalid: emit("disconnected")
        @unknown default:   emit("disconnected")
        }
    }

    private func emit(_ state: String) {
        DispatchQueue.main.async { self.eventSink?(state) }
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
