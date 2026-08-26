/// Identifies a DICOM data element by (group, element).
class DicomTag {
  const DicomTag(this.group, this.element);

  final int group;
  final int element;

  /// Combined 32-bit key: group in the high word, element in the low word.
  int get key => group * 0x10000 + element;

  bool get isDelimiter => group == 0xFFFE;
  bool get isPrivate => group % 2 == 1;

  String get description {
    final g = group.toRadixString(16).toUpperCase().padLeft(4, '0');
    final e = element.toRadixString(16).toUpperCase().padLeft(4, '0');
    return '($g,$e)';
  }

  static int makeKey(int group, int element) => group * 0x10000 + element;
}

/// Well-known tags used by the viewer (as numeric keys for fast comparison).
abstract final class Tag {
  static final int fileMetaGroupLength = DicomTag.makeKey(0x0002, 0x0000);
  static final int transferSyntaxUID = DicomTag.makeKey(0x0002, 0x0010);

  static final int patientName = DicomTag.makeKey(0x0010, 0x0010);
  static final int patientID = DicomTag.makeKey(0x0010, 0x0020);
  static final int studyDescription = DicomTag.makeKey(0x0008, 0x1030);
  static final int seriesDescription = DicomTag.makeKey(0x0008, 0x103E);
  static final int modality = DicomTag.makeKey(0x0008, 0x0060);

  static final int samplesPerPixel = DicomTag.makeKey(0x0028, 0x0002);
  static final int photometricInterp = DicomTag.makeKey(0x0028, 0x0004);
  static final int numberOfFrames = DicomTag.makeKey(0x0028, 0x0008);
  static final int rows = DicomTag.makeKey(0x0028, 0x0010);
  static final int columns = DicomTag.makeKey(0x0028, 0x0011);
  static final int planarConfiguration = DicomTag.makeKey(0x0028, 0x0006);
  static final int bitsAllocated = DicomTag.makeKey(0x0028, 0x0100);
  static final int bitsStored = DicomTag.makeKey(0x0028, 0x0101);
  static final int highBit = DicomTag.makeKey(0x0028, 0x0102);
  static final int pixelRepresentation = DicomTag.makeKey(0x0028, 0x0103);
  static final int windowCenter = DicomTag.makeKey(0x0028, 0x1050);
  static final int windowWidth = DicomTag.makeKey(0x0028, 0x1051);
  static final int rescaleIntercept = DicomTag.makeKey(0x0028, 0x1052);
  static final int rescaleSlope = DicomTag.makeKey(0x0028, 0x1053);

  static final int pixelData = DicomTag.makeKey(0x7FE0, 0x0010);

  static final int item = DicomTag.makeKey(0xFFFE, 0xE000);
  static final int itemDelimiter = DicomTag.makeKey(0xFFFE, 0xE00D);
  static final int sequenceDelimiter = DicomTag.makeKey(0xFFFE, 0xE0DD);
}
