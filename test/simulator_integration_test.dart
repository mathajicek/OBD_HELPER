import 'package:flutter_test/flutter_test.dart';
import 'package:obd_pulse/core/elm/elm327.dart';
import 'package:obd_pulse/core/obd/dtc.dart';
import 'package:obd_pulse/core/obd/live_data.dart';
import 'package:obd_pulse/core/obd/obd_service.dart';
import 'package:obd_pulse/core/obd/pids.dart';
import 'package:obd_pulse/core/transport/sim_transport.dart';
import 'package:obd_pulse/core/uds/coding_service.dart';
import 'package:obd_pulse/core/uds/uds_client.dart';

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

    test('reads stored and pending codes', () async {
      final dtcs = await ObdService(elm).readDtcs();
      expect(dtcs.where((d) => d.kind == DtcKind.stored).map((d) => d.code), ['P0300', 'P0171', 'P0420']);
      expect(dtcs.where((d) => d.kind == DtcKind.pending).map((d) => d.code), ['P0301']);
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
      final rpm = await obd.readPid(pidById[0x0C]!);
      final volts = await obd.readPid(pidById[0x42]!);
      expect(rpm, inInclusiveRange(700, 3000));
      expect(volts, inInclusiveRange(13.5, 15));
    });

    test('unsupported PID returns null', () async {
      expect(await ObdService(elm).readPid(Pid(0x0A, 'x', 'kPa', 1, 0, 1, (d) => 0)), isNull);
    });
  });

  group('Live data', () {
    test('collects history and marks unsupported PIDs', () async {
      final live = LiveDataController(ObdService(elm));
      live.selected
        ..clear()
        ..addAll([0x0C, 0x05]);
      for (var i = 0; i < 3; i++) {
        await live.sampleOnce(0x0C);
        await live.sampleOnce(0x05);
      }
      expect(live.history[0x0C], hasLength(3));
      expect(live.latest[0x05], isNotNull);
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
      expect(id.values[0xF187], '04E906016DE');
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
      expect(bytesToHex(sim.coding['714']!), bytesToHex(next));
      expect(await coding.readCoding(cluster), next);
    });

    test('writes short coding in a single frame', () async {
      final ecu = knownEcus.firstWhere((e) => e.key == 'ecu_transmission');
      final b = await coding.backup(ecu);
      await coding.writeCoding(ecu, [0x00, 0x23], backup: b);
      expect(sim.coding['7E1'], [0x00, 0x23]);
    });

    test('security access denial is reported, coding unchanged', () async {
      final b = await coding.backup(gateway);
      final before = bytesToHex(sim.coding['710']!);
      final next = List.of(b.bytes)..[0] = 0x03;
      await expectLater(
        coding.writeCoding(gateway, next, backup: b),
        throwsA(isA<CodingException>().having((e) => e.key, 'key', 'coding_security')),
      );
      expect(bytesToHex(sim.coding['710']!), before);
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
}
