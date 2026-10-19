import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/elm/elm327.dart';
import '../core/vehicle/profiles.dart';
import 'codes_screen.dart';
import 'home_screen.dart';
import 'live_screen.dart';
import 'service_screen.dart';
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
      const ServiceScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _Header(),
            Expanded(
              child: IndexedStack(index: _tab, children: pages),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), label: app.t('nav_home')),
          NavigationDestination(icon: const Icon(Icons.speed), label: app.t('nav_live')),
          NavigationDestination(icon: const Icon(Icons.list_alt), label: app.t('nav_codes')),
          NavigationDestination(icon: const Icon(Icons.build_outlined), label: app.t('nav_coding')),
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
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: app.lang == code ? Palette.onCyan : Palette.muted,
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          const Icon(Icons.hexagon_outlined, color: Palette.cyan, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.t('app'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                ),
                Text(
                  app.t('tagline').toUpperCase(),
                  style: const TextStyle(fontSize: 11, letterSpacing: 1.5, color: Palette.muted),
                ),
              ],
            ),
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
        ],
      ),
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
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
            Text(value, style: const TextStyle(fontSize: 14, color: Palette.cyan)),
          ],
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Text(app.t('settings'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        SectionLabel(app.t('profile')),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: app.profileId,
              isExpanded: true,
              dropdownColor: Palette.panel2,
              items: [for (final p in vehicleProfiles) DropdownMenuItem(value: p.id, child: Text(p.name(app.lang)))],
              onChanged: (id) => app.setProfile(id!),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(app.t('profile_hint'), style: const TextStyle(fontSize: 12, color: Palette.muted)),
        const SizedBox(height: 16),
        row(app.t('language'), app.t('lang_name')),
        row(app.t('adapter_row'), app.t('adapter_val')),
        row(app.t('protocol'), app.elm?.protocol ?? '—'),
        Text(app.t('ios_note'), style: const TextStyle(fontSize: 12, color: Palette.muted, height: 1.5)),
        const SizedBox(height: 16),
        PrimaryButton(
          label: app.t('log'),
          outlined: true,
          icon: Icons.terminal,
          onPressed: app.elm == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AppScope(state: app, child: const LogScreen()),
                  ),
                ),
        ),
      ],
    );
  }
}

class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final log = app.elm?.log ?? const [];
    String fmt(TrafficEntry e) => '${e.time.toIso8601String().substring(11, 23)} ${e.outgoing ? '>' : '<'} ${e.text}';
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Palette.bg,
        title: Text(app.t('log')),
        actions: [
          IconButton(
            tooltip: app.t('log_copy'),
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: log.map(fmt).join('\n')));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(app.t('log_copied'))));
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(app.t('log_hint'), style: const TextStyle(color: Palette.muted, fontSize: 13)),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: log.length,
              itemBuilder: (_, i) {
                final e = log[log.length - 1 - i];
                return Text(
                  fmt(e),
                  style: TextStyle(fontFamily: mono, fontSize: 12, color: e.outgoing ? Palette.cyan : Palette.text),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
