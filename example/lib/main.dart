import 'package:debug_deck/debug_deck.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Demo host app for debug_deck.
///
/// Shows the full integration (init + [DebugToolsHost] + Dio interceptor +
/// route observer) and seeds the inspector with realistic sample traffic so the
/// floating bug chip has something to show the moment it opens.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. One init at startup — gate this on your own dev/staging flag in a real
  //    app. Here it's always on so the overlay is visible in the demo.
  DebugTools.init(
    enabled: true,
    appInfo: const DebugAppInfo(
      version: '1.0.0 (42)',
      environmentName: 'staging',
      baseUrl: 'https://api.tradingapp.dev',
      isNativeCall: false,
    ),
  );

  seedDemoData();
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'debug_deck demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF61AFEF),
        useMaterial3: true,
      ),
      // 2. Mount the overlay above every screen. Transparent when disabled.
      builder:
          (context, child) =>
              DebugToolsHost(child: child ?? const SizedBox.shrink()),
      // 3. Track the current screen for the Perf banner.
      navigatorObservers: [DebugTools.routeObserver],
      initialRoute: '/PortfolioScreen',
      routes: {'/PortfolioScreen': (_) => const HomeScreen()},
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // A Dio client wired with the inspector interceptor — every call it makes is
  // captured. Points at a public API so the demo works without a backend.
  static final Dio _dio = Dio(
    BaseOptions(baseUrl: 'https://jsonplaceholder.typicode.com'),
  )..interceptors.add(DebugTools.dioInterceptor());

  Future<void> _fire() async {
    // A breadcrumb marks the user action in the timeline (and feeds the Autopsy
    // context) — library-agnostic, drop it anywhere.
    DebugTools.breadcrumb('Tapped "Fire live API calls"');
    try {
      await _dio.get('/posts/1');
      await _dio.post('/posts', data: {'title': 'hello', 'body': 'world'});
    } catch (_) {
      /* captured by the inspector */
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('debug_deck demo'),
        backgroundColor: const Color(0xFF61AFEF),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Tap the floating bug chip to open the debug overlay.\n\n'
                'It is already seeded with sample API calls, errors and logs '
                'so every tab has content to explore.',
                style: TextStyle(height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _fire,
            icon: const Icon(Icons.cloud_download),
            label: const Text('Fire live API calls (captured live)'),
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < 30; i++)
            ListTile(
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text('Sample row ${i + 1}'),
              subtitle: const Text('Fling this list, then open the Perf tab'),
            ),
        ],
      ),
    );
  }
}

