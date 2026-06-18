import 'dart:math' as math;

import 'plus_code.dart';

/// The coordinate display formats offered (mirrors the reference app).
enum CoordFormat { decimal, dms, utm, mgrs, plusCode }

extension CoordFormatX on CoordFormat {
  String get label => switch (this) {
        CoordFormat.decimal => 'Decimal',
        CoordFormat.dms => 'DMS',
        CoordFormat.utm => 'UTM',
        CoordFormat.mgrs => 'MGRS',
        CoordFormat.plusCode => 'Plus Code',
      };
}

/// Converts a lat/lon pair into the various coordinate representations.
///
/// Decimal, DMS and Plus Code are exact. UTM/MGRS use the standard WGS-84
/// transverse-Mercator projection — accurate to the metre, which is well within
/// what a phone GPS delivers.
class Coordinates {
  Coordinates._();

  static String decimal(double lat, double lon) {
    final ns = lat >= 0 ? 'N' : 'S';
    final ew = lon >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(6)}° $ns, ${lon.abs().toStringAsFixed(6)}° $ew';
  }

  static String dms(double lat, double lon) {
    return '${_dms(lat, lat >= 0 ? 'N' : 'S')} ${_dms(lon, lon >= 0 ? 'E' : 'W')}';
  }

  static String _dms(double value, String hemi) {
    final v = value.abs();
    final d = v.floor();
    final mFull = (v - d) * 60;
    final m = mFull.floor();
    final s = (mFull - m) * 60;
    return "$d°$m'${s.toStringAsFixed(1)}\"$hemi";
  }

  /// Formats per the chosen [format]. Single-line readout for the stamp.
  static String format(CoordFormat fmt, double lat, double lon) {
    switch (fmt) {
      case CoordFormat.decimal:
        return decimal(lat, lon);
      case CoordFormat.dms:
        return dms(lat, lon);
      case CoordFormat.plusCode:
        return PlusCode.encode(lat, lon);
      case CoordFormat.utm:
        final u = _utm(lat, lon);
        return '${u.zone}${u.band} ${u.easting.round()}E ${u.northing.round()}N';
      case CoordFormat.mgrs:
        return _mgrs(lat, lon);
    }
  }

  // ── UTM / MGRS (WGS-84) ──────────────────────────────────────────────
  static ({int zone, String band, double easting, double northing}) _utm(
      double lat, double lon) {
    const a = 6378137.0; // WGS-84 semi-major axis
    const f = 1 / 298.257223563;
    final e2 = f * (2 - f);
    final ep2 = e2 / (1 - e2);
    final k0 = 0.9996;

    final zone = ((lon + 180) / 6).floor() + 1;
    final lonOrigin = (zone - 1) * 6 - 180 + 3;
    final latRad = lat * math.pi / 180;
    final lonRad = lon * math.pi / 180;
    final lonOriginRad = lonOrigin * math.pi / 180;

    final n = a / math.sqrt(1 - e2 * math.sin(latRad) * math.sin(latRad));
    final t = math.tan(latRad) * math.tan(latRad);
    final c = ep2 * math.cos(latRad) * math.cos(latRad);
    final aa = math.cos(latRad) * (lonRad - lonOriginRad);

    final m = a *
        ((1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 * e2 * e2 / 256) * latRad -
            (3 * e2 / 8 + 3 * e2 * e2 / 32 + 45 * e2 * e2 * e2 / 1024) *
                math.sin(2 * latRad) +
            (15 * e2 * e2 / 256 + 45 * e2 * e2 * e2 / 1024) * math.sin(4 * latRad) -
            (35 * e2 * e2 * e2 / 3072) * math.sin(6 * latRad));

    var easting = k0 *
            n *
            (aa +
                (1 - t + c) * aa * aa * aa / 6 +
                (5 - 18 * t + t * t + 72 * c - 58 * ep2) *
                    aa *
                    aa *
                    aa *
                    aa *
                    aa /
                    120) +
        500000.0;

    var northing = k0 *
        (m +
            n *
                math.tan(latRad) *
                (aa * aa / 2 +
                    (5 - t + 9 * c + 4 * c * c) * aa * aa * aa * aa / 24 +
                    (61 - 58 * t + t * t + 600 * c - 330 * ep2) *
                        aa *
                        aa *
                        aa *
                        aa *
                        aa *
                        aa /
                        720));
    if (lat < 0) northing += 10000000.0;

    return (zone: zone, band: _band(lat), easting: easting, northing: northing);
  }

  static String _band(double lat) {
    const bands = 'CDEFGHJKLMNPQRSTUVWX';
    if (lat < -80 || lat > 84) return 'Z';
    final i = ((lat + 80) / 8).floor().clamp(0, bands.length - 1);
    return bands[i];
  }

  static String _mgrs(double lat, double lon) {
    final u = _utm(lat, lon);
    const colLetters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const rowLetters = 'ABCDEFGHJKLMNPQRSTUV';

    final setIndex = (u.zone - 1) % 3;
    // 100km easting square letter.
    final eIndex = (u.easting / 100000).floor() - 1;
    final colSetStart = [0, 8, 16][setIndex];
    final colLetter = colLetters[(colSetStart + eIndex) % 24];

    // 100km northing square letter (alternating origin by zone parity).
    final nFull = (u.northing % 2000000) / 100000;
    final rowSetStart = (u.zone % 2 == 0) ? 5 : 0;
    final rowLetter = rowLetters[(rowSetStart + nFull.floor()) % 20];

    final e = (u.easting % 100000).round().toString().padLeft(5, '0');
    final n = (u.northing % 100000).round().toString().padLeft(5, '0');
    return '${u.zone}${u.band} $colLetter$rowLetter $e $n';
  }
}
