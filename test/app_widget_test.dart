import 'package:flutter_test/flutter_test.dart';
import 'package:obd_pulse/app_state.dart';
import 'package:obd_pulse/core/transport/sim_transport.dart';
import 'package:obd_pulse/core/uds/coding_service.dart';
import 'package:obd_pulse/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('switches language CZ/EN', (tester) async {
    await tester.pumpWidget(ObdPulseApp(state: AppState(backupStore: MemoryBackupStore())));
    expect(find.text('Připojit OBD2 adaptér'), findsOneWidget);
    await tester.tap(find.text('EN'));
    await tester.pump();
    expect(find.text('Connect OBD2 adapter'), findsOneWidget);
    expect(find.text('Live data'), findsOneWidget);
  });

  testWidgets('demo mode: connect, scan and open a code', (tester) async {
    final state = AppState(backupStore: MemoryBackupStore());
    await tester.pumpWidget(ObdPulseApp(state: state));

    await tester.runAsync(() => state.connect(() async => SimTransport(latency: const Duration(milliseconds: 1))));
    await tester.pump();
    expect(find.text('Připojeno'), findsOneWidget);
    expect(find.text(SimTransport.vin), findsOneWidget);

    await tester.runAsync(state.scan);
    await tester.tap(find.text('Kódy'));
    await tester.pumpAndSettle();
    expect(find.text('P0300'), findsOneWidget);
    expect(find.text('P0171'), findsOneWidget);

    await tester.tap(find.text('P0300'));
    await tester.pumpAndSettle();
    expect(find.text('Postup řešení'.toUpperCase()), findsOneWidget);
    await tester.tap(find.text('Zkontrolujte svíčky'));
    await tester.pump();
    expect(state.doneSteps, contains('P0300-0'));

    await tester.runAsync(state.disconnect);
  });
}
