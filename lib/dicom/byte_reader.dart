import 'dart:typed_data';

import 'dicom_tag.dart';

/// Endian-aware cursor over a byte buffer, used by the DICOM parser.
class ByteReader {
  ByteReader(this.bytes, {this.littleEndian = true})
      : _view = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData _view;
  int offset = 0;
  bool littleEndian;

  int get length => bytes.length;
  bool get isAtEnd => offset >= bytes.length;
  int get remaining => (bytes.length - offset).clamp(0, bytes.length);

  void seek(int o) => offset = o;
  void skip(int n) => offset += n;
  bool canRead(int n) => n >= 0 && offset + n <= bytes.length;

  int? readUint8() {
    if (!canRead(1)) return null;
    final v = _view.getUint8(offset);
    offset += 1;
    return v;
  }

  int? readUint16() {
    if (!canRead(2)) return null;
    final v = _view.getUint16(offset, littleEndian ? Endian.little : Endian.big);
    offset += 2;
    return v;
  }

  int? readUint32() {
    if (!canRead(4)) return null;
    final v = _view.getUint32(offset, littleEndian ? Endian.little : Endian.big);
    offset += 4;
    return v;
  }

  /// Returns a view into [bytes] (shares the underlying buffer).
  Uint8List? readBytes(int n) {
    if (!canRead(n)) return null;
    final slice = Uint8List.sublistView(bytes, offset, offset + n);
    offset += n;
    return slice;
  }

  DicomTag? readTag() {
    final group = readUint16();
    final element = readUint16();
    if (group == null || element == null) return null;
    return DicomTag(group, element);
  }

  String? readString(int n) {
    final b = readBytes(n);
    if (b == null) return null;
    return decodeString(b);
  }

  /// ISO-8859-1 decode with trailing null/space and leading null trimmed.
  static String decodeString(Uint8List bytes) {
    final buf = StringBuffer();
    for (final b in bytes) {
      buf.writeCharCode(b);
    }
    var s = buf.toString();
    s = s.replaceFirst(RegExp(r'[\x00 ]+$'), '');
    s = s.replaceFirst(RegExp(r'^[\x00]+'), '');
    return s;
  }
}
