import '../elm/elm327.dart';

/// Text in both app languages.
class L {
  const L(this.cs, this.en);
  final String cs;
  final String en;
  String of(String lang) => lang == 'cs' ? cs : en;
}

enum ServiceGroup { maintenance, brakes, engine, exhaust, electrical, chassis, transmission }

/// What the engine must be doing while a function runs.
enum EngineState { any, off, running }

/// One request in an executable service function.
sealed class ServiceStep {
  const ServiceStep();

  static ServiceStep fromJson(Map<String, dynamic> j) {
    if (j.containsKey('routine')) {
      return RoutineStep(
        int.parse(j['routine'] as String, radix: 16),
        params: hexToBytes((j['params'] as String?) ?? ''),
        poll: (j['poll'] as bool?) ?? true,
      );
    }
    if (j.containsKey('write')) {
      return WriteDidStep(int.parse(j['write'] as String, radix: 16), hexToBytes(j['data'] as String));
    }
    if (j['obd'] == 'clear') return const ObdClearStep();
    throw const FormatException('unknown step');
  }
}

/// UDS RoutineControl (0x31): start the routine, then poll its results until
/// the unit reports it finished (result status byte 0x00).
class RoutineStep extends ServiceStep {
  const RoutineStep(this.rid, {this.params = const [], this.poll = true});
  final int rid;
  final List<int> params;
  final bool poll;
}

/// UDS WriteDataByIdentifier (0x2E), e.g. resetting a service counter.
class WriteDidStep extends ServiceStep {
  const WriteDidStep(this.did, this.data);
  final int did;
  final List<int> data;
}

/// OBD mode 04: clears codes and the learned values the engine unit keeps.
class ObdClearStep extends ServiceStep {
  const ObdClearStep();
}

/// How a function is carried out over the adapter. [tx]/[rx] are null for
/// pure OBD steps (functional broadcast).
class ServiceAction {
  const ServiceAction({this.tx, this.rx, this.session = 0x03, required this.steps, this.source = 'builtin'});

  final int? tx;
  final int? rx;

  /// Diagnostic session to open first (0x03 = extended); 0 = none.
  final int session;
  final List<ServiceStep> steps;

  /// `builtin`, `demo` (simulator only) or `import` (definition the user loaded).
  final String source;

  bool get isUds => tx != null;

  /// Definition format for importing (all numbers hex):
  /// `{"function":"oil_reset","profile":"vag","tx":"714","rx":"77E","session":"03",
  ///   "steps":[{"routine":"XXXX","params":"..."},{"write":"XXXX","data":"..."}]}`
  static ServiceAction fromJson(Map<String, dynamic> j) {
    int? hex(String k) => j[k] == null ? null : int.parse(j[k] as String, radix: 16);
    final steps = (j['steps'] as List).map((s) => ServiceStep.fromJson(s as Map<String, dynamic>)).toList();
    if (steps.isEmpty) throw const FormatException('no steps');
    final tx = hex('tx'), rx = hex('rx');
    if ((tx == null) != (rx == null)) throw const FormatException('tx and rx go together');
    if (tx == null && steps.any((s) => s is! ObdClearStep)) throw const FormatException('UDS steps need tx/rx');
    return ServiceAction(tx: tx, rx: rx, session: hex('session') ?? 0x03, steps: steps, source: 'import');
  }
}

class ServiceFunction {
  const ServiceFunction(
    this.id,
    this.group,
    this.name,
    this.description, {
    this.preconditions = const [],
    this.engine = EngineState.any,
    this.manual = const {},
    this.actions = const {},
    this.workshop,
  });

  final String id;
  final ServiceGroup group;
  final L name;
  final L description;

  /// Conditions the user confirms before the function runs.
  final List<L> preconditions;
  final EngineState engine;

  /// Hand procedures by profile id; `*` applies to every profile.
  final Map<String, List<L>> manual;

  /// Executable definitions by profile id (`*` = every car).
  final Map<String, ServiceAction> actions;

  /// When set, the function needs the manufacturer's own routine (and often
  /// its security access), which is not published.
  final L? workshop;

