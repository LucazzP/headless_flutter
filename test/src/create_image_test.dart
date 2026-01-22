// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foo/headless_render.dart';

void main() {
  test('createImageFromWidget', () async {
    final headlessRender = HeadlessRender();
    final image = await headlessRender.createImageFromWidget(
      Center(
        child: Container(
          color: Colors.orange,
          child: Text('Hello, World!', style: TextStyle(fontSize: 20, color: Colors.black)),
        ),
      ),
      width: 512,
    );
    final imagePath = Directory.current.uri.resolve('test.png').toFilePath(windows: Platform.isWindows);
    await File(imagePath).writeAsBytes(image);
  });
}
