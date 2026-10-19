import '../uds/uds_client.dart';

/// A range of request ids to probe in a deep scan; the response id is
/// `tx + rxOffset`. With [extended], the range is the extended address byte
/// behind the fixed [tx] tester id and the response id is `rxBase + address`.
class SweepRange {
  const SweepRange(this.from, this.to, this.rxOffset) : extended = false, tx = 0, rxBase = 0;
  const SweepRange.extended(this.tx, this.from, this.to, this.rxBase) : extended = true, rxOffset = 0;

  final int from;
  final int to;
  final int rxOffset;
  final bool extended;
  final int tx;
  final int rxBase;

  Iterable<Ecu> ecus() sync* {
    for (var a = from; a <= to; a++) {
      final hex = a.toRadixString(16).padLeft(extended ? 2 : 3, '0').toUpperCase();
      yield extended ? Ecu('0x$hex', tx, rxBase + a, extAddr: a) : Ecu('0x$hex', a, a + rxOffset);
    }
  }

  int get count => to - from + 1;
}

/// Control unit addresses for one group of manufacturers.
///
/// Built only from public sources (ISO 15765-4 / ISO 14229 and openly
/// published address lists). The listed units are starting points: cars
/// differ by model and year, so a deep scan probes the whole address range.
class VehicleProfile {
  const VehicleProfile(this.id, this.cs, this.en, this.ecus, this.sweep);
  final String id;
  final String cs;
  final String en;
  final List<Ecu> ecus;
  final List<SweepRange> sweep;

  String name(String lang) => lang == 'cs' ? cs : en;
}

/// Legislated OBD addresses (ISO 15765-4): every car with CAN OBD answers here.
const _obd = [
  Ecu('m_engine', 0x7E0, 0x7E8, name: 'Motor / Engine'),
  Ecu('m_trans', 0x7E1, 0x7E9, name: 'Převodovka / Transmission'),
  Ecu('m_obd2', 0x7E2, 0x7EA, name: 'OBD 7E2'),
  Ecu('m_obd3', 0x7E3, 0x7EB, name: 'OBD 7E3'),
  Ecu('m_obd4', 0x7E4, 0x7EC, name: 'OBD 7E4'),
  Ecu('m_obd5', 0x7E5, 0x7ED, name: 'OBD 7E5'),
  Ecu('m_obd6', 0x7E6, 0x7EE, name: 'OBD 7E6'),
  Ecu('m_obd7', 0x7E7, 0x7EF, name: 'OBD 7E7'),
];