  List<L> manualFor(String profile) => manual[profile] ?? manual['*'] ?? const [];
}

const _battery = L(
  'Napětí baterie nad 12,0 V (nejlépe připojená nabíječka)',
  'Battery above 12.0 V (ideally on a charger)',
);
const _ignition = L('Zapalování zapnuté', 'Ignition on');
const _parked = L('Vůz stojí, zatažená ruční brzda, převodovka v P/N', 'Car stationary, handbrake on, gearbox in P/N');

const _toolOnly = L(
  'Tuto funkci provádí výrobcova rutina v řídicí jednotce. Její identifikátory a zabezpečený přístup výrobci nezveřejňují, takže ji aplikace spustí jen s ověřenou definicí (import), jinak je potřeba dílenský tester.',
  'This function runs a manufacturer routine inside the control unit. Manufacturers do not publish its identifiers or security access, so the app runs it only with a verified definition (import); otherwise a workshop tool is needed.',
);

/// Demo definitions answered by the simulator (fictional routine ids).
const _demoOil = ServiceAction(tx: 0x714, rx: 0x77E, steps: [RoutineStep(0xDE01)], source: 'demo');
const _demoThrottle = ServiceAction(tx: 0x7E0, rx: 0x7E8, steps: [RoutineStep(0xDE02)], source: 'demo');
const _demoEpbOpen = ServiceAction(tx: 0x713, rx: 0x77D, steps: [RoutineStep(0xDE03)], source: 'demo');
const _demoEpbClose = ServiceAction(tx: 0x713, rx: 0x77D, steps: [RoutineStep(0xDE04)], source: 'demo');

