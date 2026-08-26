import 'dart:typed_data';

import 'byte_reader.dart';
import 'dataset.dart';
import 'dictionary.dart';
import 'dicom_tag.dart';
import 'element.dart';
import 'vr.dart';

class DicomParseError implements Exception {
  DicomParseError(this.message);
  final String message;
  @override
  String toString() => 'DicomParseError: $message';
}

const int _undefinedLength = 0xFFFFFFFF;

abstract final class TransferSyntax {
  static const implicitVRLittleEndian = '1.2.840.10008.1.2';
  static const explicitVRLittleEndian = '1.2.840.10008.1.2.1';
  static const explicitVRBigEndian = '1.2.840.10008.1.2.2';
}

/// Result of [DicomParser.parse].
class DicomFile {
  DicomFile({
    required this.meta,
    required this.dataset,
    required this.transferSyntax,
    required this.isLittleEndian,
    required this.isExplicitVR,
  });

  final DicomDataset meta;
  final DicomDataset dataset;
  final String transferSyntax;
  final bool isLittleEndian;
  final bool isExplicitVR;

  DicomElement? get(int tagKey) => dataset.get(tagKey) ?? meta.get(tagKey);
}

/// From-scratch DICOM Part 10 parser (Explicit/Implicit VR, LE/BE, sequences,
/// encapsulated pixel data).
abstract final class DicomParser {
  static DicomFile parse(Uint8List bytes) {
    if (bytes.length < 8) {
      throw DicomParseError('The file is too small to be a DICOM object.');
    }

    final reader = ByteReader(bytes, littleEndian: true);
    var meta = DicomDataset();

    final hasPreamble =
        bytes.length >= 132 && _magic(bytes, 128) == 'DICM';
    if (hasPreamble) {
      reader.seek(132);
      meta = _parseFileMeta(reader);
    }

    final tsElement = meta.get(Tag.transferSyntaxUID);
    final transferSyntax = tsElement != null
        ? ByteReader.decodeString(tsElement.value)
        : _detectSyntax(bytes, reader.offset);

    final explicit = transferSyntax != TransferSyntax.implicitVRLittleEndian;
    final little = transferSyntax != TransferSyntax.explicitVRBigEndian;

    reader.littleEndian = little;
    final dataset = _parseDataset(reader, explicit, bytes.length);

    return DicomFile(
      meta: meta,
      dataset: dataset,
      transferSyntax: transferSyntax,
      isLittleEndian: little,
      isExplicitVR: explicit,
    );
  }

  static DicomDataset _parseFileMeta(ByteReader reader) {
    reader.littleEndian = true;
    final meta = DicomDataset();

    final groupLengthStart = reader.offset;
    final first = _readElement(reader, true, reader.length);
    if (first == null) throw DicomParseError('missing file meta group');
    meta.insert(first);

    var metaEnd = reader.length;
    if (first.tag.key == Tag.fileMetaGroupLength && first.intValue != null) {
      metaEnd = (reader.offset + first.intValue!).clamp(0, reader.length);
    } else {
      reader.seek(groupLengthStart);
    }

    while (reader.offset < metaEnd) {
      final element = _readElement(reader, true, metaEnd);
      if (element == null || element.tag.group != 0x0002) break;
      meta.insert(element);
    }
    return meta;
  }

  static DicomDataset _parseDataset(
    ByteReader reader,
    bool explicitVR,
    int endOffset,
  ) {
    final dataset = DicomDataset();
    while (reader.offset < endOffset) {
      final start = reader.offset;
      final element = _readElement(reader, explicitVR, endOffset);
      if (element == null) break;
      if (element.tag.key == Tag.itemDelimiter ||
          element.tag.key == Tag.sequenceDelimiter) {
        break;
      }
      dataset.insert(element);
      if (reader.offset <= start) break;
    }
    return dataset;
  }

