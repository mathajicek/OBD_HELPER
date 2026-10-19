import 'package:flutter_test/flutter_test.dart';
import 'package:obd_pulse/core/elm/elm327.dart';
import 'package:obd_pulse/core/obd/dtc.dart';
import 'package:obd_pulse/core/obd/pids.dart';
import 'package:obd_pulse/data/dtc_related.dart';

List<EcuMessage> parseCan(String text, {bool is29 = false}) =>
    Elm327.parseHeaderMessages(text, isCan: true, is29Bit: is29);

void main() {
  group('Elm327.clean', () {
    test('removes echo and SEARCHING line', () {
      expect(Elm327.clean('010C\rSEARCHING...\r7E8 04 41 0C 1A F8\r\r', '010C'), '7E8 04 41 0C 1A F8');
    });

    test('drops a successful K-line BUS INIT status line', () {
      expect(Elm327.clean('BUS INIT: ...OK\r48 6B 10 41 00 BE 1F B8 10 C3', '0100'), '48 6B 10 41 00 BE 1F B8 10 C3');
    });
  });

  group('parseHeaderMessages', () {
    test('11-bit single frame strips the PCI byte', () {
      final m = parseCan('7E8 04 41 0C 1A F8');
      expect(m.single.source, 0x7E8);
      expect(m.single.data, [0x41, 0x0C, 0x1A, 0xF8]);
    });

    test('reassembles multi-frame per sender', () {
      const text = '7E8 10 14 49 02 01 54 4D 42\n7E8 21 4A 4A 37 4E 45 30 4B\n7E8 22 30 31 32 33 34 35 36';
      final m = parseCan(text);
      expect(m.single.data, hasLength(0x14));
      expect(String.fromCharCodes(m.single.data.sublist(3)), 'TMBJJ7NE0K0123456');
    });

    test('interleaved multi-frame from two units stays separate', () {
      const text = '7E8 10 08 43 03 03 00 01 71\n7E9 02 43 00\n7E8 21 04 20 00 00 00 00 00';
      final m = parseCan(text);
      expect(m, hasLength(2));
      final engine = m.firstWhere((x) => x.source == 0x7E8);
      expect(parseDtcMessages([engine.data], 0x43, isCan: true), ['P0300', 'P0171', 'P0420']);
    });

    test('29-bit headers', () {
      final m = parseCan('18 DA F1 10 03 41 0D 32', is29: true);
      expect(m.single.source, 0x18DAF110);
      expect(m.single.data, [0x41, 0x0D, 0x32]);
    });

    test('lines without spaces (ATS0)', () {
      expect(parseCan('7E804410C1AF8').single.data, [0x41, 0x0C, 0x1A, 0xF8]);
    });

    test('K-line header and checksum are removed', () {
      final m = Elm327.parseHeaderMessages('48 6B 10 43 01 33 00 00 00 00 C2', isCan: false);
      expect(m.single.source, 0x10);
      expect(m.single.data, [0x43, 0x01, 0x33, 0x00, 0x00, 0x00, 0x00]);
    });

    test('extended addressing drops the address byte', () {
      final m = Elm327.parseHeaderMessages('612 F1 03 7F 19 11', isCan: true, extAddr: true);
      expect(m.single.data, [0x7F, 0x19, 0x11]);
    });

    test('errors', () {
      expect(() => parseCan('NO DATA'), throwsA(isA<NoDataException>()));
      expect(() => parseCan('UNABLE TO CONNECT'), throwsA(isA<ElmException>()));
      expect(() => parseCan('CAN ERROR'), throwsA(isA<ElmException>()));
      expect(() => parseCan('BUS INIT: ...ERROR'), throwsA(isA<ElmException>()));
    });
  });

  group('DTC decoding', () {
    test('two-byte codes', () {
      expect(decodeDtc(0x03, 0x00), 'P0300');
      expect(decodeDtc(0x01, 0x71), 'P0171');
      expect(decodeDtc(0x44, 0x20), 'C0420');
      expect(decodeDtc(0x81, 0x23), 'B0123');
      expect(decodeDtc(0xC1, 0x00), 'U0100');
      expect(decodeDtc(0x1A, 0xBC), 'P1ABC');
    });

    test('K-line mode 03 padded with zeros', () {
      expect(
        parseDtcMessages(
          [
            [0x43, 0x01, 0x71, 0x00, 0x00, 0x00, 0x00],
          ],
          0x43,
          isCan: false,
        ),
        ['P0171'],
      );
    });

    test('UDS 0x19 records with failure type and status', () {
      final d = parseUdsDtcs([
        0x59,
        0x02,
        0xFF,
        0x40,
        0x35,
        0x29,
        0x2F,
        0x90,
        0x01,
        0x13,
        0x04,
        0x01,
        0x02,
        0x03,
        0x00,
      ]);
      expect(d.map((x) => x.display), ['C0035-29', 'B1001-13']);
      expect(d.first.kind, DtcKind.stored);
      expect(d.last.kind, DtcKind.pending);
    });

    test('KWP2000 0x18 records', () {
      expect(parseKwpDtcs([0x58, 0x01, 0x01, 0x71, 0x20]).single.code, 'P0171');
    });
  });

  group('PIDs', () {
    test('formulas', () {
      expect(pidByKey['0C']!.decode([0x1A, 0xF8]), 1726);
      expect(pidByKey['05']!.decode([0x7B]), 83);
      expect(pidByKey['42']!.decode([0x37, 0x1E]), closeTo(14.11, 0.01));
      expect(pidByKey['06']!.decode([0x80]), 0);
      expect(pidByKey['14v']!.decode([0x5A, 0x80]), closeTo(0.45, 0.001));
      expect(pidByKey['3C']!.decode([0x19, 0xC8]), closeTo(620, 0.1));
      expect(pidByKey['A6']!.decode([0x00, 0x01, 0xE2, 0x40]), closeTo(12345.6, 0.01));
    });

    test('keys are unique and cover many standard values', () {
      expect(pidByKey.length, allPids.length);
      expect(allPids.length, greaterThan(80));
    });

    test('supported bitmask', () {
      final s = decodeSupported(0x00, [0xBE, 0x1F, 0xA8, 0x13]);
      expect(s, containsAll([0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0C, 0x0D, 0x0F, 0x10, 0x11, 0x20]));
      expect(s.contains(0x02), isFalse);
    });
  });

  group('Related values', () {
    test('sensor codes map to live values and sensor data', () {
      final ect = relatedFor('P0117');
      expect(ect.pids, contains('05'));
      expect(ect.sensor, isNotNull);
      expect(relatedFor('P0300').pids, contains('0C'));
      expect(relatedFor('P2135').sensor, isNotNull);
      expect(relatedFor('U0100').pids, ['42']);
    });

    test('every related key exists', () {
      for (final code in [
        'P0101',
        'P0107',
        'P0113',
        'P0117',
        'P0122',
        'P0133',
        'P0171',
        'P0300',
        'P0327',
        'P0335',
        'P0401',
        'P0420',
        'P0442',
        'P0500',
        'P0505',
        'P0562',
        'P0700',
        'P2122',
        'C0035',
        'U0100',
        'P1234',
      ]) {
        for (final k in relatedFor(code).pids) {
          expect(pidByKey.containsKey(k), isTrue, reason: '$code → $k');
        }
      }
    });
  });
}
