import 'dart:async';

import 'package:flutter/foundation.dart';

import 'obd_service.dart';
import 'pids.dart';

/// Polls selected PIDs in a loop and keeps a short history for charts.
class LiveDataController extends ChangeNotifier {
  LiveDataController(this.obd, {this.historyLength = 120});

  final ObdService obd;
  final int historyLength;

  final List<int> selected = List.of(defaultDashboard);
  final Map<int, List<double>> history = {};
  final Map<int, double> latest = {};
  final Set<int> unsupported = {};
  Set<int> supported = {};

  bool _running = false;
  bool get running => _running;
  int samplesPerSecond = 0;
  int _count = 0;
  Timer? _rateTimer;

  Future<void> loadSupported() async {
    supported = await obd.supportedPids();
    notifyListeners();
  }

  void toggle(int pid) {
    selected.contains(pid) ? selected.remove(pid) : selected.add(pid);
    notifyListeners();
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _rateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      samplesPerSecond = _count;
      _count = 0;
      notifyListeners();
    });
    notifyListeners();
    while (_running) {
      final pids = selected.where((p) => !unsupported.contains(p)).toList();
      if (pids.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        continue;
      }
      for (final id in pids) {
        if (!_running) break;
        await sampleOnce(id);
      }
    }
  }

  @visibleForTesting
  Future<void> sampleOnce(int id) async {
    final pid = pidById[id]!;
    try {
      final v = await obd.readPid(pid);
      if (v == null) {
        unsupported.add(id);
      } else {
        latest[id] = v;
        final h = history.putIfAbsent(id, () => []);
        h.add(v);
        if (h.length > historyLength) h.removeAt(0);
        _count++;
      }
    } catch (_) {
      // transient adapter error: skip this sample
    }
    notifyListeners();
  }

  void stop() {
    _running = false;
    _rateTimer?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
