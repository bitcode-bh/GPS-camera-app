import '../models/geo_data.dart';
import '../models/location_integrity.dart';
import 'location_service.dart';

/// Select once for a photo or video sample; map, text and metadata share it.
GeoData geostampSnapshot({
  required GpsStatus status,
  required DateTime now,
  required double accuracyLimit,
  required MockLocationPolicy mockPolicy,
  GeoData? lastGood,
  double? heading,
}) {
  final current = status.fix;
  final state = status.stateAt(now);
  final available = state == GpsState.fix;
  final fresh = available && current != null && current.hasFreshFix(now);
  final blockedMock =
      status.integrity == LocationIntegrity.suspectedMock &&
      mockPolicy == MockLocationPolicy.omitCoordinates;
  GeoData? selected = fresh ? current : null;
  var integrity = status.integrity;
  var note = status.integrityReason;
  if (selected != null &&
      (selected.accuracy > accuracyLimit ||
          (selected.rawAccuracy ?? selected.accuracy) > accuracyLimit)) {
    if (lastGood != null &&
        lastGood.hasFreshFix(now) &&
        lastGood.accuracy <= accuracyLimit) {
      selected = lastGood;
      note = 'Last acceptable fix';
    }
    if (integrity == LocationIntegrity.trusted) {
      integrity = LocationIntegrity.lowAccuracy;
    }
    if (note.isEmpty) note = 'Weak GPS signal';
  }
  if (!available || selected == null || blockedMock) {
    return GeoData.withoutLocation(now).copyWith(
      integrity:
          integrity == LocationIntegrity.suspectedMock ||
              integrity == LocationIntegrity.suspectedSpoofing
          ? integrity
          : LocationIntegrity.unavailable,
      locationNote: blockedMock ? 'Coordinates omitted' : note,
    );
  }
  final age = now.difference(selected.fixTime!).inSeconds;
  // A retained position remains usable, but never masquerades as a new fix.
  if (age >= 15) {
    if (integrity == LocationIntegrity.trusted) {
      integrity = LocationIntegrity.lowAccuracy;
    }
    note = '${note.isEmpty ? 'Last fix' : note} · ${age}s old';
  }
  if (status.approximate && integrity == LocationIntegrity.trusted) {
    integrity = LocationIntegrity.lowAccuracy;
    note = 'Approximate location';
  }
  return selected.copyWith(
    time: now,
    heading: heading,
    integrity: integrity,
    locationNote: note,
  );
}
