import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/palette.dart';
import '../../core/design/text_styles.dart';
import '../../services/native.dart';

/// The published privacy policy. Set at build time:
/// `--dart-define=PRIVACY_POLICY_URL=https://example.com/privacy`
const privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');
const privacyContactEmail = String.fromEnvironment('PRIVACY_CONTACT_EMAIL');
const developerDisplayName = 'bitcode.bh';

const mapAccuracyNotice =
    'Maps, addresses and coordinates come from GPS signals and third-party '
    'services and can be inaccurate, incomplete or out of date. Do not rely '
    'on them for navigation, surveying, legal or emergency purposes.';

/// "1.2.0 (14)" from the installed package.
Future<String> appVersion() async {
  try {
    return await Native.appVersion() ?? '—';
  } catch (_) {
    return '—';
  }
}

bool _nativeLicencesAdded = false;

/// Flutter lists Dart package licences itself; the Android libraries linked
/// by Gradle are added here so every notice is in one place.
void _addNativeLicences() {
  if (_nativeLicencesAdded) return;
  _nativeLicencesAdded = true;
  LicenseRegistry.addLicense(() async* {
    final rows =
        jsonDecode(
              await rootBundle.loadString('assets/legal/android-notices.json'),
            )
            as List;
    for (final row in rows.cast<Map<String, dynamic>>()) {
      yield LicenseEntryWithLineBreaks(
        (row['packages'] as List).cast<String>(),
        row['text'] as String,
      );
    }
  });
}

Future<void> showOpenSourceLicences(BuildContext context) async {
  _addNativeLicences();
  final version = await appVersion();
  if (!context.mounted) return;
  showLicensePage(
    context: context,
    applicationName: 'PinShutter',
    applicationVersion: version,
    applicationLegalese:
        'Maps powered by Esri; map data © Esri and its data providers.',
  );
}

void showPrivacy(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()));

/// The privacy summary inside the app, as Google Play requires. The full
/// policy lives at [privacyPolicyUrl].
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _sections = <(String, String)>[
    (
      'Captures and details',
      'Photos, videos and their sound are saved to your gallery. The app has '
          'no account, no automatic media upload, no ads and no analytics. '
          'Stamp details and preferences are stored in app-private files. '
          'Your gallery or backup apps may separately back up saved captures.',
    ),
    (
      'Location',
      'Used only while the app is open, to add coordinates, an address and a '
          'small map to your captures, and to place them on the Library map. '
          'To draw maps, the area you are viewing is sent to our map provider '
          '(Esri). To look up the address, coordinates are sent to your '
          'phone\'s geocoding service. These requests can reveal precise '
          'location and include network information such as your IP address. '
          'Capture coordinates, addresses and accuracy/integrity details are '
          'stored in the local library index. We do not operate a server '
          'that collects your captures or location, and do not sell location.',
    ),
    (
      'Sharing',
      'When you share a capture, the app you choose receives the file, '
          'including its visible stamp and, if "Embed GPS in photo metadata" '
          'is on, its coordinates. Location can reveal where you live or work.',
    ),
    (
      'Your choices',
      'Turn location off in Android settings at any time; the app keeps '
          'working. "Embed GPS in photo metadata" controls EXIF only. Turning '
          'it off does not remove coordinates, addresses or maps printed in '
          'the visible stamp, or the local library index. Review stamp fields '
          'before sharing. Uninstalling or clearing the app\'s storage '
          'removes its settings and location index; your gallery files stay '
          'until you delete them.',
    ),
    (
      'Backups and retention',
      'The app excludes its private settings, stamp details and location index '
          'from Android cloud backup and device transfer. These local files '
          'remain until you delete the relevant entry, clear app storage or '
          'uninstall. This does not delete gallery copies, previous backups '
          'or files you shared. Map and geocoding providers have separate '
          'retention and privacy terms.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: const Text('Privacy'),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text('Developer: $developerDisplayName', style: AppText.bodyHi),
        const SizedBox(height: 20),
        for (final (title, body) in _sections) ...[
          Text(title, style: AppText.bodyHi.copyWith(color: Colors.white)),
          const SizedBox(height: 6),
          Text(body, style: AppText.body.copyWith(height: 1.4)),
          const SizedBox(height: 20),
        ],
        Text(
          'Map accuracy',
          style: AppText.bodyHi.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 6),
        Text(mapAccuracyNotice, style: AppText.body.copyWith(height: 1.4)),
        if (privacyPolicyUrl.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Full privacy policy',
            style: AppText.bodyHi.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: const Text('Read the full privacy policy'),
            onPressed: () async {
              var opened = false;
              try {
                opened = await Native.openWebPage(privacyPolicyUrl);
              } catch (_) {
                // Keep the address available if no browser can handle it.
              }
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Could not open the browser. Copy the policy address below.',
                    ),
                  ),
                );
              }
            },
          ),
          SelectableText(
            privacyPolicyUrl,
            style: AppText.body.copyWith(color: Palette.teal),
          ),
        ],
        if (privacyContactEmail.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Privacy contact', style: AppText.bodyHi),
          const SizedBox(height: 6),
          SelectableText(privacyContactEmail, style: AppText.body),
        ],
      ],
    ),
  );
}
