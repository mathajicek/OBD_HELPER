import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/obd/live_data.dart';
import '../core/obd/pids.dart';
import 'theme.dart';

class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final live = app.live;
    if (live == null) return NeedConnection(app.t('need_connection'));
    return ListenableBuilder(
      listenable: live,
      builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
        Row(children: [
          Expanded(
            child: Text(app.t('live'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          ),
          Text('${live.samplesPerSecond} ${app.t('live_rate')}',
              style: const TextStyle(fontFamily: mono, fontSize: 12, color: Palette.muted)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: PrimaryButton(
              label: live.running ? app.t('live_stop') : app.t('live_start'),
              icon: live.running ? Icons.stop : Icons.play_arrow,
              color: live.running ? Palette.amber : Palette.cyan,
              onPressed: live.running ? live.stop : live.start,
            ),
          ),
          const SizedBox(width: 12),
          IconButton.outlined(
            tooltip: app.t('live_pick'),
            iconSize: 24,
            constraints: const BoxConstraints(minWidth: 54, minHeight: 54),
            style: IconButton.styleFrom(side: const BorderSide(color: Palette.line)),
            icon: const Icon(Icons.tune, color: Palette.cyan),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => AppScope(state: app, child: _PidPicker(live: live)),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.05,
          children: [for (final id in live.selected) _Tile(pid: pidById[id]!, live: live)],
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.pid, required this.live});
  final Pid pid;
  final LiveDataController live;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final v = live.latest[pid.id];
    final unsupported = live.unsupported.contains(pid.id);
    final digits = pid.max - pid.min > 100 ? 0 : 1;
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(app.t(pid.key), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Palette.muted)),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Flexible(
            child: Text(
              unsupported ? '—' : (v == null ? '--' : v.toStringAsFixed(digits)),
              style: const TextStyle(fontFamily: mono, fontSize: 26, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 4),
          Text(pid.unit, style: const TextStyle(fontSize: 12, color: Palette.muted)),
        ]),
        if (unsupported)
          Text(app.t('live_unsupported'), style: const TextStyle(fontSize: 11, color: Palette.amber)),
        const Spacer(),
        SizedBox(
          height: 44,
          width: double.infinity,
          child: CustomPaint(painter: SparklinePainter(live.history[pid.id] ?? const [], pid.min, pid.max)),
        ),
      ]),
    );
  }
}

class SparklinePainter extends CustomPainter {
  SparklinePainter(this.values, this.min, this.max);
  final List<double> values;
  final double min;
  final double max;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = Palette.track
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), base);
    if (values.length < 2) return;
    final pts = values.length > 60 ? values.sublist(values.length - 60) : values;
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final x = size.width * i / (pts.length - 1);
      final norm = ((pts[i] - min) / (max - min)).clamp(0.0, 1.0);
      final y = size.height - norm * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = Palette.cyan.withValues(alpha: 0.10));
    canvas.drawPath(
        path,
        Paint()
          ..color = Palette.cyan
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(SparklinePainter old) => true;
}

class _PidPicker extends StatelessWidget {
  const _PidPicker({required this.live});
  final LiveDataController live;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: live,
      builder: (context, _) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
            Text(app.t('live_pick'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final p in allPids)
              CheckboxListTile(
                value: live.selected.contains(p.id),
                onChanged: (_) => live.toggle(p.id),
                activeColor: Palette.cyan,
                checkColor: Palette.onCyan,
                title: Text(app.t(p.key)),
                subtitle: Text(
                  live.supported.isEmpty || live.supported.contains(p.id)
                      ? '${p.command} · ${p.unit}'
                      : '${p.command} · ${app.t('live_unsupported')}',
                  style: const TextStyle(color: Palette.muted, fontSize: 12),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
