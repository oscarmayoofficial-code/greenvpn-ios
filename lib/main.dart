import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models/vpn_location.dart';
import 'services/api.dart';
import 'services/vpn_bridge.dart';
import 'widgets/vpn_orb.dart';

void main() => runApp(const GreenVpnApp());

// Same palette as the Android app's activity_main.xml / bg_radial.xml.
const _bgTop = Color(0xFF171A18);
const _bgBottom = Color(0xFF040605);
const _brandColor = Color(0xFFF1F3F4);
const _pillBg = Color(0xFF16161D);
const _pillBorder = Color(0x26FFFFFF);
const _pillText = Color(0xFFD9DEE2);
const _statusGrey = Color(0xFF9AA0A6);
const _ringGreen = Color(0xFF2FE84A);
const _ringRed = Color(0xFFF0453B);
const _cardBg = Color(0xFF1C1F24);
const _cardBorder = Color(0xFF2A2E35);

class GreenVpnApp extends StatelessWidget {
  const GreenVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Green VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: _bgBottom,
        colorScheme: ColorScheme.fromSeed(seedColor: _ringGreen, brightness: Brightness.dark),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = GreenVpnApi();
  final _vpn = VpnBridge.instance;

  ServerConfig? _config;
  VpnLocation? _selected;
  VpnState _state = VpnState.disconnected;
  String? _error;
  String? _publicIp; // exit IP shown under the orb once connected
  bool _pickerOpen = false;

  @override
  void initState() {
    super.initState();
    _vpn.statusStream.listen((s) {
      setState(() => _state = s);
      if (s == VpnState.connected) {
        _fetchIp();
      } else {
        setState(() => _publicIp = null);
      }
    });
    _loadServers();
  }

