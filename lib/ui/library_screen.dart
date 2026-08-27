import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../data/library_db.dart';
import '../dicom/dicom.dart';
import '../state/library_controller.dart';
import 'theme.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.controller,
    required this.onOpenSeries,
  });

  final LibraryController controller;
  final ValueChanged<SeriesInfo> onOpenSeries;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _importing = false;

  LibraryController get c => widget.controller;

  Future<void> _importFolder() async {
    setState(() => _importing = true);
    try {
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Import DICOM folder',
      );
      if (dirPath == null) return;

      final pairs = <ImportPair>[];
      final dir = Directory(dirPath);
      final rootName = p.basename(dirPath);
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        final rel = p.join(rootName, p.relative(entity.path, from: dirPath));
        try {
          final bytes = await entity.readAsBytes();
          pairs.add(ImportPair(name: name, relPath: rel, bytes: bytes));
        } catch (_) {}
      }

      if (pairs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No files found in that folder.')),
          );
        }
        return;
      }

      final firstId = await c.importPairs(pairs);
      if (firstId != null && mounted) {
        final series = c.series.where((s) => s.seriesId == firstId).firstOrNull;
        if (series != null) widget.onOpenSeries(series);
      }
      if (c.toast != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(c.toast!)),
        );
        c.clearToast();
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'DICOM Viewer',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _importing ? null : _importFolder,
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: Text(_importing ? 'Importing…' : 'Import Folder'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: c.loading
                      ? const Center(child: CircularProgressIndicator())
                      : c.series.isEmpty
                          ? _EmptyState(onImport: _importFolder)
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(6, 4, 6, 10),
                                  child: Text(
                                    '${c.series.length} ${c.series.length == 1 ? 'study' : 'studies'}',
                                    style: const TextStyle(
                                      color: AppColors.text2,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                ...c.series.map(
                                  (s) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _StudyTile(
                                      series: s,
                                      db: c.db,
                                      onTap: () => widget.onOpenSeries(s),
                                      onDelete: () => c.deleteSeries(s.seriesId),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onImport});
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_list_rounded, size: 56, color: AppColors.text3),
            const SizedBox(height: 16),
            const Text(
              'No studies yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Import a folder of DICOM files (any extension, or none) to scroll through its slices and view metadata.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text2, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onImport,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Import Folder'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudyTile extends StatefulWidget {
  const _StudyTile({
    required this.series,
    required this.db,
    required this.onTap,
    required this.onDelete,
  });

  final SeriesInfo series;
  final LibraryDb db;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_StudyTile> createState() => _StudyTileState();
}

class _StudyTileState extends State<_StudyTile> {
  ui.Image? _thumb;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  @override
  void didUpdateWidget(covariant _StudyTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.series.thumbId != widget.series.thumbId) {
      _thumb?.dispose();
      _thumb = null;
      _loadThumb();
    }
  }

  Future<void> _loadThumb() async {
    try {
      final bytes = await widget.db.getBytes(widget.series.thumbId);
      if (bytes == null || !mounted) return;
      final file = DicomParser.parse(bytes);
      final image = await DicomImage.decode(file);
      final frame = image.frameCount ~/ 2;
      final uiImg = await image.toUiImage(frame, image.defaultWindow);
      if (!mounted) {
        uiImg.dispose();
        return;
      }
      setState(() => _thumb = uiImg);
    } catch (_) {}
  }

  @override
  void dispose() {
    _thumb?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.series;
    final sliceText = '${s.count} ${s.count == 1 ? 'slice' : 'slices'}';
    return Material(
      color: AppColors.surface,
      elevation: 0,
      shadowColor: const Color(0x14201828),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14201828),
                blurRadius: 30,
                offset: Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 52,
                  height: 52,
                  color: AppColors.accentWeak,
                  child: _thumb == null
                      ? const Icon(Icons.image_outlined, color: AppColors.accent)
                      : RawImage(image: _thumb, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$sliceText · ${formatDate(s.addedAt)} · ${formatBytes(s.size)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline),
                color: AppColors.text3,
                tooltip: 'Delete',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
