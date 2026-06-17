import 'dart:convert';

import 'package:latlong2/latlong.dart';

class CydPairStatus {
  final String device;
  final int protocolVersion;
  final bool gpsFresh;
  final bool sdReady;
  final int detections;
  final int csvRows;

  const CydPairStatus({
    required this.device,
    required this.protocolVersion,
    required this.gpsFresh,
    required this.sdReady,
    required this.detections,
    required this.csvRows,
  });

  bool get isCompatible => device == 'CYD-Flock-You' && protocolVersion == 1;

  factory CydPairStatus.fromJson(Map<String, dynamic> json) {
    return CydPairStatus(
      device: json['device']?.toString() ?? '',
      protocolVersion: (json['protocol_version'] as num?)?.toInt() ?? 0,
      gpsFresh: json['gps'] == true,
      sdReady: json['sd'] == true,
      detections: (json['detections'] as num?)?.toInt() ?? 0,
      csvRows: (json['csv_rows'] as num?)?.toInt() ?? 0,
    );
  }
}

class CydFlockDetection {
  final String detectionMethod;
  final String protocol;
  final String macAddress;
  final String oui;
  final int rssi;
  final int channel;
  final int frequency;
  final String ssid;
  final LatLng? phoneLocation;
  final double? gpsAccuracyMeters;
  final int? gpsAgeMs;
  final String gpsSource;

  const CydFlockDetection({
    required this.detectionMethod,
    required this.protocol,
    required this.macAddress,
    required this.oui,
    required this.rssi,
    required this.channel,
    required this.frequency,
    required this.ssid,
    required this.phoneLocation,
    required this.gpsAccuracyMeters,
    required this.gpsAgeMs,
    required this.gpsSource,
  });

  bool get hasPhoneLocation => phoneLocation != null;

  factory CydFlockDetection.fromJson(Map<String, dynamic> json) {
    LatLng? location;
    double? accuracy;
    int? ageMs;
    String source = '';

    final gps = json['gps'];
    if (gps is Map<String, dynamic>) {
      final lat = (gps['latitude'] as num?)?.toDouble();
      final lon = (gps['longitude'] as num?)?.toDouble();
      if (lat != null && lon != null) {
        location = LatLng(lat, lon);
      }
      accuracy = (gps['accuracy'] as num?)?.toDouble();
      ageMs = (gps['age_ms'] as num?)?.toInt();
      source = gps['source']?.toString() ?? '';
    }

    return CydFlockDetection(
      detectionMethod: json['detection_method']?.toString() ?? '',
      protocol: json['protocol']?.toString() ?? '',
      macAddress: json['mac_address']?.toString() ?? '',
      oui: json['oui']?.toString() ?? '',
      rssi: (json['rssi'] as num?)?.toInt() ?? 0,
      channel: (json['channel'] as num?)?.toInt() ?? 0,
      frequency: (json['frequency'] as num?)?.toInt() ?? 0,
      ssid: json['ssid']?.toString() ?? '',
      phoneLocation: location,
      gpsAccuracyMeters: accuracy,
      gpsAgeMs: ageMs,
      gpsSource: source,
    );
  }
}

class CydSerialEvent {
  final CydPairStatus? pairStatus;
  final CydFlockDetection? detection;

  const CydSerialEvent._({this.pairStatus, this.detection});

  bool get isPairStatus => pairStatus != null;
  bool get isDetection => detection != null;

  static CydSerialEvent? parseLine(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('{')) return null;

    final Object decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    switch (decoded['event']) {
      case 'pair_status':
        return CydSerialEvent._(pairStatus: CydPairStatus.fromJson(decoded));
      case 'detection':
        return CydSerialEvent._(detection: CydFlockDetection.fromJson(decoded));
      default:
        return null;
    }
  }
}
