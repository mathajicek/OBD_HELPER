import 'package:flutter_test/flutter_test.dart';
import 'package:obd_pulse/core/elm/elm327.dart';
import 'package:obd_pulse/core/obd/dtc.dart';
import 'package:obd_pulse/core/obd/pids.dart';

void main() {
  group('Elm327.clean', () {
    test('removes echo and SEARCHING line', () {
      expect(Elm327.clean('010C\rSEARCHING...\r41 0C 1A F8\r\r', '010C'), '41 0C 1A F8');
    });
  });

  group('Elm327.parseMessages', () {
    test('single frame', () {
      expect(Elm327.parseMessages('41 0C 1A F8'), [
        [0x41, 0x0C, 0x1A, 0xF8]
      ]);
    });

    test('multi-frame VIN reply (CAN formatting)', () {
      const text = '014\n0: 49 02 01 54 4D 42\n1: 4A 4A 37 4E 45 30 4B\n2: 30 31 32 33 34 35 36';
      final m = Elm327.parseMessages(text);
      expect(m, hasLength(1));
      expect(m.first, hasLength(0x14));
      expect(String.fromCharCodes(m.first.sublist(3)), 'TMBJJ7NE0K0123456');
    });

    test('several ECUs answering', () {
      expect(Elm327.parseMessages('41 0D 32\n41 0D 32'), hasLength(2));
    });

    test('NO DATA throws NoDataException', () {
      expect(() => Elm327.parseMessages('NO DATA', '0146'), throwsA(isA<NoDataException>()));
    });

    test('bus errors throw', () {
      expect(() => Elm327.parseMessages('UNABLE TO CONNECT'), throwsA(isA<ElmException>()));
      expect(() => Elm327.parseMessages('CAN ERROR'), throwsA(isA<ElmException>()));
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

    test('CAN mode 03 with count byte', () {
      final codes = parseDtcMessages([
        [0x43, 0x02, 0x03, 0x00, 0x04, 0x20]
      ], 0x43, isCan: true);
      expect(codes, ['P0300', 'P0420']);
    });

    test('K-line mode 03 padded with zeros', () {
      final codes = parseDtcMessages([
        [0x43, 0x01, 0x71, 0x00, 0x00, 0x00, 0x00]
      ], 0x43, isCan: false);
      expect(codes, ['P0171']);
    });
  });

  group('PIDs', () {
    test('formulas', () {
      expect(pidById[0x0C]!.decode([0x1A, 0xF8]), 1726);
      expect(pidById[0x05]!.decode([0x7B]), 83);
      expect(pidById[0x42]!.decode([0x37, 0x1E]), closeTo(14.11, 0.01));
      expect(pidById[0x06]!.decode([0x80]), 0);
      expect(pidById[0x04]!.decode([0xFF]), 100);
    });

    test('supported bitmask', () {
      // BE 1F A8 13 is a typical reply to 0100
      final s = decodeSupported(0x00, [0xBE, 0x1F, 0xA8, 0x13]);
      expect(s, containsAll([0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0C, 0x0D, 0x0F, 0x10, 0x11, 0x20]));
      expect(s.contains(0x02), isFalse);
    });
  });
}
