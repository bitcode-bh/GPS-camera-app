import 'package:flutter/material.dart';

/// Base-map styles (mirrors the reference app's Normal / Satellite / Hybrid /
/// Terrain). Esri tiles are used so no API key is required.
enum MapKind { normal, satellite, hybrid, terrain }

extension MapKindX on MapKind {
  String get label => switch (this) {
        MapKind.normal => 'Normal',
        MapKind.satellite => 'Satellite',
        MapKind.hybrid => 'Hybrid',
        MapKind.terrain => 'Terrain',
      };

  IconData get icon => switch (this) {
        MapKind.normal => Icons.map_outlined,
        MapKind.satellite => Icons.satellite_alt_outlined,
        MapKind.hybrid => Icons.layers_outlined,
        MapKind.terrain => Icons.terrain_outlined,
      };

  /// The base tile layer URL.
  String get tileUrl => switch (this) {
        MapKind.normal =>
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
        MapKind.satellite || MapKind.hybrid =>
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        MapKind.terrain =>
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
      };

  /// Hybrid adds a place/label reference layer over the imagery.
  String? get overlayUrl => this == MapKind.hybrid
      ? 'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}'
      : null;
}
