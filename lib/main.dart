import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:foo/headless_render.dart';
import 'package:flutter_test/flutter_test.dart';

void main() async {
  await runZonedGuarded(() async {
    print('Creating image...');
    final size = const Size(1000, 1000);
    WidgetsFlutterBinding.ensureInitialized();
    final image = await createImageFromWidget(
      Center(
        child: Container(
          color: Colors.red,
          child: Text('Hello, World! From docker!', style: TextStyle(fontSize: 20, color: Colors.white)),
        ),
      ),
      size,
    );
    final imagePath = Directory.current.uri.resolve('test.png').path;
    await File(imagePath).writeAsBytes(image);
    print('Image created at $imagePath');

    while (true) {
      await Future.delayed(const Duration(seconds: 1));
      print('keeping alive...');
    }
  }, (error, stackTrace) {
    print('Error: $error');
    print('Stack trace: $stackTrace');
  });
}
