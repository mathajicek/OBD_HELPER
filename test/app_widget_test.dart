import 'package:flutter/material.dart';
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
    expect(find.text('Motor / Engine'), findsOneWidget);
    expect(find.text('P0300-00'), findsOneWidget);
    expect(find.text('P0171-00'), findsOneWidget);

    await tester.tap(find.text('P0300-00'));
    await tester.pumpAndSettle();
    expect(find.text('Související živé hodnoty'.toUpperCase()), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Zkontrolujte svíčky'),
      300,
      scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.physics is! NeverScrollableScrollPhysics).last,
    );
    await tester.tap(find.text('Zkontrolujte svíčky'));
    await tester.pump();
    expect(state.doneSteps, contains('P0300-0'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    // Let the in-flight related-value request finish.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(seconds: 20));
    }

    await tester.runAsync(state.disconnect);
  });
}
