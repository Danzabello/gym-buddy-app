import 'dart:async';

/// Runs one async action at a time. A call made while an earlier one is still
/// in flight is ignored, so a double tap cannot fire a write, push a page or
/// open a dialog twice. For a route push or a dialog, return the push/show
/// future from [action]: the guard then stays held until it is dismissed.
///
/// Keep one instance per State (or per shared widget) and call [dispose] from
/// its dispose(). Errors from [action] propagate unchanged.
class RunOnce {
  bool _running = false;
  bool _latched = false;
  bool _disposed = false;

  bool get isRunning => _running;

  /// Runs [action] unless one is already running (or this guard is disposed).
  /// Returns its result, or null when the call was ignored.
  Future<T?> run<T>(FutureOr<T> Function() action) async {
    if (_running || _disposed) return null;
    _running = true;
    try {
      return await action();
    } finally {
      _running = false;
    }
  }

  /// Runs [action] the first time only and never releases (not even if it
  /// throws), for a handler that closes its own sheet or dialog and then acts:
  /// a second tap during the close animation must not act again. Only use it
  /// on an instance that dies with the route, or replace the instance per open.
  Future<T?> latch<T>(FutureOr<T> Function() action) async {
    if (_latched || _disposed) return null;
    _latched = true;
    return await action();
  }

  void dispose() => _disposed = true;
}
