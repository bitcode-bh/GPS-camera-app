/// English date patterns, enough for this app: `d dd M MM MMM MMMM yy yyyy
/// E EEE EEEE H HH h hh m mm s ss a` and any other characters as written.
/// Output matches `intl`'s `DateFormat` in the en_US locale for these tokens.
class DateFormat {
  DateFormat(this.pattern) : _tokens = _tokenize(pattern);

  final String pattern;
  final List<String> _tokens;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
    'Sunday',
  ];

  static List<String> _tokenize(String pattern) {
    final tokens = <String>[];
    var i = 0;
    while (i < pattern.length) {
      final c = pattern[i];
      var j = i + 1;
      if (RegExp('[a-zA-Z]').hasMatch(c)) {
        while (j < pattern.length && pattern[j] == c) {
          j++;
        }
      }
      tokens.add(pattern.substring(i, j));
      i = j;
    }
    return tokens;
  }

  String format(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final out = StringBuffer();
    for (final token in _tokens) {
      out.write(switch (token) {
        'd' => '${t.day}',
        'dd' => two(t.day),
        'M' => '${t.month}',
        'MM' => two(t.month),
        'MMM' => _months[t.month - 1].substring(0, 3),
        'MMMM' => _months[t.month - 1],
        'yy' => two(t.year % 100),
        'yyyy' => t.year.toString().padLeft(4, '0'),
        'E' || 'EE' || 'EEE' => _days[t.weekday - 1].substring(0, 3),
        'EEEE' => _days[t.weekday - 1],
        'H' => '${t.hour}',
        'HH' => two(t.hour),
        'h' => '$hour12',
        'hh' => two(hour12),
        'm' => '${t.minute}',
        'mm' => two(t.minute),
        's' => '${t.second}',
        'ss' => two(t.second),
        'a' => t.hour < 12 ? 'AM' : 'PM',
        _ => token,
      });
    }
    return out.toString();
  }
}
