part of '../home_screen.dart';

// ═══════════════════════════════════════════════════════════════
// STREAK SORT: the four sorts, their colours, what is saved, and the sheet
// ═══════════════════════════════════════════════════════════════

/// One soft colour per sort (owner spec, 2026-11-21). Raw hex on purpose, the
/// same exception as the weekly plan tier colours: they are not theme colours.
/// Everything else in the sheet comes from the theme.
extension StreakSortColor on StreakSortMode {
  Color get color {
    switch (this) {
      case StreakSortMode.highestCurrent:
        return const Color(0xFF6FCF97);
      case StreakSortMode.mostWorkouts:
        return const Color(0xFFE8A56A);
      case StreakSortMode.bestAllTime:
        return const Color(0xFFE3C76B);
      case StreakSortMode.custom:
        return const Color(0xFF9C8FD6);
    }
  }
}

/// The one failure colour: a muted coral (owner spec, 2026-11-21), for the
/// sheet's failure line and the Custom save failure toast. Raw hex on purpose,
/// like the four sort colours, and not one of them.
const Color kStreakSortFailColor = Color(0xFFE5837A);

/// How many friends the dashboard's wheel draws (Coach Max has his own slot
/// besides). The wheel and [streakSortChangesOrder] both read this.
const int kWheelFriendSlots = 4;

/// The real text of the long-press info dialog, per sort.
extension StreakSortInfo on StreakSortMode {
  String get longDescription {
    switch (this) {
      case StreakSortMode.highestCurrent:
        return 'Shows buddies with the longest active streak first. '
            'This highlights who you\'re currently working out with most consistently.';
      case StreakSortMode.mostWorkouts:
        return 'Ranks buddies by total number of workouts completed together. '
            'Perfect for seeing your most dedicated long-term partners.';
      case StreakSortMode.bestAllTime:
        return 'Displays buddies based on your all-time best streak together. '
            'Shows legendary partnerships even if the streak has broken.';
      case StreakSortMode.custom:
        return 'Pick your own buddies and the order they appear in. Tap Custom to set it up.';
    }
  }

  String get example {
    switch (this) {
      case StreakSortMode.highestCurrent:
        return 'Example: Sarah (15 days) appears before Mike (8 days)';
      case StreakSortMode.mostWorkouts:
        return 'Example: Mike (124 workouts) appears before Sarah (89 workouts)';
      case StreakSortMode.bestAllTime:
        return 'Example: Sarah (best: 45 days) appears before Mike (best: 32 days)';
      case StreakSortMode.custom:
        return 'You choose Riley first, then Sam, then Alex, and that is the order you see.';
    }
  }
}

/// A saved value read back: one of the four, else Highest Streak (null, an old
/// "mostRecent" or "favorites", anything unknown).
@visibleForTesting
StreakSortMode parseStreakSort(Object? raw) => StreakSortMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => StreakSortMode.highestCurrent,
    );

/// Whether switching the sort from [from] to [to] changes what the wheel
/// draws: the first [kWheelFriendSlots] friend streaks, in order. A difference
/// only below those slots is not a change. Coach Max is not in that list:
/// [sortStreaks] leaves him out, and so does the Custom branch of the wheel.
/// When what is drawn is the same there is nothing on the dashboard to redraw.
@visibleForTesting
bool streakSortChangesOrder(List<TeamStreak> streaks, StreakSortMode from, StreakSortMode to) {
  if (from == to) return false;
  List<String> order(StreakSortMode mode) => (mode == StreakSortMode.custom
          ? streaks.where((s) => !s.isCoachMaxTeam).toList() // custom keeps the stored order
          : sortStreaks(streaks, mode))
      .take(kWheelFriendSlots)
      .map((s) => s.teamId)
      .toList();
  return !listEquals(order(from), order(to));
}

/// The line under the grid, from state alone: [shown] against [saved]. While
/// the saved value is not known (the read has not answered) there is nothing
/// to say until a save has failed: then only that, with no "will open on" part.
@visibleForTesting
String? streakSortStatus({
  required StreakSortMode shown,
  required StreakSortMode? saved,
  bool failed = false,
}) {
  if (saved == null) {
    return failed ? "Couldn't save. Showing ${shown.displayName} for now." : null;
  }
  if (shown == saved) {
    return 'Remembered. The app will open on ${shown.displayName} next time.';
  }
  return "Couldn't save. Showing ${shown.displayName} for now. "
      'The app will open on ${saved.displayName} next time.';
}

/// The sort on screen and the sort saved, and the saving between them.
/// Tapping applies at once; the write comes after and never holds the screen.
@visibleForTesting
class StreakSortController extends ChangeNotifier {
  StreakSortController({
    required this.write,
    void Function(Object, StackTrace?, String)? report,
    this.slowAfter = const Duration(milliseconds: 600),
  }) : _report = report ?? reportNonFatal;

  /// How long the newest save may be out before the line says "Saving...".
  final Duration slowAfter;

