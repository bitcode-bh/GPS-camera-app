import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/core/date_format.dart';

void main() {
  final morning = DateTime(2026, 11, 3, 9, 5, 7);
  final midnight = DateTime(2026, 1, 1, 0, 0, 0);
  final evening = DateTime(2026, 12, 31, 23, 59, 59);

  test('matches the patterns the app uses', () {
    expect(DateFormat('HH:mm').format(morning), '09:05');
    expect(DateFormat('hh:mm a').format(morning), '09:05 AM');
    expect(DateFormat('hh:mm a').format(midnight), '12:00 AM');
    expect(DateFormat('hh:mm a').format(evening), '11:59 PM');
    expect(DateFormat('d MMM yyyy').format(morning), '3 Nov 2026');
    expect(DateFormat('d MMMM yyyy').format(morning), '3 November 2026');
    expect(DateFormat('EEEE').format(morning), 'Tuesday');
    expect(
      DateFormat('EEE, dd MMM yyyy HH:mm:ss').format(morning),
      'Tue, 03 Nov 2026 09:05:07',
    );
    expect(
      DateFormat('EEE, dd MMM yyyy hh:mm:ss a').format(evening),
      'Thu, 31 Dec 2026 11:59:59 PM',
    );
    expect(
      DateFormat('d MMM yyyy  ·  HH:mm').format(evening),
      '31 Dec 2026  ·  23:59',
    );
    expect(
      DateFormat('d MMM yyyy, HH:mm').format(midnight),
      '1 Jan 2026, 00:00',
    );
  });
}
