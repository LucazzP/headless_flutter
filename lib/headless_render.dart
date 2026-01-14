import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const String _opensansFontDirectory = 'assets/fonts/opensans/';
const String opensansFontFamily = 'OpenSans';

Future<void> loadFonts() async {
  final FontLoader opensansLoader = FontLoader(opensansFontFamily);
  final currentDir = Directory.current.uri;
  final directory = Directory(currentDir.resolve(_opensansFontDirectory).path);
  for (final file in directory.listSync(recursive: true)) {
    if (file.path.endsWith('.ttf')) {
      opensansLoader.addFont(rootBundle.load(file.path));
    }
  }
  await Future.wait(<Future<void>>[opensansLoader.load()]);
}

Future<Uint8List> createImageFromWidget(Widget widget, Size size, {Duration? wait, double pixelRatio = 1.0}) async {
  await loadFonts();

  final RenderRepaintBoundary repaintBoundary = RenderRepaintBoundary();
  final HeadlessFlutterView view = HeadlessFlutterView(pixelRatio, size);

  // Set up a headless RenderView
  final RenderView renderView = RenderView(
    view: view,
    child: RenderPositionedBox(alignment: Alignment.center, child: repaintBoundary),
    configuration: ViewConfiguration(
      physicalConstraints: BoxConstraints.tight(size),
      logicalConstraints: BoxConstraints.tight(size),
      devicePixelRatio: pixelRatio,
    ),
  );
  final PipelineOwner pipelineOwner = PipelineOwner();
  final FocusManager focusManager = FocusManager();
  final BuildOwner buildOwner = BuildOwner(focusManager: focusManager);
  pipelineOwner.rootNode = renderView;
  renderView.prepareInitialFrame();

  // Attach the widget to the render tree
  final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
    container: repaintBoundary,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData.fromView(view),
        child: Theme(
          data: ThemeData(
            fontFamily: opensansFontFamily,
            textTheme: ThemeData.light().textTheme.apply(fontFamily: opensansFontFamily),
          ),
          child: Builder(
            builder: (BuildContext context) {
              final ThemeData theme = Theme.of(context);
              return DefaultTextStyle(
                style: theme.textTheme.bodyMedium ?? const TextStyle(),
                child: IconTheme(
                  data: theme.iconTheme,
                  child: SizedBox.fromSize(size: size, child: widget),
                ),
              );
            },
          ),
        ),
      ),
    ),
  ).attachToRenderTree(buildOwner);
  buildOwner.buildScope(rootElement);

  if (wait != null) {
    // Optionally wait for a delay if the widget needs time (e.g., for images to load)
    await Future.delayed(wait);
  }

  // Finalize build and flush the rendering pipeline
  buildOwner.buildScope(rootElement);
  buildOwner.finalizeTree();
  pipelineOwner.flushLayout();
  pipelineOwner.flushCompositingBits();
  pipelineOwner.flushPaint();

  // Obtain the image from the RepaintBoundary
  final ui.Image image = await repaintBoundary.toImage(pixelRatio: pixelRatio);
  final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData?.buffer.asUint8List() ?? Uint8List(0);
}

class HeadlessFlutterView implements ui.FlutterView {
  final double _devicePixelRatio;
  final ui.Size _physicalSize;
  final ui.Display _display;

  HeadlessFlutterView(double devicePixelRatio, ui.Size physicalSize)
    : _devicePixelRatio = devicePixelRatio,
      _physicalSize = physicalSize,
      _display = HeadlessDisplay(devicePixelRatio, physicalSize);

  @override
  double get devicePixelRatio => _devicePixelRatio;

  @override
  ui.Display get display => _display;

  @override
  List<ui.DisplayFeature> get displayFeatures => const [];

  @override
  ui.GestureSettings get gestureSettings => const ui.GestureSettings();

  @override
  ui.ViewPadding get padding => ui.ViewPadding.zero;

  @override
  ui.ViewConstraints get physicalConstraints => const ui.ViewConstraints();

  @override
  ui.Size get physicalSize => _physicalSize;

  @override
  ui.PlatformDispatcher get platformDispatcher => ui.PlatformDispatcher.instance;

  @override
  void render(ui.Scene scene, {ui.Size? size}) {
    // TODO: implement render
  }

  @override
  ui.ViewPadding get systemGestureInsets => ui.ViewPadding.zero;

  @override
  void updateSemantics(ui.SemanticsUpdate update) {
    // TODO: implement updateSemantics
  }

  @override
  int get viewId => 0;

  @override
  ui.ViewPadding get viewInsets => ui.ViewPadding.zero;

  @override
  ui.ViewPadding get viewPadding => ui.ViewPadding.zero;
}

class HeadlessDisplay implements ui.Display {
  final double _devicePixelRatio;
  final ui.Size _size;

  const HeadlessDisplay(double devicePixelRatio, ui.Size size) : _devicePixelRatio = devicePixelRatio, _size = size;

  @override
  double get devicePixelRatio => _devicePixelRatio;

  @override
  int get id => 0;

  @override
  double get refreshRate => 1.0;

  @override
  ui.Size get size => _size;
}
