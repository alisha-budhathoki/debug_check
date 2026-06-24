part of 'debug_grid_overlay.dart';

class DebugInspectorScope extends StatefulWidget {
  final Widget child;
  const DebugInspectorScope({super.key, required this.child});

  @override
  State<DebugInspectorScope> createState() => _DebugInspectorScopeState();
}

class _DebugInspectorScopeState extends State<DebugInspectorScope> {
  final GlobalKey _childKey = GlobalKey();
  _Inspection? _current;
  _Inspection? _previous; // measure anchor (the previously tapped widget)
  _WidgetReport? _report; // long-press detail sheet, when open

  /// Pick = intercept taps to inspect. Move = let taps through so you can
  /// scroll/navigate the app while the inspector stays armed.
  bool _pickMode = true;

  // Collected, de-duplicated geometry for the "Show all bounds" overlay.
  _BoundsData _bounds = const _BoundsData.empty();
  bool _boundsTicking = false;

  DebugGridController get _controller => DebugGridController.instance;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    final s = _controller.value;

    // Start/stop the per-frame bounds walker.
    final boundsOn = kDebugMode && s.paintBounds;
    if (boundsOn && !_boundsTicking) {
      _boundsTicking = true;
      _scheduleBoundsTick();
    } else if (!boundsOn && _boundsTicking) {
      _boundsTicking = false;
    }

