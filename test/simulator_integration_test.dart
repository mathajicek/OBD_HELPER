import 'package:flutter_test/flutter_test.dart';
import 'package:obd_pulse/core/elm/elm327.dart';
import 'package:obd_pulse/core/obd/dtc.dart';
import 'package:obd_pulse/core/obd/live_data.dart';
import 'package:obd_pulse/core/obd/obd_service.dart';
import 'package:obd_pulse/core/obd/pids.dart';
import 'package:obd_pulse/core/transport/sim_transport.dart';
import 'package:obd_pulse/core/uds/coding_service.dart';
import 'package:obd_pulse/core/uds/uds_client.dart';
import 'package:obd_pulse/core/vehicle/module_scanner.dart';
import 'package:obd_pulse/core/vehicle/profiles.dart';

/// End-to-end tests against the simulated Vgate iCar Pro.
void main() {
  late SimTransport sim;
  late Elm327 elm;

  setUp(() async {
    sim = SimTransport(latency: const Duration(milliseconds: 1));
    elm = Elm327(sim);
    await elm.initialize();
  });

  tearDown(() => elm.close());

  test('initialisation detects CAN protocol and version', () {
    expect(elm.version, contains('ELM327'));
    expect(elm.protocol, 'A6');
    expect(elm.isCan, isTrue);
  });

  group('OBD', () {
    test('reads VIN', () async {
      expect(await ObdService(elm).readVin(), SimTransport.vin);
    });

    test('reads stored and pending codes, with two units answering', () async {
      final dtcs = await ObdService(elm).readDtcs();
      expect(dtcs.where((d) => d.kind == DtcKind.stored).map((d) => d.code), ['P0300', 'P0171', 'P0420']);
      expect(dtcs.where((d) => d.kind == DtcKind.pending).map((d) => d.code), ['P0301']);
      expect(dtcs.every((d) => d.source == 0x7E8), isTrue);
    });

    test('clears codes', () async {
      final obd = ObdService(elm);
      await obd.clearDtcs();
      expect(await obd.readDtcs(), isEmpty);
    });

    test('supported PIDs span several ranges', () async {
      final s = await ObdService(elm).supportedPids();
      expect(s, containsAll([0x0C, 0x0D, 0x05, 0x42, 0x5C]));
      expect(s.contains(0x0A), isFalse);
    });

    test('reads live values in plausible ranges', () async {
      final obd = ObdService(elm);
      final rpm = await obd.readPid(pidByKey['0C']!);
      final volts = await obd.readPid(pidByKey['42']!);
      expect(rpm, inInclusiveRange(700, 3000));
      expect(volts, inInclusiveRange(13.5, 15));
    });

    test('unsupported PID returns null', () async {
      expect(await ObdService(elm).readPid(Pid(0x0A, 'x', 'x', 'x', 'kPa', 1, 0, 1, PidGroup.fuel, (d) => 0)), isNull);
    });
  });

  group('Live data', () {
    test('collects history and marks unsupported PIDs', () async {
      final live = LiveDataController(ObdService(elm));
      live.selected
        ..clear()
        ..addAll(['0C', '05']);
      for (var i = 0; i < 3; i++) {
        await live.sampleOnce('0C');
        await live.sampleOnce('05');
      }
      expect(live.history['0C'], hasLength(3));
      expect(live.latest['05'], isNotNull);
      live.dispose();
    });
  });

  group('Coding (UDS)', () {
    final engine = knownEcus.firstWhere((e) => e.key == 'ecu_engine');
    final cluster = knownEcus.firstWhere((e) => e.key == 'ecu_cluster');
    final gateway = knownEcus.firstWhere((e) => e.key == 'ecu_gateway');

    late MemoryBackupStore store;
    late CodingService coding;
    setUp(() {
      store = MemoryBackupStore();
      coding = CodingService(UdsClient(elm), store);
    });

    test('reads identification', () async {
      final id = await coding.readIdentity(engine);
      expect(id.values[0xF197], 'R4 1.4l TSI');
      expect(id.values[0xF190], SimTransport.vin);
    });

    test('reads multi-frame coding and stores a backup', () async {
      final b = await coding.backup(gateway);
      expect(b.hex, '0101000200000000000000000000000000000000');
      expect(store.items, hasLength(1));
    });

    test('writes long coding with manual ISO-TP and verifies it', () async {
      final b = await coding.backup(cluster);
      final next = List.of(b.bytes)..[2] ^= 0x01;
      await coding.writeCoding(cluster, next, backup: b);
      expect(bytesToHex(sim.codingOf(0x714)!), bytesToHex(next));
      expect(await coding.readCoding(cluster), next);
    });

    test('writes short coding in a single frame', () async {
      final ecu = knownEcus.firstWhere((e) => e.key == 'ecu_transmission');
      final b = await coding.backup(ecu);
      await coding.writeCoding(ecu, [0x00, 0x23], backup: b);
      expect(sim.codingOf(0x7E1), [0x00, 0x23]);
    });

    test('security access denial is reported, coding unchanged', () async {
      final b = await coding.backup(gateway);
      final before = bytesToHex(sim.codingOf(0x710)!);
      final next = List.of(b.bytes)..[0] = 0x03;
      await expectLater(
        coding.writeCoding(gateway, next, backup: b),
        throwsA(isA<CodingException>().having((e) => e.key, 'key', 'coding_security')),
      );
      expect(bytesToHex(sim.codingOf(0x710)!), before);
    });

    test('refuses a write without a matching backup or with wrong length', () async {
      final b = await coding.backup(engine);
      await expectLater(coding.writeCoding(cluster, b.bytes, backup: b), throwsA(isA<CodingException>()));
      await expectLater(coding.writeCoding(engine, [0x00], backup: b), throwsA(isA<CodingException>()));
    });

    test('adapter returns to OBD mode after coding', () async {
      await coding.readCoding(engine);
      expect(await ObdService(elm).readVin(), SimTransport.vin);
    });
  });

  group('Module scan', () {
    test('VAG profile finds every unit with its fault count', () async {
      final scanner = ModuleScanner(UdsClient(elm));
      await scanner.scan(profileById('vag'));
      final byTx = {for (final m in scanner.found) m.ecu.tx: m};
      expect(byTx.keys, containsAll([0x7E0, 0x7E1, 0x713, 0x715, 0x710, 0x714]));
      expect(byTx[0x7E0]!.dtcs.map((d) => d.code), ['P0300', 'P0171', 'P0420', 'P0301']);
      expect(byTx[0x713]!.dtcs.single.display, 'C0035-29');
      expect(byTx[0x715]!.dtcs.single.code, 'B1001');
      expect(byTx[0x710]!.dtcs.single.code, 'U0100');
      expect(byTx[0x714]!.dtcs, isEmpty);
      expect(byTx[0x7E0]!.systemName, 'R4 1.4l TSI');
      expect(scanner.faultCount, 7);
      // Adapter is back in OBD mode afterwards.
      expect(await ObdService(elm).readVin(), SimTransport.vin);
    });

    test('deep scan finds a unit missing from the profile list', () async {
      final scanner = ModuleScanner(UdsClient(elm));
      const profile = VehicleProfile('t', 't', 't', [], [SweepRange(0x710, 0x716, 0x6A)]);
      await scanner.scan(profile, deep: true);
      expect(scanner.found.map((m) => m.ecu.tx), [0x710, 0x713, 0x714, 0x715]);
    });

    test('clearing one unit removes its codes', () async {
      final scanner = ModuleScanner(UdsClient(elm));
      await scanner.scan(profileById('vag'));
      final abs = scanner.found.firstWhere((m) => m.ecu.tx == 0x713);
      await scanner.clear(abs);
      expect(abs.dtcs, isEmpty);
    });
  });
}
