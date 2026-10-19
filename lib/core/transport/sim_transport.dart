import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../elm/elm327.dart';
import 'obd_transport.dart';

/// One simulated control unit.
class SimModule {
  SimModule(this.tx, this.rx, this.name, {List<List<int>>? dtcs, this.coding, this.securityLocked = false})
    : dtcs = dtcs ?? [];

  final int tx;
  final int rx;
  final String name;

  /// UDS fault records: [hi, mid, failureType, status].
  List<List<int>> dtcs;
  List<int>? coding;
  final bool securityLocked;
  int session = 1;
}

/// A software Vgate iCar Pro on a VAG-like car: answers ELM327 AT commands
/// (headers on or off), OBD2 modes 01/03/04/07/09/0A on the functional
/// address, and UDS 0x10/0x14/0x19/0x22/0x2E/0x3E per control unit,
/// including manual ISO-TP.
///
/// Used for the in-app demo mode and for tests, so the whole app can be
/// exercised without a car.
class SimTransport implements ObdTransport {
  SimTransport({this.latency = const Duration(milliseconds: 25), Random? random}) : _rnd = random ?? Random(7);

  final Duration latency;
  final Random _rnd;
  final _incoming = StreamController<List<int>>.broadcast();
  final _start = DateTime.now();

  bool _echo = true;
  bool _caf = true;
  bool _responses = true;
  bool _headers = false;
  String _header = '7DF';
  int? _rxFilter;

  static const vin = 'TMBJJ7NE0K0123456';

  final Map<int, SimModule> modules = {
    for (final m in [
      SimModule(
        0x7E0,
        0x7E8,
        'R4 1.4l TSI',
        dtcs: [
          [0x03, 0x00, 0x00, 0x2F],
          [0x01, 0x71, 0x00, 0x2F],
          [0x04, 0x20, 0x00, 0x2F],
          [0x03, 0x01, 0x00, 0x24], // pending
        ],
        coding: hexToBytes('0000140C2400000000'),
      ),
      SimModule(0x7E1, 0x7E9, 'DQ200-MQB', coding: hexToBytes('0021')),
      SimModule(
        0x713,
        0x77D,
        'ESC MQB',
        dtcs: [
          [0x40, 0x35, 0x29, 0x2F], // C0035 wheel speed sensor
        ],
      ),
      SimModule(
        0x715,
        0x77F,
        'Airbag VW20',
        dtcs: [
          [0x90, 0x01, 0x13, 0x09], // B1001
        ],
      ),
      SimModule(
        0x710,
        0x77A,
        'GW MQB High',
        dtcs: [
          [0xC1, 0x00, 0x00, 0x08], // U0100
        ],
        coding: hexToBytes('0101000200000000000000000000000000000000'),
        securityLocked: true,
      ),
      SimModule(0x714, 0x77E, 'KOMBI', coding: hexToBytes('2D0F0A100021000001000000')),
    ])
      m.tx: m,
  };

  /// Convenience accessors used by tests.
  List<int>? codingOf(int tx) => modules[tx]?.coding;

  static const _ident = {0xF187: 'PART', 0xF189: '0004', 0xF191: 'H13'};

  static const supported = [
    0x04, 0x05, 0x06, 0x07, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x14, 0x15, 0x1F, //
    0x2F, 0x33, 0x3C, 0x42, 0x46, 0x5C,
  ];

  // ISO-TP reassembly for CAF-off requests.
  List<int>? _rxBuf;
  int _rxLen = 0;

  @override
  String get name => 'Simulátor iCar Pro';

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> close() async => _incoming.close();

  String _lineBuf = '';

  @override
  Future<void> write(List<int> data) async {
    _lineBuf += ascii.decode(data);
    while (_lineBuf.contains('\r')) {
      final i = _lineBuf.indexOf('\r');
      final cmd = _lineBuf.substring(0, i).trim();
      _lineBuf = _lineBuf.substring(i + 1);
      final reply = _handle(cmd.toUpperCase().replaceAll(' ', ''));
      final out = '${_echo ? '$cmd\r' : ''}$reply\r\r>';
      Future<void>.delayed(latency, () {
        if (!_incoming.isClosed) _incoming.add(ascii.encode(out));
      });
    }
  }

  double get _t => DateTime.now().difference(_start).inMilliseconds / 1000;

