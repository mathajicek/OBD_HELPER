import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/obd/dtc.dart';
import '../data/dtc_database.dart';
import 'theme.dart';

class CodesScreen extends StatelessWidget {
  const CodesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.conn != ConnState.on) return NeedConnection(app.t('need_connection'));
    if (app.scanning) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 120, height: 120, child: CircularProgressIndicator(strokeWidth: 3, color: Palette.cyan)),
          const SizedBox(height: 24),
          Text(app.t('scanning'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(app.t('scan_hint'), textAlign: TextAlign.center, style: const TextStyle(color: Palette.muted)),
        ]),
      );
    }
    if (!app.scanned) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        Panel(child: Text(app.t('not_scanned'), style: const TextStyle(fontSize: 18))),
        const SizedBox(height: 16),
        PrimaryButton(label: app.t('scan'), icon: Icons.search, onPressed: app.scan),
      ]);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
      Row(children: [
        Expanded(child: Text(app.t('found'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700))),
        Text('${app.dtcs.length}',
            style: const TextStyle(fontFamily: mono, fontSize: 26, fontWeight: FontWeight.w700, color: Palette.amber)),
      ]),
      const SizedBox(height: 12),
      if (app.dtcs.isEmpty)
        Panel(
          border: Palette.green.withValues(alpha: 0.4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(app.t('no_codes'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Palette.green)),
            const SizedBox(height: 6),
            Text(app.t('no_codes_hint'), style: const TextStyle(color: Palette.muted)),
          ]),
        ),
      for (final d in app.dtcs) ...[
        _CodeCard(dtc: d),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 4),
      PrimaryButton(
        label: app.t('clear'),
        outlined: true,
        color: const Color(0xFFFF8A8A),
        onPressed: app.dtcs.isEmpty
            ? null
            : () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    content: Text(app.t('clear_confirm')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(app.t('cancel'))),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(app.t('confirm'))),
                    ],
                  ),
                );
                if (ok != true) return;
                await app.clearCodes();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(app.t('cleared'))));
                }
              },
      ),
      const SizedBox(height: 8),
      Text(app.t('clear_hint'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Palette.muted)),
    ]);
  }
}

String progressText(AppState app, String code, int total) {
  final done = List.generate(total, (i) => app.doneSteps.contains('$code-$i')).where((x) => x).length;
  return '$done ${app.t('of')} $total ${app.t('steps_done')}';
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.dtc});
  final Dtc dtc;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final info = lookupDtc(dtc.code);
    final text = info.text(app.lang);
    final color = severityColor(info.severity);
    return Material(
      color: Palette.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Palette.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => AppScope(state: app, child: CodeDetailScreen(dtc: dtc)),
        )),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [
                BoxShadow(color: color, blurRadius: 12),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(dtc.code,
                      style: const TextStyle(fontFamily: mono, fontSize: 18, fontWeight: FontWeight.w700, color: Palette.cyan)),
                  const SizedBox(width: 8),
                  Text(app.t('kind_${dtc.kind.name}'), style: const TextStyle(fontSize: 12, color: Palette.muted)),
                  const Spacer(),
                  Pill(app.t(info.severity.name), color),
                ]),
                const SizedBox(height: 4),
                Text(text.title, style: const TextStyle(fontSize: 14, height: 1.35)),
                const SizedBox(height: 4),
                Text(progressText(app, dtc.code, text.steps.length),
                    style: const TextStyle(fontSize: 12, color: Palette.muted)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Palette.muted),
          ]),
        ),
      ),
    );
  }
}

class CodeDetailScreen extends StatelessWidget {
  const CodeDetailScreen({super.key, required this.dtc});
  final Dtc dtc;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final info = lookupDtc(dtc.code);
    final text = info.text(app.lang);
    final color = severityColor(info.severity);
    final done = List.generate(text.steps.length, (i) => app.doneSteps.contains('${dtc.code}-$i'));
    final doneCount = done.where((d) => d).length;

    return Scaffold(
      appBar: AppBar(backgroundColor: Palette.bg, title: Text(app.t('back'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
        Panel(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(dtc.code,
                    style: const TextStyle(fontFamily: mono, fontSize: 32, fontWeight: FontWeight.w700, color: Palette.cyan)),
              ),
              Pill(app.t(info.severity.name), color),
            ]),
            const SizedBox(height: 8),
            Text(text.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3)),
            const SizedBox(height: 8),
            Text(text.description, style: const TextStyle(fontSize: 14, color: Color(0xFFB7C6D9), height: 1.5)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: text.steps.isEmpty ? 0 : doneCount / text.steps.length,
                minHeight: 6,
                color: Palette.cyan,
                backgroundColor: Palette.track,
              ),
            ),
            const SizedBox(height: 6),
            Text(progressText(app, dtc.code, text.steps.length),
                style: const TextStyle(fontSize: 12, color: Palette.muted)),
          ]),
        ),
        if (text.causes.isNotEmpty) ...[
          const SizedBox(height: 8),
          SectionLabel(app.t('causes')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in text.causes)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: Palette.panel2, borderRadius: BorderRadius.circular(99), border: Border.all(color: Palette.line)),
                child: Text(c, style: const TextStyle(fontSize: 13)),
              ),
          ]),
        ],
        const SizedBox(height: 8),
        SectionLabel(app.t('steps')),
        for (var i = 0; i < text.steps.length; i++) ...[
          _StepTile(
            n: i + 1,
            title: text.steps[i].$1,
            detail: text.steps[i].$2,
            done: done[i],
            onTap: () => app.toggleStep('${dtc.code}-$i'),
          ),
          const SizedBox(height: 10),
        ],
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF17120A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF4A3A1C)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber_rounded, color: Palette.amber, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(app.t('safety'), style: const TextStyle(fontSize: 13, color: Color(0xFFF2D9A8), height: 1.45)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.n, required this.title, required this.detail, required this.done, required this.onTap});
  final int n;
  final String title;
  final String detail;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: done ? const Color(0xFF0C1E24) : Palette.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: done ? const Color(0xFF1F5560) : Palette.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? Palette.cyan : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: done ? Palette.cyan : const Color(0xFF2A3A4E)),
                ),
                child: done
                    ? const Icon(Icons.check, size: 16, color: Palette.onCyan)
                    : Text('$n', style: const TextStyle(fontFamily: mono, fontSize: 12, color: Palette.muted)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(detail, style: const TextStyle(fontSize: 13, color: Palette.muted, height: 1.45)),
                ]),
              ),
            ]),
          ),
        ),
      );
}
