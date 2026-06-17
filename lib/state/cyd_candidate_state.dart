import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/cyd_flock_detection.dart';
import '../models/osm_node.dart';
import '../services/cyd_candidate_service.dart';

class CydCandidateState extends ChangeNotifier {
  final CydCandidateService _candidateService;
  final List<CydFlockCandidate> _pendingCandidates = [];

  CydPairStatus? _pairStatus;
  DateTime? _lastEventAt;
  int _ignoredMissingGps = 0;
  int _ignoredDuplicates = 0;
  int _parseFailures = 0;

  CydCandidateState({CydCandidateService? candidateService})
    : _candidateService = candidateService ?? CydCandidateService();

  CydPairStatus? get pairStatus => _pairStatus;
  DateTime? get lastEventAt => _lastEventAt;
  List<CydFlockCandidate> get pendingCandidates =>
      List.unmodifiable(_pendingCandidates);
  int get pendingCount => _pendingCandidates.length;
  int get ignoredMissingGps => _ignoredMissingGps;
  int get ignoredDuplicates => _ignoredDuplicates;
  int get parseFailures => _parseFailures;

  bool get isPaired => _pairStatus?.isCompatible == true;

  CydFlockCandidate? candidateById(String candidateId) {
    for (final candidate in _pendingCandidates) {
      if (candidate.id == candidateId) return candidate;
    }
    return null;
  }

  CydSerialEvent? ingestSerialLine({
    required String line,
    required Iterable<OsmNode> existingNodes,
  }) {
    final event = CydSerialEvent.parseLine(line);
    if (event == null) {
      if (line.trim().startsWith('{')) {
        _parseFailures++;
        notifyListeners();
      }
      return null;
    }

    _lastEventAt = DateTime.now();
    if (event.pairStatus != null) {
      _pairStatus = event.pairStatus;
      notifyListeners();
      return event;
    }

    final detection = event.detection;
    if (detection == null) {
      notifyListeners();
      return event;
    }

    if (!detection.hasPhoneLocation) {
      _ignoredMissingGps++;
      notifyListeners();
      return event;
    }

    final candidate = _candidateService.buildCandidateIfNew(
      detection: detection,
      existingNodes: existingNodes,
      pendingCandidates: _pendingCandidates,
    );

    if (candidate == null) {
      _ignoredDuplicates++;
    } else {
      _pendingCandidates.add(candidate);
    }

    notifyListeners();
    return event;
  }

  void updateCandidateLocation(String candidateId, LatLng location) {
    final index = _pendingCandidates.indexWhere((c) => c.id == candidateId);
    if (index < 0) return;
    _pendingCandidates[index] = _pendingCandidates[index].copyWith(
      editableLocation: location,
    );
    notifyListeners();
  }

  void updateCandidateDirection(String candidateId, double directionDegrees) {
    final index = _pendingCandidates.indexWhere((c) => c.id == candidateId);
    if (index < 0) return;
    _pendingCandidates[index] = _pendingCandidates[index].copyWith(
      directionDegrees: _normalizeDirection(directionDegrees),
    );
    notifyListeners();
  }

  CydFlockCandidate? removeCandidate(String candidateId) {
    final index = _pendingCandidates.indexWhere((c) => c.id == candidateId);
    if (index < 0) return null;
    final candidate = _pendingCandidates.removeAt(index);
    notifyListeners();
    return candidate;
  }

  void clearCandidates() {
    if (_pendingCandidates.isEmpty) return;
    _pendingCandidates.clear();
    notifyListeners();
  }

  double _normalizeDirection(double value) {
    return ((value % 360) + 360) % 360;
  }
}
