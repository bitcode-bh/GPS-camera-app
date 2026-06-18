/// Minimal Open Location Code (plus code) encoder — the 8-character area code
/// plus two grid-refinement digits, e.g. "7JWVCF9M+W8".
class PlusCode {
  PlusCode._();

  static const String _alphabet = '23456789CFGHJMPQRVWX';
  static const String _sep = '+';
  static const List<double> _pairRes = [20.0, 1.0, 0.05, 0.0025, 0.000125];
  static const int _gridCols = 4;
  static const int _gridRows = 5;

  static String encode(double latitude, double longitude) {
    var lat = latitude.clamp(-90.0, 90.0);
    if (lat >= 90) lat = 89.9999999;
    var lon = longitude;
    while (lon < -180) {
      lon += 360;
    }
    while (lon >= 180) {
      lon -= 360;
    }

    var latVal = lat + 90.0;
    var lonVal = lon + 180.0;
    final buf = StringBuffer();

    for (var i = 0; i < 5; i++) {
      final res = _pairRes[i];
      final latDigit = (latVal / res).floor().clamp(0, 19);
      final lonDigit = (lonVal / res).floor().clamp(0, 19);
      buf.write(_alphabet[latDigit]);
      buf.write(_alphabet[lonDigit]);
      latVal -= latDigit * res;
      lonVal -= lonDigit * res;
      if (buf.length == 8) buf.write(_sep);
    }

    var latRes = _pairRes.last;
    var lonRes = _pairRes.last;
    for (var i = 0; i < 2; i++) {
      latRes /= _gridRows;
      lonRes /= _gridCols;
      final row = (latVal / latRes).floor().clamp(0, _gridRows - 1);
      final col = (lonVal / lonRes).floor().clamp(0, _gridCols - 1);
      buf.write(_alphabet[row * _gridCols + col]);
      latVal -= row * latRes;
      lonVal -= col * lonRes;
    }
    return buf.toString();
  }
}
