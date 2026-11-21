// SPDX-License-Identifier: MIT
/// Test VisProject: chặn path traversal, ghi nguyên tử, đọc tệp hỏng dễ chịu.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visdroid/core/project.dart';

void main() {
  late Directory dir;
  late VisProject project;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('visdroid_project_test_');
    project = VisProject.at(dir);
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  test('pathFor chặn ký tự đi đường — không cho ghi ra ngoài thư mục dự án', () {
    for (final bad in ['../x.vis', 'a/b.vis', 'a\\b.vis', '..', '']) {
      expect(() => project.pathFor(bad), throwsArgumentError, reason: bad);
    }
    expect(project.pathFor('hop-le.vis'), endsWith('hop-le.vis'));
  });

  test('validName chặn traversal/tên ẩn; normalizeName thêm đuôi .vis', () {
    expect(VisProject.validName('../x.vis'), isFalse);
    expect(VisProject.validName('.a.vis'), isFalse);
    expect(VisProject.validName('ok.vis'), isTrue);
    expect(VisProject.normalizeName('moi'), 'moi.vis');
    expect(VisProject.normalizeName('moi.vish'), 'moi.vish');
  });

  test('write ghi đúng nội dung và không để lại .tmp', () {
    project.create('a.vis', content: 'print("x")');
    project.write('a.vis', 'print("y")');
    expect(project.read('a.vis'), 'print("y")');
    expect(dir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
  });

  test('read tệp UTF-8 gãy → ký tự thay thế, không ném FormatException', () {
    final f = File(project.pathFor('hong.vis'));
    f.writeAsBytesSync([0x78, 0xFF, 0xFE, 0x79]); // byte lạ ngoài UTF-8 hợp lệ
    final text = project.read('hong.vis');
    expect(text.length, 4);
    expect(text.contains('\u{FFFD}'), isTrue);
  });
}
