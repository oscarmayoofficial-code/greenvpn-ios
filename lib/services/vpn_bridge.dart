import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vpn_location.dart';
import 'api.dart';

enum VpnState { disconnected, connecting, connected, error }

/// Talks to the native NEPacketTunnelProvider extension over a platform
/// channel. iOS has no "set a system proxy" API like Windows/Android — the
/// only way to route ALL device traffic through our SOCKS5 locations is a
/// Network Extension, which is a signed Xcode target + an Apple-approved
/// Personal VPN entitlement. **That native extension does not exist yet**
/// (see greenvpn-ios-app memory: blocked on the entitlement request and on
/// hand-building the PacketTunnelProvider target without local Xcode).
///
/// This class is written against the channel contract the extension will
/// expose, so the Flutter UI/state-machine can be built and tested now (incl.
/// on Android, via `flutter run`) without waiting on the native half. Until
/// the native side ships, `connect()`/`disconnect()` throw
/// [VpnUnavailableException] and callers should show that message.
class VpnBridge {
  VpnBridge._();
  static final VpnBridge instance = VpnBridge._();

  static const _channel = MethodChannel('com.oscar.greenvpn/vpn');
  static const _statusChannel = EventChannel('com.oscar.greenvpn/vpn_status');

  Stream<VpnState>? _statusStream;

  Stream<VpnState> get statusStream {
    return _statusStream ??= _statusChannel
        .receiveBroadcastStream()
        .map((event) => _parseState(event as String))
        .handleError((_) {}); // no native listener yet on iOS
  }

  VpnState _parseState(String s) => switch (s) {
        'connected' => VpnState.connected,
        'connecting' => VpnState.connecting,
        'error' => VpnState.error,
        _ => VpnState.disconnected,
      };

  Future<void> connect(VpnLocation location, ProxyCreds creds) async {
    // Pull the user's Settings toggles so the native tunnel can apply them
    // (CleanWeb/Web-blocker -> filtering DNS, small packets -> MTU 1280,
    // Discover-on-LAN -> keep the local subnet outside the tunnel).
    final p = await SharedPreferences.getInstance();
    try {
      await _channel.invokeMethod('connect', {
        'host': location.proxyHost,
        'port': location.socksPort,
        'username': creds.username,
        'password': creds.password,
        'locationId': location.id,
        'cleanweb': p.getBool('cleanweb') ?? false,
        'webblock': p.getBool('webblock') ?? false,
        'smallPackets': p.getBool('small_packets') ?? false,
        'discoverLan': p.getBool('discover_lan') ?? true,
      });
    } on MissingPluginException {
      throw VpnUnavailableException();
    }
  }

  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('disconnect');
    } on MissingPluginException {
      throw VpnUnavailableException();
    }
  }
}

/// Thrown while the PacketTunnelProvider extension isn't built/signed yet.
class VpnUnavailableException implements Exception {
  @override
  String toString() =>
      'VPN tunnel isn\'t wired up on this build yet (native extension pending).';
}
