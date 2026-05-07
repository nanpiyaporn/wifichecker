// =============================================================================
// WiFi Router Finder
// -----------------------------------------------------------------------------
// A beginner-friendly Flutter app with two screens:
//   1. WifiListScreen     - shows nearby WiFi networks + signal strength.
//   2. SignalMeterScreen  - shows a big "compass" meter for one network so the
//                           user can walk around and find the physical router.
//

// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

import 'heatmap_screen.dart';

// ----- 1. App entry point ----------------------------------------------------
// Every Flutter app starts at main(). runApp() takes our root widget and paints
// it on the screen.
void main() {
  runApp(const MyApp());
}

// ----- 2. Root widget --------------------------------------------------------
// MyApp is "stateless" - it doesn't change after it's drawn. It just sets up
// the app theme + the home screen.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WiFi Router Finder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const WifiListScreen(),
    );
  }
}

// =============================================================================
// SCREEN 1: list of nearby WiFi networks
// =============================================================================
class WifiListScreen extends StatefulWidget {
  const WifiListScreen({super.key});

  @override
  State<WifiListScreen> createState() => _WifiListScreenState();
}

class _WifiListScreenState extends State<WifiListScreen> {
  // The current list of scanned WiFi networks. Starts empty.
  List<WiFiAccessPoint> _networks = [];

  // Tracks whether we are currently scanning, so we can show a spinner.
  bool _isScanning = false;

  // A friendly status message to display at the top.
  String _status = 'Tap "Scan" to find nearby WiFi networks.';

  @override
  void initState() {
    super.initState();
    // When the screen first opens, ask for permission and do an initial scan.
    _initialize();
  }

  Future<void> _initialize() async {
    final granted = await _requestPermissions();
    if (granted) {
      await _startScan();
    }
  }

  // ----- Ask the user for location permission --------------------------------
  // Android requires location permission to see the list of WiFi networks.
  Future<bool> _requestPermissions() async {
    final statuses = await [
      Permission.location,
      Permission.locationWhenInUse,
      Permission.nearbyWifiDevices, // Android 13+
    ].request();

    final granted = statuses[Permission.location]?.isGranted == true ||
        statuses[Permission.locationWhenInUse]?.isGranted == true ||
        statuses[Permission.nearbyWifiDevices]?.isGranted == true;

    if (!granted) {
      setState(() {
        _status = 'Location permission is required to scan WiFi.';
      });
    }
    return granted;
  }

