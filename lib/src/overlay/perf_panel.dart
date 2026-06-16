part of 'debug_overlay.dart';

class _PerfPanel extends StatefulWidget {
  const _PerfPanel();

  @override
  State<_PerfPanel> createState() => _PerfPanelState();
}

class _PerfPanelState extends State<_PerfPanel> {
  @override
  void initState() {
    super.initState();
    // Idempotent — ensures capture is on even if boot wiring was skipped.
    PerfMonitor.instance.start();
  }

  Future<void> _copy(PerfStats s) async {
    await Clipboard.setData(ClipboardData(text: s.toReadableText()));
    await HapticFeedback.lightImpact();
  }

  Color _fpsColor(double fps) {
    if (fps <= 0) return Colors.white38; // idle
    if (fps >= 55) return const Color(0xFF98C379);
    if (fps >= 30) return const Color(0xFFE5C07B);
    return const Color(0xFFE06C75);
  }

  Color _verdictColor(PerfStats s) {
    if (!s.hasData) return Colors.white38;
    if (s.stallCount > 0 || s.jankRatio > 0.20) return const Color(0xFFE06C75);
    if (s.jankRatio > 0.05) return const Color(0xFFE5C07B);
    return const Color(0xFF98C379);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PerfStats>(
      valueListenable: PerfMonitor.instance.stats,
      builder: (context, s, _) {
        final fpsColor = _fpsColor(s.fps);
        return ListView(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
          children: [
            // Which screen these numbers belong to — measure, navigate, and the
            // banner follows you so the readout is never ambiguous.
            const _CurrentScreenBanner(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.verdict,
                        style: TextStyle(
                          color: _verdictColor(s),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (s.hasData && s.bottleneck != '—')
                        Text(
                          'Bottleneck: ${s.bottleneck}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10.5,
                          ),
                        ),
                    ],
                  ),
                ),
                _SectionButton(
                  icon: Icons.restart_alt,
                  label: 'Reset',
                  onTap: () => PerfMonitor.instance.reset(),
                ),
                const SizedBox(width: 4),
                _SectionButton(
                  icon: Icons.copy_all,
                  label: 'Copy',
                  onTap: () => _copy(s),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Hero FPS gauge.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: const Color(0xFF0E1116),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: fpsColor.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  Text(
                    !s.hasData ? '—' : (s.isIdle ? 'idle' : s.fps.toStringAsFixed(0)),
                    style: TextStyle(
                      color: fpsColor,
                      fontSize: s.hasData && s.isIdle ? 30 : 56,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.hasData && s.isIdle
                        ? 'FPS · static screen — fling the list to measure'
                        : 'FPS · effective rate while rendering',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _PerfStatCard(
                  label: 'Dropped frames',
                  value: '${(s.jankRatio * 100).toStringAsFixed(0)}%',
                  sub: 'UI ${s.uiJankCount} · raster ${s.rasterJankCount}',
                  color:
                      s.jankRatio > 0.05
                          ? const Color(0xFFE5C07B)
                          : const Color(0xFF98C379),
                ),
                const SizedBox(width: 8),
                _PerfStatCard(
                  label: 'Worst frame',
                  value: '${s.worstTotalMs.toStringAsFixed(0)}ms',
                  sub:
                      s.stallCount > 0
                          ? '${s.stallCount} stall(s) >100ms'
                          : 'no stalls',
                  color:
                      s.worstTotalMs > 100
                          ? const Color(0xFFE06C75)
                          : s.worstTotalMs > 16.7
                          ? const Color(0xFFE5C07B)
                          : const Color(0xFF98C379),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _PerfStatCard(
                  label: 'Avg build (UI)',
                  value: '${s.avgBuildMs.toStringAsFixed(1)}ms',
                  sub: 'peak ${s.worstBuildMs.toStringAsFixed(0)}ms',
                  color: const Color(0xFF61AFEF),
                ),
                const SizedBox(width: 8),
                _PerfStatCard(
                  label: 'Avg raster (GPU)',
                  value: '${s.avgRasterMs.toStringAsFixed(1)}ms',
                  sub: 'peak ${s.worstRasterMs.toStringAsFixed(0)}ms',
                  color: const Color(0xFFC678DD),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _DetailSection(
              title: 'Frame time · last ${s.recentTotalsMs.length} frames',
              child: SizedBox(
                height: 56,
                width: double.infinity,
                child:
                    s.recentTotalsMs.isEmpty
                        ? const Center(
                          child: Text(
                            'Interact with the app to record frames',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        )
                        : CustomPaint(
                          painter: _SparklinePainter(s.recentTotalsMs),
                        ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: const Text(
                'Green bars are within the 16.7ms / 60fps budget; amber/red bars '
                'are dropped frames. Tip: minimise the tools, run the flow you '
                'want to measure, then reopen this tab — capture never stops.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Live banner naming the screen these perf numbers belong to.
class _CurrentScreenBanner extends StatelessWidget {
  const _CurrentScreenBanner();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: CurrentScreenObserver.current,
      builder: (context, screen, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF132235),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF61AFEF).withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.smartphone, size: 16, color: Color(0xFF61AFEF)),
              const SizedBox(width: 8),
              const Text(
                'SCREEN',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  screen,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PerfStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color color;
  const _PerfStatCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1116),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bar sparkline of recent frame times. Bars are clamped to a 50ms ceiling and
/// coloured by the 16.7ms (1 frame) / 33ms (2 frames) thresholds.
class _SparklinePainter extends CustomPainter {
  final List<double> totals;
  const _SparklinePainter(this.totals);

  static const double _ceilingMs = 50;

  @override
  void paint(Canvas canvas, Size size) {
    if (totals.isEmpty) return;

    // 16.7ms budget guide line.
    final budgetY = size.height * (1 - (16.7 / _ceilingMs));
    final guide =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.18)
          ..strokeWidth = 1;
    canvas.drawLine(Offset(0, budgetY), Offset(size.width, budgetY), guide);

    final n = totals.length;
    final slot = size.width / n;
    final barW = slot * 0.7;
    for (var i = 0; i < n; i++) {
      final ms = totals[i];
      final h = (ms.clamp(0, _ceilingMs) / _ceilingMs) * size.height;
      final color =
          ms > 33
              ? const Color(0xFFE06C75)
              : ms > 16.7
              ? const Color(0xFFE5C07B)
              : const Color(0xFF98C379);
      final left = i * slot + (slot - barW) / 2;
      final rect = Rect.fromLTWH(left, size.height - h, barW, h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => !identical(old.totals, totals);
}


