import 'package:flutter/material.dart';

import 'data/library_db.dart';
import 'state/library_controller.dart';
import 'state/viewer_controller.dart';
import 'ui/library_screen.dart';
import 'ui/theme.dart';
import 'ui/viewer_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DicomApp());
}

class DicomApp extends StatelessWidget {
  const DicomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DICOM Viewer',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const _Home(),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  late final LibraryDb _db;
  late final LibraryController _library;
  late final ViewerController _viewer;
  bool _inViewer = false;

  @override
  void initState() {
    super.initState();
    _db = LibraryDb();
    _library = LibraryController(_db);
    _viewer = ViewerController(_db);
    _library.refresh();
  }

  @override
  void dispose() {
    _library.dispose();
    _viewer.dispose();
    super.dispose();
  }

  Future<void> _openSeries(series) async {
    setState(() => _inViewer = true);
    await _viewer.openSeries(series);
  }

  void _closeViewer() {
    _viewer.close();
    setState(() => _inViewer = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _inViewer
          ? ViewerScreen(
              key: const ValueKey('viewer'),
              controller: _viewer,
              onBack: _closeViewer,
            )
          : LibraryScreen(
              key: const ValueKey('library'),
              controller: _library,
              onOpenSeries: _openSeries,
            ),
    );
  }
}
