// Descriptions and troubleshooting guides for fault codes, in CZ and EN.
enum Severity { high, medium, low }

class DtcText {
  const DtcText(this.title, this.description, this.causes, this.steps);
  final String title;
  final String description;
  final List<String> causes;

  /// (title, detail) pairs.
  final List<(String, String)> steps;
}

class DtcInfo {
  const DtcInfo(this.severity, this.cs, this.en);
  final Severity severity;
  final DtcText cs;
  final DtcText en;
  DtcText text(String lang) => lang == 'cs' ? cs : en;
}

const _misfireCs = [
  ('Zkontrolujte svíčky', 'Vyšroubujte svíčky a zkontrolujte opotřebení, usazeniny a vzdálenost elektrod.'),
  ('Prohoďte cívky', 'Přehoďte cívku na jiný válec. Pokud se chyba přesune, je vadná cívka.'),
  ('Zkontrolujte vstřikovač', 'Poslechněte si vstřikovač (cvakání) nebo změřte jeho odpor.'),
  ('Vymažte kód a otestujte', 'Po opravě kód vymažte a udělejte zkušební jízdu.'),
];
const _misfireEn = [
  ('Inspect the spark plug', 'Remove the plug and check wear, deposits and electrode gap.'),
  ('Swap the coil', 'Move the coil to another cylinder. If the misfire follows it, the coil is bad.'),
  ('Check the injector', 'Listen for the injector clicking or measure its resistance.'),
  ('Clear the code and test', 'After the repair, clear the code and take a test drive.'),
];

DtcInfo _cyl(int n) => DtcInfo(
  Severity.high,
  DtcText('Vynechávání zapalování ve válci $n', 'Řídicí jednotka zjistila vynechávání zapalování ve válci $n.', const [
    'Zapalovací svíčka',
    'Zapalovací cívka',
    'Vstřikovač',
    'Komprese',
  ], _misfireCs),
  DtcText('Cylinder $n Misfire Detected', 'The engine control unit detected misfires in cylinder $n.', const [
    'Spark plug',
    'Ignition coil',
    'Fuel injector',
    'Compression',
  ], _misfireEn),
);

