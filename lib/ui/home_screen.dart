import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../app_state.dart';
import '../core/transport/ble_transport.dart';
import '../core/transport/sim_transport.dart';
import 'theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onScanned});

  /// Called after a diagnostic scan so the shell can switch to Codes.
  final VoidCallback onScanned;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ringColor = switch (app.conn) {
      ConnState.on => Palette.cyan,
      ConnState.connecting => Palette.muted,
      ConnState.off => const Color(0xFF5B6B80),
    };
    final label = app.t(app.conn.name);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Panel(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(size: const Size(200, 200), painter: _RingPainter(ringColor, app.conn == ConnState.on)),
                    if (app.conn == ConnState.connecting)
                      const SizedBox(
                        width: 186,
                        height: 186,
                        child: CircularProgressIndicator(strokeWidth: 6, color: Palette.cyan),
                      ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          app.t('adapter').toUpperCase(),
                          style: const TextStyle(fontSize: 12, letterSpacing: 2, color: Palette.muted),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: ringColor),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          app.adapterName ?? 'ELM327 · BLE',
                          style: const TextStyle(fontSize: 12, color: Palette.muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (app.error != null) ...[
                Text(
                  app.t(app.error!),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Palette.red),
                ),
                const SizedBox(height: 12),
              ],
              if (app.conn == ConnState.off) ...[
                PrimaryButton(
                  label: app.t('connect'),
                  icon: Icons.bluetooth,
                  outlined: true,
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => AppScope(state: app, child: const _AdapterSheet()),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => app.connect(() async => SimTransport()),
                  child: Text(app.t('demo'), style: const TextStyle(color: Palette.muted)),
                ),
              ],
              if (app.conn == ConnState.on) ...[
                PrimaryButton(
                  label: app.scanning ? app.t('scanning') : app.t('scan'),
                  icon: Icons.search,
                  onPressed: app.scanning
                      ? null
                      : () async {
                          await app.scan();
                          onScanned();
                        },
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: app.disconnect,
                  child: Text(app.t('disconnect'), style: const TextStyle(color: Palette.muted)),
                ),
              ],
            ],
          ),
        ),
        if (app.conn == ConnState.on) ...[
          const SizedBox(height: 8),
          SectionLabel(app.t('vin')),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.vin ?? '—',
                  style: const TextStyle(
                    fontFamily: mono,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${app.t('protocol')}: ${app.elm?.protocol ?? '?'} · ${app.elm?.version ?? ''}',
                  style: const TextStyle(color: Palette.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color, this.full);
  final Color color;
  final bool full;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final track = Paint()
      ..color = Palette.track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    canvas.drawCircle(c, 88, track);
    if (full) {
      final glow = Paint()
        ..color = color.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(c, 88, glow);
      canvas.drawCircle(c, 88, track..color = color);
    }
    final dash = Paint()
      ..color = Palette.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 60; i++) {
      final a = i * pi / 30;
      canvas.drawLine(c + Offset(cos(a), sin(a)) * 68, c + Offset(cos(a), sin(a)) * 72, dash);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color || old.full != full;
}

class _AdapterSheet extends StatefulWidget {
  const _AdapterSheet();
  @override
  State<_AdapterSheet> createState() => _AdapterSheetState();
}

class _AdapterSheetState extends State<_AdapterSheet> {
  List<ScanResult> _results = [];
  StreamSubscription<List<ScanResult>>? _sub;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _sub = FlutterBluePlus.scanResults.listen((r) {
      final list = r.where((x) => x.device.platformName.isNotEmpty).toList()
        ..sort((a, b) {
          final ao = looksLikeObdAdapter(a.device.platformName) ? 0 : 1;
          final bo = looksLikeObdAdapter(b.device.platformName) ? 0 : 1;
          return ao != bo ? ao - bo : b.rssi - a.rssi;
        });
      if (mounted) setState(() => _results = list);
    });
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      await FlutterBluePlus.isScanning.where((s) => !s).first;
    } catch (_) {}
    if (mounted) setState(() => _scanning = false);
  }

  @override
  void dispose() {
    _sub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(app.t('pick_adapter'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (_scanning) ...[
              const LinearProgressIndicator(color: Palette.cyan, backgroundColor: Palette.track),
              const SizedBox(height: 8),
              Text(app.t('scanning_ble'), style: const TextStyle(color: Palette.muted)),
            ],
            if (!_scanning && _results.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(app.t('no_adapters'), style: const TextStyle(color: Palette.muted)),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in _results)
                    ListTile(
                      leading: Icon(
                        Icons.bluetooth,
                        color: looksLikeObdAdapter(r.device.platformName) ? Palette.cyan : Palette.muted,
                      ),
                      title: Text(r.device.platformName),
                      subtitle: Text(
                        '${r.device.remoteId.str} · ${r.rssi} dBm',
                        style: const TextStyle(color: Palette.muted, fontSize: 12),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        app.connect(() => BleTransport.connect(r.device));
                      },
                    ),
                ],
              ),
            ),
            if (!_scanning) PrimaryButton(label: app.t('rescan'), outlined: true, onPressed: _scan),
          ],
        ),
      ),
    );
  }
}
