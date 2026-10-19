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

/// One complete message from one control unit.
class EcuMessage {
  const EcuMessage(this.source, this.data);

  /// CAN id (11 or 29 bit) or, on K-line/J1850, the source address byte.
  final int source;

  /// Payload with transport bytes (ISO-TP PCI, K-line header, checksum) removed.
  final List<int> data;

  @override
  String toString() => '${source.toRadixString(16).toUpperCase()}: ${bytesToHex(data, sep: ' ')}';
}

/// One line of adapter traffic, kept for the diagnostic log screen.
class TrafficEntry {
  TrafficEntry(this.outgoing, this.text) : time = DateTime.now();
  final bool outgoing;
  final String text;
  final DateTime time;
}

/// Talks the ELM327 text protocol over any [ObdTransport].
///
/// Commands are serialised: each one is sent, then the client waits for the
/// `>` prompt that ends the adapter's reply. Headers are kept on (`ATH1`) so
/// replies from several control units can be told apart and multi-frame
/// ISO-TP messages are reassembled here, per sender.
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

  /// Set while talking to a unit with ISO 15765-2 extended addressing: each
  /// received CAN frame then starts with the sender's address byte.
  bool extendedAddressing = false;

  /// Last [logLimit] lines of traffic, newest last.
  final List<TrafficEntry> log = [];
  static const logLimit = 400;

  String get _protocolDigit {
    var p = (protocol ?? '').trim().toUpperCase();
    if (p.length == 2 && p.startsWith('A')) p = p.substring(1); // "A6" = auto, 6
    return p;
  }

  /// ISO 15765 (CAN) protocols are 6–9 and user CAN B–C.
  bool get isCan => _protocolDigit.length == 1 && '6789BC'.contains(_protocolDigit);

  /// Protocols 7 and 9 use 29-bit CAN identifiers.
  bool get is29Bit => _protocolDigit == '7' || _protocolDigit == '9';

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
    // A prompt with nobody waiting is the late end of a timed-out command.
    pending?.complete(text.substring(0, idx));
  }

  void _addLog(bool outgoing, String text) {
    log.add(TrafficEntry(outgoing, text));
    if (log.length > logLimit) log.removeRange(0, log.length - logLimit);
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
    _addLog(true, cmd);
    await transport.write(ascii.encode('$cmd\r'));
    try {
      final raw = await completer.future.timeout(t);
      final cleaned = clean(raw, cmd);
      _addLog(false, cleaned.isEmpty ? '(empty)' : cleaned);
      return cleaned;
    } on TimeoutException {
      _pending = null;
      _addLog(false, '(timeout)');
      // Give a late reply time to arrive and be discarded, so its prompt
      // does not end the next command early.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _buffer.clear();
      throw ElmException('Timeout: $cmd');
    }
  }

  /// Removes the command echo, "SEARCHING...", successful "BUS INIT" and
  /// empty lines.
  static String clean(String raw, String cmd) {
    var lines = raw.replaceAll('\n', '\r').split('\r').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    String norm(String s) => s.replaceAll(' ', '').toUpperCase();
    if (lines.isNotEmpty && norm(lines.first) == norm(cmd)) {
      lines = lines.sublist(1);
    }
    lines = lines.where((l) {
      final u = l.toUpperCase();
      if (u.startsWith('SEARCHING')) return false;
      // K-line wake-up: "BUS INIT: ...OK" is a status line, not data.
      if (u.startsWith('BUS INIT') && !u.contains('ERROR')) return false;
      return true;
    }).toList();
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
    'LV RESET',
    'STOPPED',
  ];

  static void _checkErrors(String text, String cmd) {
    final upper = text.toUpperCase();
    if (upper.contains('NO DATA')) throw NoDataException(cmd);
    if (upper.trim() == '?') throw ElmException('Unknown command: $cmd');
    for (final e in _errors) {
      if (upper.contains(e)) throw ElmException('$e ($cmd)');
    }
    if (RegExp(r'\bERR\d+').hasMatch(upper)) throw ElmException('$upper ($cmd)');
  }

  /// Sends an OBD/UDS hex request and returns each complete message.
  Future<List<EcuMessage>> request(String hex, {Duration? timeout}) async {
    final text = await send(hex, timeout: timeout);
    return parseHeaderMessages(text, cmd: hex, isCan: isCan, is29Bit: is29Bit, extAddr: extendedAddressing);
  }

  /// Like [request] but returns raw CAN frames (PCI byte kept), for manual
  /// ISO-TP with CAN auto formatting off.
  Future<List<EcuMessage>> requestRaw(String hex, {Duration? timeout}) async {
    final text = await send(hex, timeout: timeout);
    return parseHeaderMessages(text, cmd: hex, isCan: true, is29Bit: is29Bit, raw: true, extAddr: extendedAddressing);
  }

  /// Parses a reply printed with headers on (`ATH1`).
  ///
  /// CAN: `7E8 06 41 00 BE 1F A8 13` (11-bit) or `18 DA F1 10 06 41 …`
  /// (29-bit). The PCI byte is used to reassemble ISO-TP messages per sender.
  /// K-line / J1850: `48 6B 10 41 00 BE 1F B8 10 C3` (3 header bytes,
  /// data, checksum).
  static List<EcuMessage> parseHeaderMessages(
    String text, {
    String cmd = '',
    required bool isCan,
    bool is29Bit = false,
    bool raw = false,
    bool extAddr = false,
  }) {
    _checkErrors(text, cmd);
    final out = <EcuMessage>[];
    final partial = <int, List<int>>{};
    final expected = <int, int>{};

    for (final rawLine in text.split('\n')) {
      final tokens = rawLine.trim().toUpperCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      if (tokens.isEmpty || !tokens.every((t) => RegExp(r'^[0-9A-F]+$').hasMatch(t))) continue;

      // Lines printed without spaces (ATS0): split into tokens ourselves.
      if (tokens.length == 1 && tokens.first.length > 3) {
        final s = tokens.first;
        tokens
          ..clear()
          ..addAll(isCan && !is29Bit ? [s.substring(0, 3), ..._pairs(s.substring(3))] : _pairs(s));
      }

      if (!isCan) {
        if (tokens.length < 5) continue;
        final bytes = tokens.map((t) => int.parse(t, radix: 16)).toList();
        out.add(EcuMessage(bytes[2], bytes.sublist(3, bytes.length - 1)));
        continue;
      }

      final int id;
      List<int> frame;
      if (is29Bit) {
        if (tokens.length < 5) continue;
        id = int.parse(tokens.take(4).join(), radix: 16);
        frame = tokens.skip(4).map((t) => int.parse(t, radix: 16)).toList();
      } else {
        if (tokens.length < 2 || tokens.first.length != 3) continue;
        id = int.parse(tokens.first, radix: 16);
        frame = tokens.skip(1).map((t) => int.parse(t, radix: 16)).toList();
      }
      if (extAddr && frame.isNotEmpty) frame = frame.sublist(1);
      if (frame.isEmpty) continue;
      if (raw) {
        out.add(EcuMessage(id, frame));
        continue;
      }

      switch (frame[0] >> 4) {
        case 0: // single frame
          final len = frame[0] & 0x0F;
          out.add(EcuMessage(id, frame.sublist(1, (1 + len).clamp(1, frame.length))));
        case 1: // first frame
          expected[id] = (frame[0] & 0x0F) << 8 | frame[1];
          partial[id] = frame.sublist(2);
        case 2: // consecutive frame
          final buf = partial[id];
          if (buf == null) continue;
          buf.addAll(frame.sublist(1));
          if (buf.length >= expected[id]!) {
            out.add(EcuMessage(id, buf.sublist(0, expected[id]!)));
            partial.remove(id);
          }
        default: // flow control or unknown: not payload
          break;
      }
    }
    // Keep incomplete multi-frame data rather than dropping it silently.
    partial.forEach((id, buf) => out.add(EcuMessage(id, buf)));
    return out;
  }

  static List<String> _pairs(String s) => [for (var i = 0; i + 1 < s.length; i += 2) s.substring(i, i + 2)];

  /// Resets and configures the adapter, then lets it find the protocol.
  Future<void> initialize() async {
    final reset = await send('ATZ', timeout: const Duration(seconds: 6));
    version = reset.split('\n').lastWhere((l) => l.isNotEmpty, orElse: () => reset);
    for (final cmd in ['ATE0', 'ATL0', 'ATS1', 'ATH1', 'ATAT1', 'ATSP0']) {
      await send(cmd);
    }
    // The first real request triggers the automatic protocol search; we only
    // need the protocol number to know how to read headers.
    await send('0100', timeout: const Duration(seconds: 15)).then((text) => _checkErrors(text, '0100'));
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
  return [for (var i = 0; i + 1 < clean.length; i += 2) int.parse(clean.substring(i, i + 2), radix: 16)];
}

String bytesToHex(List<int> bytes, {String sep = ''}) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(sep);
