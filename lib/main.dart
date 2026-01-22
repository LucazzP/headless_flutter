import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:foo/headless_render.dart';

Future<void> main() async {
  print('Creating image...');
  final headlessRender = HeadlessRender();
  final image = await headlessRender.createImageFromWidget(
    Container(
      color: Colors.red,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Hello, World!', style: TextStyle(fontSize: 20, color: Colors.white)),
          Icon(Icons.refresh, color: Colors.white),
          Icon(CupertinoIcons.zzz),
        ],
      ),
    ),
    width: 512,
  );
  final imagePath = Directory.current.uri.resolve('test.png').toFilePath(windows: Platform.isWindows);
  await File(imagePath).writeAsBytes(image);
  print('Image created at $imagePath');
}
