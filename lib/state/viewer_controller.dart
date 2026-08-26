import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../data/library_db.dart';
import '../dicom/dicom.dart';

enum NavKind { slice, frame }

enum ViewerTool { wl, pan }

class SliceCacheEntry {
  SliceCacheEntry({this.file, this.image, this.error});
  DicomFile? file;
  DicomImage? image;
  String? error;
}

class ViewerController extends ChangeNotifier {
  ViewerController(this.db);

  final LibraryDb db;

  NavKind navKind = NavKind.slice;
  List<SliceRef> slices = [];
  final Map<int, SliceCacheEntry> cache = {};
  int count = 1;
  int index = 0;
  DicomFile? baseFile;
  DicomImage? baseImage;
  DicomFile? file;
  DicomImage? image;
  WindowLevel window = const WindowLevel(center: 128, width: 256);
  ValueRange valueRange = const ValueRange(min: 0, max: 255);
  double scale = 1;
  ui.Offset offset = ui.Offset.zero;
  ViewerTool tool = ViewerTool.wl;
  int token = 0;

  bool loading = false;
  String? stageError;
  ui.Image? displayImage;
  String title = '';

  bool metaOpen = false;
  String metaQuery = '';
  List<MetaRow> metaRows = [];

  Future<void> openSeries(SeriesInfo series) async {
    token++;
    final myToken = token;
    slices = List.from(series.slices);
    cache.clear();
    scale = 1;
    offset = ui.Offset.zero;
    baseFile = baseImage = file = image = null;
    displayImage?.dispose();
    displayImage = null;
    title = series.name;
    loading = true;
    stageError = null;
    metaOpen = false;
    notifyListeners();

    try {
      final startIndex = series.count ~/ 2;
      final first = await decodeSlice(startIndex);
      if (myToken != token) return;

      if (first.image == null) {
        file = first.file;
        stageError =
            '${first.error ?? 'No displayable image.'}\n\nMetadata is still available.';
        loading = false;
        navKind = NavKind.slice;
        count = series.count;
        index = startIndex;
        notifyListeners();
        return;
      }

      if (series.count == 1 && first.image!.frameCount > 1) {
        navKind = NavKind.frame;
        baseFile = first.file;
        baseImage = first.image;
        count = first.image!.frameCount;
        index = count ~/ 2;
      } else {
        navKind = NavKind.slice;
        count = series.count;
        index = startIndex;
      }

      window = first.image!.defaultWindow;
      valueRange = first.image!.valueRange;
      await showCurrent();
      if (myToken != token) return;
      loading = false;
      notifyListeners();
    } catch (e) {
      if (myToken != token) return;
      loading = false;
      stageError = e.toString();
      notifyListeners();
    }
  }

  void close() {
    token++;
    cache.clear();
    displayImage?.dispose();
    displayImage = null;
    file = image = baseFile = baseImage = null;
    metaOpen = false;
    notifyListeners();
  }

