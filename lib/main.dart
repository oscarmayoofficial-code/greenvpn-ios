import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/vpn_location.dart';
import 'services/api.dart';
import 'services/vpn_bridge.dart';
import 'widgets/vpn_orb.dart';

void main() => runApp(const GreenVpnApp());

class GreenVpnApp extends StatelessWidget {
  const GreenVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Green VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0E1310),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2FE84A),
          brightness: Brightness.dark,
        ),
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

  @override
  void initState() {
    super.initState();
    _vpn.statusStream.listen((s) => setState(() => _state = s));
    _loadServers();
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

  Future<void> _pickLocation() async {
    final config = _config;
    if (config == null) return;
    final picked = await showModalBottomSheet<VpnLocation>(
      context: context,
      backgroundColor: const Color(0xFF161C18),
      isScrollControlled: true,
      builder: (_) => _LocationSheet(locations: config.locations),
    );
    if (picked == null) return;
    setState(() => _selected = picked);
    (await SharedPreferences.getInstance()).setString('location_id', picked.id);
  }

  String get _statusLabel => switch (_state) {
        VpnState.connected => 'CONNECTED',
        VpnState.connecting => 'CONNECTING…',
        VpnState.error => 'CONNECTION FAILED',
        VpnState.disconnected => 'NOT CONNECTED',
      };

  @override
  Widget build(BuildContext context) {
    final location = _selected;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'GREEN VPN',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              const SizedBox(height: 40),
              if (location != null)
                _LocationPill(location: location, onTap: _pickLocation)
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(_error!, textAlign: TextAlign.center),
                )
              else
                const CircularProgressIndicator(),
              const SizedBox(height: 32),
              VpnOrb(state: _state, onTap: location == null ? null : _toggleConnect),
              const SizedBox(height: 24),
              Text(
                _statusLabel,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: switch (_state) {
                    VpnState.connected => const Color(0xFF2FE84A),
                    VpnState.connecting => const Color(0xFFFFB020),
                    _ => const Color(0xFFF0453B),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationPill extends StatelessWidget {
  const _LocationPill({required this.location, required this.onTap});

  final VpnLocation location;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(location.flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(location.name, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _LocationSheet extends StatelessWidget {
  const _LocationSheet({required this.locations});

  final List<VpnLocation> locations;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.62),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: locations.length,
          itemBuilder: (context, i) {
            final l = locations[i];
            return ListTile(
              leading: Text(l.flag, style: const TextStyle(fontSize: 22)),
              title: Text(l.name),
              subtitle: Text('${l.city} · ${l.extraMs}ms'),
              trailing: l.pro
                  ? const Icon(Icons.lock_outline_rounded, color: Color(0xFFFFD166), size: 18)
                  : null,
              onTap: () => Navigator.of(context).pop(l),
            );
          },
        ),
      ),
    );
  }
}
