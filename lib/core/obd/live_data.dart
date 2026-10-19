import 'dart:async';

import 'package:flutter/foundation.dart';

import 'obd_service.dart';
import 'pids.dart';

/// Polls selected PIDs in a loop and keeps a short history for charts.
class LiveDataController extends ChangeNotifier {
  LiveDataController(this.obd, {this.historyLength = 120});

  final ObdService obd;
  final int historyLength;

  final List<String> selected = List.of(defaultDashboard);
  final Map<String, List<double>> history = {};
  final Map<String, double> latest = {};
  final Set<String> unsupported = {};
  Set<int> supported = {};

  bool _running = false;
  bool get running => _running;
  int samplesPerSecond = 0;
  int _count = 0;
  Timer? _rateTimer;
  bool _disposed = false;

  @override
  void notifyListeners() {
    // A poll that was in flight may finish after the screen closed.
    if (!_disposed) super.notifyListeners();
  }

  Future<void> loadSupported() async {
    supported = await obd.supportedPids();
    notifyListeners();
  }

  void toggle(String key) {
    selected.contains(key) ? selected.remove(key) : selected.add(key);
    notifyListeners();
  }

  /// Whether the car reported this PID as supported (unknown = assume yes).
  bool isSupported(Pid p) => supported.isEmpty || supported.contains(p.id);

  /// Polls only [keys] (e.g. values related to a fault code) until [stop].
  Future<void> watch(List<String> keys) async {
    selected
      ..clear()
      ..addAll(keys.where((k) => pidByKey.containsKey(k)));
    await start();
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
      for (final key in pids) {
        if (!_running) break;
        await sampleOnce(key);
      }
    }
  }

  @visibleForTesting
  Future<void> sampleOnce(String key) async {
    final pid = pidByKey[key]!;
    final id = key;
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
    _disposed = true;
    super.dispose();
  }
}
