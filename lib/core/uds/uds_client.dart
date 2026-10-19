import '../elm/elm327.dart';
import '../obd/dtc.dart';

/// A control unit reachable on CAN.
class Ecu {
  const Ecu(this.key, this.tx, this.rx, {this.name, this.codingDid = 0x0600, this.extAddr});

  /// Localisation key for the name (e.g. `ecu_engine`), or a free-form id.
  final String key;

  /// Optional literal name (used by manufacturer profiles).
  final String? name;

  /// Request (tester → ECU) CAN id.
  final int tx;

  /// Response (ECU → tester) CAN id.
  final int rx;

  /// Data identifier holding the coding (VAG long coding is 0x0600).
  final int codingDid;

  /// ISO 15765-2 extended address (first data byte), e.g. BMW units behind
  /// the 0x6F1 tester id. Null for normal addressing.
  final int? extAddr;

  String get txHex => tx.toRadixString(16).padLeft(3, '0').toUpperCase();
  String get rxHex => rx.toRadixString(16).padLeft(3, '0').toUpperCase();

  String get address =>
      extAddr == null ? '$txHex/$rxHex' : '$txHex/${extAddr!.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

/// Units used by the coding screen. VAG ids are common on MQB cars but not
/// universal: verify on your car.
const knownEcus = [
  Ecu('ecu_engine', 0x7E0, 0x7E8),
  Ecu('ecu_transmission', 0x7E1, 0x7E9),
  Ecu('ecu_gateway', 0x710, 0x77A),
  Ecu('ecu_cluster', 0x714, 0x77E),
];

class UdsNegativeResponse implements Exception {
  UdsNegativeResponse(this.service, this.nrc);
  final int service;
  final int nrc;

  static const names = {
    0x10: 'generalReject',
    0x11: 'serviceNotSupported',
    0x12: 'subFunctionNotSupported',
    0x13: 'incorrectMessageLength',
    0x22: 'conditionsNotCorrect',
    0x24: 'requestSequenceError',
    0x31: 'requestOutOfRange',
    0x33: 'securityAccessDenied',
    0x35: 'invalidKey',
    0x72: 'generalProgrammingFailure',
    0x7E: 'subFunctionNotSupportedInActiveSession',
    0x7F: 'serviceNotSupportedInActiveSession',
  };

  String get name => names[nrc] ?? 'NRC 0x${nrc.toRadixString(16)}';

  @override
  String toString() => 'UDS 0x${service.toRadixString(16)} rejected: $name';
}

/// Minimal ISO 14229 (UDS) / ISO 14230 (KWP2000 on CAN) client on an ELM327.
///
/// Single-frame requests use the ELM's own CAN formatting. Longer requests
/// (e.g. writing a long coding) are segmented by hand into ISO-TP frames,
/// because the ELM327 cannot send multi-frame messages by itself.
class UdsClient {
  UdsClient(this.elm);
  final Elm327 elm;
  Ecu? _ecu;

  Future<void> select(Ecu ecu, {Duration? responseTimeout}) async {
    await elm.send('ATSH ${ecu.txHex}');
    await elm.send('ATCRA ${ecu.rxHex}');
    if (ecu.extAddr != null) {
      final ea = ecu.extAddr!.toRadixString(16).padLeft(2, '0').toUpperCase();
      await elm.send('ATCEA $ea');
      elm.extendedAddressing = true;
    } else {
      await elm.send('ATCEA');
      elm.extendedAddressing = false;
    }
    await elm.send('ATFCSH ${ecu.txHex}');
    await elm.send('ATFCSD 300000');
    await elm.send('ATFCSM1');
    if (responseTimeout != null) {
      // ATST counts in units of 4 ms.
      final st = (responseTimeout.inMilliseconds ~/ 4).clamp(1, 255);
      await elm.send('ATST ${st.toRadixString(16).padLeft(2, '0').toUpperCase()}');
    }
    _ecu = ecu;
  }

  /// Returns the adapter to plain OBD (functional broadcast) mode.
  Future<void> release() async {
    await elm.send('ATCAF1');
    await elm.send('ATR1');
    await elm.send('ATFCSM0');
    await elm.send('ATCEA');
    elm.extendedAddressing = false;
    await elm.send('ATST FF');
    await elm.send('ATAR');
    await elm.send('ATSH 7DF');
    _ecu = null;
  }

