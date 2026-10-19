import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/elm/elm327.dart';
import 'core/obd/dtc.dart';
import 'core/obd/live_data.dart';
import 'core/obd/obd_service.dart';
import 'core/transport/obd_transport.dart';
import 'core/uds/coding_service.dart';
import 'core/uds/uds_client.dart';
import 'core/vehicle/module_scanner.dart';
import 'core/vehicle/profiles.dart';
import 'l10n/strings.dart';

enum ConnState { off, connecting, on }

class AppState extends ChangeNotifier {
  AppState({BackupStore? backupStore}) : backupStore = backupStore ?? PrefsBackupStore();

  final BackupStore backupStore;

  String lang = 'cs';
  ConnState conn = ConnState.off;
  String? error;
  String? adapterName;
  String? vin;

  Elm327? elm;
  ObdService? obd;
  LiveDataController? live;
  CodingService? coding;
  ModuleScanner? modules;

  /// Selected manufacturer profile (see `vehicleProfiles`).
  String profileId = 'generic';
  VehicleProfile get profile => profileById(profileId);

  bool scanning = false;
  bool scanned = false;
  List<Dtc> dtcs = [];

  /// Troubleshooting steps the user ticked off, keyed `CODE-index`.
  final Set<String> doneSteps = {};

  String t(String key) => strings[lang]?[key] ?? strings['en']?[key] ?? key;

  Future<void> loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      lang = prefs.getString('lang') ?? lang;
      profileId = prefs.getString('profile') ?? profileId;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setLang(String value) async {
    lang = value;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setString('lang', value);
    } catch (_) {}
  }

  Future<void> setProfile(String id) async {
    profileId = id;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setString('profile', id);
    } catch (_) {}
  }

  /// Opens [transport], initialises the ELM327 and reads the VIN.
  Future<void> connect(Future<ObdTransport> Function() open) async {
    conn = ConnState.connecting;
    error = null;
    notifyListeners();
    try {
      final transport = await open();
      final e = Elm327(transport);
      await e.initialize();
      elm = e;
      obd = ObdService(e);
      live = LiveDataController(obd!);
      final uds = UdsClient(e);
      coding = CodingService(uds, backupStore);
      modules = ModuleScanner(uds);
      adapterName = transport.name;
      vin = await obd!.readVin();
      await live!.loadSupported();
      conn = ConnState.on;
    } catch (ex) {
      error = 'init_failed';
      conn = ConnState.off;
      await elm?.close();
      elm = null;
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    live?.stop();
    await elm?.close();
    elm = null;
    obd = null;
    live = null;
    coding = null;
    modules?.cancel();
    modules = null;
    conn = ConnState.off;
    scanned = false;
    dtcs = [];
    notifyListeners();
  }

  /// Reads emission codes (OBD modes 03/07/0A), then connects to every
  /// control unit of the selected profile and reads its codes over UDS.
  Future<void> scan({bool deep = false}) async {
    if (obd == null) return;
    live?.stop();
    scanning = true;
    error = null;
    notifyListeners();
    try {
      dtcs = await obd!.readDtcs();
    } catch (_) {
      dtcs = [];
    }
    try {
      // UDS addressing needs CAN; older K-line cars only offer OBD modes.
      if (elm!.isCan) await modules?.scan(profile, deep: deep);
      scanned = true;
    } catch (_) {
      error = 'scan_failed';
    }
    scanning = false;
    notifyListeners();
  }

  Future<void> clearCodes() async {
    await obd?.clearDtcs();
    for (final m in List.of(modules?.found ?? <ModuleResult>[])) {
      try {
        await modules!.clear(m);
      } catch (_) {}
    }
    doneSteps.clear();
    await scan();
  }

  void toggleStep(String key) {
    doneSteps.contains(key) ? doneSteps.remove(key) : doneSteps.add(key);
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