  /// Saves the sort (and, for Custom, its order). Throws when it fails.
  final Future<void> Function(StreakSortMode mode, List<String>? customOrder) write;
  final void Function(Object, StackTrace?, String) _report;

  StreakSortMode _shown = StreakSortMode.highestCurrent;
  StreakSortMode? _saved; // null until the server has answered
  bool _touched = false; // the user chose a sort this session
  int _seq = 0; // the newest save; an older one's result is ignored
  int _pending = 0;
  bool _failed = false; // the newest save failed; a later success clears it
  bool _saving = false; // the newest save is out
  bool _slow = false; // ... and has been out longer than [slowAfter]
  Timer? _slowTimer;
  // What the line said when the first save of a run started: it keeps saying
  // that while saves are out, so a save in flight never reads as a failure.
  ({StreakSortMode shown, StreakSortMode? saved, bool failed})? _before;

  StreakSortMode get shown => _shown;

  /// What the app opens on next time, as far as it is known.
  StreakSortMode? get saved => _saved;

  /// The newest save failed. Matters when [saved] is unknown: then there is no
  /// saved sort to compare the shown one with.
  bool get failed => _failed;

  /// The newest save is out.
  bool get saving => _saving;

  /// The line under the grid. While a save is out it keeps the text it had
  /// before (never "Couldn't save" or the new "Remembered" yet); after
  /// [slowAfter] it says "Saving..."; then the result. Null when there is
  /// nothing to say.
  String? get statusLine {
    if (_saving) {
      if (_slow) return 'Saving...';
      final b = _before!;
      return streakSortStatus(shown: b.shown, saved: b.saved, failed: b.failed);
    }
    return streakSortStatus(shown: _shown, saved: _saved, failed: _failed);
  }

  /// Whether [statusLine] is a failure (coral). "Saving..." never is.
  bool get statusIsFailure {
    if (_saving) {
      if (_slow) return false;
      final b = _before!;
      return b.saved == null ? b.failed : b.saved != b.shown;
    }
    return _saved == null ? _failed : _saved != _shown;
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  /// The first paint from the saved copy: what is shown, not what is saved.
  void paint(Object? raw) {
    if (_touched) return;
    _shown = parseStreakSort(raw);
    notifyListeners();
  }

  /// The server answered with [raw]. Nothing is written back, whatever it is:
  /// an unknown value shows Highest Streak and stays as it is on the server.
  /// After a tap this session the user's pick stays and this is ignored.
  void loaded(Object? raw) {
    if (_touched) return;
    _shown = _saved = parseStreakSort(raw);
    notifyListeners();
  }

  /// A tap (or, for Custom, the picker's Save with [customOrder]). Returns
  /// whether it was saved. The sort shows at once and stays on screen if the
  /// save fails; the saved value then stays as it was.
  Future<bool> choose(StreakSortMode mode, {List<String>? customOrder}) async {
    final before = (shown: _shown, saved: _saved, failed: _failed);
    _touched = true;
    if (_shown != mode) {
      _shown = mode;
      notifyListeners(); // on screen before anything is written
    }
    // The same as saved needs no write, unless a save of another sort is still
    // out: then this tap has to win over it.
    if (mode == _saved && customOrder == null && _pending == 0) {
      if (_failed) {
        _failed = false;
        notifyListeners();
      }
      return true;
    }

    final seq = ++_seq;
    _pending++;
    // This save is now the newest: it replaces the pending state, and "Saving..."
    // waits [slowAfter] from here.
    if (!_saving) _before = before;
    _saving = true;
    _slow = false;
    _slowTimer?.cancel();
    _slowTimer = Timer(slowAfter, () {
      if (_saving && seq == _seq) {
        _slow = true;
        notifyListeners();
      }
    });
    notifyListeners();
    try {
      await write(mode, customOrder);
    } catch (e, st) {
      _pending--;
      if (isReportableError(e)) _report(e, st, 'streak_sort_save');
      if (seq == _seq) {
        // The newest save failed; an older one failing changes nothing.
        _saving = false;
        _slowTimer?.cancel();
        _failed = true;
        notifyListeners();
      }
      return false;
    }
    _pending--;
    if (seq != _seq) return true; // a newer tap came after this one: its result decides
    _saving = false;
    _slowTimer?.cancel();
    _saved = mode;
    _failed = false;
    notifyListeners();
    return true;
  }
}

/// The toast after the Custom picker's Save. The same look either way: green
/// with a check when it was saved, coral and no check when it was not, for
/// whatever reason (the network being down included: the user needs to know).
@visibleForTesting
SnackBar customOrderSnackBar({required bool saved, required AppColors colors}) {
  return SnackBar(
    content: Row(
      children: [
        if (saved) ...[
          const Icon(Icons.check_circle, color: Colors.white),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Text(
            saved ? 'Custom order saved!' : "Couldn't save your Custom order.",
            overflow: TextOverflow.ellipsis,
            style: saved
                ? null
                : TextStyle(color: colors.readableForeground(kStreakSortFailColor)),
          ),
        ),
      ],
    ),
    backgroundColor: saved ? Colors.green[600] : kStreakSortFailColor,
    duration: const Duration(seconds: 3),
  );
}

/// The sheet: four cards, a status line, no Save button. Tap applies.
@visibleForTesting
class StreakSortSheet extends StatelessWidget {
  const StreakSortSheet({
    super.key,
    required this.controller,
    required this.onPick,
    required this.onCustom,
  });

