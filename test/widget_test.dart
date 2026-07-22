import 'package:flutter_test/flutter_test.dart';

import 'package:dicom_flutter/main.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const DicomApp());
    // First frame only — library refresh hits path_provider asynchronously.
    expect(find.byType(DicomApp), findsOneWidget);
  });
}
