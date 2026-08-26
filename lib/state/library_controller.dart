import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/library_db.dart';
import '../dicom/dicom.dart';

class ImportPair {
  ImportPair({required this.name, required this.relPath, required this.bytes});
  final String name;
  final String relPath;
  final Uint8List bytes;
}

class LibraryController extends ChangeNotifier {
  LibraryController(this.db);

  final LibraryDb db;
  static const _uuid = Uuid();

  List<SeriesInfo> series = [];
  bool loading = true;
  String? toast;

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    series = await db.listSeries();
    loading = false;
    notifyListeners();
  }

  void showToast(String message) {
    toast = message;
    notifyListeners();
  }

  void clearToast() {
    toast = null;
    notifyListeners();
  }

  Future<void> deleteSeries(String seriesId) async {
    await db.deleteSeries(seriesId);
    await refresh();
  }

  /// Groups by top-level folder; returns the first imported series id, if any.
  Future<String?> importPairs(List<ImportPair> pairs) async {
    if (pairs.isEmpty) return null;

    final groups = <String, List<ImportPair>>{};
    for (final p in pairs) {
      final segments = p.relPath.split('/').where((s) => s.isNotEmpty).toList();
      final folder = segments.length > 1 ? segments.first : 'Imported';
      groups.putIfAbsent(folder, () => []).add(p);
    }

    String? firstSeries;
    var kept = 0;
    var skipped = 0;

    for (final entry in groups.entries) {
      final folder = entry.key;
      final list = entry.value
        ..sort((a, b) => LibraryDb.naturalCompare(a.relPath, b.relPath));
      final seriesId =
          '${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4().substring(0, 8)}';
      var order = 0;
      var added = 0;
      for (final p in list) {
        if (!isDicom(p.bytes, p.name)) {
          skipped++;
          continue;
        }
        await db.addSlice(p.name, p.bytes, seriesId, folder, order++);
        added++;
        kept++;
      }
      if (added > 0 && firstSeries == null) firstSeries = seriesId;
    }

    await refresh();

    if (kept == 0) {
      showToast('No DICOM files found in that folder.');
      return null;
    }
    if (skipped > 0) {
      showToast(
        'Imported $kept slice${kept == 1 ? '' : 's'} '
        '(skipped $skipped non-DICOM file${skipped == 1 ? '' : 's'}).',
      );
    }
    return firstSeries;
  }
}

bool hasDicmMagic(Uint8List buffer) {
  if (buffer.lengthInBytes < 132) return false;
  return buffer[128] == 0x44 &&
      buffer[129] == 0x49 &&
      buffer[130] == 0x43 &&
      buffer[131] == 0x4D;
}

bool isDicom(Uint8List buffer, String name) {
  if (RegExp(r'^DICOMDIR$', caseSensitive: false).hasMatch(name)) return false;
  if (name.toLowerCase().endsWith('.dcm')) return true;
  if (hasDicmMagic(buffer)) return true;
  if (buffer.lengthInBytes < 8) return false;

  try {
    final file = DicomParser.parse(buffer);
    if (file.meta.string(Tag.transferSyntaxUID) != null) return true;
    final ds = file.dataset;
    if (ds.get(Tag.pixelData) != null) return true;
    if (ds.intValue(Tag.rows) != null && ds.intValue(Tag.columns) != null) {
      return true;
    }
    final probes = [
      Tag.modality,
      Tag.patientName,
      DicomTag.makeKey(0x0008, 0x0016),
      DicomTag.makeKey(0x0008, 0x0018),
      DicomTag.makeKey(0x0020, 0x000D),
    ];
    if (probes.any((k) => ds.get(k) != null)) return true;
  } catch (_) {}
  return false;
}
