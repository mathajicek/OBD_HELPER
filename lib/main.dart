import 'package:flutter/material.dart';

import 'app_state.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState()..loadPrefs();
  runApp(ObdPulseApp(state: state));
}

class ObdPulseApp extends StatelessWidget {
  const ObdPulseApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => AppScope(
        state: state,
        child: MaterialApp(
          title: 'OBD Pulse',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: const Shell(),
        ),
      );
}
