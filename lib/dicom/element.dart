import 'dart:typed_data';

import 'byte_reader.dart';
import 'dataset.dart';
import 'dicom_tag.dart';
import 'vr.dart';

/// A single parsed DICOM data element with typed accessors.
class DicomElement {
  DicomElement(
    this.tag,
    this.vr,
    this.value, {
    required this.littleEndian,
    List<DicomDataset>? items,
    List<Uint8List>? fragments,
  })  : items = items ?? const [],
        fragments = fragments ?? const [];

  final DicomTag tag;
  final String vr;
  final Uint8List value;
  final bool littleEndian;
  final List<DicomDataset> items;
  final List<Uint8List> fragments;

  bool get isEncapsulated => fragments.isNotEmpty;

  ByteData _view() => ByteData.sublistView(value);

  List<String> get stringValues {
    final text = ByteReader.decodeString(value);
    if (text.isEmpty) return const [];
    return text.split('\\').map((s) => s.trim()).toList();
  }

  String? get stringValue => VR.isString(vr) ? ByteReader.decodeString(value) : null;

  List<int> get intValues {
    final dv = _view();
    final le = littleEndian ? Endian.little : Endian.big;
    final out = <int>[];
    final n = value.lengthInBytes;
    switch (vr) {
      case 'US':
        for (var i = 0; i + 2 <= n; i += 2) {
          out.add(dv.getUint16(i, le));
        }
        return out;
      case 'SS':
        for (var i = 0; i + 2 <= n; i += 2) {
          out.add(dv.getInt16(i, le));
        }
        return out;
      case 'UL':
        for (var i = 0; i + 4 <= n; i += 4) {
          out.add(dv.getUint32(i, le));
        }
        return out;
      case 'SL':
        for (var i = 0; i + 4 <= n; i += 4) {
          out.add(dv.getInt32(i, le));
        }
        return out;
      default:
        return stringValues
            .map(int.tryParse)
            .whereType<int>()
            .toList();
    }
  }

  int? get intValue => intValues.isEmpty ? null : intValues.first;

  List<double> get doubleValues {
    final dv = _view();
    final le = littleEndian ? Endian.little : Endian.big;
    final out = <double>[];
    final n = value.lengthInBytes;
    switch (vr) {
      case 'FL':
        for (var i = 0; i + 4 <= n; i += 4) {
          out.add(dv.getFloat32(i, le));
        }
        return out;
      case 'FD':
        for (var i = 0; i + 8 <= n; i += 8) {
          out.add(dv.getFloat64(i, le));
        }
        return out;
      default:
        return stringValues
            .map(double.tryParse)
            .whereType<double>()
            .toList();
    }
  }

  double? get doubleValue => doubleValues.isEmpty ? null : doubleValues.first;

  String get displayString {
    if (tag.key == Tag.pixelData) {
      return '<${value.lengthInBytes} bytes of pixel data>';
    }
    if (vr == 'SQ') {
      final n = items.length;
      return '<sequence · $n item${n == 1 ? '' : 's'}>';
    }
    if (VR.isString(vr)) {
      final s = ByteReader.decodeString(value);
      return s.isEmpty ? '—' : s;
    }
    switch (vr) {
      case 'US':
      case 'SS':
      case 'UL':
      case 'SL':
        return intValues.join(', ');
      case 'FL':
      case 'FD':
        return doubleValues.map((v) => _fmt(v)).join(', ');
      case 'AT':
        return '<attribute tag>';
      default:
        return '<${value.lengthInBytes} bytes>';
    }
  }

  static String _fmt(double v) {
    // Match JS toPrecision(6) loosely.
    if (v == v.roundToDouble() && v.abs() < 1e15) {
      return v.toInt().toString();
    }
    return v.toStringAsPrecision(6);
  }
}
