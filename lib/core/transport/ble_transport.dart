import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'obd_transport.dart';

/// Known service/characteristic layouts of BLE OBD2 adapters.
///
/// Vgate iCar Pro BLE (4.0) exposes one characteristic that both notifies
/// and accepts writes. Many other ELM327 BLE clones use FFF0/FFF1/FFF2.
class BleProfile {
  const BleProfile(this.label, this.service, this.notify, this.write);
  final String label;
  final String service;
  final String notify;
  final String write;
}

const knownProfiles = [
  BleProfile(
    'Vgate iCar Pro BLE',
    'e7810a71-73ae-499d-8c15-faa9aef0c3f2',
    'bef8d6c9-9c21-4c9e-b632-bd58c1009f9f',
    'bef8d6c9-9c21-4c9e-b632-bd58c1009f9f',
  ),
  BleProfile('ELM327 BLE (FFF0)', 'fff0', 'fff1', 'fff2'),
  BleProfile('ELM327 BLE (18F0)', '18f0', '2af0', '2af1'),
  BleProfile('ELM327 BLE (FFE0)', 'ffe0', 'ffe1', 'ffe1'),
];

/// Adapter names we highlight in the device list.
bool looksLikeObdAdapter(String name) {
  final n = name.toLowerCase();
  return const ['icar', 'vgate', 'obd', 'elm', 'vlink', 'v-link', 'ios-vlink', 'android-vlink'].any(n.contains);
}

class BleTransport implements ObdTransport {
  BleTransport._(this.device, this._write, this.profileLabel);

  final BluetoothDevice device;
  final BluetoothCharacteristic _write;
  final String profileLabel;
  final _incoming = StreamController<List<int>>.broadcast();
  StreamSubscription<List<int>>? _sub;

  @override
  String get name => device.platformName.isNotEmpty ? device.platformName : device.remoteId.str;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  /// Connects to [device] and locates the adapter's serial characteristics.
  static Future<BleTransport> connect(BluetoothDevice device) async {
    // The FlutterBluePlus licence is free for personal use; a commercial
    // release needs License.commercial (see the package LICENSE).
    await device.connect(license: License.nonprofit, timeout: const Duration(seconds: 15));
    final services = await device.discoverServices();

    BluetoothCharacteristic? notify;
    BluetoothCharacteristic? write;
    var label = 'BLE';
    bool same(Guid g, String s) => g.str.toLowerCase() == s || g.str128.toLowerCase().contains(s);

    for (final p in knownProfiles) {
      for (final s in services.where((s) => same(s.uuid, p.service))) {
        for (final c in s.characteristics) {
          if (same(c.uuid, p.notify) && (c.properties.notify || c.properties.indicate)) notify = c;
          if (same(c.uuid, p.write) && (c.properties.write || c.properties.writeWithoutResponse)) write = c;
        }
      }
      if (notify != null && write != null) {
        label = p.label;
        break;
      }
      notify = write = null;
    }

    // Unknown adapter: pick the first service offering notify + write.
    if (notify == null || write == null) {
      for (final s in services) {
        final n = s.characteristics.where((c) => c.properties.notify || c.properties.indicate);
        final w = s.characteristics.where((c) => c.properties.write || c.properties.writeWithoutResponse);
        if (n.isNotEmpty && w.isNotEmpty) {
          notify = n.first;
          write = w.first;
          label = 'BLE (${s.uuid.str})';
          break;
        }
      }
    }
    if (notify == null || write == null) {
      await device.disconnect();
      throw StateError('Adapter does not expose a serial characteristic');
    }

    final t = BleTransport._(device, write, label);
    t._sub = notify.onValueReceived.listen(t._incoming.add);
    device.cancelWhenDisconnected(t._sub!);
    await notify.setNotifyValue(true);
    return t;
  }

  @override
  Future<void> write(List<int> data) async {
    final noResponse = _write.properties.writeWithoutResponse;
    const chunk = 20; // safe for the default BLE MTU
    for (var i = 0; i < data.length; i += chunk) {
      final end = i + chunk < data.length ? i + chunk : data.length;
      await _write.write(data.sublist(i, end), withoutResponse: noResponse);
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _incoming.close();
    await device.disconnect();
  }
}
