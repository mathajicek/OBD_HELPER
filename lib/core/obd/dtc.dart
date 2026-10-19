// Diagnostic trouble code helpers (SAE J2012 two-byte encoding).

/// Decodes two DTC bytes into a code like `P0300`.
String decodeDtc(int a, int b) {
  const letters = 'PCBU';
  final letter = letters[(a >> 6) & 0x03];
  final d1 = (a >> 4) & 0x03;
  final d2 = (a & 0x0F).toRadixString(16);
  final rest = b.toRadixString(16).padLeft(2, '0');
  return '$letter$d1$d2$rest'.toUpperCase();
}

/// Parses mode 03/07/0A replies. [responseSid] is 0x43, 0x47 or 0x4A.
///
/// On CAN the byte after the SID is the number of codes; older protocols
/// pad each frame to three codes with `00 00`.
List<String> parseDtcMessages(List<List<int>> messages, int responseSid, {required bool isCan}) {
  final codes = <String>{};
  for (final m in messages) {
    if (m.isEmpty || m[0] != responseSid) continue;
    var data = m.sublist(1);
    if (isCan && data.isNotEmpty) {
      final count = data[0];
      data = data.sublist(1);
      if (data.length > count * 2) data = data.sublist(0, count * 2);
    }
    for (var i = 0; i + 1 < data.length; i += 2) {
      if (data[i] == 0 && data[i + 1] == 0) continue;
      codes.add(decodeDtc(data[i], data[i + 1]));
    }
  }
  return codes.toList();
}

enum DtcKind { stored, pending, permanent }

class Dtc {
  const Dtc(this.code, this.kind, {this.source, this.failureType, this.status});

  /// SAE form, e.g. `P0300`.
  final String code;
  final DtcKind kind;

  /// CAN id / address of the unit that reported it.
  final int? source;

  /// UDS failure type byte (third DTC byte), when read over UDS.
  final int? failureType;

  /// UDS status byte (ISO 14229 bit field), when read over UDS.
  final int? status;

  /// Code as shown to the user, with the UDS failure type when known.
  String get display =>
      failureType == null ? code : '$code-${failureType!.toRadixString(16).padLeft(2, '0').toUpperCase()}';

  @override
  bool operator ==(Object other) =>
      other is Dtc &&
      other.code == code &&
      other.kind == kind &&
      other.failureType == failureType &&
      other.source == source;
  @override
  int get hashCode => Object.hash(code, kind, failureType, source);
}

/// Parses a UDS `59 02 <availability mask> (DTC_hi DTC_mid FTB status)*` reply.
List<Dtc> parseUdsDtcs(List<int> data, {int? source}) {
  if (data.length < 3 || data[0] != 0x59) return const [];
  final out = <Dtc>[];
  for (var i = 3; i + 3 < data.length; i += 4) {
    final status = data[i + 3];
    if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 0) continue;
    // Active = test failed now, pending, or confirmed.
    if (status & 0x0D == 0) continue;
    out.add(
      Dtc(
        decodeDtc(data[i], data[i + 1]),
        status & 0x08 != 0 ? DtcKind.stored : DtcKind.pending,
        source: source,
        failureType: data[i + 2],
        status: status,
      ),
    );
  }
  return out;
}

/// Parses a KWP2000 `58 <count> (DTC_hi DTC_lo status)*` reply.
List<Dtc> parseKwpDtcs(List<int> data, {int? source}) {
  if (data.length < 2 || data[0] != 0x58) return const [];
  final out = <Dtc>[];
  for (var i = 2; i + 2 < data.length; i += 3) {
    if (data[i] == 0 && data[i + 1] == 0) continue;
    out.add(Dtc(decodeDtc(data[i], data[i + 1]), DtcKind.stored, source: source, status: data[i + 2]));
  }
  return out;
}
