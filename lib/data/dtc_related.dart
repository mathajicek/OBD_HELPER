// Live values and sensor electrical data related to a fault code.
//
// Values are typical ranges for common petrol/diesel passenger cars from
// public service literature; the manufacturer's data for the exact car wins.

class SensorSpec {
  const SensorSpec(this.cs, this.en, this.rows, {this.circuitTip = true});

  /// Sensor name.
  final String cs;
  final String en;

  /// (label cs, label en, value) rows.
  final List<(String, String, String)> rows;

  /// Show the generic "low/high input" circuit hint.
  final bool circuitTip;

  String name(String lang) => lang == 'cs' ? cs : en;
}

class RelatedInfo {
  const RelatedInfo(this.pids, [this.sensor]);

  /// Keys from `pidByKey` worth watching while diagnosing this code.
  final List<String> pids;
  final SensorSpec? sensor;
}

const _ntc = [
  ('Napájení (reference)', 'Supply (reference)', '5 V'),
  ('Studený motor (20 °C)', 'Cold (20 °C)', '≈ 2,5–3,5 V'),
  ('Zahřátý (90 °C)', 'Hot (90 °C)', '≈ 0,4–1,0 V'),
  ('Odpor 20 °C / 90 °C', 'Resistance 20 °C / 90 °C', '≈ 2–3 kΩ / 0,2–0,3 kΩ'),
];

const _maf = SensorSpec('Snímač hmotnosti vzduchu (MAF)', 'Mass air flow sensor (MAF)', [
  ('Napájení', 'Supply', '12 V (+ 5 V ref. u některých)'),
  ('Signál volnoběh', 'Signal at idle', '≈ 0,8–1,5 V nebo frekvence'),
  ('Signál plný plyn', 'Signal at full throttle', '≈ 3,5–4,5 V'),
  ('Průtok volnoběh (1,4–2,0 l)', 'Flow at idle (1.4–2.0 l)', '≈ 2–5 g/s'),
]);

const _map = SensorSpec('Snímač tlaku v sání (MAP)', 'Manifold pressure sensor (MAP)', [
  ('Napájení (reference)', 'Supply (reference)', '5 V'),
  ('Signál volnoběh', 'Signal at idle', '≈ 1,0–1,5 V (30–40 kPa)'),
  ('Signál vypnutý motor', 'Signal, engine off', '≈ 4,0–4,5 V (≈ 100 kPa)'),
]);

const _iat = SensorSpec('Snímač teploty nasávaného vzduchu (NTC)', 'Intake air temperature sensor (NTC)', _ntc);
const _ect = SensorSpec('Snímač teploty chladiva (NTC)', 'Coolant temperature sensor (NTC)', _ntc);

const _tps = SensorSpec('Snímač polohy škrticí klapky', 'Throttle position sensor', [
  ('Napájení (reference)', 'Supply (reference)', '5 V'),
  ('Dráha 1 zavřeno / otevřeno', 'Track 1 closed / open', '≈ 0,5 V / 4,5 V'),
  ('Dráha 2', 'Track 2', 'zrcadlová nebo posunutá vůči dráze 1'),
]);

const _app = SensorSpec('Snímač polohy plynového pedálu', 'Accelerator pedal position sensor', [
  ('Napájení (reference)', 'Supply (reference)', '5 V'),
  ('Dráha 1 volný / sešlápnutý', 'Track 1 released / pressed', '≈ 0,7 V / 4,2 V'),
  ('Dráha 2', 'Track 2', '≈ polovina dráhy 1'),
]);

const _o2 = SensorSpec('Lambda sonda (skoková)', 'Oxygen sensor (narrowband)', [
  ('Signál', 'Signal', '0,1–0,9 V, kmitá ≈ 1× za s (přední)'),
  ('Zadní sonda za katalyzátorem', 'Rear sensor after catalyst', 'klidná ≈ 0,6–0,7 V'),
  ('Ohřev', 'Heater', '12 V, odpor ≈ 3–10 Ω'),
]);

const _rail = SensorSpec('Snímač tlaku paliva v rozdělovači', 'Fuel rail pressure sensor', [
  ('Napájení (reference)', 'Supply (reference)', '5 V'),
  ('Signál', 'Signal', '≈ 0,5–4,5 V lineárně s tlakem'),
]);

const _knock = SensorSpec('Snímač klepání (piezo)', 'Knock sensor (piezo)', [
  ('Signál', 'Signal', 'střídavé napětí, bez reference'),
  ('Odpor', 'Resistance', 'typicky > 1 MΩ (bez zkratu)'),
  ('Utahovací moment', 'Tightening torque', 'podle výrobce, ≈ 20 Nm'),
], circuitTip: false);

const _crank = SensorSpec('Snímač otáček / polohy (klika, vačka)', 'Crank / cam position sensor', [
  ('Hallův snímač', 'Hall type', '5 nebo 12 V napájení, obdélník 0–5 V'),
  ('Indukční snímač', 'Inductive type', 'střídavé napětí, odpor ≈ 200–1000 Ω'),
]);

