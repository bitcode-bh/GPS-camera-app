enum MediaKind { image, video }

/// One MediaStore row. Identified by its stable MediaStore id, never by path.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.taken,
    this.modifiedSeconds = 0,
    this.duration = Duration.zero,
    this.width = 0,
    this.height = 0,
    this.sizeBytes = 0,
    this.mime = '',
  });

  final int id;
  final MediaKind kind;
  final String name;
  final DateTime taken;
  final int modifiedSeconds;
  final Duration duration;
  final int width;
  final int height;
  final int sizeBytes;
  final String mime;

  bool get isVideo => kind == MediaKind.video;

  /// Unique across images and videos, which use separate id spaces.
  String get key => '${kind.name}:$id';

  /// Changes when the file behind the row changes, so caches refresh.
  String get revision => '$key@$modifiedSeconds';

  Uri get uri => Uri.parse(
    'content://media/external/${isVideo ? 'video' : 'images'}/media/$id',
  );

  factory MediaItem.fromRow(Map<Object?, Object?> row) => MediaItem(
    id: (row['id'] as num).toInt(),
    kind: row['kind'] == 'video' ? MediaKind.video : MediaKind.image,
    name: row['name'] as String? ?? '',
    taken: DateTime.fromMillisecondsSinceEpoch(
      (row['takenMs'] as num?)?.toInt() ?? 0,
    ),
    modifiedSeconds: (row['modifiedSeconds'] as num?)?.toInt() ?? 0,
    duration: Duration(milliseconds: (row['durationMs'] as num?)?.toInt() ?? 0),
    width: (row['width'] as num?)?.toInt() ?? 0,
    height: (row['height'] as num?)?.toInt() ?? 0,
    sizeBytes: (row['size'] as num?)?.toInt() ?? 0,
    mime: row['mime'] as String? ?? '',
  );

  @override
  bool operator ==(Object other) =>
      other is MediaItem && other.revision == revision;

  @override
  int get hashCode => revision.hashCode;
}

/// Where a photo or video was captured. Never the device's current position.
class MediaLocation {
  const MediaLocation(
    this.lat,
    this.lon, {
    this.place = '',
    this.integrityNote = '',
  });

  final double lat;
  final double lon;
  final String place;
  final String integrityNote;

  /// Rejects missing, out-of-range and null-island coordinates.
  static bool isValid(double? lat, double? lon) =>
      lat != null &&
      lon != null &&
      lat.isFinite &&
      lon.isFinite &&
      lat.abs() <= 90 &&
      lon.abs() <= 180 &&
      !(lat == 0 && lon == 0);

  Map<String, Object?> toJson() => {
    'lat': lat,
    'lon': lon,
    'place': place,
    if (integrityNote.isNotEmpty) 'integrityNote': integrityNote,
  };

  static MediaLocation? fromJson(Object? json) {
    if (json is! Map) return null;
    final lat = (json['lat'] as num?)?.toDouble();
    final lon = (json['lon'] as num?)?.toDouble();
    if (!isValid(lat, lon)) return null;
    return MediaLocation(
      lat!,
      lon!,
      place: json['place'] as String? ?? '',
      integrityNote: json['integrityNote'] as String? ?? '',
    );
  }
}

String formatMediaDuration(Duration d) {
  final seconds = (d.inMilliseconds / 1000).round();
  final s = (seconds % 60).toString().padLeft(2, '0');
  final m = seconds ~/ 60 % 60;
  final h = seconds ~/ 3600;
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}