  /// Fetch the current public IP once the tunnel is up — the request routes
  /// through the VPN, so this is the exit IP. Shown under the orb like Android.
  Future<void> _fetchIp() async {
    setState(() => _publicIp = null);
    await Future.delayed(const Duration(milliseconds: 600));
    for (var attempt = 0; attempt < 4; attempt++) {
      if (!mounted || _state != VpnState.connected) return;
      try {
        final res = await http
            .get(Uri.parse('https://api.ipify.org'))
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200 && mounted && _state == VpnState.connected) {
          setState(() => _publicIp = res.body.trim());
          return;
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 900));
    }
  }

  Future<void> _loadServers() async {
    try {
      final config = await _api.fetchServers();
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString('location_id');
      VpnLocation? saved;
      for (final l in config.locations) {
        if (l.id == savedId) {
          saved = l;
          break;
        }
      }
      setState(() {
        _config = config;
        _selected = saved ?? (config.locations.isEmpty ? null : config.locations.first);
        _error = null;
      });
      // Auto-connect: if the user turned it on, connect as soon as the app opens.
      if ((prefs.getBool('auto_connect') ?? false) &&
          _selected != null &&
          _state == VpnState.disconnected) {
        _toggleConnect();
      }
    } catch (e) {
      setState(() => _error = 'Could not load locations: $e');
    }
  }

  Future<void> _toggleConnect() async {
    final config = _config;
    final location = _selected;
    if (config == null || location == null) return;

    if (_state == VpnState.connected || _state == VpnState.connecting) {
      try {
        await _vpn.disconnect();
      } catch (e) {
        _showSnack(e.toString());
      }
      setState(() => _state = VpnState.disconnected);
      return;
    }

    setState(() => _state = VpnState.connecting);
    try {
      await _vpn.connect(location, config.proxyCreds);
      setState(() => _state = VpnState.connected);
    } catch (e) {
      setState(() => _state = VpnState.error);
      _showSnack(e.toString());
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _selectLocation(VpnLocation l) async {
    setState(() {
      _selected = l;
      _pickerOpen = false;
    });
    (await SharedPreferences.getInstance()).setString('location_id', l.id);
  }

  void _showInfoDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _showSupportDialog() {
    showDialog(
      context: context,
      builder: (_) => const _SupportDialog(),
    );
  }

  String get _orbLabel => switch (_state) {
        VpnState.connected => 'CONNECTED',
        VpnState.connecting => 'CONNECTING…',
        _ => 'NOT CONNECTED',
      };

  String get _statusLine => switch (_state) {
        VpnState.connected =>
          _selected == null ? '' : '${_selected!.flag}  ${_selected!.name} · ${_selected!.city}',
        VpnState.connecting => 'Connecting…',
        VpnState.error => 'Connection failed · tap to retry',
        VpnState.disconnected => 'Not connected · tap to connect',
      };

  @override
  Widget build(BuildContext context) {
    final location = _selected;
    final ringColor = _state == VpnState.connected ? _ringGreen : _ringRed;

    return Scaffold(
      body: Stack(
        children: [
          // bg_radial.xml equivalent
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.16),
                  radius: 1.1,
                  colors: [_bgTop, _bgBottom],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _TopBar(onInfo: _showInfoDialog, onHeart: _showSupportDialog),
                const SizedBox(height: 2),
                const Text(
                  'GREEN VPN',
                  style: TextStyle(
                    color: _brandColor,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                ),
                const SizedBox(height: 14),
                _LocationPill(
                  label: location != null
                      ? '${location.flag}  ${location.name}'
                      : (_error != null ? 'Retry' : 'Select location'),
                  onTap: () {
                    if (_error != null && location == null) {
                      _loadServers();
                    } else if (location != null) {
                      setState(() => _pickerOpen = true);
                    }
                  },
                ),
                if (_error != null && location == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, left: 24, right: 24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _ringRed, fontSize: 12),
                    ),
                  ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      VpnOrb(state: _state, onTap: location == null ? null : _toggleConnect),
                      const SizedBox(height: 14),
                      Text(
                        _orbLabel,
                        style: TextStyle(
                          color: ringColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          _statusLine,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _statusGrey, fontSize: 13),
                        ),
                      ),
                      if (_state == VpnState.connected) ...[
                        const SizedBox(height: 12),
                        Text(
                          _publicIp == null ? 'Fetching IP…' : 'IP: $_publicIp',
                          style: const TextStyle(
                            color: Color(0xFF1EE38B),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const _HouseAdCard(),
                const SizedBox(height: 16),
              ],
            ),
          ),
          if (_pickerOpen)
            _LocationOverlay(
              locations: _config?.locations ?? const [],
              selectedId: _selected?.id,
              onPick: _selectLocation,
              onClose: () => setState(() => _pickerOpen = false),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onInfo, required this.onHeart});
  final VoidCallback onInfo;
  final VoidCallback onHeart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: onInfo,
            icon: const Text('☰', style: TextStyle(color: _pillText, fontSize: 26)),
          ),
          IconButton(
            onPressed: onHeart,
            icon: const Text('💚', style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
  }
}

class _LocationPill extends StatelessWidget {
  const _LocationPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: _pillBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _pillBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(color: _pillText, fontSize: 15)),
            const Text('  ▾', style: TextStyle(color: _pillText, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

/// Full-screen in-app panel, styled like the Android app's pickerOverlay +
/// card_bg (a centered card over a dim scrim), instead of a bottom sheet.
class _LocationOverlay extends StatefulWidget {
  const _LocationOverlay({
    required this.locations,
    required this.selectedId,
    required this.onPick,
    required this.onClose,
  });

  final List<VpnLocation> locations;
  final String? selectedId;
  final ValueChanged<VpnLocation> onPick;
  final VoidCallback onClose;

  @override
  State<_LocationOverlay> createState() => _LocationOverlayState();
}

class _LocationOverlayState extends State<_LocationOverlay> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.locations
        : widget.locations
            .where((l) => l.name.toLowerCase().contains(q) || l.city.toLowerCase().contains(q))
            .toList();
    return Positioned.fill(
      child: GestureDetector(
        onTap: widget.onClose,
        child: Container(
          color: const Color(0xCC000000),
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.68),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _cardBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 2),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Server Locations',
                          style: TextStyle(color: _brandColor, fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF11141A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _cardBorder),
                      ),
                      child: TextField(
                        autofocus: false,
                        style: const TextStyle(color: _brandColor, fontSize: 15),
                        cursorColor: _ringGreen,
                        decoration: const InputDecoration(
                          hintText: 'Search location…',
                          hintStyle: TextStyle(color: Color(0xFF6A716F), fontSize: 15),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 13),
                        ),
                        onChanged: (v) => setState(() => _q = v),
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 10),
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final l = list[i];
                        final selected = l.id == widget.selectedId;
                        return Column(
                          children: [
                            InkWell(
                              onTap: () => widget.onPick(l),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                                color: selected ? Colors.white.withValues(alpha: 0.04) : null,
                                child: Row(
                                  children: [
                                    Text(l.flag, style: const TextStyle(fontSize: 26)),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(l.name,
                                              style: const TextStyle(color: _brandColor, fontSize: 16)),
                                          const SizedBox(height: 2),
                                          Text(l.city,
                                              style: const TextStyle(color: _statusGrey, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    if (l.premium) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE6F4EA),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text('Pro',
                                            style: TextStyle(
                                                color: Color(0xFF16A34A), fontSize: 13, fontWeight: FontWeight.w600)),
                                      ),
                                      const SizedBox(width: 12),
                                    ],
                                    const _SignalBars(),
                                  ],
                                ),
                              ),
                            ),
                            if (i == 0)
                              const Divider(color: _cardBorder, height: 1, indent: 20, endIndent: 20),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Green signal-strength bars shown at the right of each location row (like Android).
class _SignalBars extends StatelessWidget {
  const _SignalBars();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        return Container(
          width: 5,
          height: 8.0 + i * 5,
          margin: const EdgeInsets.only(left: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E),
            borderRadius: BorderRadius.circular(1.5),
          ),
        );
      }),
    );
  }
}