  Future<SliceCacheEntry> decodeSlice(int i) async {
    if (cache.containsKey(i)) return cache[i]!;
    final slice = slices[i];
    final entry = SliceCacheEntry();
    try {
      final bytes = await db.getBytes(slice.id);
      if (bytes == null) throw Exception('Slice not found in library.');
      entry.file = DicomParser.parse(bytes);
      try {
        entry.image = await DicomImage.decode(entry.file!);
      } catch (imgErr) {
        entry.error = imgErr.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '');
      }
    } catch (err) {
      entry.error = err.toString();
    }
    cache[i] = entry;
    return entry;
  }

  Future<void> showCurrent() async {
    final myToken = token;
    DicomFile? f;
    DicomImage? img;
    late int frame;

    if (navKind == NavKind.frame) {
      f = baseFile;
      img = baseImage;
      frame = index;
    } else {
      final entry = await decodeSlice(index);
      if (myToken != token) return;
      f = entry.file;
      img = entry.image;
      frame = 0;
      if (img == null) {
        file = f;
        stageError = entry.error ?? 'No displayable image for this slice.';
        displayImage?.dispose();
        displayImage = null;
        notifyListeners();
        return;
      }
    }

    stageError = null;
    file = f;
    image = img;

    final clamped = frame.clamp(0, img!.frameCount - 1);
    final uiImg = await img.toUiImage(clamped, window);
    if (myToken != token) {
      uiImg.dispose();
      return;
    }
    displayImage?.dispose();
    displayImage = uiImg;
    notifyListeners();

    if (navKind == NavKind.slice) {
      for (final i in [index + 1, index - 1]) {
        if (i >= 0 && i < count && !cache.containsKey(i)) {
          decodeSlice(i);
        }
      }
    }
  }

  Future<void> rerenderCurrent() async {
    if (image == null) return;
    final myToken = token;
    final frame = navKind == NavKind.frame ? index : 0;
    final uiImg = await image!.toUiImage(
      frame.clamp(0, image!.frameCount - 1),
      window,
    );
    if (myToken != token) {
      uiImg.dispose();
      return;
    }
    displayImage?.dispose();
    displayImage = uiImg;
    notifyListeners();
  }

  Future<void> goToIndex(int i) async {
    index = i.clamp(0, count - 1);
    notifyListeners();
    await showCurrent();
  }

  void resetView() {
    scale = 1;
    offset = ui.Offset.zero;
    if (image != null) window = image!.defaultWindow;
    notifyListeners();
    rerenderCurrent();
  }

  void adjustWindow(double deltaCenter, double deltaWidth) {
    if (image == null || !image!.supportsWindowing) return;
    final span = math.max(1.0, valueRange.max - valueRange.min);
    final center = window.center + deltaCenter * span / 400;
    final width = math.max(1.0, window.width + deltaWidth * span / 400);
    window = WindowLevel(center: center, width: width);
    notifyListeners();
    rerenderCurrent();
  }

  void setScale(double s) {
    scale = s.clamp(0.4, 14.0);
    notifyListeners();
  }

  void setOffset(ui.Offset o) {
    offset = o;
    notifyListeners();
  }

  void setTool(ViewerTool t) {
    tool = t;
    notifyListeners();
  }

  void openMetadata() {
    if (file == null) return;
    metaRows = _collectMeta(file!);
    metaQuery = '';
    metaOpen = true;
    notifyListeners();
  }

  void closeMetadata() {
    metaOpen = false;
    notifyListeners();
  }

  void setMetaQuery(String q) {
    metaQuery = q;
    notifyListeners();
  }

  List<MetaRow> get filteredMetaRows {
    final q = metaQuery.toLowerCase();
    if (q.isEmpty) return metaRows;
    return metaRows
        .where((r) =>
            r.name.toLowerCase().contains(q) ||
            r.tag.toLowerCase().contains(q) ||
            r.value.toLowerCase().contains(q))
        .toList();
  }

  static List<MetaRow> _collectMeta(DicomFile f) {
    final rows = <MetaRow>[];
    void collect(DicomDataset ds, int depth) {
      for (final element in ds.orderedElements) {
        final name = DicomDictionary.name(element.tag) ?? 'Unknown';
        rows.add(MetaRow(
          tag: element.tag.description,
          name: name,
          vr: element.vr,
          value: element.displayString,
          depth: depth,
        ));
        if (element.vr == 'SQ') {
          for (var i = 0; i < element.items.length; i++) {
            rows.add(MetaRow(
              tag: '(FFFE,E000)',
              name: 'Item ${i + 1}',
              vr: '—',
              value: '',
              depth: depth + 1,
            ));
            collect(element.items[i], depth + 2);
          }
        }
      }
    }

    collect(f.meta, 0);
    collect(f.dataset, 0);
    return rows;
  }

  @override
  void dispose() {
    displayImage?.dispose();
    super.dispose();
  }
}

class MetaRow {
  MetaRow({
    required this.tag,
    required this.name,
    required this.vr,
    required this.value,
    required this.depth,
  });
  final String tag;
  final String name;
  final String vr;
  final String value;
  final int depth;
}
