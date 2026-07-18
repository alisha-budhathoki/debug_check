part of 'debug_overlay.dart';

class _ApiDetailScreen extends StatefulWidget {
  final DebugLogEntry entry;
  final VoidCallback onBack;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  const _ApiDetailScreen({
    required this.entry,
    required this.onBack,
    required this.onMinimize,
    required this.onClose,
  });

  @override
  State<_ApiDetailScreen> createState() => _ApiDetailScreenState();
}

class _ApiDetailScreenState extends State<_ApiDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole detail when the reveal preference flips: the masked vs.
    // real value has to change everywhere at once — headers, query, cURL, JSON
    // and HAR — or an export could carry a value the screen says is hidden.
    return ValueListenableBuilder<bool>(
      valueListenable: DebugTools.revealSecrets,
      builder: (context, _, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final e = widget.entry;
    return Material(
      color: const Color(0xFF0E1116),
      child: SafeArea(
        child: Column(
          children: [
            _header(e),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF161B22),
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: TabBar(
                controller: _tab,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                indicatorColor: const Color(0xFF61AFEF),
                indicatorWeight: 2.5,
                // Explicit so the Material-3 default (from the app theme) can't
                // leak a foreign divider colour under native launch.
                dividerColor: Colors.white12,
                overlayColor: const WidgetStatePropertyAll(Colors.white10),
                labelStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'Request'),
                  Tab(text: 'Headers'),
                  Tab(text: 'Response'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _SearchableDetail(
                    hint: 'Search overview…',
                    sections: _overviewSections(e),
                  ),
                  _SearchableDetail(
                    hint: 'Search query & body…',
                    sections: _requestSections(e),
                  ),
                  _SearchableDetail(
                    hint: 'Search headers…',
                    sections: _headerSections(e),
                  ),
                  _SearchableDetail(
                    hint: 'Search response…',
                    sections: _responseSections(e),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(DebugLogEntry e) {
    final insights = _insightsFor(e);
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _HeaderIconButton(icon: Icons.arrow_back, onTap: widget.onBack),
              _MethodBadge(method: e.method ?? '?'),
              const SizedBox(width: 6),
              _StatusBadge(kind: e.kind, statusCode: e.statusCode),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _apiPath(e.url),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Only offered when the raw value actually survived capture.
              // Under the default drop mode there is nothing to reveal, and a
              // toggle that silently does nothing would be worse than absent.
              if (DebugTools.redaction.canReveal)
                _HeaderIconButton(
                  icon:
                      DebugTools.revealSecrets.value
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                  tint:
                      DebugTools.revealSecrets.value
                          ? const Color(0xFFE5C07B)
                          : null,
                  tooltip:
                      DebugTools.revealSecrets.value
                          ? 'Hide secrets again'
                          : 'Reveal masked secrets',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    DebugTools.revealSecrets.value =
                        !DebugTools.revealSecrets.value;
                  },
                ),
              _HeaderIconButton(
                icon: Icons.terminal,
                tooltip: 'Copy as cURL',
                onTap: () => _copy(_apiCurl(e)),
              ),
              // Minimize straight from the detail page — drops back to the app
              // with this exact API detail preserved, ready to restore.
              _HeaderIconButton(
                icon: Icons.remove,
                tooltip: 'Minimize — keeps your place',
                onTap: widget.onMinimize,
              ),
              // Close — resets the tools so a reopen starts at the log list.
              _HeaderIconButton(
                icon: Icons.close,
                tooltip: 'Close — reset to start',
                onTap: widget.onClose,
              ),
            ],
          ),
          // Auto-derived "what's notable" badges — surfaces the slow call, the
          // server error, the cache hit or the oversized payload without making
          // the dev read the numbers.
          if (insights.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 4, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final i in insights)
                    _InsightChip(icon: i.icon, label: i.label, color: i.color),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Derives at-a-glance health badges from one call: status class, latency
  /// band, cache hit and payload size. Pure function of the entry.
  List<_Insight> _insightsFor(DebugLogEntry e) {
    const red = Color(0xFFE06C75);
    const amber = Color(0xFFE5C07B);
    const green = Color(0xFF98C379);
    const blue = Color(0xFF61AFEF);
    final out = <_Insight>[];

    final s = e.statusCode;
    if (e.isInFlight) {
      out.add(const _Insight(Icons.sync, 'IN FLIGHT', amber));
    } else if (s == null) {
      out.add(const _Insight(Icons.error_outline, 'FAILED', red));
    } else if (s >= 500) {
      out.add(_Insight(Icons.dns_outlined, 'SERVER $s', red));
    } else if (s == 401) {
      out.add(const _Insight(Icons.lock_outline, 'UNAUTHORIZED', amber));
    } else if (s == 403) {
      out.add(const _Insight(Icons.block, 'FORBIDDEN', amber));
    } else if (s == 304) {
      out.add(const _Insight(Icons.bolt, 'NOT MODIFIED · CACHED', blue));
    } else if (s >= 400) {
      out.add(
        _Insight(Icons.report_gmailerrorred_outlined, 'CLIENT $s', amber),
      );
    }

    final ms = e.duration?.inMilliseconds;
    if (ms != null) {
      if (ms > 1000) {
        out.add(_Insight(Icons.hourglass_bottom, 'SLOW · ${ms}ms', red));
      } else if (ms > 500) {
        out.add(_Insight(Icons.schedule, '${ms}ms', amber));
      } else {
        out.add(_Insight(Icons.flash_on, '${ms}ms', green));
      }
    }

    final b = e.responseBytes;
    if (b != null && b > 512 * 1024) {
      out.add(
        _Insight(Icons.layers_outlined, 'LARGE · ${_apiBytes(b)}', amber),
      );
    }

    return out;
  }

  // ── Section builders ──

  List<_DetailSectionData> _overviewSections(DebugLogEntry e) {
    final rows = <MapEntry<String, String>>[
      MapEntry('Method', e.method ?? '-'),
      MapEntry(
        'Status',
        e.statusCode != null
            ? '${e.statusCode} ${_statusText(e.statusCode!)}'
            : (e.isInFlight ? 'in-flight' : 'error'),
      ),
      MapEntry('URL', e.url ?? '-'),
      MapEntry('Host', _apiHost(e.url)),
      MapEntry('Path', _apiPath(e.url)),
      if (e.duration != null)
        MapEntry('Duration', '${e.duration!.inMilliseconds} ms'),
      if (e.responseBytes != null)
        MapEntry('Size', _apiBytes(e.responseBytes!)),
      MapEntry('Started', _apiTimeFull(e.timestamp)),
      if (e.errorMessage != null) MapEntry('Error', e.errorMessage!),
    ];
    return [
      _DetailSectionData(
        title: 'Overview',
        rows: rows,
        copyText: e.url,
        copyLabel: 'URL',
        copies: [
          _CopyAction(
            icon: Icons.data_object,
            label: 'JSON',
            text: _buildJson(e),
          ),
          _CopyAction(
            icon: Icons.archive_outlined,
            label: 'HAR',
            text: _buildHar(e),
          ),
        ],
      ),
    ];
  }

  List<_DetailSectionData> _requestSections(DebugLogEntry e) {
    final query =
        DebugTools.visible(e.queryParameters) ?? const <String, String>{};
    return [
      if (query.isNotEmpty)
        _DetailSectionData(
          title: 'Query parameters',
          rows: query.entries.toList(),
          // Plain `key: value` lines mirror what's on screen; the query-string
          // form is the one you actually paste into a URL or a client, so both
          // are offered rather than guessing which is wanted.
          copyText: _kvLines(query),
          copyLabel: 'Copy',
          copies: [
            _CopyAction(
              icon: Icons.link,
              label: 'Query',
              text: _queryString(query),
            ),
          ],
        ),
      if (e.requestBody?.isNotEmpty ?? false)
        _DetailSectionData(
          title: 'Request body',
          body: e.requestBody,
          copyText: e.requestBody,
          copyLabel: 'Copy',
        ),
      if ((e.queryParameters?.isEmpty ?? true) &&
          (e.requestBody?.isEmpty ?? true))
        const _DetailSectionData(
          title: 'Request',
          rows: [],
          emptyNote: 'No query parameters or request body.',
        ),
    ];
  }

  List<_DetailSectionData> _headerSections(DebugLogEntry e) {
    final out = <_DetailSectionData>[];
    final req =
        DebugTools.visible(e.requestHeaders) ?? const <String, String>{};
    final res =
        DebugTools.visible(e.responseHeaders) ?? const <String, String>{};
    if (req.isNotEmpty) {
      out.add(
        _DetailSectionData(
          title: 'Request headers',
          rows: req.entries.toList(),
          // `Name: value` is already wire format, so a copied header block
          // pastes straight into curl, an HTTP client or a bug report.
          copyText: _kvLines(req),
          copyLabel: 'Copy',
        ),
      );
    }
    if (res.isNotEmpty) {
      out.add(
        _DetailSectionData(
          title: 'Response headers',
          rows: res.entries.toList(),
          copyText: _kvLines(res),
          copyLabel: 'Copy',
        ),
      );
    }
    if (req.isNotEmpty && res.isNotEmpty) {
      // Both blocks at once — the usual thing to attach to a report, and
      // otherwise two taps plus a manual splice.
      out.first = _DetailSectionData(
        title: out.first.title,
        rows: out.first.rows,
        copyText: out.first.copyText,
        copyLabel: out.first.copyLabel,
        copies: [
          _CopyAction(
            icon: Icons.copy_all_outlined,
            label: 'All',
            text:
                '# Request headers\n${_kvLines(req)}\n\n'
                '# Response headers\n${_kvLines(res)}',
          ),
        ],
      );
    }
    if (out.isEmpty) {
      out.add(
        const _DetailSectionData(
          title: 'Headers',
          rows: [],
          emptyNote: 'No headers captured.',
        ),
      );
    }
    return out;
  }

  List<_DetailSectionData> _responseSections(DebugLogEntry e) {
    final statusRows = <MapEntry<String, String>>[
      MapEntry(
        'Status',
        e.statusCode != null
            ? '${e.statusCode} ${_statusText(e.statusCode!)}'
            : (e.isInFlight ? 'in-flight' : 'error'),
      ),
      if (e.duration != null)
        MapEntry('Duration', '${e.duration!.inMilliseconds} ms'),
      if (e.responseBytes != null)
        MapEntry('Size', _apiBytes(e.responseBytes!)),
    ];
    return [
      _DetailSectionData(
        title: 'Status',
        rows: statusRows,
        copyText: _rowLines(statusRows),
        copyLabel: 'Copy',
      ),
      if (e.responseBody?.isNotEmpty ?? false)
        _DetailSectionData(
          title: 'Response body',
          body: e.responseBody,
          copyText: e.responseBody,
          copyLabel: 'Copy',
        )
      else
        const _DetailSectionData(
          title: 'Response body',
          rows: [],
          emptyNote: 'No response body.',
        ),
    ];
  }

  // ── helpers ──

  static String _apiHost(String? url) {
    if (url == null) return '-';
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return '-';
    return (u.port == 0 || u.port == 80 || u.port == 443)
        ? u.host
        : '${u.host}:${u.port}';
  }

  static String _apiPath(String? url) {
    if (url == null) return '-';
    final u = Uri.tryParse(url);
    if (u == null) return url;
    final path = u.path.isEmpty ? '/' : u.path;
    return u.query.isEmpty ? path : '$path?${u.query}';
  }

  static String _apiBytes(int b) {
    if (b < 1024) return '${b}B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}KB';
    return '${(b / 1024 / 1024).toStringAsFixed(2)}MB';
  }

  /// `key: value` per line — the same shape the section renders, so what lands
  /// on the clipboard is what the user was looking at.
  static String _kvLines(Map<String, String> map) =>
      map.entries.map((e) => '${e.key}: ${e.value}').join('\n');

  static String _rowLines(List<MapEntry<String, String>> rows) =>
      rows.map((e) => '${e.key}: ${e.value}').join('\n');

  /// `a=b&c=d`, percent-encoded — paste-ready for a URL or an HTTP client.
  static String _queryString(Map<String, String> q) => q.entries
      .map(
        (e) =>
            '${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent(e.value)}',
      )
      .join('&');

  static String _apiTimeFull(DateTime t) =>
      '${t.year}-${_pad2(t.month)}-${_pad2(t.day)} '
      '${_pad2(t.hour)}:${_pad2(t.minute)}:${_pad2(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';

  static String _pad2(int v) => v.toString().padLeft(2, '0');

  static String _apiCurl(DebugLogEntry e) {
    final buf = StringBuffer('curl -X ${e.method ?? "GET"}');
    DebugTools.visible(
      e.requestHeaders,
    )?.forEach((k, v) => buf.write(" -H '$k: $v'"));
    if (e.requestBody?.isNotEmpty ?? false) {
      buf.write(" --data '${e.requestBody!.replaceAll("'", r"'\''")}'");
    }
    if (e.url != null) buf.write(" '${e.url}'");
    return buf.toString();
  }

  /// Flat, readable JSON dump of the whole call — bodies are nested as parsed
  /// JSON when possible, else kept as raw strings.
  static String _buildJson(DebugLogEntry e) {
    final map = <String, dynamic>{
      'method': e.method,
      'url': e.url,
      'status': e.statusCode,
      'durationMs': e.duration?.inMilliseconds,
      'startedAt': e.timestamp.toIso8601String(),
      if (e.queryParameters?.isNotEmpty ?? false)
        'queryParameters': DebugTools.visible(e.queryParameters),
      if (e.requestHeaders?.isNotEmpty ?? false)
        'requestHeaders': DebugTools.visible(e.requestHeaders),
      if (e.requestBody?.isNotEmpty ?? false)
        'requestBody': _maybeDecode(e.requestBody!),
      if (e.responseHeaders?.isNotEmpty ?? false)
        'responseHeaders': DebugTools.visible(e.responseHeaders),
      if (e.responseBytes != null) 'responseBytes': e.responseBytes,
      if (e.responseBody?.isNotEmpty ?? false)
        'responseBody': _maybeDecode(e.responseBody!),
      if (e.errorMessage != null) 'error': e.errorMessage,
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// HAR 1.2 single-entry archive — paste into any HAR viewer / browser devtools.
  static String _buildHar(DebugLogEntry e) {
    List<Map<String, String>> nv(Map<String, String>? m) =>
        (m?.entries ?? const <MapEntry<String, String>>[])
            .map((x) => {'name': x.key, 'value': x.value})
            .toList();

    String mime(Map<String, String>? headers) {
      if (headers == null) return 'application/json';
      for (final h in headers.entries) {
        if (h.key.toLowerCase() == 'content-type') return h.value;
      }
      return 'application/json';
    }

    final reqBody = e.requestBody;
    final resBody = e.responseBody;
    final har = <String, dynamic>{
      'log': {
        'version': '1.2',
        'creator': {'name': 'AppDebugTools', 'version': '1.0'},
        'entries': [
          {
            'startedDateTime': e.timestamp.toIso8601String(),
            'time': e.duration?.inMilliseconds ?? -1,
            'request': {
              'method': e.method ?? 'GET',
              'url': e.url ?? '',
              'httpVersion': 'HTTP/1.1',
              'cookies': const [],
              'headers': nv(DebugTools.visible(e.requestHeaders)),
              'queryString': nv(DebugTools.visible(e.queryParameters)),
              if (reqBody != null && reqBody.isNotEmpty)
                'postData': {
                  'mimeType': mime(e.requestHeaders),
                  'text': reqBody,
                },
              'headersSize': -1,
              'bodySize': reqBody?.length ?? 0,
            },
            'response': {
              'status': e.statusCode ?? 0,
              'statusText':
                  e.statusCode != null ? _statusText(e.statusCode!) : '',
              'httpVersion': 'HTTP/1.1',
              'cookies': const [],
              'headers': nv(DebugTools.visible(e.responseHeaders)),
              'content': {
                'size': e.responseBytes ?? (resBody?.length ?? 0),
                'mimeType': mime(e.responseHeaders),
                if (resBody != null) 'text': resBody,
              },
              'redirectURL': '',
              'headersSize': -1,
              'bodySize': e.responseBytes ?? (resBody?.length ?? 0),
            },
            'cache': const {},
            'timings': {
              'send': -1,
              'wait': e.duration?.inMilliseconds ?? -1,
              'receive': -1,
            },
          },
        ],
      },
    };
    return const JsonEncoder.withIndent('  ').convert(har);
  }

  static dynamic _maybeDecode(String body) {
    final t = body.trim();
    if (t.startsWith('{') || t.startsWith('[')) {
      try {
        return jsonDecode(t);
      } catch (_) {}
    }
    return body;
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    await HapticFeedback.lightImpact();
  }
}

/// Data for one collapsible-free section inside a tab.
class _DetailSectionData {
  final String title;
  final List<MapEntry<String, String>> rows;
  final String? body;
  final String? copyText;
  final String? copyLabel;
  final List<_CopyAction> copies; // extra copy buttons (e.g. JSON / HAR)
  final String? emptyNote;

  const _DetailSectionData({
    required this.title,
    this.rows = const [],
    this.body,
    this.copyText,
    this.copyLabel,
    this.copies = const [],
    this.emptyNote,
  });
}

/// A labelled copy button backed by ready-to-paste text.
class _CopyAction {
  final IconData icon;
  final String label;
  final String text;
  const _CopyAction({
    required this.icon,
    required this.label,
    required this.text,
  });
}

/// One search hit inside the detail view — a field row or a body line — paired
/// with a live anchor key so its result row can scroll precisely to it.
class _SearchMatch {
  final String section;
  final String snippet;
  final GlobalKey key;
  const _SearchMatch({
    required this.section,
    required this.snippet,
    required this.key,
  });
}

/// A tab body: a search field over every section. Matches stay highlighted in
/// the full content and are listed in a results bar; tapping a result (or the
/// prev/next chevrons) scrolls straight to that exact field or line.
class _SearchableDetail extends StatefulWidget {
  final String hint;
  final List<_DetailSectionData> sections;
  const _SearchableDetail({required this.hint, required this.sections});

  @override
  State<_SearchableDetail> createState() => _SearchableDetailState();
}

class _SearchableDetailState extends State<_SearchableDetail> {
  final _ctrl = TextEditingController();
  String _q = '';
  // Anchor keys reused by match index so they stay stable across rebuilds —
  // ensureVisible needs a live element, and a fresh key per build would break
  // the jump target. Grown lazily as matches are discovered.
  final List<GlobalKey> _anchorPool = [];
  // Rebuilt every build in document order; index lines up with _anchorPool.
  List<_SearchMatch> _matches = [];
  int _activeIndex = -1; // currently jumped-to match; -1 = none
  bool _resultsOpen = true;

  static const TextStyle _codeStyle = TextStyle(
    fontSize: 11.5,
    fontFamily: 'monospace',
    height: 1.5,
    color: Colors.white,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    await HapticFeedback.lightImpact();
  }

  void _onQueryChanged(String v) {
    setState(() {
      _q = v;
      _activeIndex = -1; // match set changed — drop the stale active highlight
      _resultsOpen = true;
    });
  }

  GlobalKey _registerMatch(String section, String snippet) {
    final i = _matches.length;
    if (i >= _anchorPool.length) _anchorPool.add(GlobalKey());
    final key = _anchorPool[i];
    _matches.add(_SearchMatch(section: section, snippet: snippet, key: key));
    return key;
  }

  void _jumpTo(int i) {
    if (i < 0 || i >= _matches.length) return;
    setState(() => _activeIndex = i);
    final key = _anchorPool[i];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.15,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
      );
    });
  }

  void _step(int delta) {
    if (_matches.isEmpty) return;
    final base = _activeIndex < 0 ? (delta > 0 ? -1 : 0) : _activeIndex;
    final next = (base + delta) % _matches.length;
    _jumpTo((next + _matches.length) % _matches.length);
  }

  @override
  Widget build(BuildContext context) {
    // Reset the per-build match log; _sectionCard repopulates it in document
    // order as it renders, keeping indices aligned with _anchorPool.
    _matches = [];
    final searching = _q.trim().isNotEmpty;

    final cards = <Widget>[
      for (final s in widget.sections) _sectionCard(s, searching),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: _DetailSearchField(
            controller: _ctrl,
            hint: widget.hint,
            onChanged: _onQueryChanged,
          ),
        ),
        // Built after `cards`, so _matches is fully populated here.
        if (searching) _resultsBar(),
        Expanded(
          // SingleChildScrollView (not a lazy ListView) so every anchored match
          // is realised in the tree and reachable by Scrollable.ensureVisible.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: cards,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionCard(_DetailSectionData s, bool searching) {
    final q = _q.toLowerCase();
    final children = <Widget>[];

    for (final kv in s.rows) {
      final isMatch =
          searching &&
          (kv.key.toLowerCase().contains(q) ||
              kv.value.toLowerCase().contains(q));
      if (isMatch) {
        final key = _registerMatch(s.title, '${kv.key}: ${kv.value}');
        final active = _matches.length - 1 == _activeIndex;
        children.add(_anchorWrap(key, active, _KvRow(entry: kv, query: _q)));
      } else {
        children.add(_KvRow(entry: kv, query: searching ? _q : ''));
      }
    }

    final body = s.body;
    if (body != null && body.isNotEmpty) {
      if (s.rows.isNotEmpty) children.add(const SizedBox(height: 8));
      children.addAll(_bodyWidgets(body, s.title, searching));
    }

    if (children.isEmpty) {
      children.add(
        Text(
          s.emptyNote ?? 'Empty.',
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _DetailSection(
        // The count only means something for key/value sections. A body-only
        // section has no rows, so the old unconditional suffix rendered
        // "RESPONSE BODY (0)" over a body that was plainly there.
        title: s.rows.isEmpty ? s.title : '${s.title}  (${s.rows.length})',
        actions: [
          if (s.copyText != null && s.copyText!.isNotEmpty)
            _SectionButton(
              icon: Icons.copy,
              label: s.copyLabel ?? 'Copy',
              onTap: () => _copy(s.copyText!),
            ),
          for (final a in s.copies)
            _SectionButton(
              icon: a.icon,
              label: a.label,
              onTap: () => _copy(a.text),
            ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  /// Renders a body. Without a query it's a single coloured code block; while
  /// searching it splits into runs so each matching line becomes its own
  /// anchored, tappable target (non-matching runs collapse into one block).
  List<Widget> _bodyWidgets(String body, String section, bool searching) {
    if (!searching) return [_CodeBlock(body: body)];

    final q = _q.toLowerCase();
    final lines = const LineSplitter().convert(_prettify(body));
    final blocks = <Widget>[];
    final buffer = <String>[];

    void flush() {
      if (buffer.isEmpty) return;
      blocks.add(
        SelectableText.rich(
          TextSpan(
            style: _codeStyle,
            children: _highlightJson(buffer.join('\n')),
          ),
        ),
      );
      buffer.clear();
    }

    for (final line in lines) {
      if (line.toLowerCase().contains(q)) {
        flush();
        final key = _registerMatch(section, line.trim());
        final active = _matches.length - 1 == _activeIndex;
        blocks.add(_matchLine(key, line, active));
      } else {
        buffer.add(line);
      }
    }
    flush();

    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF05080C),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: blocks,
        ),
      ),
    ];
  }

  Widget _matchLine(GlobalKey key, String line, bool active) {
    return Container(
      key: key,
      width: double.infinity,
      decoration: BoxDecoration(
        color: active ? const Color(0x44FFD54F) : null,
        borderRadius: BorderRadius.circular(3),
        border: active ? Border.all(color: const Color(0xFFFFD54F)) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: SelectableText.rich(
        TextSpan(
          style: _codeStyle,
          children: _hlSpans(line, _q, const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }

  Widget _anchorWrap(GlobalKey key, bool active, Widget child) {
    return Container(
      key: key,
      decoration:
          active
              ? BoxDecoration(
                color: const Color(0x33FFD54F),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFFFD54F)),
              )
              : null,
      padding:
          active
              ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
              : EdgeInsets.zero,
      child: child,
    );
  }

  Widget _resultsBar() {
    final n = _matches.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 2, 10, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const SizedBox(width: 10),
              Icon(
                n == 0 ? Icons.search_off : Icons.manage_search,
                size: 16,
                color: Colors.white54,
              ),
              const SizedBox(width: 6),
              Text(
                n == 0 ? 'No matches' : '$n match${n == 1 ? '' : 'es'}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (n > 0 && _activeIndex >= 0)
                Text(
                  '  ·  ${_activeIndex + 1}/$n',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              const Spacer(),
              if (n > 0) ...[
                _HeaderIconButton(
                  icon: Icons.keyboard_arrow_up,
                  tooltip: 'Previous match',
                  onTap: () => _step(-1),
                ),
                _HeaderIconButton(
                  icon: Icons.keyboard_arrow_down,
                  tooltip: 'Next match',
                  onTap: () => _step(1),
                ),
                _HeaderIconButton(
                  icon: _resultsOpen ? Icons.unfold_less : Icons.unfold_more,
                  tooltip: _resultsOpen ? 'Collapse list' : 'Expand list',
                  onTap: () => setState(() => _resultsOpen = !_resultsOpen),
                ),
                const SizedBox(width: 4),
              ],
            ],
          ),
          if (n > 0 && _resultsOpen)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 168),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 6),
                itemCount: n,
                itemBuilder: (_, i) => _resultTile(i),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultTile(int i) {
    final m = _matches[i];
    final active = i == _activeIndex;
    var snippet = m.snippet.trim();
    if (snippet.length > 140) snippet = '${snippet.substring(0, 139)}…';
    return InkWell(
      onTap: () => _jumpTo(i),
      child: Container(
        color: active ? const Color(0x2261AFEF) : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF0E1116),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                m.section,
                style: const TextStyle(
                  color: Color(0xFF61AFEF),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    height: 1.35,
                  ),
                  children: _hlSpans(
                    snippet,
                    _q,
                    const TextStyle(color: Colors.white),
                  ),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              active ? Icons.my_location : Icons.chevron_right,
              size: 14,
              color: active ? const Color(0xFF61AFEF) : Colors.white24,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  const _DetailSearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        cursorColor: Colors.white70,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
          border: InputBorder.none,
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 0,
          ),
          suffixIcon:
              controller.text.isEmpty
                  ? null
                  : GestureDetector(
                    onTap: () {
                      controller.clear();
                      onChanged('');
                    },
                    child: const Icon(
                      Icons.close,
                      color: Colors.white38,
                      size: 16,
                    ),
                  ),
        ),
      ),
    );
  }
}

/// Key/value row with the search term highlighted in both key and value.
class _KvRow extends StatelessWidget {
  final MapEntry<String, String> entry;
  final String query;
  const _KvRow({required this.entry, required this.query});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SelectableText.rich(
        TextSpan(
          style: const TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            height: 1.4,
          ),
          children: [
            ..._hlSpans(
              '${entry.key}: ',
              query,
              const TextStyle(color: Color(0xFF7EE7E7)),
            ),
            ..._hlSpans(
              entry.value,
              query,
              const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// One at-a-glance health badge derived from an API call (see `_insightsFor`).
class _Insight {
  final IconData icon;
  final String label;
  final Color color;
  const _Insight(this.icon, this.label, this.color);
}

/// Compact pill rendering an [_Insight] — icon + tinted label.
class _InsightChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InsightChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

/// Body code block reduced to only the lines that match the query, highlighted.
/// Splits [text] around case-insensitive matches of [query], highlighting them.
