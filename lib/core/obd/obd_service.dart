import 'dart:convert';

import '../elm/elm327.dart';
import 'dtc.dart';
import 'pids.dart';

/// High level OBD2 operations: VIN, fault codes, live parameters.
class ObdService {
  ObdService(this.elm);
  final Elm327 elm;
  Set<int>? _supported;

  Future<Set<int>> supportedPids() async {
    if (_supported != null) return _supported!;
    final out = <int>{};
    for (var base = 0; base <= 0xA0; base += 0x20) {
      if (base != 0 && !out.contains(base)) break;
      try {
        final msgs = await elm.request('01${base.toRadixString(16).padLeft(2, '0').toUpperCase()}');
        for (final m in msgs) {
          if (m.length >= 6 && m[0] == 0x41 && m[1] == base) out.addAll(decodeSupported(base, m.sublist(2, 6)));
        }
      } on NoDataException {
        break;
      }
    }
    return _supported = out;
  }

  Future<double?> readPid(Pid pid) async {
    try {
      return decodePidResponse(pid, await elm.request(pid.command));
    } on NoDataException {
      return null;
    }
  }

  Future<String?> readVin() async {
    try {
      final msgs = await elm.request('0902', timeout: const Duration(seconds: 6));
      for (final m in msgs) {
        if (m.length > 3 && m[0] == 0x49 && m[1] == 0x02) {
          final chars = m.sublist(3).where((b) => b >= 0x30 && b <= 0x5A).toList();
          final vin = ascii.decode(chars);
          return vin.length >= 17 ? vin.substring(vin.length - 17) : vin;
        }
      }
    } on ElmException {
      return null;
    }
    return null;
  }

  Future<List<Dtc>> readDtcs() async {
    final result = <Dtc>[];
    Future<void> mode(String cmd, int sid, DtcKind kind) async {
      try {
        final codes = parseDtcMessages(await elm.request(cmd, timeout: const Duration(seconds: 6)), sid,
            isCan: elm.isCan);
        result.addAll(codes.map((c) => Dtc(c, kind)));
      } on NoDataException {
        // no codes of this kind
      }
    }

    await mode('03', 0x43, DtcKind.stored);
    await mode('07', 0x47, DtcKind.pending);
    if (elm.isCan) await mode('0A', 0x4A, DtcKind.permanent);
    return result;
  }

  /// Mode 04: clears stored codes and freeze frames, turns off the MIL.
  Future<void> clearDtcs() async {
    final msgs = await elm.request('04', timeout: const Duration(seconds: 6));
    if (!msgs.any((m) => m.isNotEmpty && m[0] == 0x44)) {
      throw ElmException('Vehicle did not confirm clearing');
    }
  }
}
