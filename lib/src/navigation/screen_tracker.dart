import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:debug_deck/debug_deck.dart';

/// Publishes the name of the top-most route so the debug Perf tab can label
/// *which* screen the current frame-timing numbers belong to. Added to the
/// app's GoRouter `observers`; updates as routes are pushed/popped/replaced.
class CurrentScreenObserver extends NavigatorObserver {
  CurrentScreenObserver._();
  static final CurrentScreenObserver instance = CurrentScreenObserver._();

  static final ValueNotifier<String> current = ValueNotifier<String>('—');

  void _update(Route<dynamic>? route) {
    if (!DebugTools.enabled) return;
    if (route is! PageRoute) return;
    final name = route.settings.name;
    final value =
        (name == null || name.isEmpty)
            ? '(unnamed route)'
            : (name.startsWith('/') ? name.substring(1) : name);
    if (current.value == value) return;

    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      current.value = value;
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        current.value = value;
      });
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _update(newRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(previousRoute);
}
