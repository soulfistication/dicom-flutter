import 'element.dart';

/// Ordered collection of DICOM elements with convenience lookups.
class DicomDataset {
  final Map<int, DicomElement> elements = {};
  final List<int> order = [];

  void insert(DicomElement element) {
    final key = element.tag.key;
    if (!elements.containsKey(key)) order.add(key);
    elements[key] = element;
  }

  DicomElement? get(int tagKey) => elements[tagKey];

  List<DicomElement> get orderedElements =>
      order.map((k) => elements[k]).whereType<DicomElement>().toList();

  String? string(int tagKey) => get(tagKey)?.stringValue;
  int? intValue(int tagKey) => get(tagKey)?.intValue;
  List<int> ints(int tagKey) => get(tagKey)?.intValues ?? const [];
  double? doubleValue(int tagKey) => get(tagKey)?.doubleValue;
  List<double> doubles(int tagKey) => get(tagKey)?.doubleValues ?? const [];
}
