import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/elm/elm327.dart';
import '../core/uds/coding_service.dart';
import '../core/uds/uds_client.dart';
import 'theme.dart';

class CodingScreen extends StatefulWidget {
  const CodingScreen({super.key});
  @override
  State<CodingScreen> createState() => _CodingScreenState();
}

class _CodingScreenState extends State<CodingScreen> {
  Ecu _ecu = knownEcus.first;
  EcuIdentity? _identity;
  CodingBackup? _backup;
  List<int>? _edited;
  List<CodingBackup> _backups = [];
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  AppState get app => AppScope.of(context);

  Future<void> _run(Future<void> Function(CodingService c) action) async {
    final c = app.coding;
    if (c == null) return;
    app.live?.stop();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action(c);
    } on CodingException catch (e) {
      _showError('${app.t(e.key)}${e.detail != null ? ' (${e.detail})' : ''}');
    } on UdsNegativeResponse catch (e) {
      _showError(e.name);
    } on ElmException catch (e) {
      _showError(e.message);
    }
    _backups = (await app.backupStore.all()).where((b) => b.tx == _ecu.tx).toList().reversed.toList();
    if (mounted) setState(() => _busy = false);
  }

  void _showError(String text) {
    _message = text;
    _messageIsError = true;
  }

  Future<void> _readIdentity() => _run((c) async => _identity = await c.readIdentity(_ecu));

  /// Reading the coding always stores a backup, so a later write can be undone.
  Future<void> _readCoding() => _run((c) async {
        _backup = await c.backup(_ecu);
        _edited = List.of(_backup!.bytes);
      });

  Future<bool> _confirm() async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(app.t('coding_write')),
          content: Text(app.t('coding_write_confirm')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(app.t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(app.t('confirm'))),
          ],
        ),
      ) ==
      true;

  Future<void> _write(List<int> bytes) async {
    if (!await _confirm()) return;
    await _run((c) async {
      // Fresh backup of what is in the unit right now, then write.
      final current = await c.backup(_ecu);
      await c.writeCoding(_ecu, bytes, backup: current);
      _backup = await c.backup(_ecu);
      _edited = List.of(_backup!.bytes);
      _message = app.t('coding_written');
      _messageIsError = false;
    });
  }

  int get _changedBits {
    final a = _backup?.bytes, b = _edited;
    if (a == null || b == null) return 0;
    var n = 0;
    for (var i = 0; i < a.length; i++) {
      var x = a[i] ^ b[i];
      while (x != 0) {
        n += x & 1;
        x >>= 1;
      }
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.conn != ConnState.on) return NeedConnection(app.t('need_connection'));
    final changed = _changedBits;

    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
      Text(app.t('coding'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
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
          Expanded(child: Text(app.t('coding_warning'), style: const TextStyle(fontSize: 13, color: Color(0xFFF2D9A8), height: 1.45))),
        ]),
      ),
      SectionLabel(app.t('coding_ecu')),
      Panel(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<Ecu>(
            value: _ecu,
            isExpanded: true,
            dropdownColor: Palette.panel2,
            items: [
              for (final e in knownEcus)
                DropdownMenuItem(value: e, child: Text('${app.t(e.key)}  ·  ${e.txHex}/${e.rxHex}')),
            ],
            onChanged: _busy
                ? null
                : (e) => setState(() {
                      _ecu = e!;
                      _identity = null;
                      _backup = null;
                      _edited = null;
                      _message = null;
                      _backups = [];
                    }),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: PrimaryButton(label: app.t('coding_read_id'), outlined: true, onPressed: _busy ? null : _readIdentity)),
        const SizedBox(width: 12),
        Expanded(child: PrimaryButton(label: app.t('coding_read'), onPressed: _busy ? null : _readCoding)),
      ]),
      if (_busy) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(color: Palette.cyan, backgroundColor: Palette.track),
      ],
      if (_message != null) ...[
        const SizedBox(height: 12),
        Text(_message!, style: TextStyle(color: _messageIsError ? Palette.red : Palette.green)),
      ],
      if (_identity != null) ...[
        const SizedBox(height: 8),
        SectionLabel(app.t('coding_ecu')),
        Panel(
          child: Column(children: [
            for (final e in _identity!.values.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text(app.t(EcuIdentity.dids[e.key]!), style: const TextStyle(color: Palette.muted))),
                  Text(e.value, style: const TextStyle(fontFamily: mono)),
                ]),
              ),
          ]),
        ),
      ],
      if (_edited != null) ...[
        const SizedBox(height: 8),
        SectionLabel(app.t('coding_current'),
            trailing: Text(changed == 0 ? app.t('coding_no_changes') : '${app.t('coding_changed')}: $changed',
                style: TextStyle(fontSize: 12, color: changed == 0 ? Palette.muted : Palette.amber))),
        Panel(
          child: SelectableText(bytesToHex(_edited!, sep: ' '),
              style: const TextStyle(fontFamily: mono, fontSize: 15, height: 1.6, color: Palette.cyan)),
        ),
        SectionLabel(app.t('coding_edit')),
        for (var i = 0; i < _edited!.length; i++)
          _ByteRow(
            label: '${app.t('coding_byte')} $i',
            value: _edited![i],
            original: _backup!.bytes[i],
            onToggle: _busy ? null : (bit) => setState(() => _edited![i] ^= 1 << bit),
          ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: app.t('coding_write'),
          icon: Icons.save_alt,
          color: Palette.amber,
          onPressed: _busy || changed == 0 ? null : () => _write(List.of(_edited!)),
        ),
      ],
      if (_backups.isNotEmpty) ...[
        const SizedBox(height: 8),
        SectionLabel(app.t('coding_backups')),
        for (final b in _backups.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.time.toLocal().toString().substring(0, 19), style: const TextStyle(fontSize: 12, color: Palette.muted)),
                    const SizedBox(height: 2),
                    Text(b.hex, style: const TextStyle(fontFamily: mono, fontSize: 12), overflow: TextOverflow.ellipsis),
                  ]),
                ),
                IconButton(
                  tooltip: app.t('coding_restore'),
                  icon: const Icon(Icons.restore, color: Palette.cyan),
                  onPressed: _busy || _backup == null || b.hex == _backup!.hex ? null : () => _write(b.bytes),
                ),
              ]),
            ),
          ),
      ],
    ]);
  }
}

class _ByteRow extends StatelessWidget {
  const _ByteRow({required this.label, required this.value, required this.original, required this.onToggle});
  final String label;
  final int value;
  final int original;
  final void Function(int bit)? onToggle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(
            width: 74,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Palette.muted)),
          ),
          SizedBox(
            width: 28,
            child: Text(value.toRadixString(16).padLeft(2, '0').toUpperCase(),
                style: const TextStyle(fontFamily: mono, fontSize: 13)),
          ),
          for (var bit = 7; bit >= 0; bit--)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Semantics(
                  label: '$label bit $bit',
                  button: true,
                  child: InkWell(
                    onTap: onToggle == null ? null : () => onToggle!(bit),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: value >> bit & 1 == 1 ? Palette.cyan.withValues(alpha: 0.18) : Palette.panel,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (value ^ original) >> bit & 1 == 1 ? Palette.amber : Palette.line,
                        ),
                      ),
                      child: Text('${value >> bit & 1}',
                          style: TextStyle(
                              fontFamily: mono,
                              fontSize: 12,
                              color: value >> bit & 1 == 1 ? Palette.cyan : Palette.muted)),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
}