final Map<String, DtcInfo> dtcDatabase = {
  'P0300': const DtcInfo(
    Severity.high,
    DtcText(
      'Zjištěno náhodné / vícenásobné vynechávání zapalování',
      'Řídicí jednotka zaznamenala vynechávání zapalování ve více válcích. Motor může cukat a hrozí poškození katalyzátoru.',
      ['Zapalovací svíčky', 'Zapalovací cívky', 'Vstřikovače', 'Netěsnost sání', 'Nízký tlak paliva'],
      [
        ('Zkontrolujte svíčky', 'Vyšroubujte svíčky a zkontrolujte opotřebení, usazeniny a vzdálenost elektrod.'),
        ('Prohoďte cívky', 'Přehoďte cívky mezi válci. Pokud se chyba přesune na jiný válec, je vadná cívka.'),
        ('Hledejte netěsnost sání', 'Poslouchejte syčení u hadic a sacího potrubí, případně udělejte kouřový test.'),
        ('Změřte tlak paliva', 'Porovnejte tlak paliva s hodnotou předepsanou výrobcem.'),
        ('Vymažte kód a otestujte', 'Po opravě kód vymažte a udělejte zkušební jízdu.'),
      ],
    ),
    DtcText(
      'Random/Multiple Cylinder Misfire Detected',
      'The engine control unit detected misfires in several cylinders. The engine may run rough and the catalytic converter can be damaged.',
      ['Spark plugs', 'Ignition coils', 'Fuel injectors', 'Intake vacuum leak', 'Low fuel pressure'],
      [
        ('Inspect the spark plugs', 'Remove the plugs and check wear, deposits and electrode gap.'),
        ('Swap the coils', 'Swap coils between cylinders. If the misfire moves with the coil, the coil is bad.'),
        ('Look for intake leaks', 'Listen for hissing around hoses and the intake manifold, or run a smoke test.'),
        ('Measure fuel pressure', 'Compare fuel pressure with the manufacturer spec.'),
        ('Clear the code and test', 'After the repair, clear the code and take a test drive.'),
      ],
    ),
  ),
  for (var n = 1; n <= 6; n++) 'P030$n': _cyl(n),
  'P0171': const DtcInfo(
    Severity.medium,
    DtcText(
      'Směs příliš chudá (řada 1)',
      'Motor dostává více vzduchu nebo méně paliva, než by měl. Řídicí jednotka už nedokáže směs dorovnat.',
      ['Netěsné podtlakové hadice', 'Znečištěný snímač MAF', 'Slabé palivové čerpadlo', 'Ucpaný palivový filtr'],
      [
        ('Zkontrolujte podtlakové hadice', 'Hledejte prasklé nebo uvolněné hadice a těsnění sání.'),
        ('Vyčistěte snímač MAF', 'Použijte čistič určený pro snímače MAF, nikdy se snímače nedotýkejte.'),
        ('Sledujte korekce paliva', 'V živých datech sledujte STFT a LTFT. Hodnoty nad +10 % potvrzují chudou směs.'),
        ('Ověřte dodávku paliva', 'Změřte tlak paliva a zkontrolujte palivový filtr.'),
      ],
    ),
    DtcText(
      'System Too Lean (Bank 1)',
      'The engine is getting more air or less fuel than it should, and the control unit can no longer compensate.',
      ['Leaking vacuum hoses', 'Dirty MAF sensor', 'Weak fuel pump', 'Clogged fuel filter'],
      [
        ('Check vacuum hoses', 'Look for cracked or loose hoses and intake gaskets.'),
        ('Clean the MAF sensor', 'Use a dedicated MAF cleaner and never touch the sensor element.'),
        ('Watch fuel trims', 'In live data, watch STFT and LTFT. Values above +10 % confirm a lean mixture.'),
        ('Verify fuel delivery', 'Measure fuel pressure and check the fuel filter.'),
      ],
    ),
  ),
  'P0420': const DtcInfo(
    Severity.low,
    DtcText(
      'Účinnost katalyzátoru pod prahovou hodnotou (řada 1)',
      'Zadní lambda sonda ukazuje, že katalyzátor nečistí výfukové plyny dostatečně.',
      ['Opotřebovaný katalyzátor', 'Vadná zadní lambda sonda', 'Netěsnost výfuku', 'Vynechávání zapalování'],
      [
        ('Nejdřív vyřešte ostatní kódy', 'Vynechávání zapalování a chudá směs často způsobují P0420.'),
        ('Zkontrolujte výfuk', 'Hledejte netěsnosti před a za katalyzátorem.'),
        (
          'Porovnejte lambda sondy',
          'Přední sonda má kmitat, zadní má být klidná. Podobný průběh znamená slabý katalyzátor.',
        ),
        ('Zvažte výměnu katalyzátoru', 'Pokud je vše ostatní v pořádku, katalyzátor je nejspíš na konci životnosti.'),
      ],
    ),
    DtcText(
      'Catalyst System Efficiency Below Threshold (Bank 1)',
      'The downstream oxygen sensor shows the catalytic converter is not cleaning the exhaust well enough.',
      ['Worn catalytic converter', 'Faulty rear O2 sensor', 'Exhaust leak', 'Engine misfire'],
      [
        ('Fix other codes first', 'Misfires and lean mixture often cause P0420.'),
        ('Inspect the exhaust', 'Look for leaks before and after the converter.'),
        (
          'Compare O2 sensors',
          'The front sensor should switch, the rear should stay steady. Similar signals mean a weak converter.',
        ),
        ('Consider replacing the converter', 'If everything else checks out, the converter is likely worn out.'),
      ],
    ),
  ),
  'P0128': const DtcInfo(
    Severity.low,
    DtcText(
      'Teplota chladiva pod pracovní teplotou termostatu',
      'Motor se zahřívá příliš pomalu nebo nedosáhne provozní teploty.',
      ['Termostat zaseknutý v otevřené poloze', 'Vadné čidlo teploty chladiva', 'Nízká hladina chladiva'],
      [
        ('Zkontrolujte hladinu chladiva', 'Na studeném motoru ověřte hladinu v expanzní nádobce.'),
        ('Sledujte teplotu v živých datech', 'Po 10–15 minutách jízdy by teplota měla být kolem 90 °C.'),
        ('Vyměňte termostat', 'Pokud teplota stoupá pomalu, termostat je pravděpodobně otevřený.'),
      ],
    ),
    DtcText(
      'Coolant Temperature Below Thermostat Regulating Temperature',
      'The engine warms up too slowly or never reaches operating temperature.',
      ['Thermostat stuck open', 'Faulty coolant temperature sensor', 'Low coolant level'],
      [
        ('Check coolant level', 'With the engine cold, check the level in the expansion tank.'),
        ('Watch temperature in live data', 'After 10–15 minutes of driving it should reach about 90 °C.'),
        ('Replace the thermostat', 'If temperature rises slowly, the thermostat is likely stuck open.'),
      ],
    ),
  ),
  'P0101': const DtcInfo(
    Severity.medium,
    DtcText(
      'Snímač hmotnosti vzduchu (MAF) – rozsah / výkon',
      'Signál snímače MAF neodpovídá očekávané hodnotě podle otáček a zatížení.',
      ['Znečištěný snímač MAF', 'Netěsnost sání za snímačem', 'Ucpaný vzduchový filtr'],
      [
        ('Zkontrolujte vzduchový filtr', 'Ucpaný filtr omezuje průtok vzduchu.'),
        ('Vyčistěte snímač MAF', 'Použijte čistič určený pro snímače MAF.'),
        ('Porovnejte MAF v živých datech', 'Na volnoběhu bývá kolem 2–5 g/s u motorů 1,4–2,0 l.'),
      ],
    ),
    DtcText(
      'Mass Air Flow Circuit Range/Performance',
      'The MAF sensor signal does not match what is expected for engine speed and load.',
      ['Dirty MAF sensor', 'Intake leak after the sensor', 'Clogged air filter'],
      [
        ('Check the air filter', 'A clogged filter restricts airflow.'),
        ('Clean the MAF sensor', 'Use a dedicated MAF cleaner.'),
        ('Compare MAF in live data', 'At idle it is usually about 2–5 g/s on 1.4–2.0 l engines.'),
      ],
    ),
  ),
};

