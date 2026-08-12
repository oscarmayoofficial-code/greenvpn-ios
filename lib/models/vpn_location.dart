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
    required this.socksPort,
    required this.extraMs,
    required this.mbps,
    required this.premium,
    required this.pro,
  });

  final String id;
  final String name;
  final String city;
  final String cc;
  final String flag;
  final String api; // proxy host, e.g. https://vpn.greenhole.app
  final int socksPort;
  final int extraMs;
  final int mbps;
  final bool premium;
  final bool pro; // true = locked behind Pro when the gate is on

  factory VpnLocation.fromJson(Map<String, dynamic> j) => VpnLocation(
        id: j['id'] as String,
        name: j['name'] as String,
        city: j['city'] as String? ?? '',
        cc: j['cc'] as String? ?? '',
        flag: j['flag'] as String? ?? '🌐',
        api: j['api'] as String? ?? '',
        socksPort: j['socks_port'] as int? ?? 0,
        extraMs: j['extra_ms'] as int? ?? 0,
        mbps: j['mbps'] as int? ?? 0,
        premium: j['premium'] as bool? ?? false,
        pro: j['pro'] as bool? ?? false,
      );

  /// Host to dial the SOCKS5 proxy on — `api` is a URL, we just need the host.
  String get proxyHost => Uri.parse(api).host;
}
