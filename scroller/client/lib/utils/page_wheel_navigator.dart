enum PageWheelAction { next, previous }

/// Maps mouse-wheel scroll deltas to discrete page steps with a short cooldown
/// so one notch advances one page instead of pixel-scrolling a full viewport.
class PageWheelNavigator {
  PageWheelNavigator({
    this.cooldown = const Duration(milliseconds: 400),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration cooldown;
  final DateTime Function() _clock;

  DateTime? _lastAcceptedAt;

  PageWheelAction? resolve(
    double scrollDeltaDy, {
    required bool canGoNext,
    required bool canGoPrevious,
  }) {
    if (scrollDeltaDy == 0) {
      return null;
    }

    final now = _clock();
    final lastAcceptedAt = _lastAcceptedAt;
    if (lastAcceptedAt != null && now.difference(lastAcceptedAt) < cooldown) {
      return null;
    }

    if (scrollDeltaDy > 0) {
      if (!canGoNext) {
        return null;
      }
      _lastAcceptedAt = now;
      return PageWheelAction.next;
    }

    if (!canGoPrevious) {
      return null;
    }
    _lastAcceptedAt = now;
    return PageWheelAction.previous;
  }
}
