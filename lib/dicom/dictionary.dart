import 'dicom_tag.dart';

/// Compact subset of the DICOM data dictionary.
abstract final class DicomDictionary {
  static final Map<int, ({String name, String vr})> _entries = () {
    final m = <int, ({String name, String vr})>{};
    void add(int g, int e, String name, String vr) {
      m[DicomTag.makeKey(g, e)] = (name: name, vr: vr);
    }

    add(0x0002, 0x0000, 'File Meta Information Group Length', 'UL');
    add(0x0002, 0x0001, 'File Meta Information Version', 'OB');
    add(0x0002, 0x0002, 'Media Storage SOP Class UID', 'UI');
    add(0x0002, 0x0003, 'Media Storage SOP Instance UID', 'UI');
    add(0x0002, 0x0010, 'Transfer Syntax UID', 'UI');
    add(0x0002, 0x0012, 'Implementation Class UID', 'UI');
    add(0x0002, 0x0013, 'Implementation Version Name', 'SH');

    add(0x0008, 0x0016, 'SOP Class UID', 'UI');
    add(0x0008, 0x0018, 'SOP Instance UID', 'UI');
    add(0x0008, 0x0020, 'Study Date', 'DA');
    add(0x0008, 0x0030, 'Study Time', 'TM');
    add(0x0008, 0x0050, 'Accession Number', 'SH');
    add(0x0008, 0x0060, 'Modality', 'CS');
    add(0x0008, 0x0070, 'Manufacturer', 'LO');
    add(0x0008, 0x0080, 'Institution Name', 'LO');
    add(0x0008, 0x0090, "Referring Physician's Name", 'PN');
    add(0x0008, 0x1030, 'Study Description', 'LO');
    add(0x0008, 0x103E, 'Series Description', 'LO');
    add(0x0008, 0x1090, "Manufacturer's Model Name", 'LO');

    add(0x0010, 0x0010, "Patient's Name", 'PN');
    add(0x0010, 0x0020, 'Patient ID', 'LO');
    add(0x0010, 0x0030, "Patient's Birth Date", 'DA');
    add(0x0010, 0x0040, "Patient's Sex", 'CS');
    add(0x0010, 0x1010, "Patient's Age", 'AS');

    add(0x0018, 0x0050, 'Slice Thickness', 'DS');
    add(0x0018, 0x0060, 'KVP', 'DS');
    add(0x0018, 0x1030, 'Protocol Name', 'LO');
    add(0x0018, 0x0088, 'Spacing Between Slices', 'DS');

    add(0x0020, 0x000D, 'Study Instance UID', 'UI');
    add(0x0020, 0x000E, 'Series Instance UID', 'UI');
    add(0x0020, 0x0011, 'Series Number', 'IS');
    add(0x0020, 0x0013, 'Instance Number', 'IS');
    add(0x0020, 0x0032, 'Image Position (Patient)', 'DS');
    add(0x0020, 0x0037, 'Image Orientation (Patient)', 'DS');
    add(0x0020, 0x1041, 'Slice Location', 'DS');

    add(0x0028, 0x0002, 'Samples per Pixel', 'US');
    add(0x0028, 0x0004, 'Photometric Interpretation', 'CS');
    add(0x0028, 0x0006, 'Planar Configuration', 'US');
    add(0x0028, 0x0008, 'Number of Frames', 'IS');
    add(0x0028, 0x0010, 'Rows', 'US');
    add(0x0028, 0x0011, 'Columns', 'US');
    add(0x0028, 0x0030, 'Pixel Spacing', 'DS');
    add(0x0028, 0x0100, 'Bits Allocated', 'US');
    add(0x0028, 0x0101, 'Bits Stored', 'US');
    add(0x0028, 0x0102, 'High Bit', 'US');
    add(0x0028, 0x0103, 'Pixel Representation', 'US');
    add(0x0028, 0x1050, 'Window Center', 'DS');
    add(0x0028, 0x1051, 'Window Width', 'DS');
    add(0x0028, 0x1052, 'Rescale Intercept', 'DS');
    add(0x0028, 0x1053, 'Rescale Slope', 'DS');
    add(0x0028, 0x1054, 'Rescale Type', 'LO');
    add(0x0028, 0x2110, 'Lossy Image Compression', 'CS');

    add(0x7FE0, 0x0010, 'Pixel Data', 'OW');

    add(0xFFFE, 0xE000, 'Item', 'UN');
    add(0xFFFE, 0xE00D, 'Item Delimitation Item', 'UN');
    add(0xFFFE, 0xE0DD, 'Sequence Delimitation Item', 'UN');

    return m;
  }();

  static const _syntaxNames = {
    '1.2.840.10008.1.2': 'Implicit VR Little Endian',
    '1.2.840.10008.1.2.1': 'Explicit VR Little Endian',
    '1.2.840.10008.1.2.2': 'Explicit VR Big Endian',
    '1.2.840.10008.1.2.4.50': 'JPEG Baseline (Process 1)',
    '1.2.840.10008.1.2.4.51': 'JPEG Extended (Process 2 & 4)',
    '1.2.840.10008.1.2.4.57': 'JPEG Lossless (Process 14)',
    '1.2.840.10008.1.2.4.70': 'JPEG Lossless (SV1)',
    '1.2.840.10008.1.2.4.90': 'JPEG 2000 (Lossless Only)',
    '1.2.840.10008.1.2.4.91': 'JPEG 2000',
    '1.2.840.10008.1.2.5': 'RLE Lossless',
  };

  static const _nativeJpeg = {
    '1.2.840.10008.1.2.4.50',
    '1.2.840.10008.1.2.4.51',
  };

  static String? name(DicomTag tag) {
    final entry = _entries[tag.key];
    if (entry != null) return entry.name;
    if (tag.element == 0x0000) return 'Group Length';
    if (tag.isPrivate) return 'Private Tag';
    return null;
  }

  static String? vr(DicomTag tag) {
    final entry = _entries[tag.key];
    if (entry != null) return entry.vr;
    if (tag.element == 0x0000) return 'UL';
    return null;
  }

  static String transferSyntaxName(String uid) => _syntaxNames[uid] ?? uid;

  static bool isNativelyDecodableJpeg(String uid) => _nativeJpeg.contains(uid);
}