/// Generic guide for codes that are not in the database.
DtcInfo fallbackInfo(String code) {
  final manufacturer = code.length > 1 && code[1] != '0';
  final system = switch (code[0]) {
    'P' => ('motor a převodovka', 'engine and transmission'),
    'C' => ('podvozek', 'chassis'),
    'B' => ('karoserie', 'body'),
    _ => ('komunikace mezi jednotkami', 'network communication'),
  };
  return DtcInfo(
    Severity.medium,
    DtcText(
      manufacturer ? 'Kód specifický pro výrobce' : 'Obecný kód: ${system.$1}',
      'Tento kód zatím nemáme v databázi. Týká se oblasti: ${system.$1}.',
      const [],
      const [
        ('Poznamenejte si podmínky', 'Kdy se chyba objevila, zda svítí kontrolka a jak se auto chová.'),
        ('Vymažte kód a sledujte', 'Pokud se kód vrátí, závada trvá. Pokud ne, mohlo jít o jednorázový výpadek.'),
        ('Vyhledejte kód pro svůj vůz', 'U kódů výrobce se význam liší podle značky.'),
      ],
    ),
    DtcText(
      manufacturer ? 'Manufacturer-specific code' : 'Generic code: ${system.$2}',
      'This code is not in our database yet. It relates to: ${system.$2}.',
      const [],
      const [
        ('Note the conditions', 'When it appeared, whether the warning light is on and how the car behaves.'),
        ('Clear the code and watch', 'If it comes back the fault is still there. If not, it may have been a one-off.'),
        ('Look up the code for your car', 'Manufacturer codes mean different things per brand.'),
      ],
    ),
  );
}

DtcInfo lookupDtc(String code) => dtcDatabase[code] ?? fallbackInfo(code);
