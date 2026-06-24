import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:debug_deck/debug_deck.dart';

part 'grid_panel.dart';
part 'inspector_scope.dart';
part 'inspector_bounds.dart';
part 'inspector_pick.dart';
part 'inspector_report.dart';
part 'inspector_toolbar.dart';

/// Visual layout inspector for the debug overlay — a designer-style spacing grid
/// plus Flutter's own layout/padding paint, toggled live across every screen.
///
/// All state lives in [DebugGridController] (a singleton [ValueNotifier]) so the
/// full-screen [DebugGridLayer] and the [DebugGridPanel] controls stay in sync.
@immutable
class DebugGridSettings {
  /// Designer baseline grid (evenly spaced lines).
  final bool gridEnabled;

  /// Spacing between grid lines, in logical pixels.
  final double spacing;

  /// Translucent column guides (like a design column grid).
  final bool columnsEnabled;
  final int columnCount;

  /// Outline the MediaQuery safe area.
  final bool safeAreaEnabled;

  /// Flutter's `debugPaintSizeEnabled` — draws every box, padding and alignment.
  final bool paintBounds;

  /// Flutter's `debugPaintBaselinesEnabled` — text baselines.
  final bool paintBaselines;

  /// Tap-to-inspect a single widget's size & padding (readable, one at a time).
  final bool inspectEnabled;

  const DebugGridSettings({
    this.gridEnabled = false,
    this.spacing = 8,
    this.columnsEnabled = false,
    this.columnCount = 4,
    this.safeAreaEnabled = false,
    this.paintBounds = false,
    this.paintBaselines = false,
    this.inspectEnabled = false,
  });

  /// True when something needs to be drawn by [DebugGridLayer].
  bool get hasOverlay => gridEnabled || columnsEnabled || safeAreaEnabled;

