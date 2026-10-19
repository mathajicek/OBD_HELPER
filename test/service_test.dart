import 'package:flutter_test/flutter_test.dart';
import 'package:obd_pulse/core/elm/elm327.dart';
import 'package:obd_pulse/core/obd/obd_service.dart';
import 'package:obd_pulse/core/service/service_catalog.dart';
import 'package:obd_pulse/core/service/service_runner.dart';
import 'package:obd_pulse/core/transport/sim_transport.dart';
import 'package:obd_pulse/core/uds/uds_client.dart';
import 'package:obd_pulse/core/vehicle/profiles.dart';

void main() {
  late SimTransport sim;
  late Elm327 elm;
  late ServiceRunner runner;

  setUp(() async {
    sim = SimTransport(latency: const Duration(milliseconds: 1));
    elm = Elm327(sim);
    await elm.initialize();
    runner = ServiceRunner(ObdService(elm), UdsClient(elm));
  });

  tearDown(() => elm.close());

  group('Catalog', () {
    test('ids are unique and every group has functions', () {
      expect(serviceFunctions.map((f) => f.id).toSet().length, serviceFunctions.length);
      for (final g in ServiceGroup.values) {
        expect(serviceFunctions.where((f) => f.group == g), isNotEmpty, reason: g.name);
      }
    });

    test('every function offers a way for every profile', () {
      for (final f in serviceFunctions) {
        for (final p in vehicleProfiles) {
          final hasWay = f.actions.containsKey('*') || f.manualFor(p.id).isNotEmpty || f.workshop != null;
          expect(hasWay, isTrue, reason: '${f.id} / ${p.id}');
        }
      }
    });

    test('oil reset has a hand procedure for every make', () {
      final oil = serviceById('oil_reset');
      for (final p in vehicleProfiles) {
        expect(oil.manualFor(p.id), isNotEmpty, reason: p.id);
      }
    });

    test('demo definitions never apply to a real profile', () {
      for (final f in serviceFunctions) {
        for (final p in vehicleProfiles) {
          expect(f.actions[p.id]?.source, isNot('demo'));
        }
        expect(f.actions['*']?.source, isNot('demo'));
      }
    });
  });

  group('Runner', () {
    test('runs a routine to completion and returns to OBD mode', () async {
      await runner.run(serviceById('oil_reset').actions['demo']!);
      expect(sim.modules[0x714]!.completed, [0xDE01]);
      expect(sim.modules[0x714]!.session, 0x01);
      expect(await ObdService(elm).readVin(), SimTransport.vin);
    });

    test('generic adaptation reset uses OBD mode 04', () async {
      await runner.run(serviceById('fuel_trim_reset').actions['*']!);
      expect(await ObdService(elm).readDtcs(), isEmpty);
    });

    test('unknown routine is reported as not supported', () async {
      const bad = ServiceAction(tx: 0x714, rx: 0x77E, steps: [RoutineStep(0x1234)]);
      await expectLater(
        runner.run(bad),
        throwsA(isA<ServiceException>().having((e) => e.key, 'key', 'svc_not_supported')),
      );
      expect(await ObdService(elm).readVin(), SimTransport.vin);
    });

    test('engine state is checked', () async {
      // The simulated engine idles, so an engine-off function is refused.
      await expectLater(
        runner.verify(serviceById('throttle_adapt')),
        throwsA(isA<ServiceException>().having((e) => e.key, 'key', 'svc_engine_off')),
      );
      await runner.verify(serviceById('throttle_adapt'), checkEngine: false);
      await runner.verify(serviceById('dpf_regen'));
    });
  });

  group('Import', () {
    test('parses definitions and prefers the profile match', () {
      final imports = ServiceImports();
      final n = imports.add(
        '[{"function":"oil_reset","profile":"vag","tx":"714","rx":"77E","steps":[{"routine":"DE01"}]},'
        '{"function":"dpf_regen","tx":"7E0","rx":"7E8","session":"03","steps":[{"routine":"DE05","params":"01","poll":false}]}]',
      );
      expect(n, 2);
      expect(imports.find('oil_reset', 'vag')!.tx, 0x714);
      expect(imports.find('oil_reset', 'bmw'), isNull);
      final dpf = imports.find('dpf_regen', 'bmw')!.steps.single as RoutineStep;
      expect(dpf.params, [0x01]);
      expect(dpf.poll, isFalse);
    });

    test('rejects bad definitions', () {
      final imports = ServiceImports();
      expect(() => imports.add('{"function":"nope","steps":[{"obd":"clear"}]}'), throwsA(anything));
      expect(() => imports.add('{"function":"oil_reset","steps":[{"routine":"DE01"}]}'), throwsA(anything));
      expect(() => imports.add('{"function":"oil_reset","tx":"714","steps":[]}'), throwsA(anything));
    });
  });
}
