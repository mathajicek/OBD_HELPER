# OBD Pulse

Mobilní aplikace (Flutter, Android + iOS) pro diagnostiku vozů přes OBD2 adaptér
**Vgate iCar Pro BLE** (a další ELM327 adaptéry s Bluetooth LE).

## Co umí

- **Připojení** k adaptéru přes Bluetooth LE, automatické rozpoznání Vgate iCar Pro
  (služba `E7810A71-…`) i běžných klonů ELM327 (FFF0 / 18F0 / FFE0).
- **Chybové kódy**: čtení uložených, čekajících a trvalých kódů (módy 03/07/0A),
  mazání (mód 04), popis a postup řešení krok za krokem v češtině i angličtině.
- **Všechny jednotky**: sken řídicích jednotek podle značky (UDS / KWP2000) se seznamem a počtem chyb.
- **Živá data**: asi 90 parametrů SAE J1979 ve skupinách, výběr parametrů, grafy průběhu.
- **Servis a základní nastavení**: reset servisu oleje, brzdy, adaptace motoru, DPF, baterie,
  podvozek, převodovka. Ve skupinách, s kontrolou podmínek (napětí, motor) a postupem pro každou značku.
- **Kódování** (UDS přes CAN): identifikace jednotky, čtení kódování, editor bitů,
  zápis s automatickou zálohou, ověřením zpětným čtením a obnovou ze zálohy.
- **Demo režim** se simulovaným adaptérem, takže vše jde vyzkoušet bez auta.
- Přepínání **CZ / EN**.

## Testování

```bash
flutter pub get
flutter test          # parser ELM327, DTC, PID, UDS/ISO-TP, sken jednotek, servis, kódování, UI
flutter run           # na připojeném telefonu
```

Na telefonu:
1. Zapněte zapalování, adaptér zapojte do OBD zásuvky (pod volantem).
2. V aplikaci *Připojit OBD2 adaptér* → vyberte adaptér ze seznamu (OBD adaptéry jsou zvýrazněné nahoře).
   Adaptér se **nepáruje** v nastavení Bluetooth telefonu, připojení dělá aplikace.
3. Bez auta: *Vyzkoušet demo bez auta*.

APK se sestaví automaticky v GitHub Actions (`.github/workflows/build.yml`),
ke stažení v záložce Actions → artefakt `obd-pulse-apk`.

## Instalace na iPhone

Bez placeného účtu Apple Developer se aplikace podepisuje vlastním Apple ID a běží 7 dní,
pak se nainstaluje znovu (data v aplikaci zůstanou).

**Z Macu** (Xcode, Flutter, iPhone připojený kabelem):

```bash
TEAM=<team id> ./tool/install_ios.sh   # poprvé; team id je v Xcode › Settings › Accounts
./tool/install_ios.sh                   # příště: stáhne novou verzi a nainstaluje ji
```

**Bez Xcode**: GitHub Actions vytvoří nepodepsaný balíček `obd-pulse-ios-unsigned`
(`OBD-Pulse-unsigned.ipa`). Ten nainstalujete přes Sideloadly nebo AltStore, které ho
podepíšou vaším Apple ID.

## Pokrytí aut

| Oblast | Pokrytí |
|---|---|
| Emisní chyby, živá data, reset adaptací (OBD) | Všechna auta s OBD2: benzín EU od 2001, diesel od 2004, USA od 1996 |
| Sken všech jednotek | Auta s CAN (zhruba od 2008). Seznamy adres z veřejných zdrojů, neověřené na každém modelu; zbytek najde hloubkový sken |
| Starší auta s K-line | Jen motor přes OBD |
| Ford MS-CAN, GM SW-CAN | Karoserie a přístroje na těchto sběrnicích nejsou adaptérem iCar Pro dosažitelné |
| Auta s bezpečnostní bránou (FCA od 2018, VAG SFD od 2020 a další) | Čtení funguje, mazání, kódování a servisní rutiny brána blokuje |
| Servisní rutiny výrobce | Jen s ověřenou importovanou definicí; jinak návod nebo dílenský tester |

## Struktura

```
lib/core/transport/   BLE (flutter_blue_plus) a simulátor adaptéru
lib/core/elm/         protokol ELM327 (fronta příkazů, parser odpovědí)
lib/core/obd/         PID, chybové kódy, živá data
lib/core/uds/         UDS klient, ruční ISO-TP, služba kódování a zálohy
lib/core/vehicle/     profily značek a sken jednotek
lib/core/service/     katalog servisních funkcí a jejich spouštění
lib/data/             databáze kódů s postupy řešení (CZ/EN)
lib/ui/               obrazovky
```

## Omezení této verze

- Kódování umí jednotky bez přihlášení (Security Access 0x27 zatím není).
  Adresy jednotek VAG (gateway 710, přístrojový štít 714) jsou běžné pro platformu MQB,
  u jiných vozů je ověřte.
- iCar Pro s klasickým Bluetooth 3.0 (jen Android) zatím podporován není, jen verze BLE.
- Knihovna `flutter_blue_plus` je zdarma pro osobní a neziskové použití;
  komerční vydání aplikace vyžaduje její placenou licenci (`License.commercial`).
