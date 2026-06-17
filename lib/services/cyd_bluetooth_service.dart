import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class CydBluetoothService extends ChangeNotifier {
  static final Guid _serviceUuid = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid _rxUuid = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid _txUuid = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e');
  static const String _deviceName = 'CYD-Flock-You';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxCharacteristic;
  StreamSubscription<List<int>>? _notificationSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  final StreamController<String> _lineController =
      StreamController<String>.broadcast();
  final StringBuffer _lineBuffer = StringBuffer();

  bool _isConnected = false;
  bool _isConnecting = false;
  String? _lastError;

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get lastError => _lastError;
  Stream<String> get lines => _lineController.stream;

  Future<bool> connectFirstAvailable() async {
    if (_isConnecting) return false;
    _isConnecting = true;
    _lastError = null;
    notifyListeners();

    try {
      final ready = await _ensureReady();
      if (!ready) return false;

      for (var attempt = 1; attempt <= 3; attempt++) {
        final device = await _findDevice();
        if (device == null) {
          _setError('CYD Bluetooth device not found');
          return false;
        }

        final connected = await connect(device);
        if (connected) return true;

        if (attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 900));
        }
      }

      return false;
    } catch (e) {
      _setError('CYD Bluetooth connection failed: $e');
      await disconnect();
      return false;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<bool> connect(BluetoothDevice device) async {
    await disconnect();

    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 20),
        mtu: 185,
      );

      final services = await device.discoverServices();
      final service = services.where((s) => s.uuid == _serviceUuid).firstOrNull;
      if (service == null) {
        _setError('CYD Bluetooth service not found');
        await device.disconnect();
        return false;
      }

      final rx = service.characteristics
          .where((c) => c.uuid == _rxUuid)
          .firstOrNull;
      final tx = service.characteristics
          .where((c) => c.uuid == _txUuid)
          .firstOrNull;
      if (rx == null || tx == null) {
        _setError('CYD Bluetooth UART characteristics not found');
        await device.disconnect();
        return false;
      }

      _device = device;
      _rxCharacteristic = rx;
      _isConnected = true;
      _lastError = null;

      _connectionSubscription = device.connectionState.listen((state) {
        final connected = state == BluetoothConnectionState.connected;
        if (_isConnected != connected) {
          _isConnected = connected;
          notifyListeners();
        }
      });

      await tx.setNotifyValue(true);
      _notificationSubscription = tx.onValueReceived.listen(
        _handleBytes,
        onError: (Object error) {
          _setError('CYD Bluetooth read failed: $error');
        },
      );

      await writeLine('FYHELLO');
      notifyListeners();
      return true;
    } catch (e) {
      _setError('CYD Bluetooth connection failed: $e');
      await disconnect();
      return false;
    }
  }

  Future<void> disconnect() async {
    await _notificationSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _notificationSubscription = null;
    _connectionSubscription = null;
    _rxCharacteristic = null;
    final device = _device;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {
        // Already disconnected; nothing else to clean up.
      }
    }
    if (_isConnected) {
      _isConnected = false;
      notifyListeners();
    }
  }

  Future<bool> writeLine(String line) async {
    final rx = _rxCharacteristic;
    if (rx == null || !_isConnected) {
      _setError('CYD Bluetooth is not connected');
      return false;
    }

    try {
      await rx.write(utf8.encode('$line\n'), withoutResponse: false);
      return true;
    } catch (e) {
      _setError('CYD Bluetooth write failed: $e');
      return false;
    }
  }

  Future<bool> sendPhoneGps({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    double speedKmph = 0,
    double courseDegrees = 0,
    int satellites = 0,
    double hdop = 0,
  }) {
    final now = DateTime.now();
    final epochSeconds = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    final utcOffsetMinutes = now.timeZoneOffset.inMinutes;
    return writeLine(
      'FYGPS,'
      '${latitude.toStringAsFixed(6)},'
      '${longitude.toStringAsFixed(6)},'
      '${accuracyMeters.toStringAsFixed(1)},'
      '${speedKmph.toStringAsFixed(1)},'
      '${courseDegrees.toStringAsFixed(1)},'
      '$satellites,'
      '${hdop.toStringAsFixed(1)},'
      '$epochSeconds,'
      '$utcOffsetMinutes',
    );
  }

  Future<bool> sendSimulatedDetection() {
    return writeLine('FYSIM');
  }

  Future<bool> _ensureReady() async {
    if (!await FlutterBluePlus.isSupported) {
      _setError('Bluetooth LE is not supported on this device');
      return false;
    }

    final permissions = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final scanGranted =
        permissions[Permission.bluetoothScan]?.isGranted ?? true;
    final connectGranted =
        permissions[Permission.bluetoothConnect]?.isGranted ?? true;
    final locationGranted =
        permissions[Permission.locationWhenInUse]?.isGranted ?? false;
    if (!scanGranted || !connectGranted || !locationGranted) {
      _setError('Bluetooth and location permissions are required');
      return false;
    }

    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      _setError('Bluetooth is turned off');
      return false;
    }
    return true;
  }

  Future<BluetoothDevice?> _findDevice() async {
    final systemDevices = await FlutterBluePlus.systemDevices([_serviceUuid]);
    for (final device in systemDevices) {
      if (_matchesCyd(device)) return device;
    }

    final completer = Completer<BluetoothDevice?>();
    StreamSubscription<List<ScanResult>>? subscription;
    subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        if (_matchesCyd(result.device)) {
          if (!completer.isCompleted) {
            completer.complete(result.device);
          }
          break;
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [_serviceUuid],
        timeout: const Duration(seconds: 10),
      );
      final device = await completer.future.timeout(
        const Duration(seconds: 11),
        onTimeout: () => null,
      );
      return device;
    } finally {
      await FlutterBluePlus.stopScan();
      await subscription.cancel();
    }
  }

  bool _matchesCyd(BluetoothDevice device) {
    return device.platformName == _deviceName || device.advName == _deviceName;
  }

  void _handleBytes(List<int> bytes) {
    final chunk = utf8.decode(bytes, allowMalformed: true);
    for (final codeUnit in chunk.codeUnits) {
      if (codeUnit == 13) continue;
      if (codeUnit == 10) {
        final line = _lineBuffer.toString();
        _lineBuffer.clear();
        if (line.isNotEmpty) {
          _lineController.add(line);
        }
      } else {
        _lineBuffer.writeCharCode(codeUnit);
      }
    }
  }

  void _setError(String message) {
    _lastError = message;
    debugPrint('[CydBluetoothService] $message');
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(disconnect());
    _lineController.close();
    super.dispose();
  }
}
