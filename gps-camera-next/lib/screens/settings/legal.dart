import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/design/palette.dart';
import '../../core/design/text_styles.dart';
import '../../services/native.dart';

/// The published privacy policy. Set at build time:
/// `--dart-define=PRIVACY_POLICY_URL=https://example.com/privacy`
const privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');

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
    yield const LicenseEntryWithLineBreaks([
      'AndroidX CameraX',
      'AndroidX Media3 (ExoPlayer, Transformer, Effect)',
      'AndroidX ExifInterface',
      'AndroidX libraries',
      'Kotlin standard library',
    ], _apacheNotice);
  });
}

const _apacheNotice =
    'Licensed under the Apache License, Version 2.0 (the "License"); you may '
    'not use these files except in compliance with the License. You may '
    'obtain a copy of the License at\n\n'
    'http://www.apache.org/licenses/LICENSE-2.0\n\n'
    'Unless required by applicable law or agreed to in writing, software '
    'distributed under the License is distributed on an "AS IS" BASIS, '
    'WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. '
    'See the License for the specific language governing permissions and '
    'limitations under the License.';

Future<void> showOpenSourceLicences(BuildContext context) async {
  _addNativeLicences();
  final version = await appVersion();
  if (!context.mounted) return;
  showLicensePage(
    context: context,
    applicationName: 'GPS Camera Next',
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
      'What stays on your phone',
      'Photos, videos and their sound are saved to your gallery. The app has '
          'no account, no cloud upload, no ads and no analytics. Text you type '
          'into the stamp stays on the device.',
    ),
    (
      'Location',
      'Used only while the app is open, to add coordinates, an address and a '
          'small map to your captures, and to place them on the Library map. '
          'To draw maps, the area you are viewing is sent to our map provider '
          '(Esri). To look up the address, coordinates are sent to your '
          'phone\'s geocoding service. We do not store or sell your location.',
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
          'working. Turn off "Embed GPS in photo metadata" to keep coordinates '
          'out of saved files. Uninstalling or clearing the app\'s storage '
          'removes its settings and location index; your gallery files stay '
          'until you delete them.',
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
          SelectableText(
            privacyPolicyUrl,
            style: AppText.body.copyWith(color: Palette.teal),
          ),
        ],
      ],
    ),
  );
}
