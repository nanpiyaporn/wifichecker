// =============================================================================
// HeatmapScreen
// -----------------------------------------------------------------------------
// Walk around the room. Each time you tap on the dark canvas the app reads the
// current signal strength of the target router and drops a colored "blob" at
// that spot:
//
//    red    = weak signal
//    yellow = okay
//    green  = strong signal
//
// After 6-12 taps you get a quick visual map of where reception is good and
// where it's weak.
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wifi_scan/wifi_scan.dart';

/// One sample = "I tapped here at this signal strength".
class HeatmapSample {
  final Offset position; // where the user tapped on the canvas
  final int rssi;        // signal strength at that moment, in dBm
  HeatmapSample(this.position, this.rssi);
}

class HeatmapScreen extends StatefulWidget {
  final WiFiAccessPoint target;
  const HeatmapScreen({super.key, required this.target});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  final List<HeatmapSample> _samples = [];
  int _currentRssi = -100;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentRssi = widget.target.level;
    // Refresh signal reading once a second so each tap captures a fresh value.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshRssi());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshRssi() async {
    try {
      final canScan = await WiFiScan.instance.canStartScan();
      if (canScan == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
      }
      final canGet = await WiFiScan.instance.canGetScannedResults();
      if (canGet != CanGetScannedResults.yes) return;

      final results = await WiFiScan.instance.getScannedResults();
      final match = results.firstWhere(
        (r) => r.bssid == widget.target.bssid,
        orElse: () => widget.target,
      );
      if (!mounted) return;
      setState(() => _currentRssi = match.level);
    } catch (_) {
      // ignore - try again on the next tick
    }
  }

  void _addSample(Offset position) {
    setState(() {
      _samples.add(HeatmapSample(position, _currentRssi));
    });
  }

  void _undo() {
    if (_samples.isEmpty) return;
    setState(() => _samples.removeLast());
  }

  void _clear() {
    setState(() => _samples.clear());
  }

  // RSSI -> 0.0..1.0 fraction. -90 = weak, -30 = strong.
  static double rssiFraction(int rssi) {
    final clamped = rssi.clamp(-90, -30);
    return (clamped + 90) / 60.0;
  }

  // RSSI -> color (red->yellow->green).
  static Color rssiColor(int rssi) {
    return Color.lerp(Colors.red, Colors.green, rssiFraction(rssi))!;
  }

  @override
  Widget build(BuildContext context) {
    final ssid =
        widget.target.ssid.isEmpty ? '(hidden network)' : widget.target.ssid;
    final liveColor = rssiColor(_currentRssi);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        title: Text('Heatmap: $ssid'),
        actions: [
          IconButton(
            tooltip: 'Undo last',
            icon: const Icon(Icons.undo),
            onPressed: _samples.isEmpty ? null : _undo,
          ),
          IconButton(
            tooltip: 'Clear all',
            icon: const Icon(Icons.delete_outline),
            onPressed: _samples.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          // ---- Top status card ----
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Icon(Icons.wifi, color: liveColor, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ssid,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Live: $_currentRssi dBm  ·  '
                        '${_samples.length} samples',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ---- The big tap-to-record canvas ----
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF101a33),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  // GestureDetector turns taps into onTapDown events.
                  // The LayoutBuilder gives us the exact pixel size of the
                  // canvas so we can paint at the right location.
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) =>
                            _addSample(details.localPosition),
                        child: CustomPaint(
                          size: Size(constraints.maxWidth,
                              constraints.maxHeight),
                          painter: _HeatmapPainter(_samples),
                          child: _samples.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      'Walk to a spot in the room, then tap '
                                      'here to record the signal at your '
                                      'current position.\n\n'
                                      'Repeat in different spots to build '
                                      'your heatmap.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // ---- Color legend at the bottom ----
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  height: 14,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    gradient: const LinearGradient(
                      colors: [Colors.red, Colors.orange, Colors.yellow,
                          Colors.lightGreen, Colors.green],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Weak  -90 dBm',
                        style: TextStyle(
                            color: Colors.grey.shade400, fontSize: 12)),
                    Text('Strong  -30 dBm',
                        style: TextStyle(
                            color: Colors.grey.shade400, fontSize: 12)),
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

// =============================================================================
// _HeatmapPainter
// -----------------------------------------------------------------------------
// Draws each sample as a glowing colored blob using a radial gradient. Multiple
// blobs blend together because we use BlendMode.plus, which approximates the
// look of a real heatmap without doing expensive interpolation math.
// =============================================================================
class _HeatmapPainter extends CustomPainter {
  final List<HeatmapSample> samples;
  _HeatmapPainter(this.samples);

  @override
  void paint(Canvas canvas, Size size) {
    // Save a layer so BlendMode.plus only affects our blobs, not the bg.
    canvas.saveLayer(Offset.zero & size, Paint());

    for (final s in samples) {
      final color = _HeatmapScreenState.rssiColor(s.rssi);
      const radius = 70.0;

      final paint = Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            color.withOpacity(0.55),
            color.withOpacity(0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: s.position, radius: radius));

      canvas.drawCircle(s.position, radius, paint);
    }

    canvas.restore();

    // Draw a small dot + dBm label on top of each sample so the user can
    // see exactly where they tapped.
    for (final s in samples) {
      final dot = Paint()..color = Colors.white;
      canvas.drawCircle(s.position, 3, dot);

      final tp = TextPainter(
        text: TextSpan(
          text: '${s.rssi}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, s.position + const Offset(6, -14));
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      old.samples.length != samples.length ||
      !identical(old.samples, samples);
}
