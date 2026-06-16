part of 'debug_grid_overlay.dart';

class DebugGridPanel extends StatelessWidget {
  const DebugGridPanel({super.key});

  static const _bg = Color(0xFF0E1116);
  static const _accent = Color(0xFF61AFEF);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DebugGridSettings>(
      valueListenable: DebugGridController.instance,
      builder: (context, s, _) {
        final c = DebugGridController.instance;
        return ListView(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
          children: [
            const _PanelHint(
              'Inspect spacing, alignment and padding on any screen. Toggles '
              'apply live across the whole app.',
            ),
            const SizedBox(height: 10),
            _PanelCard(
              title: 'Inspect widget  ·  recommended',
              children: [
                _ToggleRow(
                  label: 'Tap to inspect',
                  hint:
                      'Tap = select · long-press = full details · '
                      'tap two widgets = measure the gap',
                  value: s.inspectEnabled,
                  onChanged: c.setInspectEnabled,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _PanelCard(
              title: 'Spacing grid',
              children: [
                _ToggleRow(
                  label: 'Baseline grid',
                  value: s.gridEnabled,
                  onChanged: c.setGridEnabled,
                ),
                if (s.gridEnabled)
                  _SliderRow(
                    label: 'Spacing',
                    value: s.spacing,
                    min: 4,
                    max: 32,
                    divisions: 28,
                    suffix: 'px',
                    onChanged: c.setSpacing,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _PanelCard(
              title: 'Column guides',
              children: [
                _ToggleRow(
                  label: 'Show columns',
                  value: s.columnsEnabled,
                  onChanged: c.setColumnsEnabled,
                ),
                if (s.columnsEnabled)
                  _StepperRow(
                    label: 'Columns',
                    value: s.columnCount,
                    min: 1,
                    max: 12,
                    onChanged: c.setColumnCount,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _PanelCard(
              title: 'Layout & padding bounds',
              children: [
                _ToggleRow(
                  label: 'Show all bounds',
                  hint:
                      'Padding filled green, box edges faint & de-duplicated '
                      'so lines never pile up',
                  value: s.paintBounds,
                  onChanged: c.setPaintBounds,
                ),
                _ToggleRow(
                  label: 'Safe area outline',
                  value: s.safeAreaEnabled,
                  onChanged: c.setSafeAreaEnabled,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _PanelCard(
              title: 'Advanced',
              children: [
                _ToggleRow(
                  label: 'Text baselines',
                  hint: "Flutter's debugPaintBaselines (whole screen)",
                  value: s.paintBaselines,
                  onChanged: c.setPaintBaselines,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: c.reset,
                style: TextButton.styleFrom(
                  foregroundColor: _accent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text(
                  'Reset all',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PanelHint extends StatelessWidget {
  final String text;
  const _PanelHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white60,
        fontSize: 11,
        height: 1.4,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _PanelCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DebugGridPanel._bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    hint!,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: DebugGridPanel._accent,
            inactiveThumbColor: Colors.white54,
            inactiveTrackColor: Colors.white12,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: DebugGridPanel._accent,
              inactiveTrackColor: Colors.white12,
              thumbColor: DebugGridPanel._accent,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${value.toStringAsFixed(0)}$suffix',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _StepperRow extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _StepperRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
          _StepButton(
            icon: Icons.remove,
            onTap: value > min ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add,
            onTap: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: enabled ? 0.08 : 0.03),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? Colors.white70 : Colors.white24,
        ),
      ),
    );
  }
}

// ─── Tap-to-inspect ──────────────────────────────────────────────────────────

/// Wraps the whole app so "Tap to inspect" can hit-test the real widget tree.
/// When inspect mode is on it absorbs taps, finds the tapped render box, and
/// highlights just that one widget (box + padding) with a readable card —
/// unlike the global `debugPaintSize` which paints every box at once.
///
/// Hit-testing targets the wrapped child's render object directly, so the
/// debug overlay itself is never matched.

