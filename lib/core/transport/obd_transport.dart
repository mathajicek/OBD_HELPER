import 'dart:async';

/// A byte pipe to an ELM327-compatible adapter (BLE, simulator, …).
abstract class ObdTransport {
  /// Raw bytes coming from the adapter.
  Stream<List<int>> get incoming;

  /// Sends raw bytes to the adapter.
  Future<void> write(List<int> data);

  Future<void> close();

  /// Human readable name shown in the UI.
  String get name;
}
