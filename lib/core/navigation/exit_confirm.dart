/// The "press back again to exit" window.
///
/// Static rather than injected because it is genuinely app-global: the shell
/// and any screen with nowhere to go up to share one window, and two
/// implementations of it would drift. `now` is injectable so the window is
/// testable without real waiting, and [reset] exists so tests start clean.
class PgExitConfirm {
  PgExitConfirm._();

  static const Duration window = Duration(seconds: 2);

  static DateTime? _lastPress;

  /// Records a back press. Returns true when the app should exit — i.e. this
  /// is the second press inside [window].
  static bool press({DateTime? now}) {
    final at = now ?? DateTime.now();
    final last = _lastPress;
    _lastPress = at;
    return last != null && at.difference(last) < window;
  }

  static void reset() => _lastPress = null;
}