  final StreakSortController controller;
  final void Function(StreakSortMode mode) onPick;

  /// Custom has its own picker: it is saved when that picker is saved.
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final slow = MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 160);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final shown = controller.shown;
        final status = controller.statusLine;
        final failed = controller.statusIsFailure;
        final tint = failed ? kStreakSortFailColor : shown.color;

        Widget row(StreakSortMode a, StreakSortMode b) => IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _card(context, a, a == shown, appColors, cs, slow)),
                  const SizedBox(width: 10),
                  Expanded(child: _card(context, b, b == shown, appColors, cs, slow)),
                ],
              ),
            );

        const modes = StreakSortMode.values;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: ColoredBox(
            color: appColors.cardBackground,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The sheet's top border follows the selected sort.
                AnimatedContainer(
                  key: const ValueKey('streak_sort_top_border'),
                  duration: slow,
                  height: 3,
                  color: shown.color,
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                        20, 18, 20, MediaQuery.paddingOf(context).bottom + 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Sort Your Streaks',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tap to select · Long-press for info',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: appColors.subtleText),
                        ),
                        const SizedBox(height: 18),
                        row(modes[0], modes[1]),
                        const SizedBox(height: 10),
                        row(modes[2], modes[3]),
                        if (status != null) ...[
                          const SizedBox(height: 14),
                          // A live region, so a screen reader hears it change.
                          Semantics(
                            liveRegion: true,
                            container: true,
                            child: AnimatedContainer(
                              key: const ValueKey('streak_sort_status'),
                              duration: slow,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: tint.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: tint, width: 1.5),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(fontSize: 14, height: 1.35, color: cs.onSurface),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _card(BuildContext context, StreakSortMode mode, bool selected, AppColors appColors,
      ColorScheme cs, Duration slow) {
    final color = mode.color;
    return Semantics(
      button: true,
      selected: selected,
      label: '${mode.displayName}. ${mode.description}',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('streak_sort_card_${mode.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          if (mode == StreakSortMode.custom) {
            onCustom();
          } else {
            onPick(mode);
          }
        },
        // A long press shows the info and does not select.
        onLongPress: () {
          HapticFeedback.mediumImpact();
          showDialog<void>(context: context, builder: (_) => StreakSortInfoDialog(mode: mode));
        },
        child: AnimatedContainer(
          duration: slow,
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: selected ? 0.22 : 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? color : color.withValues(alpha: 0.33), width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mode.displayName,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: selected ? cs.onSurface : color),
              ),
              const SizedBox(height: 4),
              Text(
                mode.description,
                style: TextStyle(
                    fontSize: 12,
                    color: selected ? cs.onSurface.withValues(alpha: 0.85) : appColors.subtleText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The long-press dialog: text only.
@visibleForTesting
class StreakSortInfoDialog extends StatelessWidget {
  const StreakSortInfoDialog({super.key, required this.mode});
  final StreakSortMode mode;

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final color = mode.color;
    // The box is labelled EXAMPLE, so a leading "Example: " is not said twice.
    final example = mode.example.replaceFirst(RegExp(r'^Example:\s*'), '');

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: appColors.cardBackground,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color, width: 2),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                mode.displayName,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                mode.longDescription,
                style: TextStyle(
                    fontSize: 15, height: 1.55, color: cs.onSurface.withValues(alpha: 0.85)),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withValues(alpha: 0.33)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EXAMPLE',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          color: color),
                    ),
                    const SizedBox(height: 6),
                    Text(example, style: TextStyle(fontSize: 14, color: cs.onSurface)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Semantics(
                button: true,
                label: 'Got it',
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey('streak_sort_got_it'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration:
                        BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
                    child: Text(
                      'Got it',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: appColors.readableForeground(color)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sort button on the streaks screen: tinted in the selected sort's colour
/// with a 2 px border in it.
@visibleForTesting
class StreakSortButton extends StatelessWidget {
  const StreakSortButton({super.key, required this.controller, required this.onTap});
  final StreakSortController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final slow = MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 160);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final color = controller.shown.color;
        return GestureDetector(
          onTap: onTap,
          child: Tooltip(
            message: 'Sort streaks, ${controller.shown.displayName}',
            child: AnimatedContainer(
              key: const ValueKey('streak_sort_button'),
              duration: slow,
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.14),
                border: Border.all(color: color, width: 2),
              ),
              child: Icon(Icons.tune_rounded, color: color, size: 22),
            ),
          ),
        );
      },
    );
  }
}
