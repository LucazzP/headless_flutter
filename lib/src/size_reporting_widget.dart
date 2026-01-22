import 'dart:async';

import 'package:flutter/material.dart';

class SizeReportingWidget extends StatefulWidget {
  final Widget child;
  final ValueChanged<Size> onSizeChange;

  const SizeReportingWidget({super.key, required this.child, required this.onSizeChange});

  @override
  State<SizeReportingWidget> createState() => _SizeReportingWidgetState();
}

class _SizeReportingWidgetState extends State<SizeReportingWidget> {
  Size? _oldSize;

  @override
  void didUpdateWidget(covariant SizeReportingWidget oldWidget) {
    if (oldWidget.child != widget.child) {
      _oldSize = null;
      if (mounted) {
        setState(() {});
      }
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    scheduleMicrotask(_notifySize);
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        scheduleMicrotask(_notifySize);
        return false;
      },
      child: SizeChangedLayoutNotifier(child: widget.child),
    );
  }

  void _notifySize() {
    if (!mounted) return;
    final Size? size = context.size;
    if (_oldSize != size) {
      _oldSize = size;
      if (size != null) {
        widget.onSizeChange(size);
      }
    }
  }
}
