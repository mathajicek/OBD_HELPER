import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../elm/elm327.dart';
import 'uds_client.dart';

class EcuIdentity {
  EcuIdentity(this.values);

  /// DID → decoded text, e.g. 0xF187 → "5Q0907530".
  final Map<int, String> values;

  static const dids = {
    0xF190: 'id_vin',
    0xF187: 'id_part',
    0xF189: 'id_sw',
    0xF191: 'id_hw',
    0xF197: 'id_system',
  };
}

class CodingBackup {
  CodingBackup(this.ecuKey, this.tx, this.did, this.bytes, this.time);
  final String ecuKey;
  final int tx;
  final int did;
  final List<int> bytes;
  final DateTime time;

  String get hex => bytesToHex(bytes);

  Map<String, dynamic> toJson() =>
      {'ecu': ecuKey, 'tx': tx, 'did': did, 'hex': hex, 'time': time.toIso8601String()};

  static CodingBackup fromJson(Map<String, dynamic> j) => CodingBackup(
      j['ecu'] as String, j['tx'] as int, j['did'] as int, hexToBytes(j['hex'] as String), DateTime.parse(j['time'] as String));
}

abstract class BackupStore {
  Future<void> save(CodingBackup b);
  Future<List<CodingBackup>> all();
}

class MemoryBackupStore implements BackupStore {
  final List<CodingBackup> items = [];
  @override
  Future<void> save(CodingBackup b) async => items.add(b);
  @override
  Future<List<CodingBackup>> all() async => List.of(items);
}

class PrefsBackupStore implements BackupStore {
  static const _key = 'coding_backups';
  @override
  Future<void> save(CodingBackup b) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.add(jsonEncode(b.toJson()));
    await prefs.setStringList(_key, list);
  }

  @override
  Future<List<CodingBackup>> all() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? [])
        .map((s) => CodingBackup.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }
}

class CodingException implements Exception {
  CodingException(this.key, [this.detail]);

  /// Localisation key of the message.
  final String key;
  final String? detail;
  @override
  String toString() => 'CodingException($key${detail != null ? ': $detail' : ''})';
}

/// Reads identification and coding of a control unit and writes new coding.
///
/// Writing is guarded: a backup of the current coding must exist, the new
/// coding must have the same length, and the result is read back to verify.
class CodingService {
  CodingService(this.uds, this.store);
  final UdsClient uds;
  final BackupStore store;

  Future<EcuIdentity> readIdentity(Ecu ecu) async {
    await uds.select(ecu);
    final values = <int, String>{};
    try {
      for (final did in EcuIdentity.dids.keys) {
        try {
          final data = await uds.readDid(did);
          values[did] = String.fromCharCodes(data.where((b) => b >= 0x20 && b < 0x7F)).trim();
        } on UdsNegativeResponse {
          // DID not offered by this ECU
        }
      }
    } finally {
      await uds.release();
    }
    if (values.isEmpty) throw CodingException('coding_no_response');
    return EcuIdentity(values);
  }

  Future<List<int>> readCoding(Ecu ecu) async {
    await uds.select(ecu);
    try {
      return await uds.readDid(ecu.codingDid);
    } on UdsNegativeResponse catch (e) {
      throw CodingException('coding_read_failed', e.name);
    } finally {
      await uds.release();
    }
  }

  Future<CodingBackup> backup(Ecu ecu) async {
    final bytes = await readCoding(ecu);
    final b = CodingBackup(ecu.key, ecu.tx, ecu.codingDid, bytes, DateTime.now());
    await store.save(b);
    return b;
  }

  Future<void> writeCoding(Ecu ecu, List<int> coding, {required CodingBackup backup}) async {
    if (backup.tx != ecu.tx || backup.did != ecu.codingDid) {
      throw CodingException('coding_backup_mismatch');
    }
    if (coding.length != backup.bytes.length) {
      throw CodingException('coding_length_mismatch');
    }
    await uds.select(ecu);
    try {
      await uds.session(0x03); // extended diagnostic session
      await uds.writeDid(ecu.codingDid, coding);
      final check = await uds.readDid(ecu.codingDid);
      if (bytesToHex(check) != bytesToHex(coding)) {
        throw CodingException('coding_verify_failed');
      }
    } on UdsNegativeResponse catch (e) {
      throw CodingException(
          e.nrc == 0x33 ? 'coding_security' : 'coding_write_failed', e.name);
    } finally {
      try {
        await uds.session(0x01);
      } catch (_) {}
      await uds.release();
    }
  }
}
