# debug_deck

Isolated, drop-in **in-app debug tools** for Flutter — fully decoupled from the
host app and switched on with a single flag.

<p align="center">
  <img width="300" src="https://raw.githubusercontent.com/alisha-budhathoki/debug_check/main/screenshots/00-demo.gif" alt="The debug_deck overlay: tapping the floating bug chip opens the inspector, drilling into a failing 500 call, searching inside a response body, then the Autopsy grade, live FPS and the app-info snapshot"><br>
  <sub>Bug chip → inspector → a failing call → search a response → <b>Autopsy grade</b> → live FPS</sub>
</p>

<table>
  <tr>
    <td align="center" width="33%">
      <img width="250" src="https://raw.githubusercontent.com/alisha-budhathoki/debug_check/main/screenshots/01-log-list.png" alt="Inspector log list with method/status badges, latency colours, a red Errors tab carrying an error count, and duplicate detection"><br>
      <sub><b>Inspector</b> · calls, errors &amp; duplicates</sub>
    </td>
    <td align="center" width="33%">
      <img width="250" src="https://raw.githubusercontent.com/alisha-budhathoki/debug_check/main/screenshots/03-search-response.png" alt="Search inside a response body with highlighted matches and jump-to-match navigation"><br>
      <sub><b>Search a response</b> · jump to each match</sub>
    </td>
    <td align="center" width="33%">
      <img width="250" src="https://raw.githubusercontent.com/alisha-budhathoki/debug_check/main/screenshots/02-api-detail.png" alt="API call detail with insight chips and cURL/JSON/HAR export"><br>
      <sub><b>Call detail</b> · insight chips &amp; export</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="33%">
      <img width="250" src="https://raw.githubusercontent.com/alisha-budhathoki/debug_check/main/screenshots/06-secrets-masked.png" alt="Headers tab showing an Authorization header masked as Bearer with dots, preserving the last four characters"><br>
      <sub><b>Secrets masked</b> · safe to paste anywhere</sub>
    </td>
    <td align="center" width="33%">
      <img width="250" src="https://raw.githubusercontent.com/alisha-budhathoki/debug_check/main/screenshots/07-secrets-revealed.png" alt="The same Headers tab after tapping the eye toggle, showing the full bearer token"><br>
      <sub><b>…revealed on demand</b> · one tap, reversible</sub>
    </td>
    <td align="center" width="33%">
      <img width="250" src="https://raw.githubusercontent.com/alisha-budhathoki/debug_check/main/screenshots/08-pinned.png" alt="A log row pinned with a blue pin marker and blue border, exempt from ring-buffer eviction"><br>
      <sub><b>Pin a row</b> · survives the 200-entry cap</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="33%">
      <img width="250" src="https://raw.githubusercontent.com/alisha-budhathoki/debug_check/main/screenshots/04-performance.png" alt="Live performance monitor with FPS gauge, jank split and frame-time sparkline"><br>
      <sub><b>Performance</b> · FPS, jank &amp; frames</sub>
    </td>
    <td align="center" width="33%">
      <img width="250" src="https://raw.githubusercontent.com/alisha-budhathoki/debug_check/main/screenshots/05-app-info.png" alt="App-info snapshot with build, API stats, errors and device facts"><br>
      <sub><b>App-info snapshot</b> · copy for reports</sub>
    </td>
    <td align="center" width="33%"></td>
  </tr>
</table>

> A runnable demo lives in [`example/`](example/) — `cd example && flutter run`.
> It wires the overlay and seeds sample traffic, so every tab has content to
> explore. The same app powers these screenshots (see
> `example/integration_test/screenshot_test.dart`).

What you get, as a floating overlay (a draggable bug chip → full viewer):

- **App Autopsy** — a one-tap health diagnosis that grades the whole app (A–F /
  0–100) across **Network**, **Rendering** and **Stability**, with prioritized,
  plain-language findings and a Markdown export for a bug report or PR.
- **API inspector** — every Dio request/response with headers, query, bodies,
  timings, status, duplicate-call detection, and per-tab search that jumps to
  the exact matching line.
- **Logs & errors console** — captured `FlutterError` / uncaught platform errors.
- **Performance monitor** — live FPS (scroll-time), UI vs raster jank split,
  stalls, worst frame, frame-time sparkline, a plain-language verdict, and the
  **current screen name** so a reading is never ambiguous.
- **Layout grid inspector** — spacing/alignment/bounds overlay.
- **App-info snapshot** — build/env/device/a11y, copyable for bug reports.

It renders **nothing** and does **no work** unless you enable it.

## Why debug_deck

A few things it does that most in-app inspectors don't:

### 🩺 App Autopsy — one tap tells you what the app *is* right now

