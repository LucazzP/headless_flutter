import 'package:flutter/material.dart';

import 'headless_flutter_view.dart';

class HeadlessMaterialApp extends StatelessWidget {
  final Widget child;
  final HeadlessFlutterView view;
  final String fontFamily;
  final Size size;
  final ThemeData? theme;

  const HeadlessMaterialApp({
    super.key,
    required this.child,
    required this.view,
    required this.fontFamily,
    required this.size,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    ThemeData resolvedTheme = theme ?? ThemeData();
    resolvedTheme = resolvedTheme.copyWith(textTheme: resolvedTheme.textTheme.apply(fontFamily: fontFamily));

    return MediaQuery(
      data: MediaQueryData.fromView(view),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: resolvedTheme,
        initialRoute: '/',
        onGenerateRoute: (settings) => PageRouteBuilder(
          pageBuilder: (_, __, ___) => Material(color: Colors.transparent, child: child),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, __, ___, child) => child,
        ),
      ),
    );
  }
}