  Future<List<int>> request(List<int> req, {Duration? timeout}) async {
    if (_ecu == null) throw StateError('No ECU selected');
    final List<EcuMessage> messages;
    if (req.length <= (_ecu!.extAddr == null ? 7 : 6)) {
      messages = await elm.request(bytesToHex(req, sep: ' '), timeout: timeout ?? const Duration(seconds: 5));
    } else {
      messages = await _sendMultiFrame(req);
    }
    return _positive(req[0], messages);
  }

  List<int> _positive(int sid, List<EcuMessage> messages) {
    for (final m in messages) {
      final d = m.data;
      if (d.isNotEmpty && d[0] == sid + 0x40) return d;
    }
    for (final m in messages) {
      final d = m.data;
      if (d.length >= 3 && d[0] == 0x7F && d[2] != 0x78) throw UdsNegativeResponse(d[1], d[2]);
    }
    throw ElmException('No response to service 0x${sid.toRadixString(16)}');
  }

  Future<List<EcuMessage>> _sendMultiFrame(List<int> req) async {
    await elm.send('ATCAF0');
    try {
      final first = [0x10 | (req.length >> 8 & 0x0F), req.length & 0xFF, ...req.take(6)];
      final fc = await elm.requestRaw(bytesToHex(first, sep: ' '));
      final flow = fc
          .map((m) => m.data)
          .firstWhere(
            (d) => d.isNotEmpty && d[0] >> 4 == 3,
            orElse: () => throw ElmException('No ISO-TP flow control'),
          );
      if (flow[0] & 0x0F != 0) throw ElmException('ECU refused ISO-TP transfer');
      final stMin = flow.length > 2 ? flow[2] : 0;

      final rest = req.sublist(6);
      final frames = <List<int>>[];
      for (var i = 0, sn = 1; i < rest.length; i += 7, sn++) {
        final chunk = rest.sublist(i, i + 7 > rest.length ? rest.length : i + 7);
        frames.add(_pad([0x20 | (sn & 0x0F), ...chunk]));
      }
      await elm.send('ATR0');
      for (var i = 0; i < frames.length - 1; i++) {
        await elm.send(bytesToHex(frames[i], sep: ' '));
        if (stMin > 0 && stMin <= 0x7F) await Future<void>.delayed(Duration(milliseconds: stMin));
      }
      await elm.send('ATR1');
      final reply = await elm.requestRaw(bytesToHex(frames.last, sep: ' '), timeout: const Duration(seconds: 5));
      // CAF off: frames are raw; keep single-frame payloads.
      return [
        for (final m in reply)
          if (m.data.isNotEmpty && m.data[0] >> 4 == 0)
            EcuMessage(m.source, m.data.sublist(1, (1 + (m.data[0] & 0x0F)).clamp(1, m.data.length))),
      ];
    } finally {
      await elm.send('ATR1');
      await elm.send('ATCAF1');
    }
  }

  static List<int> _pad(List<int> f) => [...f, ...List.filled(8 - f.length, 0x55)];

  Future<void> session(int type) => request([0x10, type]);

  Future<void> testerPresent() => request([0x3E, 0x00]);

  Future<List<int>> readDid(int did) async {
    final r = await request([0x22, did >> 8, did & 0xFF]);
    return r.sublist(3);
  }

  Future<void> writeDid(int did, List<int> data) => request([0x2E, did >> 8, did & 0xFF, ...data]);

  /// Reads active fault codes: UDS 0x19 0x02, falling back to KWP2000 0x18.
  Future<List<Dtc>> readDtcs() async {
    try {
      final r = await request([0x19, 0x02, 0xFF], timeout: const Duration(seconds: 4));
      return parseUdsDtcs(r, source: _ecu?.rx);
    } on UdsNegativeResponse catch (e) {
      if (e.nrc != 0x11 && e.nrc != 0x12) rethrow;
    }
    final r = await request([0x18, 0x02, 0xFF, 0x00], timeout: const Duration(seconds: 4));
    return parseKwpDtcs(r, source: _ecu?.rx);
  }

  /// Clears all fault codes: UDS 0x14 FFFFFF, falling back to KWP2000 0x14 FF00.
  Future<void> clearDtcs() async {
    try {
      await request([0x14, 0xFF, 0xFF, 0xFF]);
    } on UdsNegativeResponse catch (e) {
      if (e.nrc != 0x13 && e.nrc != 0x11) rethrow;
      await request([0x14, 0xFF, 0x00]);
    }
  }
}