    setState(() {
      // Leaving inspect mode clears the selection, measure anchor and sheet.
      if (!s.inspectEnabled) {
        _current = null;
        _previous = null;
        _report = null;
      }
      if (!boundsOn) _bounds = const _BoundsData.empty();
    });
  }

  /// Re-walks after each real frame (piggybacks on app frames, so it stays in
  /// sync while scrolling but costs nothing when the UI is idle).
  void _scheduleBoundsTick() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_boundsTicking) return;
      _collectBounds();
      _scheduleBoundsTick();
    });
  }

  void _collectBounds() {
    final root = _childKey.currentContext?.findRenderObject();
    if (root is! RenderBox) return;

    final boxes = <Rect>[];
    final seen = <int>{};
    final pads = <_PadBand>[];

    void visit(RenderObject node) {
      if (node is RenderBox && node.attached && node.hasSize) {
        try {
          final size = node.size;
          if (size.width >= 1 && size.height >= 1) {
            final tl = node.localToGlobal(Offset.zero);
            final rect = tl & size;
            // Round to whole pixels so chains of coincident wrappers collapse
            // to a single line instead of stacking up.
            final key = _rectKey(rect);
            if (seen.add(key)) boxes.add(rect);
            if (node is RenderPadding) {
              final p = node.padding.resolve(TextDirection.ltr);
              if (p != EdgeInsets.zero) {
                final inner = Rect.fromLTRB(
                  rect.left + p.left,
                  rect.top + p.top,
                  rect.right - p.right,
                  rect.bottom - p.bottom,
                );
                if (inner.width > 0 && inner.height > 0) {
                  pads.add(_PadBand(rect, inner));
                }
              }
            }
          }
        } catch (_) {
          // localToGlobal can throw for detached/offscreen layers — skip.
        }
      }
      // Walk via the semantics traversal rather than visitChildren: it follows
      // paint order and skips everything that isn't actually on screen — most
      // importantly the Navigator overlay's covered routes (which stay laid out
      // but offstage), so bounds no longer pile up from every pushed page. It
      // also prunes Offstage/zero-opacity/Visibility.gone subtrees, unselected
      // IndexedStack children and off-list viewport items. Partial overlays
      // (modal sheets, dialogs) keep their base route onstage, so both layers
      // still render correctly.
      node.visitChildrenForSemantics(visit);
    }

    visit(root);

    final next = _BoundsData(boxes: boxes, pads: pads);
    if (next.signature != _bounds.signature) {
      setState(() => _bounds = next);
    }
  }

  static int _rectKey(Rect r) => Object.hash(
    r.left.round(),
    r.top.round(),
    r.width.round(),
    r.height.round(),
  );

  _RenderHit? _hitTestAt(Offset globalPosition) {
    final ro = _childKey.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return null;

    final result = BoxHitTestResult();
    ro.hitTest(result, position: ro.globalToLocal(globalPosition));

    RenderBox? target;
    EdgeInsets? padding;
    for (final entry in result.path) {
      final t = entry.target;
      if (t is RenderPadding && padding == null) {
        padding = t.padding.resolve(TextDirection.ltr);
      }
      if (target == null &&
          t is RenderBox &&
          t.hasSize &&
          t.size.width > 0 &&
          t.size.height > 0) {
        target = t;
      }
    }
    if (target == null) return null;
    return _RenderHit(
      target: target,
      padding: padding,
      path: result.path.toList(growable: false),
    );
  }

  _Inspection _inspectionOf(_RenderHit hit, String name) => _Inspection(
    rect: hit.target.localToGlobal(Offset.zero) & hit.target.size,
    padding: hit.padding,
    name: name,
  );

  /// Tap selects a widget; the previous selection is kept as the measure anchor.
  void _selectAt(Offset globalPosition) {
    final hit = _hitTestAt(globalPosition);
    if (hit == null) return;
    final ins = _inspectionOf(hit, _inspectWidgetName(hit.target));
    setState(() {
      _previous = _current;
      _current = ins;
      _report = null; // a fresh tap dismisses an open detail sheet
    });
  }

  /// Long-press opens the full detail "assistant" sheet for that widget.
  void _reportAt(Offset globalPosition) {
    final hit = _hitTestAt(globalPosition);
    if (hit == null) return;
    final report = _buildReport(hit, MediaQuery.sizeOf(context));
    HapticFeedback.selectionClick();
    setState(() {
      _current = _inspectionOf(hit, report.type);
      _report = report;
    });
  }

  void _setMode(bool pick) {
    if (pick == _pickMode) return;
    setState(() {
      _pickMode = pick;
      // Leaving Inspect hides the (now scroll-stale) selection so the screen is
      // clean to navigate; Inspect starts fresh on whatever view you land on.
      if (!pick) {
        _current = null;
        _previous = null;
        _report = null;
      }
    });
    HapticFeedback.selectionClick();
  }

  void _clearSelection() {
    setState(() {
      _current = null;
      _previous = null;
      _report = null;
    });
  }

  /// One short, state-aware line of guidance shown in the control bar.
  String _inspectHint() {
    if (!_pickMode) return 'Browse mode — scroll & navigate freely';
    if (_current == null) {
      return 'Tap a widget to inspect  ·  long-press for full details';
    }
    if (_previous == null) {
      return 'Tap another widget to measure the gap';
    }
    return 'Tap to reselect  ·  long-press for full details';
  }

  @override
  Widget build(BuildContext context) {
    final s = _controller.value;
    final inspecting = kDebugMode && s.inspectEnabled;
    final showBounds = kDebugMode && s.paintBounds;

    return Stack(
      children: [
        KeyedSubtree(key: _childKey, child: widget.child),
        if (showBounds && _bounds.isNotEmpty) ...[
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _BoundsPainter(_bounds)),
            ),
          ),
          _BoundsLegend(data: _bounds),
        ],
        if (inspecting) ...[
          // Pick mode only: absorb gestures so taps inspect instead of reaching
          // the app. In Move mode this layer is absent, so the app is fully
          // usable (scroll, navigate) while the inspector stays armed.
          if (_pickMode)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _selectAt(d.globalPosition),
                onLongPressStart: (d) => _reportAt(d.globalPosition),
              ),
            ),
          if (_pickMode && _current != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _InspectPainter(
                    current: _current!,
                    // Hide the measure line while the detail sheet is open.
                    previous: _report == null ? _previous : null,
                  ),
                ),
              ),
            ),
          // Selection detail only shows once you've actually tapped something,
          // so enabling inspect no longer drops a floating hint chip on screen.
          if (_pickMode && _current != null)
            _report != null
                ? _ReportSheet(
                  report: _report!,
                  onClose: () => setState(() => _report = null),
                )
                : _InspectHud(current: _current!, previous: _previous),
          // One clean control bar: Inspect⇄Browse, contextual hint, clear, exit.
          _InspectToolbar(
            pickMode: _pickMode,
            hint: _inspectHint(),
            hasSelection: _current != null,
            onSetMode: _setMode,
            onClear: _clearSelection,
            onClose: () => _controller.setInspectEnabled(false),
          ),
        ],
      ],
    );
  }
}

/// One render-tree hit: the chosen box, its nearest padding, and the full path.