Every other inspector shows you raw logs and leaves the diagnosis to you. The
**Autopsy** tab does the diagnosis: it reads the network traffic, the frame
timings and the captured errors it already recorded and synthesizes them into a
single **graded verdict** —

- an overall **grade (A–F)** and **0–100 score**, with a one-line headline a
  junior can read (`Healthy — nothing urgent, one thing to watch`);
- three **subsystem scores** — **Network**, **Rendering**, **Stability** — so a
  senior sees exactly *where* the health went;
- a **prioritized findings list** (most-urgent first) that *diagnoses and
  prescribes* rather than restating numbers you can already see — "failures are
  server-side, not in the app", "the same request is firing more than once —
  debounce or guard it", "the UI thread is the bottleneck — move heavy work off
  build()";
- **one-tap Markdown export** of the whole report, ready to paste into a bug
  report, PR description or ticket.

It recomputes live as calls complete and frames land. The grading is a pure,
unit-tested function you can also call yourself:

```dart
final autopsy = AppAutopsy.diagnose(
  entries: DebugLogger.instance.entries.value,
  perf: PerfMonitor.instance.stats.value,
);
print(autopsy.grade.letter); // A / B / C / D / F
print(autopsy.toMarkdown());
```

Duplicate-call detection runs automatically over `entries`. Pass
`duplicateWindow:` to change what counts as "the same call fired twice"
(default 5s). The detectors are public too, if you want them on their own:

```dart
findDuplicateApiCalls(entries);      // entry id → how many times it fired
findDuplicateCallClusters(entries);  // distinct bursts, for counting problems
```

### 🧭 Breadcrumbs from any state layer — no coupling

Want state transitions and user actions in the trail (and in the Autopsy's
context)? Drop a breadcrumb from anywhere — it's deliberately library-agnostic,
so it works with Bloc, Riverpod, Redux, provider or a plain button handler
without the package depending on your state management:

```dart
DebugTools.breadcrumb('CartBloc', 'AddItem(sku: 42)'); // from onTransition
DebugTools.breadcrumb('Tapped “Checkout”');            // from a tap handler
```

It's a no-op when the tools are disabled, so it's safe to leave in shipping code.

### 🔎 Search *inside* every request and response — and jump to the hit

The standout feature. Open any API call and each tab (Overview · Request ·
Headers · Response) carries **its own field-and-body search**. As you type:

- every match is **highlighted in place** across key/value rows *and* inside the
  pretty-printed, syntax-highlighted JSON body;
- a **results bar** lists each hit with the section it lives in (e.g.
  `Response body`) and a snippet;
- **prev / next chevrons** (or tapping a result) **scroll straight to that exact
  field or line** and ring it — so finding one token in a 2,000-line payload is
  one tap, not a manual scroll.

No more copying a body into another editor just to `Ctrl-F` it.

### 🧠 Insight at a glance

Open a call and auto-derived **insight chips** call out what matters —
`SLOW · 1480ms`, `SERVER 500`, `NOT MODIFIED · CACHED`, `LARGE · 1.2MB`,
`UNAUTHORIZED` — so you read the verdict before the numbers. In the list,
**latency is colour-banded** (green → amber → red) and oversized payloads are
flagged, so the problem call is obvious without opening anything.

### 🪪 Duplicate-call detection

The inspector flags requests that fire **identical method + path + params + body
within 5 s** of each other (a classic double-tap / rebuild bug), badges each row
with the cluster size, and shows a warning bar with the count.

### 📤 One-tap export

Copy any call as **cURL**, a flat **JSON** dump, or a **HAR 1.2** archive you can
drop into browser devtools or any HAR viewer — ready to paste into a bug report.

Or export the **whole session** from the header: a Markdown bug report leading
with the grade, the environment, what failed and the trail that led there; a HAR
archive of every request; or just the Autopsy. Callable directly too:

```dart
SessionExport.toMarkdown(
  entries: DebugLogger.instance.entries.value,
  perf: PerfMonitor.instance.stats.value,
);
SessionExport.toHar(entries: DebugLogger.instance.entries.value);
```

### 🔬 Filter down to the one call that matters

Beyond the tabs, the filter button opens type (**API / Errors / Events**), status
band (**2xx…5xx**, plus **Failed** for calls that never got a response), HTTP
method, and pinned-only. It badges how many filters are on, and previews the
match count before you apply — so a filtered-empty list never masquerades as
"no logs".

**Events** are your breadcrumbs; **pinned** rows are exempt from the 200-entry
eviction, so the call you're investigating can't scroll out of existence while
you read it. Long-press any row to pin.

### 💾 Survive the crash that lost your log

The buffer lives in memory, so the run that died takes its evidence with it.
Opt in and the session's tail is written to disk for the next launch to restore:

```dart
DebugTools.init(enabled: true, persistSession: true);
```

