import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Base-map styles: Normal, Satellite, Hybrid (imagery + labels), Terrain.
enum MapKind { normal, satellite, hybrid, terrain }

/// Esri basemap access.
///
/// Esri's terms require authentication for apps distributed to the public
/// (Product-Specific Terms E300, footnote 89). Release builds therefore show
/// maps only when built with an ArcGIS Location Platform API key:
///
///   `flutter build appbundle --dart-define=ESRI_API_KEY=YOUR_KEY`
///
/// Restrict the key to this app's package and signing certificate, and set a
/// billing cap in the ArcGIS Location Platform dashboard. Debug builds without
/// a key fall back to the public tile endpoints for development only.
class MapTiles {
  MapTiles._();

  static const _key = String.fromEnvironment('ESRI_API_KEY');

  static bool get authenticated => _key.isNotEmpty;

  /// Whether this build may draw Esri maps at all.
  static bool get available => authenticated || !kReleaseMode;

  static const userAgent = 'com.gpscamera.gps_camera_next';

  static const _static =
      'https://static-map-tiles-api.arcgis.com/arcgis/rest/services/'
      'static-basemap-tiles-service/v1';
  static const _imagery =
      'https://ibasemaps-api.arcgis.com/arcgis/rest/services/'
      'World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const _legacy = 'https://server.arcgisonline.com/ArcGIS/rest/services';

  static String _styled(String style) =>
      '$_static/$style/static/tile/{z}/{y}/{x}?token=$_key';
}

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

  bool get _imagery => this == MapKind.satellite || this == MapKind.hybrid;

  /// The base tile layer URL.
  String get tileUrl {
    if (MapTiles.authenticated) {
      return switch (this) {
        MapKind.normal => MapTiles._styled('arcgis/streets'),
        MapKind.terrain => MapTiles._styled('arcgis/outdoor'),
        MapKind.satellite ||
        MapKind.hybrid => '${MapTiles._imagery}?token=${MapTiles._key}',
      };
    }
    return switch (this) {
      MapKind.normal =>
        '${MapTiles._legacy}/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
      MapKind.satellite || MapKind.hybrid =>
        '${MapTiles._legacy}/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      MapKind.terrain =>
        '${MapTiles._legacy}/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
    };
  }

  /// Static basemap tiles are 512 px; the imagery service is 256 px.
  int get tileDimension => MapTiles.authenticated && !_imagery ? 512 : 256;

  /// Hybrid adds a place/label reference layer over the imagery.
  String? get overlayUrl {
    if (this != MapKind.hybrid) return null;
    return MapTiles.authenticated
        ? MapTiles._styled('arcgis/imagery/labels')
        : '${MapTiles._legacy}/Reference/World_Boundaries_and_Places/'
              'MapServer/tile/{z}/{y}/{x}';
  }

  int get overlayDimension => MapTiles.authenticated ? 512 : 256;

  /// Data providers to credit next to "Powered by Esri". These are the
  /// services' published credits; Esri's per-style attribution endpoint is the
  /// authoritative list and may add regional sources.
  String get dataCredit => _imagery
      ? 'Esri, Maxar, Earthstar Geographics, and the GIS User Community'
      : 'Esri, HERE, Garmin, FAO, NOAA, USGS, © OpenStreetMap contributors';
}