  // ----- Trigger a WiFi scan and load the results ----------------------------
  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _status = 'Scanning...';
    });

    try {
      // Step 1: ask the OS to start a new scan.
      final canScan = await WiFiScan.instance.canStartScan();
      if (canScan == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
      }

      // Step 2: read whatever scan results are available right now.
      final canGet = await WiFiScan.instance.canGetScannedResults();
      if (canGet == CanGetScannedResults.yes) {
        final results = await WiFiScan.instance.getScannedResults();
        // Sort strongest first so closest networks appear at the top.
        results.sort((a, b) => b.level.compareTo(a.level));
        setState(() {
          _networks = results;
          _status = 'Found ${results.length} networks. Pull down to refresh.';
        });
      } else {
        setState(() {
          _status = 'Cannot read scan results: $canGet';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Scan failed: $e';
      });
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  // ----- Convert an RSSI value (dBm) to a friendly bars label ---------------
  String _signalLabel(int rssi) {
    if (rssi >= -50) return 'Excellent';
    if (rssi >= -60) return 'Good';
    if (rssi >= -70) return 'Fair';
    if (rssi >= -80) return 'Weak';
    return 'Very weak';
  }

  IconData _signalIcon(int rssi) {
    if (rssi >= -50) return Icons.signal_wifi_4_bar;
    if (rssi >= -65) return Icons.network_wifi_3_bar;
    if (rssi >= -75) return Icons.network_wifi_2_bar;
    if (rssi >= -85) return Icons.network_wifi_1_bar;
    return Icons.signal_wifi_0_bar;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Router Finder'),
        actions: [
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _startScan,
            tooltip: 'Scan',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status banner at the top.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.indigo.shade50,
            child: Text(
              _status,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          // The list of networks. Empty-state if nothing found.
          Expanded(
            child: _networks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _isScanning
                            ? 'Scanning for nearby WiFi...'
                            : 'No networks yet. Tap the refresh icon above.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _startScan,
                    child: ListView.separated(
                      itemCount: _networks.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final ap = _networks[index];
                        final name = ap.ssid.isEmpty ? '(hidden)' : ap.ssid;
                        return ListTile(
                          leading: Icon(_signalIcon(ap.level),
                              color: Colors.indigo),
                          title: Text(
                            name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${ap.bssid}  ·  ${ap.level} dBm  ·  '
                            '${_signalLabel(ap.level)}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            // Open the signal-meter "find this router" screen.
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SignalMeterScreen(target: ap),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SCREEN 2: signal strength meter for a single network
// =============================================================================
class SignalMeterScreen extends StatefulWidget {
  final WiFiAccessPoint target;
  const SignalMeterScreen({super.key, required this.target});

  @override
  State<SignalMeterScreen> createState() => _SignalMeterScreenState();
}

class _SignalMeterScreenState extends State<SignalMeterScreen> {
  // Current signal in dBm. Starts at the value we got from the previous screen.
  int _currentRssi = -100;

  // Timer that re-scans every 2 seconds.
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentRssi = widget.target.level;

    // Re-scan periodically so the meter updates as you walk around.
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final canScan = await WiFiScan.instance.canStartScan();
      if (canScan == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
      }
      final canGet = await WiFiScan.instance.canGetScannedResults();
      if (canGet != CanGetScannedResults.yes) return;

      final results = await WiFiScan.instance.getScannedResults();
      // Match by BSSID (the router's MAC) - it's unique per radio.
      final match = results.firstWhere(
        (r) => r.bssid == widget.target.bssid,
        orElse: () => widget.target, // keep last value if not found this round
      );
      if (!mounted) return;
      setState(() {
        _currentRssi = match.level;
      });
    } catch (_) {
      // Ignore scan errors and try again on the next tick.
    }
  }

  // Map a dBm value to a 0.0-1.0 fraction.
  // -30 dBm = right next to the router, -90 dBm = barely reaching us.
  double get _strengthFraction {
    final clamped = _currentRssi.clamp(-90, -30);
    return (clamped + 90) / 60.0;
  }

  Color get _color {
    final f = _strengthFraction;
    if (f > 0.75) return Colors.green;
    if (f > 0.45) return Colors.orange;
    return Colors.red;
  }

  String get _hint {
    final f = _strengthFraction;
    if (f > 0.85) return 'You are right next to the router! 🎯';
    if (f > 0.65) return 'Very close - keep going.';
    if (f > 0.40) return 'Getting warmer...';
    if (f > 0.20) return 'Cold. Try a different direction.';
    return 'Very far. Move toward another room.';
  }

  @override
  Widget build(BuildContext context) {
    final ssid =
        widget.target.ssid.isEmpty ? '(hidden network)' : widget.target.ssid;
    final percent = (_strengthFraction * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: Text('Find: $ssid'),
        actions: [
          IconButton(
            tooltip: 'Open heatmap',
            icon: const Icon(Icons.grid_on),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => HeatmapScreen(target: widget.target),
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Text(
              ssid,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.target.bssid,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 40),

            // Big circular percentage display.
            SizedBox(
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 180,
                    width: 180,
                    child: CircularProgressIndicator(
                      value: _strengthFraction,
                      strokeWidth: 16,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(_color),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$percent%',
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.bold,
                          color: _color,
                        ),
                      ),
                      Text(
                        '$_currentRssi dBm',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Linear meter underneath, easier to see at a glance while walking.
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LinearProgressIndicator(
                value: _strengthFraction,
                minHeight: 24,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(_color),
              ),
            ),

            const SizedBox(height: 24),

            Text(
              _hint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),

            const Spacer(),

            // Manual refresh button (the timer auto-refreshes too).
            FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh now'),
            ),
            const SizedBox(height: 8),
            Text(
              'Auto-updates every 2 seconds. Walk slowly and watch the bar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
