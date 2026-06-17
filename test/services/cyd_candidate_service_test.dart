import 'package:deflockapp/models/cyd_flock_detection.dart';
import 'package:deflockapp/models/osm_node.dart';
import 'package:deflockapp/services/cyd_candidate_service.dart';
import 'package:deflockapp/state/cyd_candidate_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('CYD serial parsing', () {
    test('parses pair status', () {
      final event = CydSerialEvent.parseLine(
        '{"event":"pair_status","device":"CYD-Flock-You","protocol_version":1,"gps":true,"sd":false,"detections":2,"csv_rows":1}',
      );

      expect(event, isNotNull);
      expect(event!.isPairStatus, isTrue);
      expect(event.pairStatus!.isCompatible, isTrue);
      expect(event.pairStatus!.gpsFresh, isTrue);
      expect(event.pairStatus!.sdReady, isFalse);
    });

    test('parses detection with phone GPS', () {
      final event = CydSerialEvent.parseLine(
        '{"event":"detection","detection_method":"wifi_wildcard_probe","protocol":"wifi_2_4ghz","mac_address":"70:c9:4e:aa:bb:cc","oui":"70:c9:4e","rssi":-62,"channel":6,"frequency":2437,"ssid":"","gps":{"latitude":45.171234,"longitude":-93.225678,"accuracy":6.5,"age_ms":250,"source":"phone"}}',
      );

      expect(event, isNotNull);
      expect(event!.isDetection, isTrue);
      expect(event.detection!.hasPhoneLocation, isTrue);
      expect(
        event.detection!.phoneLocation!.latitude,
        closeTo(45.171234, 0.000001),
      );
      expect(event.detection!.gpsAccuracyMeters, 6.5);
    });

    test('ignores debug lines', () {
      expect(CydSerialEvent.parseLine('[flockyou] scanning'), isNull);
    });
  });

  group('CYD candidate policy', () {
    final service = CydCandidateService();
    const phoneLocation = LatLng(45.171234, -93.225678);
    const nearbyCameraLocation = LatLng(45.171320, -93.225710);
    const farCameraLocation = LatLng(45.174000, -93.225678);

    const detection = CydFlockDetection(
      detectionMethod: 'wifi_wildcard_probe',
      protocol: 'wifi_2_4ghz',
      macAddress: '70:c9:4e:aa:bb:cc',
      oui: '70:c9:4e',
      rssi: -62,
      channel: 6,
      frequency: 2437,
      ssid: '',
      phoneLocation: phoneLocation,
      gpsAccuracyMeters: 6.5,
      gpsAgeMs: 250,
      gpsSource: 'phone',
    );

    test('suppresses candidate when a camera is already within 250 feet', () {
      final candidate = service.buildCandidateIfNew(
        detection: detection,
        existingNodes: [
          OsmNode(
            id: 1,
            coord: nearbyCameraLocation,
            tags: const {
              'man_made': 'surveillance',
              'surveillance:type': 'ALPR',
            },
          ),
        ],
      );

      expect(candidate, isNull);
    });

    test('creates manual-review candidate when no nearby camera exists', () {
      final candidate = service.buildCandidateIfNew(
        detection: detection,
        existingNodes: [
          OsmNode(
            id: 1,
            coord: farCameraLocation,
            tags: const {
              'man_made': 'surveillance',
              'surveillance:type': 'ALPR',
            },
          ),
        ],
      );

      expect(candidate, isNotNull);
      expect(candidate!.requiresLocationAdjustment, isTrue);
      expect(candidate.requiresDirection, isTrue);
      expect(candidate.directionDegrees, isNull);
      expect(candidate.editableLocation, phoneLocation);
      expect(candidate.hasManualLocationAdjustment, isFalse);
      expect(candidate.isReadyForUpload, isFalse);
    });

    test('suppresses candidate when another pending candidate is nearby', () {
      final first = service.buildCandidateIfNew(
        detection: detection,
        existingNodes: const [],
        createdAt: DateTime(2026),
      );

      final second = service.buildCandidateIfNew(
        detection: detection,
        existingNodes: const [],
        pendingCandidates: [first!],
        createdAt: DateTime(2026),
      );

      expect(second, isNull);
    });

    test('candidate is ready only after location adjustment and direction', () {
      final candidate = service.buildCandidateIfNew(
        detection: detection,
        existingNodes: const [],
        createdAt: DateTime(2026),
      );

      final adjusted = candidate!
          .copyWith(editableLocation: const LatLng(45.171260, -93.225710))
          .copyWith(directionDegrees: 135);

      expect(adjusted.hasManualLocationAdjustment, isTrue);
      expect(adjusted.hasManualDirection, isTrue);
      expect(adjusted.isReadyForUpload, isTrue);
    });
  });

  group('CYD candidate state', () {
    test('ingests detection JSON into pending queue', () {
      final state = CydCandidateState();

      final event = state.ingestSerialLine(
        line:
            '{"event":"detection","detection_method":"wifi_wildcard_probe","protocol":"wifi_2_4ghz","mac_address":"70:c9:4e:aa:bb:cc","oui":"70:c9:4e","rssi":-62,"channel":6,"frequency":2437,"ssid":"","gps":{"latitude":45.171234,"longitude":-93.225678,"accuracy":6.5,"age_ms":250,"source":"phone"}}',
        existingNodes: const [],
      );

      expect(event, isNotNull);
      expect(state.pendingCount, 1);
      expect(
        state.pendingCandidates.first.detection.macAddress,
        '70:c9:4e:aa:bb:cc',
      );
    });

    test('tracks pair status and ignores detections without GPS', () {
      final state = CydCandidateState();

      state.ingestSerialLine(
        line:
            '{"event":"pair_status","device":"CYD-Flock-You","protocol_version":1,"gps":true,"sd":true,"detections":3,"csv_rows":2}',
        existingNodes: const [],
      );
      state.ingestSerialLine(
        line:
            '{"event":"detection","detection_method":"wifi_wildcard_probe","protocol":"wifi_2_4ghz","mac_address":"70:c9:4e:aa:bb:cc","oui":"70:c9:4e","rssi":-62,"channel":6,"frequency":2437,"ssid":""}',
        existingNodes: const [],
      );

      expect(state.isPaired, isTrue);
      expect(state.pendingCount, 0);
      expect(state.ignoredMissingGps, 1);
    });
  });
}
