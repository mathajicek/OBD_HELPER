import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../elm/elm327.dart';
import '../obd/obd_service.dart';
import '../obd/pids.dart';
import '../uds/uds_client.dart';
import 'service_catalog.dart';

class ServiceException implements Exception {
  ServiceException(this.key, [this.detail]);

  /// Localisation key.
  final String key;
  final String? detail;
}

/// Readings checked before a function runs.
class ServiceChecks {
  ServiceChecks(this.battery, this.rpm);
  final double? battery;
  final double? rpm;

  bool get engineRunning => (rpm ?? 0) > 300;
}

/// Runs executable service functions over the adapter.
class ServiceRunner {
  ServiceRunner(this.obd, this.uds);
  final ObdService obd;
  final UdsClient uds;

  static const minBattery = 12.0;

  Future<ServiceChecks> checks() async {
    Future<double?> pid(String key) async {
      try {
        return await obd.readPid(pidByKey[key]!);
      } catch (_) {
        return null;
      }
    }

    return ServiceChecks(await pid('42'), await pid('0C'));
  }

  /// Verifies battery and engine state for [f]; throws with the reason.
  /// [checkEngine] is off in demo mode, where the simulated engine always idles.
  Future<void> verify(ServiceFunction f, {bool checkEngine = true}) async {
    final c = await checks();
    if (c.battery != null && c.battery! < minBattery) {
      throw ServiceException('svc_low_battery', '${c.battery!.toStringAsFixed(1)} V');
    }
    if (!checkEngine) return;
    if (f.engine == EngineState.off && c.engineRunning) throw ServiceException('svc_engine_off');
    if (f.engine == EngineState.running && c.rpm != null && !c.engineRunning) {
      throw ServiceException('svc_engine_on');
    }
  }

  /// Runs [action]. [onProgress] receives a localisation key per stage.
  Future<void> run(ServiceAction action, {void Function(String key)? onProgress}) async {
    if (!action.isUds) {
      for (final s in action.steps) {
        if (s is ObdClearStep) {
          onProgress?.call('svc_step_obd');
          await obd.clearDtcs();
        }
      }
      return;
    }
    try {
      await uds.select(Ecu('svc', action.tx!, action.rx!));
      if (action.session != 0) {
        onProgress?.call('svc_step_session');
        await uds.session(action.session);
      }
      for (final s in action.steps) {
        switch (s) {
          case RoutineStep():
            onProgress?.call('svc_step_routine');
            await _routine(s);
          case WriteDidStep():
            onProgress?.call('svc_step_write');
            await uds.writeDid(s.did, s.data);
          case ObdClearStep():
            break;
        }
      }
      onProgress?.call('svc_step_done');
    } on UdsNegativeResponse catch (e) {
      throw ServiceException(switch (e.nrc) {
        0x33 || 0x35 => 'svc_security',
        0x22 || 0x24 => 'svc_conditions',
        0x11 || 0x12 || 0x31 || 0x7E || 0x7F => 'svc_not_supported',
        _ => 'svc_failed',
      }, e.name);
    } on ElmException catch (e) {
      throw ServiceException('svc_no_response', e.message);
    } finally {
      try {
        if (action.session != 0) await uds.session(0x01);
      } catch (_) {}
      await uds.release();
    }
  }

  Future<void> _routine(RoutineStep s) async {
    final id = [s.rid >> 8, s.rid & 0xFF];
    await uds.request([0x31, 0x01, ...id, ...s.params], timeout: const Duration(seconds: 10));
    if (!s.poll) return;
    for (var i = 0; i < 120; i++) {
      final List<int> r;
      try {
        r = await uds.request([0x31, 0x03, ...id]);
      } on UdsNegativeResponse catch (e) {
        // Units that report no results finish on start.
        if (e.nrc == 0x12 || e.nrc == 0x31 || e.nrc == 0x24) return;
        rethrow;
      }
      // 71 03 RID status…: 0x00 = finished, anything else still running.
      if (r.length < 5 || r[4] == 0x00) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw ServiceException('svc_timeout');
  }
}

/// Definitions the user imported, keyed `function:profile`.
class ServiceImports {
  static const _key = 'service_imports';
  final Map<String, ServiceAction> actions = {};
  final Map<String, String> _raw = {};

  ServiceAction? find(String function, String profile) => actions['$function:$profile'] ?? actions['$function:*'];

  /// Parses a JSON object or array of definitions; returns how many were added.
  int add(String text) {
    final decoded = jsonDecode(text);
    final list = decoded is List ? decoded : [decoded];
    var n = 0;
    for (final item in list) {
      final j = item as Map<String, dynamic>;
      final fn = j['function'] as String;
      serviceById(fn); // throws for unknown functions
      final key = '$fn:${(j['profile'] as String?) ?? '*'}';
      actions[key] = ServiceAction.fromJson(j);
      _raw[key] = jsonEncode(j);
      n++;
    }
    return n;
  }

  void clear() {
    actions.clear();
    _raw.clear();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final s in prefs.getStringList(_key) ?? <String>[]) {
        try {
          add(s);
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      (await SharedPreferences.getInstance()).setStringList(_key, _raw.values.toList());
    } catch (_) {}
  }
}
