/// A single server location as served by GET https://green-vpn.app/api/servers
/// (see the `servers` array). Field names match the JSON exactly so decoding
/// stays a straight `fromJson` with no renaming to track on the server side.
class VpnLocation {
  const VpnLocation({
    required this.id,
    required this.name,
    required this.city,
    required this.cc,
    required this.flag,
    required this.api,
    required this.proxyHost,
    required this.socksPort,
    required this.dhost,
    required this.dsport,
    required this.extraMs,
    required this.mbps,
    required this.free,
  });

  final String id;
  final String name;
  final String city;
  final String cc;
  final String flag;
  final String api; // control URL, e.g. https://vpn.greenhole.app (NOT the SOCKS host)
  final String proxyHost; // SOCKS5 host to dial = the top-level `proxy_host` (relay IP)
  final int socksPort;
  final String dhost; // per-location DIRECT relay host (e.g. USA -> US relay, skips SG); '' = use proxyHost
  final int dsport; // its socks port; 0 = use socksPort on the global relay
  final int extraMs;
  final int mbps;
  final bool free; // server's `free` flag: usable without any purchase

  /// [proxyHost] is the top-level `proxy_host` (the relay IP the SOCKS5 proxy
  /// actually listens on) — same value the Android app dials. The per-server
  /// `api` field is only a control URL and must NOT be used as the SOCKS host.
  factory VpnLocation.fromJson(Map<String, dynamic> j, String proxyHost) =>
      VpnLocation(
        id: j['id'] as String,
        name: j['name'] as String,
        city: j['city'] as String? ?? '',
        cc: j['cc'] as String? ?? '',
        flag: j['flag'] as String? ?? '🌐',
        api: j['api'] as String? ?? '',
        proxyHost: proxyHost.isNotEmpty
            ? proxyHost
            : Uri.parse(j['api'] as String? ?? '').host,
        socksPort: j['socks_port'] as int? ?? 0,
        dhost: j['dhost'] as String? ?? '',
        dsport: j['dsport'] as int? ?? 0,
        extraMs: j['extra_ms'] as int? ?? 0,
        mbps: j['mbps'] as int? ?? 0,
        free: j['free'] as bool? ?? false,
      );

  /// iOS ships as a free app with no in-app purchase, so only locations the
  /// server marks `free` (plus the Auto picker, which itself only chooses
  /// among free exits) are ever offered — nothing shown is ever locked.
  bool get offeredOnIos => free || id == 'auto';

  /// The host/port the tunnel should actually dial: a location's own direct
  /// relay (dhost/dsport) when present — e.g. USA cities go straight to the US
  /// relay, skipping the Singapore hop — otherwise the global proxyHost:socksPort.
  bool get isDirect => dhost.isNotEmpty && dsport > 0;
  String get dialHost => isDirect ? dhost : proxyHost;
  int get dialPort => isDirect ? dsport : socksPort;
}
