import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../elm/elm327.dart';
import 'obd_transport.dart';

/// A software Vgate iCar Pro: answers ELM327 AT commands, OBD2 modes
/// 01/03/04/07/09/0A and UDS 0x10/0x22/0x2E/0x3E, including manual ISO-TP.
///
/// Used for the in-app demo mode and for tests, so the whole app can be
/// exercised without a car.
class SimTransport implements ObdTransport {
  SimTransport({this.latency = const Duration(milliseconds: 25), Random? random})
      : _rnd = random ?? Random(7);

  final Duration latency;
  final Random _rnd;
  final _incoming = StreamController<List<int>>.broadcast();
  final _start = DateTime.now();

  bool _echo = true;
  bool _caf = true;
  bool _responses = true;
  String _header = '7DF';
  final Map<String, int> _session = {};

  /// Stored and pending codes as raw two-byte pairs.
  List<List<int>> stored = [
    [0x03, 0x00],
    [0x01, 0x71],
    [0x04, 0x20],
  ];
  List<List<int>> pending = [
    [0x03, 0x01],
  ];

  static const vin = 'TMBJJ7NE0K0123456';

  /// Coding per ECU request id; gateway (710) demands security access.
  final Map<String, List<int>> coding = {
    '7E0': hexToBytes('0000140C2400000000'),
    '7E1': hexToBytes('0021'),
    '710': hexToBytes('0101000200000000000000000000000000000000'),
    '714': hexToBytes('2D0F0A100021000001000000'),
  };

  static const _ident = {
    '7E0': {0xF187: '04E906016DE', 0xF189: '0004', 0xF191: 'H13', 0xF197: 'R4 1.4l TSI'},
    '7E1': {0xF187: '0CW300041T', 0xF189: '4517', 0xF197: 'DQ200-MQB'},
    '710': {0xF187: '5Q0907530AA', 0xF189: '2114', 0xF197: 'GW MQB High'},
    '714': {0xF187: '5E0920740B', 0xF189: '0612', 0xF197: 'KOMBI'},
  };

  static const supported = [
    0x04, 0x05, 0x06, 0x07, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x2F, 0x33, 0x42, 0x46, 0x5C, //
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
    if (!_caf) return _rawFrame(bytes);
    if (_header == '7DF') return _obd(bytes);
    final resp = _uds(_header, bytes);
    return resp == null ? 'NO DATA' : _format(resp);
  }

  String _at(String c) {
    if (c == 'Z') {
      _echo = true;
      _caf = true;
      _responses = true;
      _header = '7DF';
      return '\rELM327 v2.3';
    }
    if (c == 'I') return 'ELM327 v2.3';
    if (c == 'E0') _echo = false;
    if (c == 'E1') _echo = true;
    if (c == 'CAF0') _caf = false;
    if (c == 'CAF1') _caf = true;
    if (c == 'R0') _responses = false;
    if (c == 'R1') _responses = true;
    if (c == 'DPN') return 'A6';
    if (c == 'RV') return '${(13.8 + _rnd.nextDouble() * 0.6).toStringAsFixed(1)}V';
    if (c.startsWith('SH')) _header = c.substring(2);
    return 'OK';
  }

  String _obd(List<int> b) {
    final mode = b[0];
    switch (mode) {
      case 0x01:
        final pid = b.length > 1 ? b[1] : 0;
        if (pid % 0x20 == 0) return _format([0x41, pid, ..._mask(pid)]);
        final v = _pidValue(pid);
        return v == null ? 'NO DATA' : _format([0x41, pid, ...v]);
      case 0x03:
        return _format([0x43, stored.length, ...stored.expand((e) => e)]);
      case 0x07:
        return _format([0x47, pending.length, ...pending.expand((e) => e)]);
      case 0x0A:
        return _format([0x4A, 0]);
      case 0x04:
        stored = [];
        pending = [];
        return _format([0x44]);
      case 0x09:
        if (b.length > 1 && b[1] == 0x02) return _format([0x49, 0x02, 0x01, ...ascii.encode(vin)]);
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

  List<int>? _uds(String ecu, List<int> req) {
    if (!coding.containsKey(ecu)) return null;
    final sid = req[0];
    List<int> nrc(int code) => [0x7F, sid, code];
    switch (sid) {
      case 0x10:
        _session[ecu] = req[1];
        return [0x50, req[1], 0x00, 0x32, 0x01, 0xF4];
      case 0x3E:
        return [0x7E, 0x00];
      case 0x22:
        final did = req[1] << 8 | req[2];
        if (did == 0x0600) return [0x62, req[1], req[2], ...coding[ecu]!];
        if (did == 0xF190) return [0x62, req[1], req[2], ...ascii.encode(vin)];
        final text = _ident[ecu]?[did];
        if (text == null) return nrc(0x31);
        return [0x62, req[1], req[2], ...ascii.encode(text)];
      case 0x2E:
        final did = req[1] << 8 | req[2];
        if (did != 0x0600) return nrc(0x31);
        if ((_session[ecu] ?? 1) != 0x03) return nrc(0x7F);
        if (ecu == '710') return nrc(0x33);
        final data = req.sublist(3);
        if (data.length != coding[ecu]!.length) return nrc(0x13);
        coding[ecu] = data;
        return [0x6E, req[1], req[2]];
    }
    return nrc(0x11);
  }

  /// Handles a raw CAN frame sent with CAN auto formatting off.
  String _rawFrame(List<int> f) {
    final pci = f[0] >> 4;
    if (pci == 1) {
      _rxLen = (f[0] & 0x0F) << 8 | f[1];
      _rxBuf = f.sublist(2);
      return _responses ? '30 00 00 55 55 55 55 55' : '';
    }
    if (pci == 2 && _rxBuf != null) {
      _rxBuf!.addAll(f.sublist(1));
      if (_rxBuf!.length < _rxLen) return _responses ? 'NO DATA' : '';
      final req = _rxBuf!.sublist(0, _rxLen);
      _rxBuf = null;
      final resp = _uds(_header, req);
      if (resp == null || !_responses) return '';
      return bytesToHex([resp.length, ...resp, ...List.filled(7 - resp.length, 0x55)], sep: ' ');
    }
    if (pci == 0) {
      final resp = _uds(_header, f.sublist(1, 1 + (f[0] & 0x0F)));
      if (resp == null) return 'NO DATA';
      return bytesToHex([resp.length, ...resp, ...List.filled(max(0, 7 - resp.length), 0x55)], sep: ' ');
    }
    return 'NO DATA';
  }

  /// Formats a message the way an ELM327 prints it with headers off.
  static String _format(List<int> msg) {
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
