/// Mode 01 parameter definitions (SAE J1979) with decoding formulas.
class Pid {
  const Pid(this.id, this.key, this.unit, this.bytes, this.min, this.max, this.decode);

  final int id;

  /// Localisation key for the name, e.g. `pid_rpm`.
  final String key;
  final String unit;
  final int bytes;
  final double min;
  final double max;
  final double Function(List<int> d) decode;

  String get command => '01${id.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

double _pct(List<int> d) => d[0] * 100 / 255;
double _temp(List<int> d) => d[0] - 40.0;
double _trim(List<int> d) => d[0] * 100 / 128 - 100;

final List<Pid> allPids = [
  Pid(0x0C, 'pid_rpm', 'rpm', 2, 0, 8000, (d) => (d[0] * 256 + d[1]) / 4),
  Pid(0x0D, 'pid_speed', 'km/h', 1, 0, 250, (d) => d[0].toDouble()),
  Pid(0x05, 'pid_coolant', '°C', 1, -40, 130, _temp),
  Pid(0x0F, 'pid_intake_temp', '°C', 1, -40, 80, _temp),
  Pid(0x5C, 'pid_oil_temp', '°C', 1, -40, 150, _temp),
  Pid(0x04, 'pid_load', '%', 1, 0, 100, _pct),
  Pid(0x11, 'pid_throttle', '%', 1, 0, 100, _pct),
  Pid(0x0B, 'pid_map', 'kPa', 1, 0, 255, (d) => d[0].toDouble()),
  Pid(0x10, 'pid_maf', 'g/s', 2, 0, 300, (d) => (d[0] * 256 + d[1]) / 100),
  Pid(0x06, 'pid_stft1', '%', 1, -25, 25, _trim),
  Pid(0x07, 'pid_ltft1', '%', 1, -25, 25, _trim),
  Pid(0x0E, 'pid_timing', '°', 1, -64, 64, (d) => d[0] / 2 - 64),
  Pid(0x42, 'pid_voltage', 'V', 2, 0, 16, (d) => (d[0] * 256 + d[1]) / 1000),
  Pid(0x2F, 'pid_fuel', '%', 1, 0, 100, _pct),
  Pid(0x46, 'pid_ambient', '°C', 1, -40, 60, _temp),
  Pid(0x33, 'pid_baro', 'kPa', 1, 0, 255, (d) => d[0].toDouble()),
];

final Map<int, Pid> pidById = {for (final p in allPids) p.id: p};

/// PIDs shown on the dashboard by default.
const defaultDashboard = [0x0C, 0x0D, 0x05, 0x42, 0x04, 0x11];

/// Decodes a supported-PIDs bitmask reply (`41 00 AA BB CC DD`).
/// [base] is the PID that was queried (0x00, 0x20, 0x40 …).
Set<int> decodeSupported(int base, List<int> mask) {
  final out = <int>{};
  for (var i = 0; i < 32 && i ~/ 8 < mask.length; i++) {
    if (mask[i ~/ 8] & (0x80 >> (i % 8)) != 0) out.add(base + i + 1);
  }
  return out;
}

/// Finds the `41 <pid> …` message in [messages] and decodes it.
double? decodePidResponse(Pid pid, List<List<int>> messages) {
  for (final m in messages) {
    if (m.length >= 2 + pid.bytes && m[0] == 0x41 && m[1] == pid.id) {
      return pid.decode(m.sublist(2, 2 + pid.bytes));
    }
  }
  return null;
}