Off by default — it writes request and response bodies to disk, which is a call
your app should make knowingly. Writes are debounced and bounded (60 entries),
consumed on restore so they can't resurface a third time, and a no-op on web.
No new dependency: it uses `dart:io` behind a conditional import, keeping `dio`
the package's only dependency.

### 🧭 Keeps your place

Minimise to the app and the viewer is preserved exactly — filter tab, search
text, the open API detail, its tab, and every scroll offset all survive the
round-trip. **Close** resets to the start; **minimise** picks up where you left
off.

### ⚡ Zero cost when off

`DebugTools.enabled == false` short-circuits the logger, interceptor, perf
monitor, route observer and overlay to no-ops, and `DebugToolsHost` becomes a
transparent pass-through — no debug widgets or listeners exist in the tree in
production.

## Install

```yaml
# pubspec.yaml
dependencies:
  debug_deck:
    path: packages/debug_deck
```

## Integrate (4 touch-points)

### 1. Initialise once in `main()`

Gate it on your own dev/staging flag and feed it your app facts:

```dart
DebugTools.init(
  enabled: EnvironmentConfig.isDevelopment,
  appInfo: DebugAppInfo(
    version: AppConstants.versionNumber,
    environmentName: EnvironmentConfig.environmentName,
    baseUrl: ApiEndpoint.baseURL,
    isNativeCall: AppConstants.isNativeCall,
  ),
);
```

`init` also installs Flutter/platform error capture, starts the perf monitor,
and stamps app-start time — but only when `enabled` is true.

#### Secrets are masked by default

Because the cURL / JSON / HAR exports are meant to be pasted into a bug report
or a PR, credentials are masked **at capture time** — a raw token never enters
the log buffer, so it can't leak through an export, a screenshot of the Headers
tab, or a surface added later.

```
Authorization: Bearer ••••4f2a      # scheme kept, 4-char tail kept
```

Keeping the scheme means a `Basic`-where-you-expected-`Bearer` bug is still
visible, and the tail is enough to tell two tokens apart or confirm the app is
sending the one you expect. Values shorter than 12 characters are masked
entirely, since revealing 4 of 8 characters gives away too much.

The default set covers `authorization`, `cookie` / `set-cookie`, `x-api-key`,
`access_token`, `refresh_token`, CSRF tokens and similar, matched
case-insensitively across headers **and** query parameters. Add your own names,
or unmask one that's inert in your API:

```dart
DebugTools.init(
  enabled: true,
  redaction: DebugRedaction.standard(
    also: {'x-tenant-signature'},
    except: {'x-csrf-token'},
  ),
);
```

#### Letting the user decide

Sometimes you genuinely need to read the token. `RedactionMode` makes the
trade-off explicit, because **a secret you can reveal later is a secret that is
still in memory**:

| Mode | Stored | Shown | Revealable |
|---|---|---|---|
| `drop` *(default)* | masked only | masked | no — the raw value is gone |
| `hide` | raw | masked | yes — eye toggle in the Headers view |
| `off` | raw | raw | n/a |

```dart
DebugTools.init(
  enabled: true,
  redaction: DebugRedaction.standard(mode: RedactionMode.hide),
);
```

Under `hide`, the API detail header grows an eye button. Tapping it swaps every
surface at once — headers, query params, cURL, JSON and HAR — so an export can
never carry a value the screen says is hidden. It resets to hidden on every
launch, so revealing is always a deliberate act rather than a state you forgot
you left on. Under `drop` the button isn't shown at all, since a toggle that
silently does nothing is worse than no toggle.

`DebugRedaction.disabled` (`mode: off`) turns masking off entirely — only
sensible for a local session you aren't going to export or screenshot.

### 2. Mount the overlay

```dart
MaterialApp.router(
  builder: (context, child) =>
      DebugToolsHost(child: child ?? const SizedBox.shrink()),
  // ...
);
```

`DebugToolsHost` is a transparent pass-through when disabled — no debug
widgets, controllers or listeners exist in the tree in production.

### 3. Capture network traffic

```dart
dio.interceptors.add(DebugTools.dioInterceptor());
```

### 4. Track the current screen (optional, powers the Perf banner)

```dart
GoRouter(
  observers: [
    if (DebugTools.enabled) DebugTools.routeObserver,
  ],
  // ...
);
```

## The master switch

`DebugTools.enabled` is the single source of truth. When false, the logger,
interceptor, perf monitor, route observer and overlay all short-circuit to
no-ops. Flip it from any signal you like (build mode, env, remote flag).

## Decoupling

The package never imports the host app. The only thing it needs from the app is
the four `DebugAppInfo` values, passed in via `init`. That keeps it reusable
across projects — drop the folder in, add the path dependency, wire the four
touch-points.