/// Green Hole house-ad — same AdMob-native-style card as the Android app
/// (server-driven house_ad; static here for the visual match).
class _HouseAdCard extends StatelessWidget {
  const _HouseAdCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF203A2C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF9C823),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text('Ad',
                style: TextStyle(color: Color(0xFF202124), fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.download_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Green Hole',
                        style: TextStyle(color: Color(0xFFF1F3F4), fontSize: 18, fontWeight: FontWeight.bold)),
                    SizedBox(height: 3),
                    Text('★★★★★  4.9  ·  App Store',
                        style: TextStyle(color: Color(0xFFF9C823), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Download videos from FB, TikTok, Instagram & YouTube - free',
              style: TextStyle(color: Color(0xFF9AA6A0), fontSize: 13)),
          const Spacer(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF3A3A3A)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.apple, color: Colors.white, size: 26),
                SizedBox(width: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Download on the', style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 8)),
                    Text('App Store',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full card-style Settings screen — exact copy of the Android app's Surfshark-style
/// Settings (CONNECTIVITY / CONTENT / ADVANCED / ACCOUNT). Toggles persist locally;
/// the actual VPN behaviour is wired to the native extension once it exists.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<String, bool> _t = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      for (final k in ['auto_connect', 'cleanweb', 'killswitch', 'webblock', 'discover_lan', 'small_packets', 'rotate_ip']) {
        _t[k] = p.getBool(k) ?? (k == 'discover_lan');
      }
    });
  }

  Future<void> _set(String k, bool v) async {
    setState(() => _t[k] = v);
    (await SharedPreferences.getInstance()).setBool(k, v);
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8, left: 6),
        child: Text(t,
            style: const TextStyle(
                color: Color(0xFF7C8B83), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
      );

  Widget _iconBox(String emoji, Color color) => Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Text(emoji, style: const TextStyle(fontSize: 20)),
      );

  Widget _titleDesc(String title, String desc) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(color: Color(0xFFF1F3F4), fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              Text(desc, style: const TextStyle(color: Color(0xFF8A9791), fontSize: 12)),
            ],
          ),
        ),
      );

  BoxDecoration get _cardDeco => BoxDecoration(
        color: const Color(0xFF141B18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2A24)),
      );

  Widget _toggle(String emoji, Color color, String title, String desc, String key) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: _cardDeco,
        child: Row(children: [
          _iconBox(emoji, color),
          _titleDesc(title, desc),
          Switch(
            value: _t[key] ?? false,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF22C55E),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFF3A4A42),
            onChanged: (v) => _set(key, v),
          ),
        ]),
      );

  Widget _row(String emoji, String title, String desc, {VoidCallback? onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: _cardDeco,
          child: Row(children: [
            _iconBox(emoji, const Color(0xFF1E2A24)),
            _titleDesc(title, desc),
            const Text('›', style: TextStyle(color: Color(0xFF7C8B83), fontSize: 22)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F0D),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 16, 10),
              child: Row(children: [
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Text('←', style: TextStyle(color: Color(0xFFEDEFEE), fontSize: 26))),
                const Text('Settings',
                    style: TextStyle(color: Color(0xFFF1F3F4), fontSize: 24, fontWeight: FontWeight.bold)),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 26),
                children: [
                  _label('CONNECTIVITY'),
                  _row('🌐', 'Quick-connect', 'Connect button uses: Auto · Fastest'),
                  _row('📍', 'Default location', 'Auto-connect to this if a location fails: Not set'),
                  _toggle('⚡', const Color(0xFFF5B301), 'Auto-connect', 'Connects automatically when you open Green VPN.', 'auto_connect'),
                  _toggle('🧹', const Color(0xFF3B82F6), 'CleanWeb', 'Blocks ads, trackers and malware when the VPN is connected.', 'cleanweb'),
                  _toggle('🛡', const Color(0xFF16A34A), 'Kill switch', 'Cuts off the internet if the VPN drops or is turned off.', 'killswitch'),
                  _row('🔒', 'System Lock', 'Always-on VPN & block connections without VPN.'),
                  _row('⚙', 'Protocol', 'Automatic (Secure Proxy)'),
                  _row('🔀', 'Bypasser', 'Choose apps that skip the VPN.'),
                  _label('CONTENT'),
                  _toggle('🚫', const Color(0xFFEF4444), 'Web content blocker', 'Blocks adult, gambling and similar websites.', 'webblock'),
                  _label('ADVANCED'),
                  _toggle('📶', const Color(0xFF0EA5E9), 'Discover on LAN', 'Access other devices on your local network while connected.', 'discover_lan'),
                  _toggle('📦', const Color(0xFF8B5CF6), 'Use small packets', 'Smaller packets improve compatibility with some routers and mobile networks.', 'small_packets'),
                  _toggle('🔁', const Color(0xFFF59E0B), 'Use rotating IP', 'Automatically changes your IP every few minutes.', 'rotate_ip'),
                  _label('ACCOUNT'),
                  _row('🎟', 'Redeem Pro code', 'Unlock all premium locations'),
                  _row('📄', 'Privacy Policy', 'How we protect your data'),
                  const SizedBox(height: 20),
                  const Center(
                      child: Text('Green VPN  v7.8', style: TextStyle(color: Color(0xFF5C6B63), fontSize: 12))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportDialog extends StatelessWidget {
  const _SupportDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _cardBg,
      title: const Text('💚 Support Green VPN', style: TextStyle(color: _brandColor)),
      content: const Text(
        'Traffic is routed through our servers to keep you private. '
        'If Green VPN is useful to you, a review on the App Store helps a lot.',
        style: TextStyle(color: _statusGrey),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK', style: TextStyle(color: _ringGreen)),
        ),
      ],
    );
  }
}