/// Service and basic-settings functions, grouped. Hand procedures are the
/// usual ones per manufacturer group and vary by model and year.
const serviceFunctions = <ServiceFunction>[
  // ── Servis ──────────────────────────────────────────────────────────────
  ServiceFunction(
    'oil_reset',
    ServiceGroup.maintenance,
    L('Reset servisu oleje / inspekce', 'Oil service / inspection reset'),
    L(
      'Vynuluje servisní interval po výměně oleje nebo prohlídce.',
      'Resets the service interval after an oil change or inspection.',
    ),
    preconditions: [_ignition, L('Motor neběží', 'Engine not running')],
    engine: EngineState.off,
    actions: {'demo': _demoOil},
    workshop: _toolOnly,
    manual: {
      'vag': [
        L(
          'Novější vozy: Menu palubního počítače › Nastavení › Servis › Vynulovat (nebo Infotainment › Vozidlo › Servis).',
          'Newer cars: trip computer menu › Settings › Service › Reset (or Infotainment › Vehicle › Service).',
        ),
        L(
          'Starší vozy: při vypnutém zapalování držte tlačítko nulování km (0.0 / SET), zapněte zapalování, pusťte, až se ukáže servis, a potvrďte znovu stisknutím.',
          'Older cars: with ignition off hold the trip reset button (0.0 / SET), switch ignition on, release when the service display appears, then press again to confirm.',
        ),
      ],
      'bmw': [
        L(
          'Zapalování zapnuté, motor neběží. Držte tlačítko trip na přístrojovce asi 10 s, až se zobrazí servisní položky (CBS).',
          'Ignition on, engine off. Hold the trip button on the cluster for about 10 s until the service items (CBS) appear.',
        ),
        L(
          'Krátkým stiskem vyberte Olej, podržením zvolte Reset a dalším podržením potvrďte.',
          'Short presses select Oil, hold to choose Reset, hold again to confirm.',
        ),
      ],
      'mercedes': [
        L(
          'Zapalování zapnuté. Tlačítky na volantu: Servis › ASSYST PLUS › Provedené servisy › vyberte olej › Potvrdit.',
          'Ignition on. Steering wheel buttons: Service › ASSYST PLUS › Completed services › select oil › Confirm.',
        ),
      ],
      'french': [
        L(
          'Peugeot / Citroën / DS: zapalování vypnuté, držte tlačítko nulování km, zapněte zapalování a držte asi 10 s, až se servis vynuluje.',
          'Peugeot / Citroën / DS: ignition off, hold the trip reset button, switch ignition on and keep holding for about 10 s until the service resets.',
        ),
        L(
          'Renault / Dacia: zapalování zapnuté, tlačítkem trip zobrazte servisní interval a podržte asi 10 s.',
          'Renault / Dacia: ignition on, show the service interval with the trip button and hold for about 10 s.',
        ),
      ],
      'japan': [
        L(
          'Toyota / Lexus: zobrazte Trip A, vypněte zapalování, držte reset, zapněte zapalování a držte, dokud se údaj nevynuluje.',
          'Toyota / Lexus: show Trip A, switch ignition off, hold reset, switch ignition on and hold until the reading resets.',
        ),
        L(
          'Honda (Maintenance Minder) / Mazda / Nissan: zapalování zapnuté, v menu údržby podržte Select/Reset asi 10 s.',
          'Honda (Maintenance Minder) / Mazda / Nissan: ignition on, in the maintenance menu hold Select/Reset for about 10 s.',
        ),
      ],
      'usa': [
        L(
          'GM (Chevrolet, Cadillac…): zapalování zapnuté, motor neběží, do 5 s třikrát pomalu sešlápněte plyn na doraz.',
          'GM (Chevrolet, Cadillac…): ignition on, engine off, press the accelerator fully three times slowly within 5 s.',
        ),
        L(
          'Chrysler / Jeep / Dodge: zapalování zapnuté, do 10 s třikrát pomalu sešlápněte plyn.',
          'Chrysler / Jeep / Dodge: ignition on, press the accelerator slowly three times within 10 s.',
        ),
        L(
          'Ford: zapalování zapnuté, současně sešlápněte brzdu i plyn a držte asi 25 s.',
          'Ford: ignition on, press brake and accelerator together and hold for about 25 s.',
        ),
      ],
      '*': [
        L(
          'Hledejte v menu palubního počítače položku Servis / Údržba › Reset.',
          'Look for Service / Maintenance › Reset in the trip computer menu.',
        ),
        L(
          'Bez menu se obvykle drží tlačítko nulování km při zapínání zapalování.',
          'Without a menu, usually hold the trip reset button while switching the ignition on.',
        ),
      ],
    },
  ),
  ServiceFunction(
    'brake_service_reset',
    ServiceGroup.maintenance,
    L('Reset servisu brzd', 'Brake service reset'),
    L(
      'Vynuluje upozornění na výměnu destiček nebo brzdové kapaliny (např. BMW CBS).',
      'Resets the brake pad or brake fluid reminder (e.g. BMW CBS).',
    ),
    preconditions: [_ignition],
    workshop: _toolOnly,
    manual: {
      'bmw': [
        L(
          'Stejně jako reset oleje: držte trip asi 10 s, vyberte Brzdy vpředu / vzadu / Brzdová kapalina a podržením resetujte. Při výměně destiček vyměňte i snímač opotřebení.',
          'Same as the oil reset: hold trip for about 10 s, select Front / Rear brakes / Brake fluid and hold to reset. Replace the wear sensor with the pads.',
        ),
      ],
      '*': [
        L(
          'Většina aut nemá samostatný reset: po výměně destiček a snímače opotřebení kontrolka zhasne sama.',
          'Most cars have no separate reset: after replacing the pads and wear sensor the warning clears by itself.',
        ),
      ],
    },
  ),

  // ── Brzdy ───────────────────────────────────────────────────────────────
  ServiceFunction(
    'epb_open',
    ServiceGroup.brakes,
    L('Elektrická ruční brzda: servisní poloha (otevřít)', 'Electric parking brake: service position (open)'),
    L(
      'Zajede písty brzdových třmenů pro výměnu zadních destiček.',
      'Retracts the caliper pistons to change the rear pads.',
    ),
    preconditions: [_parked, _battery, L('Kola zajištěná klíny', 'Wheels chocked')],
    engine: EngineState.off,
    actions: {'demo': _demoEpbOpen},
    workshop: _toolOnly,
    manual: {
      '*': [
        L(
          'Písty elektrické brzdy nikdy netlačte zpět ručně ani nepřipojujte motorek mimo servisní režim, poškodíte mechanismus.',
          'Never push electric brake pistons back by hand or drive the motor outside service mode; it damages the mechanism.',
        ),
      ],
    },
  ),
  ServiceFunction(
    'epb_close',
    ServiceGroup.brakes,
    L('Elektrická ruční brzda: ukončit servis (zavřít)', 'Electric parking brake: end service (close)'),
    L(
      'Po výměně destiček vrátí písty a provede kalibraci.',
      'After the pad change, closes the pistons and calibrates.',
    ),
    preconditions: [_parked, _battery, L('Destičky a třmeny jsou namontované', 'Pads and calipers are refitted')],
    engine: EngineState.off,
    actions: {'demo': _demoEpbClose},
    workshop: _toolOnly,
  ),
  ServiceFunction(
    'abs_bleed',
    ServiceGroup.brakes,
    L('Odvzdušnění brzd přes ABS', 'Brake bleeding via ABS'),
    L(
      'Řízené otevírání ventilů ABS při výměně kapaliny nebo hydrauliky.',
      'Controlled opening of ABS valves when replacing fluid or hydraulics.',
    ),
    preconditions: [_parked, _battery],
    workshop: _toolOnly,
    manual: {
      '*': [
        L(
          'Klasické odvzdušnění pedálem nebo tlakovým zařízením stačí, pokud se neotevíral hydraulický blok ABS.',
          'Classic pedal or pressure bleeding is enough if the ABS hydraulic unit was not opened.',
        ),
      ],
    },
  ),

  // ── Motor a snímače (základní nastavení) ────────────────────────────────
  ServiceFunction(
    'throttle_adapt',
    ServiceGroup.engine,
    L('Adaptace škrticí klapky', 'Throttle body adaptation'),
    L(
      'Po čištění nebo výměně škrticí klapky či pedálu plynu se jednotka naučí koncové polohy.',
      'After cleaning or replacing the throttle body or pedal, the unit learns the end positions.',
    ),
    preconditions: [_ignition, L('Motor neběží, plyn nesešlápnutý', 'Engine off, accelerator released'), _battery],
    engine: EngineState.off,
    actions: {'demo': _demoThrottle},
    workshop: _toolOnly,
    manual: {
      '*': [
        L(
          'Mnoho aut se naučí samo: zapněte zapalování na 10 s bez plynu, vypněte na 10 s, nastartujte a nechte 10 minut běžet na volnoběh bez spotřebičů.',
          'Many cars relearn by themselves: ignition on for 10 s without throttle, off for 10 s, then start and idle for 10 minutes with loads off.',
        ),
      ],
    },
  ),
  ServiceFunction(
    'fuel_trim_reset',
    ServiceGroup.engine,
    L('Reset adaptací motoru (po výměně snímače)', 'Engine adaptation reset (after a sensor change)'),
    L(
      'Standardní OBD příkaz smaže chyby a naučené hodnoty (korekce paliva) po výměně snímače MAF, MAP, lambda sondy nebo vstřiků. Funguje na všech autech s OBD2.',
      'The standard OBD command clears codes and learned values (fuel trims) after replacing a MAF, MAP, oxygen sensor or injectors. Works on every OBD2 car.',
    ),
    preconditions: [
      _ignition,
      L('Motor neběží', 'Engine not running'),
      L(
        'Rozumím, že se smažou všechny chyby i připravenost monitorů pro STK',
        'I understand all codes and the readiness monitors (inspection) are cleared',
      ),
    ],
    engine: EngineState.off,
    actions: {
      '*': ServiceAction(steps: [ObdClearStep()]),
    },
    manual: {
      '*': [
        L(
          'Poté nechte motor běžet do zahřátí a jeďte asi 20 minut, aby se adaptace naučily znovu.',
          'Then let the engine warm up and drive for about 20 minutes so the adaptations relearn.',
        ),
      ],
    },
  ),
  ServiceFunction(
    'injector_coding',
    ServiceGroup.engine,
    L('Kódování vstřikovačů (IMA / IQA)', 'Injector coding (IMA / IQA)'),
    L(
      'Zápis korekčního kódu z hlavy nového vstřikovače do jednotky motoru (hlavně diesely).',
      'Writes the correction code printed on a new injector into the engine unit (mainly diesels).',
    ),
    preconditions: [_ignition, _battery],
    engine: EngineState.off,
    workshop: _toolOnly,
  ),
  ServiceFunction(
    'crank_relearn',
    ServiceGroup.engine,
    L('Naučení snímače otáček (CKP)', 'Crankshaft position relearn (CKP)'),
    L(
      'Po výměně snímače, setrvačníku nebo jednotky se naučí odchylka zubů kola (např. GM, Ford).',
      'After replacing the sensor, flywheel or unit, the tooth variation is learned (e.g. GM, Ford).',
    ),
    preconditions: [_parked],
    engine: EngineState.running,
    workshop: _toolOnly,
  ),

  // ── Výfuk / diesel ──────────────────────────────────────────────────────
  ServiceFunction(
    'dpf_regen',
    ServiceGroup.exhaust,
    L('Regenerace filtru pevných částic (DPF)', 'Diesel particulate filter (DPF) regeneration'),
    L(
      'Vypálení sazí z filtru. Výfuk se rozpálí na více než 600 °C.',
      'Burns the soot out of the filter. The exhaust gets hotter than 600 °C.',
    ),
    preconditions: [
      L('Venku, mimo trávu a hořlavé předměty', 'Outdoors, away from grass and flammables'),
      L('Nádrž alespoň ze čtvrtiny plná', 'Tank at least a quarter full'),
      _parked,
    ],
    engine: EngineState.running,
    workshop: _toolOnly,
    manual: {
      '*': [
        L(
          'Obvykle pomůže jízda 20–30 minut po dálnici při 2 500–3 000 ot/min na nižší rychlostní stupeň bez vypnutí motoru.',
          'Usually a 20–30 minute motorway drive at 2,500–3,000 rpm in a lower gear, without switching the engine off, does it.',
        ),
      ],
    },
  ),
  ServiceFunction(
    'dpf_new',
    ServiceGroup.exhaust,
    L('Nový DPF / snímač diferenčního tlaku', 'New DPF / differential pressure sensor'),
    L(
      'Vynuluje naučené zanesení a popel po výměně filtru nebo snímače tlaku.',
      'Resets learned soot and ash load after replacing the filter or pressure sensor.',
    ),
    preconditions: [_ignition, L('Motor neběží', 'Engine not running')],
    engine: EngineState.off,
    workshop: _toolOnly,
  ),

  // ── Elektro ─────────────────────────────────────────────────────────────
  ServiceFunction(
    'battery_register',
    ServiceGroup.electrical,
    L('Registrace nové baterie', 'New battery registration'),
    L(
      'Řízení nabíjení se nastaví na novou baterii (BMW, VAG, Mercedes, Ford se start-stop).',
      'Sets charge management to the new battery (BMW, VAG, Mercedes, Ford with start-stop).',
    ),
    preconditions: [
      _ignition,
      L('Údaje nové baterie po ruce (Ah, typ AGM/EFB)', 'New battery data at hand (Ah, AGM/EFB type)'),
    ],
    engine: EngineState.off,
    workshop: _toolOnly,
    manual: {
      '*': [
        L(
          'Auta bez start-stop a bez snímače baterie (IBS) registraci obvykle nepotřebují.',
          'Cars without start-stop and without a battery sensor (IBS) usually need no registration.',
        ),
      ],
    },
  ),
  ServiceFunction(
    'window_init',
    ServiceGroup.electrical,
    L('Inicializace oken a střechy po odpojení baterie', 'Window and roof initialisation after battery disconnect'),
    L(
      'Obnoví automatické stahování a ochranu proti přivření.',
      'Restores one-touch operation and anti-pinch protection.',
    ),
    preconditions: [_ignition],
    manual: {
      '*': [
        L(
          'Každé okno zavřete úplně nahoru a držte spínač ještě asi 3 s.',
          'Close each window fully and keep holding the switch for about 3 more seconds.',
        ),
        L(
          'Pak okno úplně stáhněte a držte spínač dolů ještě asi 3 s. Střechu nastavte stejně.',
          'Then open it fully and hold the switch down for about 3 more seconds. Do the sunroof the same way.',
        ),
      ],
    },
  ),

  // ── Podvozek ────────────────────────────────────────────────────────────
  ServiceFunction(
    'sas_calibration',
    ServiceGroup.chassis,
    L('Kalibrace snímače úhlu natočení volantu', 'Steering angle sensor calibration'),
    L(
      'Po geometrii, výměně snímače, hřebene nebo jednotky ESP.',
      'After wheel alignment or replacing the sensor, rack or ESP unit.',
    ),
    preconditions: [_parked, L('Kola rovně, volant rovně', 'Wheels and steering wheel straight')],
    engine: EngineState.running,
    workshop: _toolOnly,
    manual: {
      '*': [
        L(
          'Mnoho aut se nakalibruje samo: s běžícím motorem otočte volantem do obou dorazů, vraťte rovně a krátce jeďte rovně.',
          'Many cars self-calibrate: with the engine running turn the wheel to both locks, return to centre and drive straight briefly.',
        ),
        L(
          'Když kontrolka ESP nezhasne, je potřeba základní nastavení v jednotce ABS dílenským testerem.',
          'If the ESP light stays on, a basic setting in the ABS unit with a workshop tool is needed.',
        ),
      ],
    },
  ),
  ServiceFunction(
    'tpms_relearn',
    ServiceGroup.chassis,
    L('Učení tlaku pneumatik (TPMS)', 'Tyre pressure monitoring relearn (TPMS)'),
    L('Po úpravě tlaku, přezutí nebo výměně kol.', 'After adjusting pressures, swapping tyres or wheels.'),
    manual: {
      '*': [
        L(
          'Nahustěte všechny pneumatiky na předepsaný tlak (štítek ve dveřích).',
          'Inflate all tyres to the specified pressure (door label).',
        ),
        L(
          'V menu vozu nebo tlačítkem TPMS uložte tlaky (Nastavit / Uložit).',
          'Store the pressures in the car menu or with the TPMS button (Set / Store).',
        ),
        L(
          'Jeďte 10–20 minut rychlostí nad 25 km/h. Auta s ventilkovými snímači mohou potřebovat programovací nástroj.',
          'Drive for 10–20 minutes above 25 km/h. Cars with valve sensors may need a programming tool.',
        ),
      ],
    },
  ),
  ServiceFunction(
    'headlight_level',
    ServiceGroup.chassis,
    L('Základní nastavení světlometů', 'Headlight basic setting'),
    L(
      'Po výměně snímače výšky karoserie nebo světlometu (xenon, LED).',
      'After replacing a ride height sensor or headlight (xenon, LED).',
    ),
    preconditions: [_parked, L('Vůz na rovině, bez nákladu', 'Car on level ground, unladen')],
    workshop: _toolOnly,
  ),

  // ── Převodovka ──────────────────────────────────────────────────────────
  ServiceFunction(
    'trans_adapt_reset',
    ServiceGroup.transmission,
    L('Reset adaptací automatické převodovky', 'Automatic transmission adaptation reset'),
    L(
      'Po výměně oleje, ventilového bloku nebo opravě převodovky.',
      'After an oil change, valve body replacement or gearbox repair.',
    ),
    preconditions: [_parked, _battery],
    engine: EngineState.off,
    workshop: _toolOnly,
  ),
  ServiceFunction(
    'clutch_adapt',
    ServiceGroup.transmission,
    L('Základní nastavení spojky (DSG / robotizované)', 'Clutch basic setting (DSG / automated manual)'),
    L(
      'Naučení záběrových bodů spojek po výměně nebo opravě.',
      'Learns the clutch bite points after replacement or repair.',
    ),
    preconditions: [_parked, L('Převodovka zahřátá na provozní teplotu', 'Gearbox at operating temperature')],
    engine: EngineState.running,
    workshop: _toolOnly,
  ),
];

ServiceFunction serviceById(String id) => serviceFunctions.firstWhere((f) => f.id == id);
