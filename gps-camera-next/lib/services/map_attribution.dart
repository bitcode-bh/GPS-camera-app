import 'dart:convert';
import 'dart:io';

import '../models/map_kind.dart';

/// Cache service-wide copyright metadata, never user locations or map tiles.
class MapAttribution {
  MapAttribution({Future<String> Function(Uri)? fetch})
    : _fetch = fetch ?? _request;

  static MapAttribution instance = MapAttribution();
  final Future<String> Function(Uri) _fetch;
  final _pending = <MapKind, Future<String>>{};
  final _ready = <MapKind, String>{};
  final _generation = <MapKind, int>{};

  /// Photo snapshots need already-verified credits on their first frame.
  String? cached(MapKind kind) => _ready[kind];

  Future<String> forKind(MapKind kind) => _pending.putIfAbsent(kind, () async {
    final generation = _generation[kind] ?? 0;
    final credits = <String>{};
    for (final uri in kind.metadataUrls) {
      credits.add(parse(await _fetch(uri)));
    }
    final result = 'Powered by Esri · ${credits.join(' · ')}';
    if (generation == (_generation[kind] ?? 0)) _ready[kind] = result;
    return result;
  });

  void retry(MapKind kind) {
    _generation[kind] = (_generation[kind] ?? 0) + 1;
    _ready.remove(kind);
    _pending.remove(kind);
  }

  static String parse(String body) {
    final value = jsonDecode(body);
    if (value is! Map ||
        value['error'] != null ||
        value['copyrightText'] is! String) {
      throw const FormatException('Map credits unavailable');
    }
    var text = (value['copyrightText'] as String)
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&copy;', '©')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    text = text
        .replaceAllMapped(RegExp(r'&#(x[0-9a-fA-F]+|[0-9]+);'), (m) {
          final raw = m[1]!;
          final code = int.tryParse(
            raw.startsWith('x') ? raw.substring(1) : raw,
            radix: raw.startsWith('x') ? 16 : 10,
          );
          return code != null && code > 0 && code <= 0x10ffff
              ? String.fromCharCode(code)
              : m[0]!;
        })
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) throw const FormatException('Map credits unavailable');
    return text;
  }

  static Future<String> _request(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      MapTiles.headers.forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != 200) {
        throw const HttpException('Map credits unavailable');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 5))) {
        bytes.addAll(chunk);
        if (bytes.length > 128 * 1024) {
          throw const FormatException('Map metadata too large');
        }
      }
      return utf8.decode(bytes);
    } finally {
      client.close(force: true);
    }
  }
}
