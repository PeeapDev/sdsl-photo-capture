import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/folder_screen.dart';
import 'screens/camera_screen.dart';
import 'screens/folder_detail_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock to portrait
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]).then((_) => runApp(const SchoolPhotoApp()));
}

class SchoolPhotoApp extends StatelessWidget {
  const SchoolPhotoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'School Photo Capture',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      routes: {
        '/': (_) => const FolderScreen(),
        CameraScreen.routeName: (_) => const CameraScreen(),
        '/folderDetail': (ctx) {
          final args = ModalRoute.of(ctx)!.settings.arguments as Map<String, String>;
          return FolderDetailScreen(
            folderName: args['name']!,
            sessionPath: args['path']!,
          );
        },
      },
    );
  }
}

