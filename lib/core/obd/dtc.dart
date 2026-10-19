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
  const Dtc(this.code, this.kind);
  final String code;
  final DtcKind kind;

  @override
  bool operator ==(Object other) => other is Dtc && other.code == code && other.kind == kind;
  @override
  int get hashCode => Object.hash(code, kind);
}
