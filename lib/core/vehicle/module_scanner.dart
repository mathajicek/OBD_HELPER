import 'package:flutter/foundation.dart';

import '../elm/elm327.dart';
import '../obd/dtc.dart';
import '../uds/uds_client.dart';
import 'profiles.dart';

class ModuleResult {
  ModuleResult(this.ecu, {this.dtcs = const [], this.systemName, this.error});
  final Ecu ecu;
  List<Dtc> dtcs;
  final String? systemName;

  /// Set when the unit answered but refused reading fault codes.
  final String? error;

  String title(String fallback) => ecu.name ?? systemName ?? fallback;
}

/// Connects to every control unit of a [VehicleProfile] and reads its codes.
class ModuleScanner extends ChangeNotifier {
  ModuleScanner(this.uds);
  final UdsClient uds;

  final List<ModuleResult> found = [];
  bool running = false;
  int probed = 0;
  int total = 0;
  bool _cancel = false;

  int get faultCount => found.fold(0, (n, m) => n + m.dtcs.length);

  void cancel() => _cancel = true;

  /// Probes the profile's known units; with [deep], also every address of
  /// its sweep ranges.
  Future<void> scan(VehicleProfile profile, {bool deep = false}) async {
    final candidates = <Ecu>[...profile.ecus];
    if (deep) {
      final known = {for (final e in candidates) '${e.tx}/${e.rx}/${e.extAddr}'};
      for (final r in profile.sweep) {
        candidates.addAll(r.ecus().where((e) => known.add('${e.tx}/${e.rx}/${e.extAddr}')));
      }
    }
    found.clear();
    running = true;
    _cancel = false;
    probed = 0;
    total = candidates.length;
    notifyListeners();
    try {
      for (final ecu in candidates) {
        if (_cancel) break;
        final r = await probe(ecu);
        if (r != null) found.add(r);
        probed++;
        notifyListeners();
      }
    } finally {
      try {
        await uds.release();
      } catch (_) {}
      running = false;
      notifyListeners();
    }
  }

  /// Returns null when nothing answers at [ecu]'s address.
  @visibleForTesting
  Future<ModuleResult?> probe(Ecu ecu) async {
    try {
      await uds.select(ecu, responseTimeout: const Duration(milliseconds: 160));
      List<Dtc> dtcs;
      String? error;
      try {
        dtcs = await uds.readDtcs();
      } on UdsNegativeResponse catch (e) {
        dtcs = const [];
        error = e.name;
      }
      String? name;
      try {
        final raw = await uds.readDid(0xF197);
        name = String.fromCharCodes(raw.where((b) => b >= 0x20 && b < 0x7F)).trim();
        if (name.isEmpty) name = null;
      } catch (_) {}
      return ModuleResult(ecu, dtcs: dtcs, systemName: name, error: error);
    } on UdsNegativeResponse catch (e) {
      return ModuleResult(ecu, error: e.name);
    } on ElmException {
      return null;
    }
  }

  /// Clears codes in one unit and reads them again.
  Future<void> clear(ModuleResult m) async {
    await uds.select(m.ecu);
    try {
      await uds.clearDtcs();
      m.dtcs = await uds.readDtcs();
    } finally {
      await uds.release();
    }
    notifyListeners();
  }
}
