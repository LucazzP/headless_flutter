import 'dart:ui';

class HeadlessFlutterView implements FlutterView {
  final double _devicePixelRatio;
  Size _physicalSize;
  final HeadlessDisplay _display;

  HeadlessFlutterView(double devicePixelRatio, Size physicalSize)
    : _devicePixelRatio = devicePixelRatio,
      _physicalSize = physicalSize,
      _display = HeadlessDisplay(devicePixelRatio, physicalSize);

  void updatePhysicalSize(Size newSize) {
    _physicalSize = newSize;
    _display.updateSize(newSize);
  }

  @override
  double get devicePixelRatio => _devicePixelRatio;

  @override
  Display get display => _display;

  @override
  List<DisplayFeature> get displayFeatures => const [];

  @override
  GestureSettings get gestureSettings => const GestureSettings();

  @override
  ViewPadding get padding => ViewPadding.zero;

  @override
  ViewConstraints get physicalConstraints => const ViewConstraints();

  @override
  Size get physicalSize => _physicalSize;

  @override
  PlatformDispatcher get platformDispatcher => PlatformDispatcher.instance;

  @override
  void render(Scene scene, {Size? size}) {
    // Intentionally unused; headless view does not present scenes.
  }

  @override
  ViewPadding get systemGestureInsets => ViewPadding.zero;

  @override
  void updateSemantics(SemanticsUpdate update) {
    // Intentionally unused; semantics not needed for headless rendering.
  }

  @override
  int get viewId => 0;

  @override
  ViewPadding get viewInsets => ViewPadding.zero;

  @override
  ViewPadding get viewPadding => ViewPadding.zero;
}

class HeadlessDisplay implements Display {
  final double _devicePixelRatio;
  Size _size;

  HeadlessDisplay(double devicePixelRatio, Size size) : _devicePixelRatio = devicePixelRatio, _size = size;

  void updateSize(Size size) {
    _size = size;
  }

  @override
  double get devicePixelRatio => _devicePixelRatio;

  @override
  int get id => 0;

  @override
  double get refreshRate => 1.0;

  @override
  Size get size => _size;
}
