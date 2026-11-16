import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'packaged native notices cover the selected runtime inventory',
    () async {
      final components =
          (jsonDecode(
                    await rootBundle.loadString(
                      'assets/legal/android-components.json',
                    ),
                  )
                  as List)
              .cast<Map<String, dynamic>>();
      final entries =
          (jsonDecode(
                    await rootBundle.loadString(
                      'assets/legal/android-notices.json',
                    ),
                  )
                  as List)
              .cast<Map<String, dynamic>>();
      final credited = {
        for (final entry in entries)
          ...(entry['packages'] as List).cast<String>(),
      };
      for (final component in components) {
        expect(
          credited,
          contains(component['coordinate']),
          reason: component['coordinate'] as String,
        );
      }
      final text = entries.map((e) => e['text'] as String).join('\n');
      expect(text, contains('END OF TERMS AND CONDITIONS'));
      expect(text, contains('Copyright 2011 The LibYuv Project Authors'));
      expect(
        components.any(
          (c) => c['coordinate'] == 'com.google.guava:guava:33.7.2-android',
        ),
        isTrue,
      );
      expect(
        components.any(
          (c) => c['coordinate'] == 'com.google.guava:guava:33.5.0-android',
        ),
        isFalse,
      );
    },
  );
}
