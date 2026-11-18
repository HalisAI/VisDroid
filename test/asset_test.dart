// SPDX-License-Identifier: MIT
/// Test nạp asset logo — chạy: flutter test test/asset_test.dart
library;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('asset logo tồn tại và nạp được', () async {
    final data = await rootBundle.load('assets/visdroid-icon.png');
    expect(data.lengthInBytes, greaterThan(1000));
    expect(data.lengthInBytes, lessThan(500000));
  });
}
