part of 'debug_overlay.dart';

// ─── Autopsy panel (unified health diagnosis) ────────────────────────────────

/// The flagship "what is this app, right now" view. Synthesizes the network
/// traffic, rendering timings and captured errors already recorded into one
/// graded diagnosis with prioritized findings and a Markdown export.
///
/// Rebuilds live off both the log buffer and the perf stats, so the grade moves
/// as traffic completes and frames land. Diagnosis itself is a pure function
/// ([AppAutopsy.diagnose]); this widget is only presentation + copy.
class _AutopsyPanel extends StatelessWidget {
  const _AutopsyPanel();

  static const _green = Color(0xFF98C379);
  static const _amber = Color(0xFFE5C07B);
  static const _red = Color(0xFFE06C75);
  static const _blue = Color(0xFF61AFEF);

  static Color _gradeColor(AutopsyGrade g) {
    switch (g) {
      case AutopsyGrade.a:
      case AutopsyGrade.b:
        return _green;
      case AutopsyGrade.c:
        return _amber;
      case AutopsyGrade.d:
      case AutopsyGrade.f:
        return _red;
    }
  }

  static Color _severityColor(AutopsySeverity s) {
    switch (s) {
      case AutopsySeverity.critical:
        return _red;
      case AutopsySeverity.warning:
        return _amber;
      case AutopsySeverity.info:
        return _blue;
      case AutopsySeverity.good:
        return _green;
    }
  }

  static IconData _severityIcon(AutopsySeverity s) {
    switch (s) {
      case AutopsySeverity.critical:
        return Icons.error_outline;
      case AutopsySeverity.warning:
        return Icons.warning_amber_rounded;
      case AutopsySeverity.info:
        return Icons.info_outline;
      case AutopsySeverity.good:
        return Icons.check_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Two live sources: rebuild when either traffic or frames change.
    return ValueListenableBuilder<List<DebugLogEntry>>(
      valueListenable: DebugLogger.instance.entries,
      builder: (context, entries, _) {
        return ValueListenableBuilder<PerfStats>(
          valueListenable: PerfMonitor.instance.stats,
          builder: (context, perf, _) {
            final autopsy = AppAutopsy.diagnose(
              entries: entries,
              perf: perf,
              duplicates: findDuplicateApiCalls(entries),
            );
            return _body(context, autopsy);
          },
        );
      },
    );
  }

  Widget _body(BuildContext context, AppAutopsy a) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'One-tap diagnosis — copy for a bug report or PR',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _SectionButton(
              icon: Icons.description_outlined,
              label: 'Markdown',
              onTap: () => _copy(a.toMarkdown()),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _GradeHero(autopsy: a, color: _gradeColor(a.grade)),
        const SizedBox(height: 12),
        Row(
          children: [
            _SubsystemBar(health: a.network),
            const SizedBox(width: 8),
            _SubsystemBar(health: a.rendering),
            const SizedBox(width: 8),
            _SubsystemBar(health: a.stability),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Text(
              'FINDINGS',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${a.findings.length}',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final f in a.findings) ...[
          _FindingCard(
            finding: f,
            color: _severityColor(f.severity),
            icon: _severityIcon(f.severity),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: const Text(
            'The autopsy grades Network, Rendering and Stability from data '
            'captured this session. Exercise the flow you care about, then '
            'reopen — it recomputes live. Log state changes or user actions '
            'with DebugTools.breadcrumb(...) to see them in the timeline.',
            style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
          ),
        ),
      ],
    );
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    await HapticFeedback.lightImpact();
  }
}

/// The hero card: a big letter grade in a coloured ring, the numeric score, and
/// the one-line verdict. This is the first thing a junior reads.
class _GradeHero extends StatelessWidget {
  final AppAutopsy autopsy;
  final Color color;
  const _GradeHero({required this.autopsy, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1116),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 66,
            height: 66,
            child: CustomPaint(
              painter: _RingPainter(
                fraction: autopsy.score / 100,
                color: color,
              ),
              child: Center(
                child: Text(
                  autopsy.grade.letter,
                  style: TextStyle(
                    color: color,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '${autopsy.score}',
                      style: TextStyle(
                        color: color,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Text(
                      ' / 100',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  autopsy.headline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  autopsy.criticalCount > 0 || autopsy.warningCount > 0
                      ? 'Ranked most-urgent first — start at the top'
                      : 'Exercise a flow, then reopen to re-grade',
                  style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the three subsystem score chips with a mini progress track.
class _SubsystemBar extends StatelessWidget {
  final SubsystemHealth health;
  const _SubsystemBar({required this.health});

  Color get _color {
    if (!health.hasData) return Colors.white24;
    if (health.score >= 80) return const Color(0xFF98C379);
    if (health.score >= 60) return const Color(0xFFE5C07B);
    return const Color(0xFFE06C75);
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
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
              health.name.toUpperCase(),
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),
            Text(
              health.hasData ? '${health.score}' : '—',
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: health.hasData ? health.score / 100 : 0,
                minHeight: 4,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single finding rendered as a left-accented card: severity icon + title on
/// top, evidence detail underneath.
class _FindingCard extends StatelessWidget {
  final AutopsyFinding finding;
  final Color color;
  final IconData icon;
  const _FindingCard({
    required this.finding,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  finding.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                if (finding.detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    finding.detail,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A simple circular gauge: a dim full track with a coloured arc sweeping
/// [fraction] of the way round, matching the grade colour.
class _RingPainter extends CustomPainter {
  final double fraction; // 0..1
  final Color color;
  const _RingPainter({required this.fraction, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 5.0;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - stroke) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withValues(alpha: 0.10);
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708, // -90° (12 o'clock)
      6.2832 * fraction.clamp(0, 1),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color;
}