  String _handle(String cmd) {
    if (cmd.startsWith('AT')) return _at(cmd.substring(2));
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(cmd) || cmd.length.isOdd) return '?';
    final bytes = hexToBytes(cmd);
    final tx = int.parse(_header, radix: 16);
    if (!_caf) return _rawFrame(tx, bytes);
    if (tx == 0x7DF) return _obd(bytes);
    final m = modules[tx];
    if (m == null || (_rxFilter != null && _rxFilter != m.rx)) return 'NO DATA';
    final resp = _uds(m, bytes);
    return resp == null ? 'NO DATA' : _format(m.rx, resp);
  }

  String _at(String c) {
    if (c == 'Z') {
      _echo = true;
      _caf = true;
      _responses = true;
      _headers = false;
      _header = '7DF';
      _rxFilter = null;
      return '\rELM327 v2.3';
    }
    if (c == 'I') return 'ELM327 v2.3';
    if (c == 'E0') _echo = false;
    if (c == 'E1') _echo = true;
    if (c == 'H0') _headers = false;
    if (c == 'H1') _headers = true;
    if (c == 'CAF0') _caf = false;
    if (c == 'CAF1') _caf = true;
    if (c == 'R0') _responses = false;
    if (c == 'R1') _responses = true;
    if (c == 'AR') _rxFilter = null;
    if (c.startsWith('CRA')) _rxFilter = c.length > 3 ? int.parse(c.substring(3), radix: 16) : null;
    if (c == 'DPN') return 'A6';
    if (c == 'RV') return '${(13.8 + _rnd.nextDouble() * 0.6).toStringAsFixed(1)}V';
    if (c.startsWith('SH')) _header = c.substring(2);
    return 'OK';
  }

  SimModule get _engine => modules[0x7E0]!;

  String _obd(List<int> b) {
    final mode = b[0];
    final e = _engine;
    switch (mode) {
      case 0x01:
        final pid = b.length > 1 ? b[1] : 0;
        if (pid % 0x20 == 0) return _format(e.rx, [0x41, pid, ..._mask(pid)]);
        final v = _pidValue(pid);
        return v == null ? 'NO DATA' : _format(e.rx, [0x41, pid, ...v]);
      case 0x03:
      case 0x07:
        final codes = e.dtcs.where((d) => mode == 0x03 ? d[3] & 0x08 != 0 : d[3] & 0x0C == 0x04).toList();
        // The transmission answers too, with no codes: two senders in one reply.
        return [
          _format(e.rx, [0x40 + mode, codes.length, ...codes.expand((d) => d.take(2))]),
          _format(0x7E9, [0x40 + mode, 0]),
        ].join('\r');
      case 0x0A:
        return _format(e.rx, [0x4A, 0]);
      case 0x04:
        e.dtcs = [];
        return '${_format(e.rx, [0x44])}\r${_format(0x7E9, [0x44])}';
      case 0x09:
        if (b.length > 1 && b[1] == 0x02) return _format(e.rx, [0x49, 0x02, 0x01, ...ascii.encode(vin)]);
        return 'NO DATA';
    }
    return 'NO DATA';
  }

  List<int> _mask(int base) {
    final m = [0, 0, 0, 0];
    for (final p in [...supported, 0x20, 0x40]) {
      if (p > base && p <= base + 0x20) {
        final i = p - base - 1;
        m[i ~/ 8] |= 0x80 >> (i % 8);
      }
    }
    return m;
  }

  List<int>? _pidValue(int pid) {
    final t = _t;
    final rpm = 820 + 1800 * (0.5 + 0.5 * sin(t / 3)) + _rnd.nextInt(40);
    int clamp(num v) => v.round().clamp(0, 255);
    switch (pid) {
      case 0x0C:
        final raw = (rpm * 4).round();
        return [raw >> 8, raw & 0xFF];
      case 0x0D:
        return [clamp(45 + 35 * sin(t / 6))];
      case 0x05:
        return [clamp(min(90.0, 40 + t * 2) + 40)];
      case 0x0F:
        return [clamp(28 + 40)];
      case 0x5C:
        return [clamp(min(95.0, 35 + t * 1.5) + 40)];
      case 0x04:
        return [clamp((22 + 30 * (0.5 + 0.5 * sin(t / 3))) * 2.55)];
      case 0x11:
        return [clamp((15 + 40 * (0.5 + 0.5 * sin(t / 3))) * 2.55)];
      case 0x0B:
        return [clamp(35 + 60 * (0.5 + 0.5 * sin(t / 3)))];
      case 0x10:
        final maf = ((4 + 20 * (0.5 + 0.5 * sin(t / 3))) * 100).round();
        return [maf >> 8, maf & 0xFF];
      case 0x06:
        return [clamp((8 + _rnd.nextDouble() * 4 + 100) * 1.28)];
      case 0x07:
        return [clamp((11 + 100) * 1.28)];
      case 0x0E:
        return [clamp((12 + 6 * sin(t / 2) + 64) * 2)];
      case 0x14:
        return [clamp((0.45 + 0.4 * sin(t * 3)) * 200), 0x80];
      case 0x15:
        return [clamp(0.65 * 200), 0xFF];
      case 0x1F:
        return [0, clamp(t)];
      case 0x3C:
        final raw = ((620 + 40) * 10).round();
        return [raw >> 8, raw & 0xFF];
      case 0x42:
        final mv = ((14.0 + _rnd.nextDouble() * 0.3) * 1000).round();
        return [mv >> 8, mv & 0xFF];
      case 0x2F:
        return [clamp(0.62 * 255)];
      case 0x46:
        return [clamp(14 + 40)];
      case 0x33:
        return [99];
    }
    return null;
  }

  List<int>? _uds(SimModule m, List<int> req) {
    final sid = req[0];
    List<int> nrc(int code) => [0x7F, sid, code];
    switch (sid) {
      case 0x10:
        m.session = req[1];
        return [0x50, req[1], 0x00, 0x32, 0x01, 0xF4];
      case 0x3E:
        return [0x7E, 0x00];
      case 0x19:
        if (req.length < 3 || req[1] != 0x02) return nrc(0x12);
        final mask = req[2];
        return [0x59, 0x02, 0xFF, ...m.dtcs.where((d) => d[3] & mask != 0).expand((d) => d)];
      case 0x14:
        m.dtcs = [];
        return [0x54];
      case 0x22:
        final did = req[1] << 8 | req[2];
        if (did == 0x0600) return m.coding == null ? nrc(0x31) : [0x62, req[1], req[2], ...m.coding!];
        if (did == 0xF190) return [0x62, req[1], req[2], ...ascii.encode(vin)];
        if (did == 0xF197) return [0x62, req[1], req[2], ...ascii.encode(m.name)];
        final text = _ident[did];
        if (text == null) return nrc(0x31);
        return [0x62, req[1], req[2], ...ascii.encode(text)];
      case 0x2E:
        final did = req[1] << 8 | req[2];
        if (did != 0x0600 || m.coding == null) return nrc(0x31);
        if (m.session != 0x03) return nrc(0x7F);
        if (m.securityLocked) return nrc(0x33);
        final data = req.sublist(3);
        if (data.length != m.coding!.length) return nrc(0x13);
        m.coding = data;
        return [0x6E, req[1], req[2]];
    }
    return nrc(0x11);
  }

  /// Handles a raw CAN frame sent with CAN auto formatting off.
  String _rawFrame(int tx, List<int> f) {
    final m = modules[tx];
    if (m == null) return _responses ? 'NO DATA' : '';
    String raw(List<int> frame) =>
        _headers ? '${_id(m.rx)} ${bytesToHex(frame, sep: ' ')}' : bytesToHex(frame, sep: ' ');
    final pci = f[0] >> 4;
    if (pci == 1) {
      _rxLen = (f[0] & 0x0F) << 8 | f[1];
      _rxBuf = f.sublist(2);
      return _responses ? raw([0x30, 0, 0, 0x55, 0x55, 0x55, 0x55, 0x55]) : '';
    }
    if (pci == 2 && _rxBuf != null) {
      _rxBuf!.addAll(f.sublist(1));
      if (_rxBuf!.length < _rxLen) return _responses ? 'NO DATA' : '';
      final req = _rxBuf!.sublist(0, _rxLen);
      _rxBuf = null;
      final resp = _uds(m, req);
      if (resp == null || !_responses) return '';
      return raw([resp.length, ...resp, ...List.filled(max(0, 7 - resp.length), 0x55)]);
    }
    if (pci == 0) {
      final resp = _uds(m, f.sublist(1, 1 + (f[0] & 0x0F)));
      if (resp == null) return 'NO DATA';
      return raw([resp.length, ...resp, ...List.filled(max(0, 7 - resp.length), 0x55)]);
    }
    return 'NO DATA';
  }

  static String _id(int id) => id.toRadixString(16).padLeft(3, '0').toUpperCase();

  /// Formats a message the way an ELM327 prints it (CAN auto formatting on).
  String _format(int rx, List<int> msg) {
    if (_headers) {
      if (msg.length <= 7) return '${_id(rx)} ${bytesToHex([msg.length, ...msg], sep: ' ')}';
      final lines = <String>[
        '${_id(rx)} ${bytesToHex([0x10 | (msg.length >> 8), msg.length & 0xFF, ...msg.take(6)], sep: ' ')}',
      ];
      var sn = 1;
      for (var i = 6; i < msg.length; i += 7, sn++) {
        final chunk = msg.sublist(i, min(i + 7, msg.length));
        lines.add('${_id(rx)} ${bytesToHex([0x20 | (sn & 0x0F), ...chunk], sep: ' ')}');
      }
      return lines.join('\r');
    }
    if (msg.length <= 7) return bytesToHex(msg, sep: ' ');
    final lines = <String>[msg.length.toRadixString(16).padLeft(3, '0').toUpperCase()];
    lines.add('0: ${bytesToHex(msg.take(6).toList(), sep: ' ')}');
    var n = 1;
    for (var i = 6; i < msg.length; i += 7, n++) {
      final chunk = msg.sublist(i, min(i + 7, msg.length));
      lines.add('${(n % 16).toRadixString(16).toUpperCase()}: ${bytesToHex(chunk, sep: ' ')}');
    }
    return lines.join('\r');
  }
}