const _wheel = SensorSpec('Snímač otáček kola', 'Wheel speed sensor', [
  ('Aktivní (Hall)', 'Active (Hall)', 'proud ≈ 7 / 14 mA, napájení 12 V'),
  ('Pasivní (indukční)', 'Passive (inductive)', 'odpor ≈ 1–2 kΩ, střídavé napětí'),
  ('Vůle k ozubenému kolu', 'Air gap to tone ring', '≈ 0,3–1,5 mm'),
]);

const _battery = SensorSpec('Napájení / dobíjení', 'Supply / charging', [
  ('Motor vypnutý', 'Engine off', '12,4–12,7 V'),
  ('Motor běží', 'Engine running', '13,8–14,7 V'),
  ('Při startování', 'While cranking', 'neklesne pod ≈ 9,6 V'),
], circuitTip: false);

const _canBus = SensorSpec('Sběrnice CAN', 'CAN bus', [
  ('Odpor CAN-H ↔ CAN-L (vypnuto)', 'Resistance CAN-H ↔ CAN-L (off)', '≈ 60 Ω'),
  ('CAN-H proti kostře', 'CAN-H to ground', '≈ 2,5–3,5 V'),
  ('CAN-L proti kostře', 'CAN-L to ground', '≈ 1,5–2,5 V'),
], circuitTip: false);

bool _in(int n, int a, int b) => n >= a && n <= b;

/// Related live values and sensor data for [code] (e.g. `P0117`).
RelatedInfo relatedFor(String code) {
  if (code.length < 5) return const RelatedInfo([]);
  final sys = code[0];
  final n = int.tryParse(code.substring(1, 5), radix: 16);
  if (n == null) return const RelatedInfo([]);
  // Work with the decimal-looking form of generic codes (P0117 → 117).
  final g = code[1] == '0' ? int.tryParse(code.substring(2, 5)) : null;
  final g2 = code[1] == '2' ? int.tryParse(code.substring(2, 5)) : null;

  if (sys == 'U') return const RelatedInfo(['42'], _canBus);
  if (sys == 'C') {
    if (g != null && _in(g, 35, 50)) return const RelatedInfo(['0D'], _wheel);
    return const RelatedInfo(['0D', '42']);
  }
  if (sys == 'B') return const RelatedInfo(['42']);

  if (g2 != null) {
    if (_in(g2, 120, 138)) return const RelatedInfo(['49', '4A', '5A', '11', '45'], _app);
    if (_in(g2, 100, 119)) return const RelatedInfo(['11', '45', '47', '4C', '49'], _tps);
    return const RelatedInfo([]);
  }
  if (g == null) return const RelatedInfo(['0C', '05', '42']); // manufacturer specific

  if (_in(g, 87, 93) || _in(g, 190, 194)) return const RelatedInfo(['22', '23', '59', '0A', '0C'], _rail);
  if (_in(g, 95, 99) || _in(g, 110, 114)) return const RelatedInfo(['0F', '46', '05'], _iat);
  if (_in(g, 100, 104)) return const RelatedInfo(['10', '0C', '04', '0B', '06', '07'], _maf);
  if (_in(g, 105, 109)) return const RelatedInfo(['0B', '33', '0C', '04'], _map);
  if (_in(g, 115, 119) || g == 125 || g == 128) return const RelatedInfo(['05', '0F', '0C', '1F'], _ect);
  if (_in(g, 120, 124) || _in(g, 220, 229)) return const RelatedInfo(['11', '45', '47', '48', '4C'], _tps);
  if (_in(g, 130, 167)) return const RelatedInfo(['14v', '15v', '14t', '06', '07', '24l'], _o2);
  if (_in(g, 170, 175)) return const RelatedInfo(['06', '07', '08', '09', '10', '0B', '14v'], _maf);
  if (_in(g, 300, 312)) return const RelatedInfo(['0C', '04', '05', '06', '07', '0E', '10']);
  if (_in(g, 325, 334)) return const RelatedInfo(['0E', '0C', '04'], _knock);
  if (_in(g, 335, 349)) return const RelatedInfo(['0C'], _crank);
  if (_in(g, 400, 409)) return const RelatedInfo(['2C', '2D', '0B', '10']);
  if (_in(g, 420, 434)) return const RelatedInfo(['14v', '15v', '3C', '06', '07']);
  if (_in(g, 440, 457)) return const RelatedInfo(['2E', '32', '53', '2F']);
  if (_in(g, 500, 503)) return const RelatedInfo(['0D'], _wheel);
  if (_in(g, 505, 507)) return const RelatedInfo(['0C', '11', '0B', '04']);
  if (_in(g, 560, 563) || _in(g, 600, 606)) return const RelatedInfo(['42'], _battery);
  if (_in(g, 700, 999)) return const RelatedInfo(['0D', '0C', '04']);
  return const RelatedInfo(['0C', '05', '04', '42']);
}
