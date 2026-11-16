import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'state/prefs.dart';

import 'core/theme.dart';
import 'core/widgets/stash_glass.dart';
import 'screens/camera/camera_screen.dart';
import 'state/settings_controller.dart';
import 'state/template_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  await StashGlass.prepare();
  final prefs = await Prefs.load();
  SettingsController.instance.attach(prefs);
  TemplateController.instance.attach(prefs);

  runApp(const GpsCameraApp());
}

class GpsCameraApp extends StatelessWidget {
  const GpsCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PinShutter',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const CameraScreen(),
    );
  }
}