  DebugGridSettings copyWith({
    bool? gridEnabled,
    double? spacing,
    bool? columnsEnabled,
    int? columnCount,
    bool? safeAreaEnabled,
    bool? paintBounds,
    bool? paintBaselines,
    bool? inspectEnabled,
  }) {
    return DebugGridSettings(
      gridEnabled: gridEnabled ?? this.gridEnabled,
      spacing: spacing ?? this.spacing,
      columnsEnabled: columnsEnabled ?? this.columnsEnabled,
      columnCount: columnCount ?? this.columnCount,
      safeAreaEnabled: safeAreaEnabled ?? this.safeAreaEnabled,
      paintBounds: paintBounds ?? this.paintBounds,
      paintBaselines: paintBaselines ?? this.paintBaselines,
      inspectEnabled: inspectEnabled ?? this.inspectEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DebugGridSettings &&
      other.gridEnabled == gridEnabled &&
      other.spacing == spacing &&
      other.columnsEnabled == columnsEnabled &&
      other.columnCount == columnCount &&
      other.safeAreaEnabled == safeAreaEnabled &&
      other.paintBounds == paintBounds &&
      other.paintBaselines == paintBaselines &&
      other.inspectEnabled == inspectEnabled;

  @override
  int get hashCode => Object.hash(
    gridEnabled,
    spacing,
    columnsEnabled,
    columnCount,
    safeAreaEnabled,
    paintBounds,
    paintBaselines,
    inspectEnabled,
  );
}

class DebugGridController extends ValueNotifier<DebugGridSettings> {
  DebugGridController._() : super(const DebugGridSettings());

  static final DebugGridController instance = DebugGridController._();

  void setGridEnabled(bool v) => value = value.copyWith(gridEnabled: v);
  void setSpacing(double v) =>
      value = value.copyWith(spacing: v.clamp(2, 64).toDouble());
  void setColumnsEnabled(bool v) => value = value.copyWith(columnsEnabled: v);
  void setColumnCount(int v) =>
      value = value.copyWith(columnCount: v.clamp(1, 12));
  void setSafeAreaEnabled(bool v) => value = value.copyWith(safeAreaEnabled: v);
  void setInspectEnabled(bool v) => value = value.copyWith(inspectEnabled: v);

  /// Drives the custom, de-cluttered bounds overlay (NOT Flutter's global
  /// `debugPaintSize`, which outlines every box and is unreadable).
  void setPaintBounds(bool v) => value = value.copyWith(paintBounds: v);

  void setPaintBaselines(bool v) {
    value = value.copyWith(paintBaselines: v);
    _applyBaselines();
  }

  /// Turn everything off (used by the panel's "reset" action).
  void reset() {
    value = const DebugGridSettings();
    _applyBaselines();
  }

  /// Baselines still use Flutter's render flag (it's light and rarely on).
  /// Debug builds only — the flag is a no-op outside debug mode.
  void _applyBaselines() {
    if (!kDebugMode) return;
    debugPaintBaselinesEnabled = value.paintBaselines;
    WidgetsBinding.instance.reassembleApplication();
  }
}

/// Full-screen, non-interactive layer that paints the designer grid. Mounted
/// inside the debug overlay's stack so it floats above every route. Touches
/// pass straight through via [IgnorePointer].
class DebugGridLayer extends StatelessWidget {
  const DebugGridLayer({super.key});

  @override
  Widget build(BuildContext context) {
    // Pure-paint designer grid — gate on the native `dev` environment so it
    // tracks the debug overlay's own visibility (works in any build mode).
    if (!DebugTools.enabled) return const SizedBox.shrink();

    // NOTE: callers must wrap this in a Positioned (e.g. Positioned.fill) when
    // placing it in a Stack — it intentionally returns a plain (non-positioned)
    // widget so it can be used anywhere.
    return ValueListenableBuilder<DebugGridSettings>(
      valueListenable: DebugGridController.instance,
      builder: (context, settings, _) {
        if (!settings.hasOverlay) return const SizedBox.shrink();
        return IgnorePointer(
          child: CustomPaint(
            painter: _GridPainter(
              settings: settings,
              safeArea: MediaQuery.paddingOf(context),
            ),
          ),
        );
      },
    );
  }
}

class _GridPainter extends CustomPainter {
  final DebugGridSettings settings;
  final EdgeInsets safeArea;

  _GridPainter({required this.settings, required this.safeArea});

  static const _minorColor = Color(0x14F50057); // faint magenta
  static const _majorColor = Color(0x40F50057);
  static const _columnColor = Color(0x142196F3); // faint blue band
  static const _safeColor = Color(0x803F51B5); // indigo outline

  @override
  void paint(Canvas canvas, Size size) {
    if (settings.columnsEnabled) _paintColumns(canvas, size);
    if (settings.gridEnabled) _paintGrid(canvas, size);
    if (settings.safeAreaEnabled) _paintSafeArea(canvas, size);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final minor =
        Paint()
          ..color = _minorColor
          ..strokeWidth = 0.5;
    final major =
        Paint()
          ..color = _majorColor
          ..strokeWidth = 1;
    final sp = settings.spacing;
    if (sp < 2) return;

    var i = 0;
    for (double x = 0; x <= size.width; x += sp, i++) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        i % 10 == 0 ? major : minor,
      );
    }
    i = 0;
    for (double y = 0; y <= size.height; y += sp, i++) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        i % 10 == 0 ? major : minor,
      );
    }
  }

  void _paintColumns(Canvas canvas, Size size) {
    const margin = 16.0;
    const gutter = 16.0;
    final cols = settings.columnCount;
    final usable = size.width - margin * 2 - gutter * (cols - 1);
    if (usable <= 0) return;
    final colW = usable / cols;
    final band = Paint()..color = _columnColor;
    var x = margin;
    for (var c = 0; c < cols; c++) {
      canvas.drawRect(Rect.fromLTWH(x, 0, colW, size.height), band);
      x += colW + gutter;
    }
  }

  void _paintSafeArea(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..color = _safeColor
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke;
    canvas.drawRect(
      Rect.fromLTRB(
        safeArea.left,
        safeArea.top,
        size.width - safeArea.right,
        size.height - safeArea.bottom,
      ),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.settings != settings || old.safeArea != safeArea;
}

// ─── Control panel ───────────────────────────────────────────────────────────

/// The "Grid" tab body in the debug viewer. Dark-themed to match the viewer.
