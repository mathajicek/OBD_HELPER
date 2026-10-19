import 'dart:async';
import 'dart:convert';

import '../transport/obd_transport.dart';

class ElmException implements Exception {
  ElmException(this.message);
  final String message;
  @override
  String toString() => 'ElmException: $message';
}

/// The adapter answered, but the vehicle did not (e.g. unsupported PID).
class NoDataException extends ElmException {
  NoDataException(String cmd) : super('NO DATA for $cmd');
}

/// Talks the ELM327 text protocol over any [ObdTransport].
///
/// Commands are serialised: each one is sent, then the client waits for the
/// `>` prompt that ends the adapter's reply. Works with genuine ELM327 and
/// with Vgate iCar Pro (ELM327 v2.x compatible firmware).
class Elm327 {
  Elm327(this.transport, {this.timeout = const Duration(seconds: 4)});

  final ObdTransport transport;
  final Duration timeout;

  final StringBuffer _buffer = StringBuffer();
  Completer<String>? _pending;
  StreamSubscription<List<int>>? _sub;
  Future<void> _queue = Future.value();

  String? version;
  String? protocol;

  /// ISO 15765 (CAN) protocols are 6–9 and user CAN A–C.
  bool get isCan {
    var p = (protocol ?? '').trim().toUpperCase();
    if (p.length == 2 && p.startsWith('A')) p = p.substring(1); // "A6" = auto, 6
    return p.length == 1 && '6789ABC'.contains(p);
  }

  void attach() {
    _sub ??= transport.incoming.listen(_onData);
  }

  void _onData(List<int> data) {
    _buffer.write(latin1.decode(data, allowInvalid: true));
    final text = _buffer.toString();
    final idx = text.indexOf('>');
    if (idx < 0) return;
    _buffer
      ..clear()
      ..write(text.substring(idx + 1));
    final pending = _pending;
    _pending = null;
    pending?.complete(text.substring(0, idx));
  }

  /// Sends [cmd] and returns the cleaned reply (echo and status lines removed).
  Future<String> send(String cmd, {Duration? timeout}) {
    final result = _queue.then((_) => _send(cmd, timeout ?? this.timeout));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<String> _send(String cmd, Duration t) async {
    attach();
    _buffer.clear();
    final completer = Completer<String>();
    _pending = completer;
    await transport.write(ascii.encode('$cmd\r'));
    try {
      final raw = await completer.future.timeout(t);
      return clean(raw, cmd);
    } on TimeoutException {
      _pending = null;
      throw ElmException('Timeout: $cmd');
    }
  }

  /// Removes the command echo, "SEARCHING..." and empty lines.
  static String clean(String raw, String cmd) {
    var lines = raw
        .replaceAll('\n', '\r')
        .split('\r')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    String norm(String s) => s.replaceAll(' ', '').toUpperCase();
    if (lines.isNotEmpty && norm(lines.first) == norm(cmd)) {
      lines = lines.sublist(1);
    }
    lines = lines.where((l) => !l.toUpperCase().startsWith('SEARCHING')).toList();
    return lines.join('\n');
  }

  static const _errors = [
    'UNABLE TO CONNECT',
    'CAN ERROR',
    'BUS INIT',
    'BUS ERROR',
    'BUFFER FULL',
    'DATA ERROR',
    'FB ERROR',
    'STOPPED',
    'ERR',
  ];

  /// Sends an OBD/UDS hex request and returns each ECU message as bytes.
  Future<List<List<int>>> request(String hex, {Duration? timeout}) async {
    final text = await send(hex, timeout: timeout);
    return parseMessages(text, hex);
  }

  /// Parses an ELM reply (headers off) into whole messages.
  ///
  /// Handles single frames (`41 0C 1A F8`) and the ISO-TP multi-frame layout
  /// the ELM prints with CAN auto formatting on:
  /// ```
  /// 014
  /// 0: 49 02 01 31 4A 34
  /// 1: 47 41 35 39 ...
  /// ```
  static List<List<int>> parseMessages(String text, [String cmd = '']) {
    final upper = text.toUpperCase();
    if (upper.contains('NO DATA')) throw NoDataException(cmd);
    if (upper.trim() == '?') throw ElmException('Unknown command: $cmd');
    for (final e in _errors) {
      if (upper.contains(e)) throw ElmException('$e ($cmd)');
    }
    final messages = <List<int>>[];
    List<int>? multi;
    var multiLen = 0;
    for (final rawLine in text.split('\n')) {
      final line = rawLine.replaceAll(' ', '').trim().toUpperCase();
      if (line.isEmpty) continue;
      if (RegExp(r'^[0-9A-F]{3}$').hasMatch(line)) {
        if (multi != null) messages.add(multi.take(multiLen).toList());
        multi = <int>[];
        multiLen = int.parse(line, radix: 16);
        continue;
      }
      final frame = RegExp(r'^([0-9A-F]):([0-9A-F]*)$').firstMatch(line);
      if (frame != null && multi != null) {
        multi.addAll(hexToBytes(frame.group(2)!));
        if (multi.length >= multiLen) {
          messages.add(multi.take(multiLen).toList());
          multi = null;
        }
        continue;
      }
      if (RegExp(r'^[0-9A-F]+$').hasMatch(line) && line.length.isEven) {
        messages.add(hexToBytes(line));
      }
    }
    if (multi != null && multi.isNotEmpty) messages.add(multi);
    return messages;
  }

  /// Resets and configures the adapter, then lets it find the protocol.
  Future<void> initialize() async {
    final reset = await send('ATZ', timeout: const Duration(seconds: 6));
    version = reset.split('\n').lastWhere((l) => l.isNotEmpty, orElse: () => reset);
    for (final cmd in ['ATE0', 'ATL0', 'ATS1', 'ATH0', 'ATAT1', 'ATSP0']) {
      await send(cmd);
    }
    // First real request triggers the automatic protocol search.
    await request('0100', timeout: const Duration(seconds: 12));
    protocol = (await send('ATDPN')).trim();
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    await transport.close();
  }
}

List<int> hexToBytes(String hex) {
  final clean = hex.replaceAll(' ', '');
  return [
    for (var i = 0; i + 1 < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ];
}

String bytesToHex(List<int> bytes, {String sep = ''}) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(sep);
