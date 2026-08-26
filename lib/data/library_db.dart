import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class SliceRef {
  SliceRef({required this.id, required this.name, required this.order});
  final String id;
  final String name;
  final int order;
}

class SeriesInfo {
  SeriesInfo({
    required this.seriesId,
    required this.name,
    required this.slices,
    required this.count,
    required this.size,
    required this.addedAt,
    required this.thumbId,
  });

  final String seriesId;
  final String name;
  final List<SliceRef> slices;
  final int count;
  final int size;
  final int addedAt;
  final String thumbId;
}

class _SliceRecord {
  _SliceRecord({
    required this.id,
    required this.name,
    required this.size,
    required this.addedAt,
    required this.seriesId,
    required this.seriesName,
    required this.order,
    required this.fileName,
  });

  final String id;
  final String name;
  final int size;
  final int addedAt;
  final String seriesId;
  final String seriesName;
  final int order;
  final String fileName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'size': size,
        'addedAt': addedAt,
        'seriesId': seriesId,
        'seriesName': seriesName,
        'order': order,
        'fileName': fileName,
      };

  factory _SliceRecord.fromJson(Map<String, dynamic> j) => _SliceRecord(
        id: j['id'] as String,
        name: j['name'] as String,
        size: j['size'] as int,
        addedAt: j['addedAt'] as int,
        seriesId: j['seriesId'] as String,
        seriesName: j['seriesName'] as String,
        order: j['order'] as int,
        fileName: j['fileName'] as String,
      );
}

/// Persistent library: JSON index + raw DICOM bytes on disk.
class LibraryDb {
  LibraryDb();

  static const _uuid = Uuid();
  Directory? _root;
  File? _indexFile;
  final List<_SliceRecord> _records = [];

  Future<void> open() async {
    if (_root != null) return;
    final docs = await getApplicationDocumentsDirectory();
    _root = Directory(p.join(docs.path, 'dicom-viewer'));
    await _root!.create(recursive: true);
    await Directory(p.join(_root!.path, 'files')).create(recursive: true);
    _indexFile = File(p.join(_root!.path, 'index.json'));
    await _loadIndex();
  }

  Future<void> _loadIndex() async {
    _records.clear();
    if (_indexFile == null || !await _indexFile!.exists()) return;
    try {
      final raw = await _indexFile!.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      for (final item in list) {
        _records.add(_SliceRecord.fromJson(item as Map<String, dynamic>));
      }
    } catch (_) {
      _records.clear();
    }
  }

  Future<void> _saveIndex() async {
    final data = jsonEncode(_records.map((r) => r.toJson()).toList());
    await _indexFile!.writeAsString(data);
  }

  Future<List<SeriesInfo>> listSeries() async {
    await open();
    final groups = <String, _Group>{};
    for (final r in _records) {
      final key = r.seriesId;
      final g = groups.putIfAbsent(
        key,
        () => _Group(seriesId: key, name: r.seriesName),
      );
      g.slices.add(SliceRef(id: r.id, name: r.name, order: r.order));
      g.size += r.size;
      g.addedAt = mathMax(g.addedAt, r.addedAt);
    }

    final series = <SeriesInfo>[];
    for (final g in groups.values) {
      g.slices.sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        if (byOrder != 0) return byOrder;
        return naturalCompare(a.name, b.name);
      });
      series.add(SeriesInfo(
        seriesId: g.seriesId,
        name: g.name,
        slices: List.unmodifiable(g.slices),
        count: g.slices.length,
        size: g.size,
        addedAt: g.addedAt,
        thumbId: g.slices[g.slices.length ~/ 2].id,
      ));
    }
    series.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return series;
  }

  Future<String> addSlice(
    String name,
    Uint8List buffer,
    String seriesId,
    String seriesName,
    int order,
  ) async {
    await open();
    final id = '${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4().substring(0, 8)}';
    final fileName = '$id.bin';
    final file = File(p.join(_root!.path, 'files', fileName));
    await file.writeAsBytes(buffer, flush: true);
    _records.add(_SliceRecord(
      id: id,
      name: name,
      size: buffer.lengthInBytes,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      seriesId: seriesId,
      seriesName: seriesName,
      order: order,
      fileName: fileName,
    ));
    await _saveIndex();
    return id;
  }

  Future<Uint8List?> getBytes(String id) async {
    await open();
    _SliceRecord? rec;
    for (final r in _records) {
      if (r.id == id) {
        rec = r;
        break;
      }
    }
    if (rec == null) return null;
    final file = File(p.join(_root!.path, 'files', rec.fileName));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> deleteSeries(String seriesId) async {
    await open();
    final toRemove = _records.where((r) => r.seriesId == seriesId).toList();
    for (final r in toRemove) {
      final file = File(p.join(_root!.path, 'files', r.fileName));
      if (await file.exists()) await file.delete();
      _records.remove(r);
    }
    await _saveIndex();
  }

  static int naturalCompare(String a, String b) {
    return _naturalCompare(a.toLowerCase(), b.toLowerCase());
  }

  static int _naturalCompare(String a, String b) {
    final ra = RegExp(r'(\d+|\D+)');
    final aa = ra.allMatches(a).map((m) => m.group(0)!).toList();
    final bb = ra.allMatches(b).map((m) => m.group(0)!).toList();
    final n = mathMin(aa.length, bb.length);
    for (var i = 0; i < n; i++) {
      final x = aa[i];
      final y = bb[i];
      final xi = int.tryParse(x);
      final yi = int.tryParse(y);
      if (xi != null && yi != null) {
        final c = xi.compareTo(yi);
        if (c != 0) return c;
      } else {
        final c = x.compareTo(y);
        if (c != 0) return c;
      }
    }
    return aa.length.compareTo(bb.length);
  }
}

class _Group {
  _Group({required this.seriesId, required this.name});
  final String seriesId;
  String name;
  final List<SliceRef> slices = [];
  int size = 0;
  int addedAt = 0;
}

int mathMax(int a, int b) => a > b ? a : b;
int mathMin(int a, int b) => a < b ? a : b;
