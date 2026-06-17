import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';

class CydUsbSerialService extends ChangeNotifier {
  UsbPort? _port;
  StreamSubscription<Uint8List>? _inputSubscription;
  final StreamController<String> _lineController =
      StreamController<String>.broadcast();
  final StringBuffer _lineBuffer = StringBuffer();

  bool _isConnected = false;
  String? _lastError;

  bool get isConnected => _isConnected;
  String? get lastError => _lastError;
  Stream<String> get lines => _lineController.stream;

  Future<List<UsbDevice>> listDevices() => UsbSerial.listDevices();

  Future<bool> connectFirstAvailable() async {
    final devices = await listDevices();
    if (devices.isEmpty) {
      _setError('No USB serial devices found');
      return false;
    }

    return connect(devices.first);
  }

  Future<bool> connect(UsbDevice device) async {
    await disconnect();

    try {
      final port = await device.create();
      if (port == null) {
        _setError('Could not create USB serial port');
        return false;
      }

      final opened = await port.open();
      if (!opened) {
        _setError('Could not open USB serial port');
        await port.close();
        return false;
      }

      await port.setDTR(true);
      await port.setRTS(true);
      await port.setPortParameters(
        115200,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      _port = port;
      _isConnected = true;
      _lastError = null;
      _inputSubscription = port.inputStream?.listen(
        _handleBytes,
        onError: (Object error) {
          _setError('USB serial read failed: $error');
        },
        onDone: () {
          _isConnected = false;
          notifyListeners();
        },
      );

      await writeLine('FYHELLO');
      notifyListeners();
      return true;
    } catch (e) {
      _setError('USB serial connection failed: $e');
      await disconnect();
      return false;
    }
  }

  Future<void> disconnect() async {
    await _inputSubscription?.cancel();
    _inputSubscription = null;
    final port = _port;
    _port = null;
    if (port != null) {
      await port.close();
    }
    if (_isConnected) {
      _isConnected = false;
      notifyListeners();
    }
  }

  Future<bool> writeLine(String line) async {
    final port = _port;
    if (port == null || !_isConnected) {
      _setError('USB serial port is not connected');
      return false;
    }

    final bytes = Uint8List.fromList(utf8.encode('$line\n'));
    await port.write(bytes);
    return true;
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

  void _handleBytes(Uint8List bytes) {
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
    debugPrint('[CydUsbSerialService] $message');
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_inputSubscription?.cancel());
    final closeFuture = _port?.close();
    if (closeFuture != null) {
      unawaited(closeFuture.then((_) {}));
    }
    _inputSubscription = null;
    _port = null;
    _lineController.close();
    super.dispose();
  }
}
