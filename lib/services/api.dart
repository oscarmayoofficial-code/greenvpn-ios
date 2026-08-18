import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/vpn_location.dart';

/// Everything the app needs from the server in one shot. Mirrors the JSON
/// shape the Android app + Chrome extension already parse — see
/// greenvpn-single-source / greenvpn-perplatform-paywall in the server repo.
class ServerConfig {
  ServerConfig({
    required this.locations,
    required this.proxyCreds,
    required this.proGateApp,
    required this.proPrice,
  });

  final List<VpnLocation> locations;
  final ProxyCreds proxyCreds;
  final bool proGateApp;
  final int proPrice;
}

class ProxyCreds {
  const ProxyCreds(this.username, this.password);
  final String username;
  final String password;
}

class GreenVpnApi {
  GreenVpnApi({this.baseUrl = 'https://green-vpn.app'});
  final String baseUrl;

  // Same obfuscation as the Android app / Chrome extension: the server never
  // ships plaintext creds, just base64(bytes XOR key). Not real secrecy (the
  // key ships in every client) — the point is server-side rotatability, see
  // greenvpn-ext-creds. Keep this key in sync with app.py / background.js.
  static const _obfKey = 'GrnV!2026#px';

  ProxyCreds _deobfuscate(String px) {
    final raw = base64.decode(px);
    final key = utf8.encode(_obfKey);
    final out = List<int>.generate(
      raw.length,
      (i) => raw[i] ^ key[i % key.length],
    );
    final decoded = utf8.decode(out);
    final sep = decoded.indexOf(':');
    return ProxyCreds(decoded.substring(0, sep), decoded.substring(sep + 1));
  }

  /// GET /api/servers. `src=ios` is sent explicitly (like the Android app
  /// sends `src=app`) so the server's per-platform Pro gate can eventually
  /// tell iOS apart from the extension/Android app — see
  /// greenvpn-perplatform-paywall for why relying on User-Agent sniffing
  /// through the reverse proxy doesn't work.
  Future<ServerConfig> fetchServers() async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/servers?src=ios'))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('servers fetch failed: HTTP ${res.statusCode}');
    }
    final root = jsonDecode(res.body) as Map<String, dynamic>;
    // The SOCKS5 proxy lives on the relay IP given by the top-level `proxy_host`
    // (same host the Android app dials). Each server's `api` is only a control
    // URL, not the SOCKS host — so thread proxy_host down into every location.
    final proxyHost = root['proxy_host'] as String? ?? '';
    final servers = (root['servers'] as List<dynamic>)
        .map((e) => VpnLocation.fromJson(e as Map<String, dynamic>, proxyHost))
        .toList();
    return ServerConfig(
      locations: servers,
      proxyCreds: _deobfuscate(root['px'] as String),
      proGateApp: root['pro_gate_app'] as bool? ?? false,
      proPrice: root['price'] as int? ?? 0,
    );
  }
}
