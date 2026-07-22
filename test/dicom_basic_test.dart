import 'package:flutter_test/flutter_test.dart';

import 'package:dicom_flutter/dicom/dicom.dart';
import 'dart:typed_data';

void main() {
  test('ByteReader reads little-endian uint16/32', () {
    final bytes = Uint8List.fromList([0x34, 0x12, 0x78, 0x56, 0x34, 0x12]);
    final r = ByteReader(bytes, littleEndian: true);
    expect(r.readUint16(), 0x1234);
    expect(r.readUint32(), 0x12345678);
  });

  test('DicomTag key and description', () {
    const tag = DicomTag(0x0010, 0x0010);
    expect(tag.key, 0x00100010);
    expect(tag.description, '(0010,0010)');
    expect(tag.isPrivate, false);
  });

  test('VR helpers', () {
    expect(VR.isValid('US'), true);
    expect(VR.usesExtendedLength('OB'), true);
    expect(VR.isString('PN'), true);
  });
}
