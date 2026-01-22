import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'headless_flutter_view.dart';
import 'headless_material_app.dart';
import 'size_reporting_widget.dart';

const String _opensansFontDirectory = 'assets/fonts/opensans/';
const String opensansFontFamily = 'OpenSans';

class HeadlessRender {
  HeadlessRender({String? fontFamily, Uri? assetsDirectory})
    : defaultFontFamily = fontFamily ?? opensansFontFamily,
      assetsDirectory = assetsDirectory ?? Directory.current.uri;

  final String defaultFontFamily;
  final Uri assetsDirectory;

  late final WidgetsBinding _binding;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _binding = WidgetsFlutterBinding.ensureInitialized();

    final Uri fontDirectory = assetsDirectory.resolve(_opensansFontDirectory);
    await _loadFont(defaultFontFamily, fontDirectory);

    _initialized = true;
  }

  Future<Uint8List> createImageFromWidget(
    Widget widget, {
    double width = 1280,
    double height = 12000,
    Future<void>? wait,
    double pixelRatio = 1.0,
    bool shrinkWrap = true,
  }) async {
    await initialize();

    final Size size = Size(width, height);
    final RenderRepaintBoundary repaintBoundary = RenderRepaintBoundary();
    final HeadlessFlutterView view = HeadlessFlutterView(pixelRatio, size);
    RenderObjectToWidgetElement<RenderBox>? rootElement;

    final RenderView renderView = RenderView(
      view: view,
      child: RenderPositionedBox(alignment: Alignment.center, child: repaintBoundary),
      configuration: ViewConfiguration(
        physicalConstraints: BoxConstraints.loose(size),
        logicalConstraints: BoxConstraints.loose(size),
        devicePixelRatio: pixelRatio,
      ),
    );

    final PipelineOwner pipelineOwner = PipelineOwner();
    final FocusManager focusManager = FocusManager();
    final BuildOwner buildOwner = BuildOwner(focusManager: focusManager);
    pipelineOwner.rootNode = renderView;
    renderView.prepareInitialFrame();

    final ThemeData theme = ThemeData(
      fontFamily: defaultFontFamily,
      textTheme: ThemeData.light().textTheme.apply(fontFamily: defaultFontFamily),
    );

    rootElement = RenderObjectToWidgetAdapter<RenderBox>(
      container: repaintBoundary,
      child: HeadlessMaterialApp(
        view: view,
        fontFamily: defaultFontFamily,
        size: size,
        theme: theme,
        child: shrinkWrap
            ? Center(
                child: SizeReportingWidget(
                  child: widget,
                  onSizeChange: (newSize) async {
                    if (newSize == size) return;
                    _resizeView(renderView, view, newSize, pixelRatio);
                    await _pumpFrames(buildOwner, pipelineOwner, rootElement!, count: 3);
                  },
                ),
              )
            : widget,
      ),
    ).attachToRenderTree(buildOwner);

    // Initial frame.
    buildOwner.buildScope(rootElement);
    pipelineOwner.flushLayout();
    pipelineOwner.flushCompositingBits();
    pipelineOwner.flushPaint();

    if (wait != null) {
      // Allow async work (e.g. image loading) before final frame.
      await wait;
    }

    await _pumpFrames(buildOwner, pipelineOwner, rootElement, count: 3);

    final ui.Image image = await repaintBoundary.toImage(pixelRatio: pixelRatio);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List() ?? Uint8List(0);
  }

  void _resizeView(RenderView renderView, HeadlessFlutterView view, Size size, double pixelRatio) {
    view.updatePhysicalSize(size);
    renderView.configuration = ViewConfiguration(
      physicalConstraints: BoxConstraints.loose(size),
      logicalConstraints: BoxConstraints.loose(size),
      devicePixelRatio: pixelRatio,
    );
  }

  Future<void> _pumpFrames(BuildOwner build, PipelineOwner pipeline, Element rootElement, {int count = 1}) async {
    for (var i = 0; i < count; i++) {
      await _pumpFrame(build, pipeline, rootElement);
    }
  }

  Future<void> _pumpFrame(BuildOwner build, PipelineOwner pipeline, Element rootElement) async {
    build.buildScope(rootElement);
    build.finalizeTree();
    pipeline.flushLayout();
    pipeline.flushCompositingBits();
    pipeline.flushPaint();
    _binding.scheduleFrame();
    _binding.handleBeginFrame(Duration.zero);
    _binding.handleDrawFrame();
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }

  Future<void> _loadFont(String family, Uri path) async {
    final String resolvedPath = path.toFilePath(windows: Platform.isWindows);
    final FileSystemEntityType type = FileSystemEntity.typeSync(resolvedPath);
    if (type == FileSystemEntityType.notFound) {
      return;
    }

    final FontLoader loader = FontLoader(family);

    if (type == FileSystemEntityType.file) {
      loader.addFont(File(resolvedPath).readAsBytes().then((Uint8List bytes) => ByteData.view(bytes.buffer)));
    } else if (type == FileSystemEntityType.directory) {
      for (final FileSystemEntity entity in Directory(resolvedPath).listSync(recursive: true)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.ttf')) {
          loader.addFont(entity.readAsBytes().then((Uint8List bytes) => ByteData.view(bytes.buffer)));
        }
      }
    }

    await loader.load();
  }
}
