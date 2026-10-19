import '../elm/elm327.dart';

enum PidGroup { engine, fuel, air, oxygen, temperature, electrical, distance }

/// One value from a mode 01 parameter (SAE J1979). Some PIDs carry several
/// values (e.g. O2 sensor voltage and trim); each gets its own [Pid] with a
/// distinct [key].
class Pid {
  const Pid(this.id, this.key, this.cs, this.en, this.unit, this.bytes, this.min, this.max, this.group, this.decode);

  final int id;

  /// Stable identifier used for selection and history, e.g. `0C` or `14v`.
  final String key;
  final String cs;
  final String en;
  final String unit;

  /// Data bytes the vehicle must send for this PID.
  final int bytes;
  final double min;
  final double max;
  final PidGroup group;
  final double Function(List<int> d) decode;

  String name(String lang) => lang == 'cs' ? cs : en;

  String get command => '01${id.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

double _pct(List<int> d) => d[0] * 100 / 255;
double _temp(List<int> d) => d[0] - 40.0;
double _trim(List<int> d) => d[0] * 100 / 128 - 100;
double _u16(List<int> d) => (d[0] * 256 + d[1]).toDouble();
double _lambda(List<int> d) => _u16(d) * 2 / 65536;

const _g = PidGroup.engine, _f = PidGroup.fuel, _a = PidGroup.air, _o = PidGroup.oxygen;
const _t = PidGroup.temperature, _e = PidGroup.electrical, _d = PidGroup.distance;

final List<Pid> allPids = [
  Pid(0x0C, '0C', 'Otáčky motoru', 'Engine speed', 'rpm', 2, 0, 8000, _g, (d) => _u16(d) / 4),
  Pid(0x0D, '0D', 'Rychlost vozidla', 'Vehicle speed', 'km/h', 1, 0, 250, _g, (d) => d[0].toDouble()),
  Pid(0x04, '04', 'Vypočtené zatížení', 'Calculated load', '%', 1, 0, 100, _g, _pct),
  Pid(0x43, '43', 'Absolutní zatížení', 'Absolute load', '%', 2, 0, 400, _g, (d) => _u16(d) * 100 / 255),
  Pid(0x11, '11', 'Poloha škrticí klapky', 'Throttle position', '%', 1, 0, 100, _a, _pct),
  Pid(0x45, '45', 'Relativní poloha klapky', 'Relative throttle', '%', 1, 0, 100, _a, _pct),
  Pid(0x47, '47', 'Absolutní poloha klapky B', 'Absolute throttle B', '%', 1, 0, 100, _a, _pct),
  Pid(0x48, '48', 'Absolutní poloha klapky C', 'Absolute throttle C', '%', 1, 0, 100, _a, _pct),
  Pid(0x49, '49', 'Plynový pedál D', 'Accelerator pedal D', '%', 1, 0, 100, _a, _pct),
  Pid(0x4A, '4A', 'Plynový pedál E', 'Accelerator pedal E', '%', 1, 0, 100, _a, _pct),
  Pid(0x4B, '4B', 'Plynový pedál F', 'Accelerator pedal F', '%', 1, 0, 100, _a, _pct),
  Pid(0x5A, '5A', 'Relativní poloha pedálu', 'Relative pedal position', '%', 1, 0, 100, _a, _pct),
  Pid(0x4C, '4C', 'Požadovaná poloha klapky', 'Commanded throttle', '%', 1, 0, 100, _a, _pct),
  Pid(0x0E, '0E', 'Předstih zážehu', 'Timing advance', '°', 1, -64, 64, _g, (d) => d[0] / 2 - 64),
  Pid(0x1F, '1F', 'Doba od startu', 'Run time since start', 's', 2, 0, 65535, _g, _u16),
  Pid(0x61, '61', 'Požadovaný moment', 'Driver demand torque', '%', 1, -125, 130, _g, (d) => d[0] - 125.0),
  Pid(0x62, '62', 'Skutečný moment', 'Actual torque', '%', 1, -125, 130, _g, (d) => d[0] - 125.0),
  Pid(0x63, '63', 'Referenční moment', 'Reference torque', 'Nm', 2, 0, 1000, _g, _u16),
  // Air
  Pid(0x10, '10', 'Průtok vzduchu (MAF)', 'Mass air flow', 'g/s', 2, 0, 300, _a, (d) => _u16(d) / 100),
  Pid(0x0B, '0B', 'Tlak v sání (MAP)', 'Intake pressure (MAP)', 'kPa', 1, 0, 255, _a, (d) => d[0].toDouble()),
  Pid(0x33, '33', 'Atmosférický tlak', 'Barometric pressure', 'kPa', 1, 0, 255, _a, (d) => d[0].toDouble()),
  Pid(0x2C, '2C', 'Požadované EGR', 'Commanded EGR', '%', 1, 0, 100, _a, _pct),
  Pid(0x2D, '2D', 'Chyba EGR', 'EGR error', '%', 1, -100, 100, _a, _trim),
  // Fuel
  Pid(0x06, '06', 'Krátkodobá korekce paliva B1', 'Short-term fuel trim B1', '%', 1, -25, 25, _f, _trim),
  Pid(0x07, '07', 'Dlouhodobá korekce paliva B1', 'Long-term fuel trim B1', '%', 1, -25, 25, _f, _trim),
  Pid(0x08, '08', 'Krátkodobá korekce paliva B2', 'Short-term fuel trim B2', '%', 1, -25, 25, _f, _trim),
  Pid(0x09, '09', 'Dlouhodobá korekce paliva B2', 'Long-term fuel trim B2', '%', 1, -25, 25, _f, _trim),
  Pid(0x0A, '0A', 'Tlak paliva', 'Fuel pressure', 'kPa', 1, 0, 765, _f, (d) => d[0] * 3.0),
  Pid(
    0x22,
    '22',
    'Tlak v rozdělovači (rel.)',
    'Fuel rail pressure (rel.)',
    'kPa',
    2,
    0,
    5178,
    _f,
    (d) => _u16(d) * 0.079,
  ),
  Pid(0x23, '23', 'Tlak v rozdělovači', 'Fuel rail gauge pressure', 'kPa', 2, 0, 655350, _f, (d) => _u16(d) * 10),
  Pid(
    0x59,
    '59',
    'Absolutní tlak v rozdělovači',
    'Fuel rail absolute pressure',
    'kPa',
    2,
    0,
    655350,
    _f,
    (d) => _u16(d) * 10,
  ),
  Pid(0x2F, '2F', 'Hladina paliva', 'Fuel level', '%', 1, 0, 100, _f, _pct),
  Pid(0x52, '52', 'Podíl etanolu', 'Ethanol content', '%', 1, 0, 100, _f, _pct),
  Pid(0x5D, '5D', 'Časování vstřiku', 'Injection timing', '°', 2, -210, 302, _f, (d) => _u16(d) / 128 - 210),
  Pid(0x5E, '5E', 'Spotřeba paliva', 'Engine fuel rate', 'L/h', 2, 0, 100, _f, (d) => _u16(d) / 20),
  Pid(0x44, '44', 'Požadovaný lambda', 'Commanded lambda', 'λ', 2, 0, 2, _f, _lambda),
  Pid(0x2E, '2E', 'Odvětrání nádrže (EVAP)', 'Commanded evap purge', '%', 1, 0, 100, _f, _pct),
  Pid(
    0x32,
    '32',
    'Tlak par EVAP',
    'Evap vapour pressure',
    'Pa',
    2,
    -8192,
    8192,
    _f,
    (d) => (((d[0] << 8 | d[1]) ^ 0x8000) - 0x8000) / 4,
  ),
  Pid(0x53, '53', 'Absolutní tlak par EVAP', 'Absolute evap pressure', 'kPa', 2, 0, 328, _f, (d) => _u16(d) / 200),
  // Oxygen sensors (narrowband: voltage + trim)
  for (var i = 0; i < 8; i++) ...[
    Pid(
      0x14 + i,
      '${(0x14 + i).toRadixString(16).toUpperCase()}v',
      'Lambda sonda ${_o2Name(i)} – napětí',
      'O2 sensor ${_o2Name(i)} voltage',
      'V',
      2,
      0,
      1.275,
      _o,
      (d) => d[0] / 200,
    ),
    Pid(
      0x14 + i,
      '${(0x14 + i).toRadixString(16).toUpperCase()}t',
      'Lambda sonda ${_o2Name(i)} – korekce',
      'O2 sensor ${_o2Name(i)} trim',
      '%',
      2,
      -100,
      100,
      _o,
      (d) => d[1] == 0xFF ? 0 : d[1] * 100 / 128 - 100,
    ),
  ],
  // Wideband sensors
  for (var i = 0; i < 8; i++) ...[
    Pid(
      0x24 + i,
      '${(0x24 + i).toRadixString(16).toUpperCase()}l',
      'Širokopásmová sonda ${_o2Name(i)} – lambda',
      'Wideband O2 ${_o2Name(i)} lambda',
      'λ',
      4,
      0,
      2,
      _o,
      _lambda,
    ),
    Pid(
      0x24 + i,
      '${(0x24 + i).toRadixString(16).toUpperCase()}v',
      'Širokopásmová sonda ${_o2Name(i)} – napětí',
      'Wideband O2 ${_o2Name(i)} voltage',
      'V',
      4,
      0,
      8,
      _o,
      (d) => (d[2] * 256 + d[3]) * 8 / 65536,
    ),
    Pid(
      0x34 + i,
      '${(0x34 + i).toRadixString(16).toUpperCase()}c',
      'Širokopásmová sonda ${_o2Name(i)} – proud',
      'Wideband O2 ${_o2Name(i)} current',
      'mA',
      4,
      -128,
      128,
      _o,
      (d) => (d[2] * 256 + d[3]) / 256 - 128,
    ),
  ],
  for (var i = 0; i < 4; i++)
    Pid(
      0x55 + i,
      (0x55 + i).toRadixString(16).toUpperCase(),
      'Korekce zadní sondy ${i + 1}',
      'Secondary O2 trim ${i + 1}',
      '%',
      1,
      -100,
      100,
      _o,
      _trim,
    ),
  // Temperatures
  Pid(0x05, '05', 'Teplota chladiva', 'Coolant temperature', '°C', 1, -40, 130, _t, _temp),
  Pid(0x0F, '0F', 'Teplota nasávaného vzduchu', 'Intake air temperature', '°C', 1, -40, 80, _t, _temp),
  Pid(0x5C, '5C', 'Teplota oleje', 'Oil temperature', '°C', 1, -40, 150, _t, _temp),
  Pid(0x46, '46', 'Venkovní teplota', 'Ambient temperature', '°C', 1, -40, 60, _t, _temp),
  for (final (i, label) in const [(0, 'B1S1'), (1, 'B2S1'), (2, 'B1S2'), (3, 'B2S2')])
    Pid(
      0x3C + i,
      (0x3C + i).toRadixString(16).toUpperCase(),
      'Teplota katalyzátoru $label',
      'Catalyst temperature $label',
      '°C',
      2,
      -40,
      1000,
      _t,
      (d) => _u16(d) / 10 - 40,
    ),
  // Electrical
  Pid(0x42, '42', 'Napětí řídicí jednotky', 'Control module voltage', 'V', 2, 0, 16, _e, (d) => _u16(d) / 1000),
  Pid(0x5B, '5B', 'Hybridní baterie – nabití', 'Hybrid battery charge', '%', 1, 0, 100, _e, _pct),
  // Distance / counters
  Pid(0x21, '21', 'Ujeto s rozsvícenou MIL', 'Distance with MIL on', 'km', 2, 0, 65535, _d, _u16),
  Pid(0x31, '31', 'Ujeto od smazání kódů', 'Distance since codes cleared', 'km', 2, 0, 65535, _d, _u16),
  Pid(0x30, '30', 'Zahřátí od smazání kódů', 'Warm-ups since codes cleared', '', 1, 0, 255, _d, (d) => d[0].toDouble()),
  Pid(0x4D, '4D', 'Doba s rozsvícenou MIL', 'Time with MIL on', 'min', 2, 0, 65535, _d, _u16),
  Pid(0x4E, '4E', 'Doba od smazání kódů', 'Time since codes cleared', 'min', 2, 0, 65535, _d, _u16),
  Pid(
    0xA6,
    'A6',
    'Stav tachometru',
    'Odometer',
    'km',
    4,
    0,
    1e7,
    _d,
    (d) => ((d[0] << 24) | (d[1] << 16) | (d[2] << 8) | d[3]) / 10,
  ),
];

String _o2Name(int i) => 'B${i ~/ 4 + 1}S${i % 4 + 1}';

final Map<String, Pid> pidByKey = {for (final p in allPids) p.key: p};

/// PIDs shown on the dashboard by default.
const defaultDashboard = ['0C', '0D', '05', '42', '04', '11'];

/// Decodes a supported-PIDs bitmask reply (`41 00 AA BB CC DD`).
/// [base] is the PID that was queried (0x00, 0x20, 0x40 …).
Set<int> decodeSupported(int base, List<int> mask) {
  final out = <int>{};
  for (var i = 0; i < 32 && i ~/ 8 < mask.length; i++) {
    if (mask[i ~/ 8] & (0x80 >> (i % 8)) != 0) out.add(base + i + 1);
  }
  return out;
}

/// Finds the first `41 <pid> …` message and decodes it.
double? decodePidResponse(Pid pid, List<EcuMessage> messages) {
  for (final m in messages) {
    final d = m.data;
    if (d.length >= 2 + pid.bytes && d[0] == 0x41 && d[1] == pid.id) {
      return pid.decode(d.sublist(2, 2 + pid.bytes));
    }
  }
  return null;
}