/// Populates the inspector with a realistic spread of traffic: fast/slow calls,
/// a server error, a 404, a duplicate pair, plus an info log and an error — so
/// the log list, API detail, insight chips, search and duplicate detection all
/// have something to show.
void seedDemoData() {
  final log = DebugLogger.instance;
  const base = 'https://api.tradingapp.dev';
  const jsonHeaders = {
    'content-type': 'application/json',
    'authorization': 'Bearer eyJhbGciOiJIUzI1Ni.demo.token',
  };

  log.logInfo('App started', 'environment: staging - cold start 812ms');

  // Breadcrumbs — state transitions / user actions fed in from anywhere via
  // DebugTools.breadcrumb(...). They interleave with traffic in the timeline and
  // give the Autopsy tab context for what the app was doing.
  DebugTools.breadcrumb('AuthBloc', 'Authenticated(user: 42)');
  DebugTools.breadcrumb('Opened PortfolioScreen');

  // Fast GET with a searchable JSON list response.
  log.completeApiSuccess(
    id: null,
    method: 'GET',
    url: '$base/api/v1/watchlist',
    statusCode: 200,
    duration: const Duration(milliseconds: 142),
    requestHeaders: jsonHeaders,
    responseHeaders: const {'content-type': 'application/json'},
    responseBody:
        '[{"symbol":"AAPL","name":"Apple Inc.","price":214.29,"change":1.12},'
        '{"symbol":"NABIL","name":"Nabil Bank","price":512.0,"change":-0.4},'
        '{"symbol":"GOOGL","name":"Alphabet","price":178.3,"change":0.8}]',
    responseBytes: 184,
  );

  // Long URL-encoded query — exercises full-path wrapping + query decoding in
  // the log list (renders as filter[duration]=1D&filter[type]=INDEX&…).
  log.completeApiSuccess(
    id: null,
    method: 'GET',
    url:
        '$base/api/v1/market-index'
        '?filter%5Bduration%5D=1D'
        '&filter%5Btype%5D=INDEX'
        '&filter%5Bsymbol%5D=NEPSE',
    statusCode: 200,
    duration: const Duration(milliseconds: 2367),
    requestHeaders: jsonHeaders,
    responseHeaders: const {'content-type': 'application/json'},
    responseBody: '{"index":"NEPSE","value":2678.4,"change":12.3}',
    responseBytes: 106600,
  );

  // Login POST with request + response bodies.
  log.completeApiSuccess(
    id: null,
    method: 'POST',
    url: '$base/api/v1/auth/login',
    statusCode: 201,
    duration: const Duration(milliseconds: 380),
    requestHeaders: jsonHeaders,
    responseHeaders: const {'content-type': 'application/json'},
    requestBody: '{"email":"trader@demo.app","password":"demo-pass"}',
    responseBody:
        '{"token":"eyJhbGciOiJIUzI1Ni",'
        '"user":{"id":42,"name":"Demo Trader","tier":"pro"}}',
    responseBytes: 156,
  );

  // Slow holdings call — triggers the SLOW insight chip + red latency.
  log.completeApiSuccess(
    id: null,
    method: 'GET',
    url: '$base/api/v1/portfolio/holdings',
    statusCode: 200,
    duration: const Duration(milliseconds: 1480),
    requestHeaders: jsonHeaders,
    responseHeaders: const {'content-type': 'application/json'},
    responseBody:
        '{"holdings":['
        '{"symbol":"AAPL","quantity":120,"averagePrice":188.40,"marketValue":25714.80},'
        '{"symbol":"NABIL","quantity":50,"averagePrice":498.10,"marketValue":25600.00},'
        '{"symbol":"GOOGL","quantity":18,"averagePrice":165.20,"marketValue":3209.40}],'
        '"totalValue":54524.20,"dayChange":612.35}',
    responseBytes: 712,
  );

  // Server error.
  log.completeApiError(
    id: null,
    method: 'GET',
    url: '$base/api/v1/orders/history',
    statusCode: 500,
    duration: const Duration(milliseconds: 5052),
    requestHeaders: jsonHeaders,
    responseBody: '{"error":"Internal server error","traceId":"a1b2c3"}',
    errorMessage: 'DioException [bad response]: status 500',
  );

  // Not found.
  log.completeApiError(
    id: null,
    method: 'GET',
    url: '$base/api/v1/quotes/UNKNOWN',
    statusCode: 404,
    duration: const Duration(milliseconds: 98),
    requestHeaders: jsonHeaders,
    responseBody: '{"error":"Symbol not found"}',
    errorMessage: 'DioException [bad response]: status 404',
  );

  // Duplicate pair — identical POSTs fired back-to-back (double-tap bug).
  for (var i = 0; i < 2; i++) {
    log.completeApiSuccess(
      id: null,
      method: 'POST',
      url: '$base/api/v1/orders',
      statusCode: 201,
      duration: const Duration(milliseconds: 264),
      requestHeaders: jsonHeaders,
      requestBody: '{"symbol":"AAPL","qty":10,"side":"BUY","type":"MARKET"}',
      responseBody: '{"orderId":"ORD-7781","status":"ACCEPTED"}',
      responseBytes: 64,
    );
  }

  // A captured app error for the console.
  log.logPlatformError(
    StateError('Null check operator used on a null value in QuoteCard'),
    StackTrace.fromString(
      '#0      QuoteCard.build (package:tradingapp/quote_card.dart:48:23)\n'
      '#1      StatelessElement.build (package:flutter/src/widgets/framework.dart)\n'
      '#2      ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart)',
    ),
  );
}
