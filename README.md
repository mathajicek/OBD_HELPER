# OBD Pulse

Mobilní aplikace (Flutter, Android + iOS) pro diagnostiku vozů přes OBD2 adaptér
**Vgate iCar Pro BLE** (a další ELM327 adaptéry s Bluetooth LE).

## Co umí

- **Připojení** k adaptéru přes Bluetooth LE, automatické rozpoznání Vgate iCar Pro
  (služba `E7810A71-…`) i běžných klonů ELM327 (FFF0 / 18F0 / FFE0).
- **Chybové kódy**: čtení uložených, čekajících a trvalých kódů (módy 03/07/0A),
  mazání (mód 04), popis a postup řešení krok za krokem v češtině i angličtině.
- **Živá data**: 16 parametrů (otáčky, rychlost, teploty, MAF, korekce paliva, napětí…),
  výběr parametrů, grafy průběhu, rychlost vzorkování.
- **Kódování** (UDS přes CAN): identifikace jednotky, čtení kódování, editor bitů,
  zápis s automatickou zálohou, ověřením zpětným čtením a obnovou ze zálohy.
- **Demo režim** se simulovaným adaptérem, takže vše jde vyzkoušet bez auta.
- Přepínání **CZ / EN**.

## Testování

```bash
flutter pub get
flutter test          # 28 testů: parser ELM327, DTC, PID, UDS/ISO-TP, kódování, UI
flutter run           # na připojeném telefonu
```

Na telefonu:
1. Zapněte zapalování, adaptér zapojte do OBD zásuvky (pod volantem).
2. V aplikaci *Připojit OBD2 adaptér* → vyberte `IOS-Vlink` / `Vgate` ze seznamu.
   Adaptér se **nepáruje** v nastavení Bluetooth telefonu, připojení dělá aplikace.
3. Bez auta: *Vyzkoušet demo bez auta*.

APK se sestaví automaticky v GitHub Actions (`.github/workflows/build.yml`),
ke stažení v záložce Actions → artefakt `obd-pulse-apk`.

## Struktura

```
lib/core/transport/   BLE (flutter_blue_plus) a simulátor adaptéru
lib/core/elm/         protokol ELM327 (fronta příkazů, parser odpovědí)
lib/core/obd/         PID, chybové kódy, živá data
lib/core/uds/         UDS klient, ruční ISO-TP, služba kódování a zálohy
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