  static DicomElement? _readElement(
    ByteReader reader,
    bool explicitVR,
    int endOffset,
  ) {
    final tag = reader.readTag();
    if (tag == null) return null;
    final little = reader.littleEndian;

    if (tag.isDelimiter) {
      final length = reader.readUint32();
      if (length == null) return null;
      if (length != _undefinedLength && length > 0) reader.skip(length);
      return DicomElement(tag, 'UN', Uint8List(0), littleEndian: little);
    }

    late String vr;
    late int length;

    if (explicitVR) {
      final code = reader.readString(2);
      if (code == null) return null;
      vr = VR.isValid(code) ? code : (DicomDictionary.vr(tag) ?? 'UN');
      if (VR.usesExtendedLength(vr)) {
        reader.skip(2);
        final l = reader.readUint32();
        if (l == null) return null;
        length = l == _undefinedLength ? -1 : l;
      } else {
        final l = reader.readUint16();
        if (l == null) return null;
        length = l;
      }
    } else {
      vr = DicomDictionary.vr(tag) ??
          (tag.key == Tag.pixelData ? 'OW' : 'UN');
      final l = reader.readUint32();
      if (l == null) return null;
      length = l == _undefinedLength ? -1 : l;
    }

    if (length < 0) {
      if (tag.key == Tag.pixelData) {
        final fragments = _readEncapsulatedFragments(reader);
        return DicomElement(
          tag,
          'OB',
          Uint8List(0),
          littleEndian: little,
          fragments: fragments,
        );
      }
      final items = _readSequenceItems(reader, explicitVR, endOffset);
      return DicomElement(
        tag,
        'SQ',
        Uint8List(0),
        littleEndian: little,
        items: items,
      );
    }

    if (vr == 'SQ') {
      final seqEnd = (reader.offset + length).clamp(0, endOffset);
      final items = _readSequenceItems(reader, explicitVR, seqEnd);
      return DicomElement(
        tag,
        'SQ',
        Uint8List(0),
        littleEndian: little,
        items: items,
      );
    }

    if (length < 0 || !reader.canRead(length)) return null;
    final value = reader.readBytes(length) ?? Uint8List(0);
    return DicomElement(tag, vr, value, littleEndian: little);
  }

  static List<DicomDataset> _readSequenceItems(
    ByteReader reader,
    bool explicitVR,
    int endOffset,
  ) {
    final items = <DicomDataset>[];
    while (reader.offset < endOffset) {
      final tag = reader.readTag();
      final rawLength = reader.readUint32();
      if (tag == null || rawLength == null) break;
      if (tag.key == Tag.sequenceDelimiter) break;
      if (tag.key != Tag.item) break;

      if (rawLength == _undefinedLength) {
        items.add(_parseDataset(reader, explicitVR, endOffset));
      } else {
        final itemEnd = (reader.offset + rawLength).clamp(0, reader.length);
        items.add(_parseDataset(reader, explicitVR, itemEnd));
        reader.seek(itemEnd);
      }
    }
    return items;
  }

  static List<Uint8List> _readEncapsulatedFragments(ByteReader reader) {
    final fragments = <Uint8List>[];
    var isFirst = true;
    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      final length = reader.readUint32();
      if (tag == null || length == null) break;
      if (tag.key == Tag.sequenceDelimiter) break;
      if (tag.key != Tag.item) break;
      final bytes = reader.readBytes(length) ?? Uint8List(0);
      if (isFirst) {
        isFirst = false;
        continue; // Basic Offset Table
      }
      fragments.add(bytes);
    }
    return fragments;
  }

  static String? _magic(Uint8List bytes, int offset) {
    if (bytes.length < offset + 4) return null;
    return ByteReader.decodeString(
      Uint8List.sublistView(bytes, offset, offset + 4),
    );
  }

  static String _detectSyntax(Uint8List bytes, int offset) {
    if (bytes.length < offset + 6) {
      return TransferSyntax.implicitVRLittleEndian;
    }
    final code = ByteReader.decodeString(
      Uint8List.sublistView(bytes, offset + 4, offset + 6),
    );
    return VR.isValid(code)
        ? TransferSyntax.explicitVRLittleEndian
        : TransferSyntax.implicitVRLittleEndian;
  }
}