const vehicleProfiles = <VehicleProfile>[
  VehicleProfile('generic', 'Obecný OBD2', 'Generic OBD2', _obd, [SweepRange(0x700, 0x7DF, 8)]),
  VehicleProfile(
    'vag',
    'VW / Škoda / Audi / Seat / Cupra',
    'VW / Skoda / Audi / Seat / Cupra',
    [
      Ecu('vag01', 0x7E0, 0x7E8, name: '01 Motor'),
      Ecu('vag02', 0x7E1, 0x7E9, name: '02 Převodovka'),
      Ecu('vag03', 0x713, 0x77D, name: '03 ABS / ESC'),
      Ecu('vag08', 0x746, 0x7B0, name: '08 Klimatizace'),
      Ecu('vag09', 0x70E, 0x778, name: '09 Centrální elektronika'),
      Ecu('vag13', 0x757, 0x7C1, name: '13 Adaptivní tempomat'),
      Ecu('vag15', 0x715, 0x77F, name: '15 Airbag'),
      Ecu('vag16', 0x70C, 0x776, name: '16 Elektronika volantu'),
      Ecu('vag17', 0x714, 0x77E, name: '17 Přístrojový štít'),
      Ecu('vag19', 0x710, 0x77A, name: '19 Gateway'),
      Ecu('vag42', 0x74A, 0x7B4, name: '42 Dveře řidiče'),
      Ecu('vag44', 0x712, 0x77C, name: '44 Posilovač řízení'),
      Ecu('vag52', 0x74B, 0x7B5, name: '52 Dveře spolujezdce'),
      Ecu('vag5F', 0x773, 0x7DD, name: '5F Infotainment'),
    ],
    [SweepRange(0x700, 0x77F, 0x6A)],
  ),
  VehicleProfile(
    'bmw',
    'BMW / Mini',
    'BMW / Mini',
    [
      Ecu('bmw12', 0x6F1, 0x612, extAddr: 0x12, name: 'DME Motor'),
      Ecu('bmw18', 0x6F1, 0x618, extAddr: 0x18, name: 'EGS Převodovka'),
      Ecu('bmw29', 0x6F1, 0x629, extAddr: 0x29, name: 'DSC Stabilizace'),
      Ecu('bmw01', 0x6F1, 0x601, extAddr: 0x01, name: 'ACSM Airbag'),
      Ecu('bmw10', 0x6F1, 0x610, extAddr: 0x10, name: 'ZGW Gateway'),
      Ecu('bmw40', 0x6F1, 0x640, extAddr: 0x40, name: 'FEM / BDC Karoserie'),
      Ecu('bmw60', 0x6F1, 0x660, extAddr: 0x60, name: 'KOMBI Přístroje'),
      Ecu('bmw63', 0x6F1, 0x663, extAddr: 0x63, name: 'Head unit'),
      Ecu('bmw78', 0x6F1, 0x678, extAddr: 0x78, name: 'IHKA Klimatizace'),
      Ecu('bmw30', 0x6F1, 0x630, extAddr: 0x30, name: 'EPS Řízení'),
    ],
    [SweepRange.extended(0x6F1, 0x00, 0x7F, 0x600)],
  ),
  VehicleProfile('mercedes', 'Mercedes-Benz / Smart', 'Mercedes-Benz / Smart', _obd, [
    SweepRange(0x700, 0x7DF, 8),
    SweepRange(0x400, 0x4FF, 0x100),
  ]),
  VehicleProfile(
    'french',
    'Renault / Dacia / Peugeot / Citroën',
    'Renault / Dacia / Peugeot / Citroën',
    [
      ..._obd,
      Ecu('ren_abs', 0x740, 0x760, name: 'ABS / ESP'),
      Ecu('ren_cluster', 0x743, 0x763, name: 'Přístrojový štít'),
      Ecu('ren_uch', 0x745, 0x765, name: 'UCH / BCM Karoserie'),
      Ecu('ren_airbag', 0x752, 0x772, name: 'Airbag'),
    ],
    [SweepRange(0x700, 0x75F, 0x20), SweepRange(0x6A0, 0x6FF, -0x20)],
  ),
  VehicleProfile(
    'japan',
    'Toyota / Honda / Nissan / Mazda / Hyundai / Kia',
    'Toyota / Honda / Nissan / Mazda / Hyundai / Kia',
    [
      ..._obd,
      Ecu('jp_abs', 0x7B0, 0x7B8, name: 'ABS / VSC'),
      Ecu('jp_cluster', 0x7C0, 0x7C8, name: 'Přístrojový štít'),
      Ecu('jp_airbag', 0x780, 0x788, name: 'Airbag'),
      Ecu('jp_eps', 0x7A1, 0x7A9, name: 'Posilovač řízení'),
      Ecu('jp_ac', 0x7C4, 0x7CC, name: 'Klimatizace'),
    ],
    [SweepRange(0x700, 0x7DF, 8)],
  ),
  VehicleProfile(
    'usa',
    'Ford / GM / Chrysler / Jeep',
    'Ford / GM / Chrysler / Jeep',
    [
      ..._obd,
      Ecu('us_abs', 0x760, 0x768, name: 'ABS'),
      Ecu('us_ipc', 0x720, 0x728, name: 'Přístrojový štít'),
      Ecu('us_bcm', 0x726, 0x72E, name: 'BCM Karoserie'),
      Ecu('us_pscm', 0x730, 0x738, name: 'Posilovač řízení'),
      Ecu('us_rcm', 0x737, 0x73F, name: 'Airbag'),
      Ecu('us_apim', 0x7D0, 0x7D8, name: 'Infotainment'),
    ],
    [SweepRange(0x700, 0x7DF, 8), SweepRange(0x240, 0x25F, 0x400)],
  ),
];

VehicleProfile profileById(String id) =>
    vehicleProfiles.firstWhere((p) => p.id == id, orElse: () => vehicleProfiles.first);
