import 'package:latlong2/latlong.dart';

import '../models/cyd_flock_detection.dart';
import '../models/osm_node.dart';

class CydFlockCandidate {
  static const double requiredLocationAdjustmentMeters = 2.0;
  static const Distance _distance = Distance();

  final String id;
  final CydFlockDetection detection;
  final LatLng initialLocation;
  final LatLng editableLocation;
  final double? directionDegrees;
  final DateTime createdAt;
  final bool requiresLocationAdjustment;
  final bool requiresDirection;

  CydFlockCandidate({
    required this.id,
    required this.detection,
    required this.initialLocation,
    required this.editableLocation,
    required this.directionDegrees,
    required this.createdAt,
    this.requiresLocationAdjustment = true,
    this.requiresDirection = true,
  });

  double get locationAdjustmentMeters =>
      _distance.as(LengthUnit.Meter, initialLocation, editableLocation);

  bool get hasManualLocationAdjustment =>
      !requiresLocationAdjustment ||
      locationAdjustmentMeters >= requiredLocationAdjustmentMeters;

  bool get hasManualDirection => !requiresDirection || directionDegrees != null;

  bool get isReadyForUpload =>
      hasManualLocationAdjustment && hasManualDirection;

  CydFlockCandidate copyWith({
    LatLng? editableLocation,
    double? directionDegrees,
  }) {
    return CydFlockCandidate(
      id: id,
      detection: detection,
      initialLocation: initialLocation,
      editableLocation: editableLocation ?? this.editableLocation,
      directionDegrees: directionDegrees ?? this.directionDegrees,
      createdAt: createdAt,
      requiresLocationAdjustment: requiresLocationAdjustment,
      requiresDirection: requiresDirection,
    );
  }
}

class CydCandidateService {
  static const double defaultDuplicateRadiusMeters = 76.2; // 250 feet.
  static const Distance _distance = Distance();

  CydFlockCandidate? buildCandidateIfNew({
    required CydFlockDetection detection,
    required Iterable<OsmNode> existingNodes,
    Iterable<CydFlockCandidate> pendingCandidates = const [],
    double duplicateRadiusMeters = defaultDuplicateRadiusMeters,
    DateTime? createdAt,
  }) {
    final location = detection.phoneLocation;
    if (location == null) return null;

    if (hasNearbyDocumentedCamera(
      location: location,
      existingNodes: existingNodes,
      duplicateRadiusMeters: duplicateRadiusMeters,
    )) {
      return null;
    }

    if (hasNearbyPendingCandidate(
      location: location,
      macAddress: detection.macAddress,
      pendingCandidates: pendingCandidates,
      duplicateRadiusMeters: duplicateRadiusMeters,
    )) {
      return null;
    }

    return CydFlockCandidate(
      id: _candidateIdFor(detection, location),
      detection: detection,
      initialLocation: location,
      editableLocation: location,
      directionDegrees: null,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  bool hasNearbyDocumentedCamera({
    required LatLng location,
    required Iterable<OsmNode> existingNodes,
    double duplicateRadiusMeters = defaultDuplicateRadiusMeters,
  }) {
    for (final node in existingNodes) {
      if (!_looksLikeCameraOrAlpr(node)) continue;
      final meters = _distance.as(LengthUnit.Meter, location, node.coord);
      if (meters <= duplicateRadiusMeters) return true;
    }
    return false;
  }

  bool hasNearbyPendingCandidate({
    required LatLng location,
    required String macAddress,
    required Iterable<CydFlockCandidate> pendingCandidates,
    double duplicateRadiusMeters = defaultDuplicateRadiusMeters,
  }) {
    for (final candidate in pendingCandidates) {
      if (candidate.detection.macAddress == macAddress) return true;
      final meters = _distance.as(
        LengthUnit.Meter,
        location,
        candidate.initialLocation,
      );
      if (meters <= duplicateRadiusMeters) return true;
    }
    return false;
  }

  String _candidateIdFor(CydFlockDetection detection, LatLng location) {
    final lat = location.latitude.toStringAsFixed(5);
    final lon = location.longitude.toStringAsFixed(5);
    return '${detection.macAddress}@$lat,$lon';
  }

  bool _looksLikeCameraOrAlpr(OsmNode node) {
    final tags = node.tags;
    if (tags['_pending_deletion'] == 'true') return false;
    if (tags['man_made'] == 'surveillance') return true;

    final surveillanceType = tags['surveillance:type']?.toLowerCase();
    if (surveillanceType == 'alpr' || surveillanceType == 'camera') {
      return true;
    }

    final manufacturer = tags['manufacturer']?.toLowerCase() ?? '';
    return manufacturer.contains('flock');
  }
}
