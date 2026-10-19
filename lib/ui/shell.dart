import 'package:flutter/material.dart';

import '../app_state.dart';
import 'codes_screen.dart';
import 'coding_screen.dart';
import 'home_screen.dart';
import 'live_screen.dart';
import 'theme.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pages = [
      HomeScreen(onScanned: () => setState(() => _tab = 2)),
      const LiveScreen(),
      const CodesScreen(),
      const CodingScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          const _Header(),
          Expanded(child: IndexedStack(index: _tab, children: pages)),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), label: app.t('nav_home')),
          NavigationDestination(icon: const Icon(Icons.speed), label: app.t('nav_live')),
          NavigationDestination(icon: const Icon(Icons.list_alt), label: app.t('nav_codes')),
          NavigationDestination(icon: const Icon(Icons.memory), label: app.t('nav_coding')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), label: app.t('nav_settings')),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    Widget lang(String code, String label) => Semantics(
          button: true,
          selected: app.lang == code,
          child: InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: () => app.setLang(code),
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: app.lang == code ? Palette.cyan : Colors.transparent,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: app.lang == code ? Palette.onCyan : Palette.muted)),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(children: [
        const Icon(Icons.hexagon_outlined, color: Palette.cyan, size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(app.t('app'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            Text(app.t('tagline').toUpperCase(),
                style: const TextStyle(fontSize: 11, letterSpacing: 1.5, color: Palette.muted)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Palette.panel2,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Palette.line),
          ),
          child: Row(children: [lang('cs', 'CZ'), lang('en', 'EN')]),
        ),
      ]),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Panel(
            child: Row(children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
              Text(value, style: const TextStyle(fontSize: 14, color: Palette.cyan)),
            ]),
          ),
        );
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
      Text(app.t('settings'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      row(app.t('language'), app.t('lang_name')),
      row(app.t('adapter_row'), app.t('adapter_val')),
      row(app.t('protocol'), app.elm?.protocol ?? '—'),
      Text(app.t('ios_note'), style: const TextStyle(fontSize: 12, color: Palette.muted, height: 1.5)),
    ]);
  }
}
