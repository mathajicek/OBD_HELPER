import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/service/service_catalog.dart';
import '../core/service/service_runner.dart';
import 'coding_screen.dart';
import 'theme.dart';

/// Service tab: coding plus service and basic-settings functions by group.
class ServiceScreen extends StatelessWidget {
  const ServiceScreen({super.key});

  static const groupIcons = {
    ServiceGroup.maintenance: Icons.oil_barrel_outlined,
    ServiceGroup.brakes: Icons.album_outlined,
    ServiceGroup.engine: Icons.settings_input_component,
    ServiceGroup.exhaust: Icons.local_fire_department_outlined,
    ServiceGroup.electrical: Icons.battery_charging_full,
    ServiceGroup.chassis: Icons.tire_repair,
    ServiceGroup.transmission: Icons.account_tree_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    void open(Widget page, String title) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppScope(
          state: app,
          child: Scaffold(
            appBar: AppBar(backgroundColor: Palette.bg, title: Text(title)),
            body: page,
          ),
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Text(app.t('service'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          '${app.t('profile')}: ${app.profile.name(app.lang)}',
          style: const TextStyle(fontSize: 13, color: Palette.muted),
        ),
        const SizedBox(height: 12),
        _Tile(
          icon: Icons.memory,
          title: app.t('coding'),
          subtitle: app.t('svc_coding_hint'),
          onTap: () => open(const CodingScreen(), app.t('coding')),
        ),
        for (final g in ServiceGroup.values) ...[
          const SizedBox(height: 8),
          SectionLabel(app.t('svc_grp_${g.name}')),
          for (final f in serviceFunctions.where((f) => f.group == g))
            _Tile(
              icon: groupIcons[g]!,
              title: f.name.of(app.lang),
              badge: _badge(app, f),
              onTap: () => open(ServiceDetail(function: f), f.name.of(app.lang)),
            ),
        ],
        const SizedBox(height: 16),
        PrimaryButton(
          label: app.t('svc_import'),
          outlined: true,
          icon: Icons.file_download_outlined,
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => AppScope(state: app, child: const _ImportDialog()),
          ),
        ),
        if (app.imports.actions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${app.t('svc_imported')}: ${app.imports.actions.length}',
            style: const TextStyle(fontSize: 12, color: Palette.muted),
          ),
          TextButton(onPressed: app.clearImports, child: Text(app.t('svc_import_clear'))),
        ],
      ],
    );
  }

  static Widget _badge(AppState app, ServiceFunction f) {
    if (app.actionFor(f) != null) return Pill(app.t('svc_auto'), Palette.cyan);
    if (f.manualFor(app.profileId).isNotEmpty) return Pill(app.t('svc_manual'), Palette.green);
    return Pill(app.t('svc_workshop'), Palette.amber);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, this.subtitle, this.badge, required this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Panel(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: Palette.cyan),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12, color: Palette.muted)),
                ],
              ),
            ),
            if (badge != null) ...[const SizedBox(width: 8), badge!],
          ],
        ),
      ),
    ),
  );
}

class ServiceDetail extends StatefulWidget {
  const ServiceDetail({super.key, required this.function});
  final ServiceFunction function;
  @override
  State<ServiceDetail> createState() => _ServiceDetailState();
}

class _ServiceDetailState extends State<ServiceDetail> {
  final Set<int> _confirmed = {};
  bool _busy = false;
  String? _progress;
  String? _message;
  bool _error = false;

  ServiceFunction get f => widget.function;

  Future<void> _run(AppState app, ServiceAction action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(f.name.of(app.lang)),
        content: Text(app.t(action.source == 'import' ? 'svc_confirm_import' : 'svc_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(app.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(app.t('confirm'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    app.live?.stop();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await app.service!.verify(f, checkEngine: !app.isDemo);
      await app.service!.run(action, onProgress: (k) => mounted ? setState(() => _progress = k) : null);
      _message = app.t('svc_ok');
      _error = false;
    } on ServiceException catch (e) {
      _message = '${app.t(e.key)}${e.detail != null ? ' (${e.detail})' : ''}';
      _error = true;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _progress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final action = app.actionFor(f);
    final manual = f.manualFor(app.profileId);
    final ready = _confirmed.length == f.preconditions.length && app.conn == ConnState.on && !_busy;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Text(f.description.of(app.lang), style: const TextStyle(fontSize: 15, height: 1.4)),
        if (action != null) ...[
          const SizedBox(height: 20),
          SectionLabel(app.t('svc_run_title')),
          if (action.source == 'demo')
            Text(app.t('svc_demo_note'), style: const TextStyle(fontSize: 12, color: Palette.amber)),
          if (action.source == 'import')
            Text(app.t('svc_import_note'), style: const TextStyle(fontSize: 12, color: Palette.amber)),
          for (var i = 0; i < f.preconditions.length; i++)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirmed.contains(i),
              activeColor: Palette.cyan,
              checkColor: Palette.onCyan,
              onChanged: _busy ? null : (v) => setState(() => v == true ? _confirmed.add(i) : _confirmed.remove(i)),
              title: Text(f.preconditions[i].of(app.lang), style: const TextStyle(fontSize: 14)),
            ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: _busy ? app.t(_progress ?? 'svc_step_session') : app.t('svc_run'),
            icon: Icons.play_arrow,
            onPressed: ready ? () => _run(app, action) : null,
          ),
          if (app.conn != ConnState.on)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(app.t('need_connection'), style: const TextStyle(fontSize: 12, color: Palette.muted)),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_message!, style: TextStyle(color: _error ? Palette.red : Palette.green, fontSize: 14)),
            ),
        ],
        if (manual.isNotEmpty) ...[
          const SizedBox(height: 20),
          SectionLabel(app.t(action == null ? 'svc_manual_title' : 'svc_manual_alt')),
          for (var i = 0; i < manual.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}.',
                    style: const TextStyle(fontFamily: mono, color: Palette.cyan),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(manual[i].of(app.lang), style: const TextStyle(height: 1.4))),
                ],
              ),
            ),
          Text(app.t('svc_manual_note'), style: const TextStyle(fontSize: 12, color: Palette.muted)),
        ],
        if (action == null && f.workshop != null) ...[
          const SizedBox(height: 20),
          SectionLabel(app.t('svc_workshop_title')),
          Text(f.workshop!.of(app.lang), style: const TextStyle(fontSize: 13, color: Palette.muted, height: 1.4)),
        ],
      ],
    );
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return AlertDialog(
      title: Text(app.t('svc_import')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(app.t('svc_import_hint'), style: const TextStyle(fontSize: 12, color: Palette.muted)),
          const SizedBox(height: 8),
          TextField(
            controller: _text,
            maxLines: 6,
            style: const TextStyle(fontFamily: mono, fontSize: 12),
            decoration: InputDecoration(errorText: _error, border: const OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(app.t('cancel'))),
        FilledButton(
          onPressed: () {
            try {
              final n = app.importServices(_text.text);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${app.t('svc_imported')}: $n')));
            } catch (_) {
              setState(() => _error = app.t('svc_import_bad'));
            }
          },
          child: Text(app.t('confirm')),
        ),
      ],
    );
  }
}
