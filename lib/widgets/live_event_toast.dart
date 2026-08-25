import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../theme/accent_theme_provider.dart';

/// Lets context-less singletons (NotificationService) reach an Overlay so a
/// toast can render above whatever page is on screen. Wired to MaterialApp in
/// main.dart. Declared here rather than main.dart because notification_service
/// imports this file — importing main.dart back would be a cycle.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Clay-surface slide-down toast: 450ms ease-out entrance, auto-dismiss on a
/// draining progress line, swipe-up to dismiss early.
///
/// Two callers, deliberately kept separate:
///  * the dashboard's realtime check-in banner (buddy avatar + accent name),
///    driven by the daily_team_checkins Postgres subscription;
///  * every foreground FCM push, via [show] — generic title/body, rendered in
///    the navigator overlay so it appears on any screen.
class LiveEventToast {
  // ── buddy_checked_in de-duplication ──────────────────────────────────────
  // A buddy check-in fires BOTH paths: the Realtime INSERT the dashboard
  // listens to, and a `buddy_checked_in` push (trigger notify_buddy_checkin,
  // migration 20260627155120, targets the same other team member). These two
  // flags say whether the dashboard's own banner will actually be *visible*
  // for it — if so, the push toast stands down instead of stacking a second
  // banner. Off the dashboard tab, or with the banner setting disabled, the
  // dashboard shows nothing, so the generic toast takes over.
  static bool dashboardTabActive = false;
  static bool dashboardCheckInBannerEnabled = true;

  static bool get dashboardOwnsCheckIns =>
      dashboardTabActive && dashboardCheckInBannerEnabled;

  /// Emoji for a push's `data['type']`. Types come from the categoryMap in
  /// supabase/functions/send-notification/index.ts.
  static String iconForType(String? type) {
    switch (type) {
      case 'friend_request':
      case 'friend_accepted':
        return '👋';
      case 'workout_invite':
      case 'workout_accepted':
      case 'workout_declined':
      case 'workout_starting_soon':
      case 'buddy_started_workout':
      case 'join_window_expiring':
        return '🏋️';
      case 'buddy_checked_in':
      case 'streak_complete':
      case 'streak_milestone':
      case 'streak_danger':
      case 'streak_broken':
      case 'buddy_nudge':
        return '🔥';
      case 'break_day_taken':
        return '🛡';
      case 'coach_max_checked_in':
      case 'coach_max_motivational':
        return '🤖';
      default:
        return '🔔';
    }
  }

  /// Shows a toast in the navigator overlay — works from any screen, and from
  /// callers with no BuildContext. No-op if no overlay is mounted yet.
  static void show({
    required String title,
    String? subtitle,
    String icon = '🔔',
  }) {
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => LiveEventToastCard(
        leading: Text(icon, style: const TextStyle(fontSize: 26)),
        title: title,
        subtitle: subtitle,
        onDismissed: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

/// The card itself. Used directly by the dashboard (which renders it inside its
/// own Stack with a buddy avatar) and by [LiveEventToast.show] via an overlay.
class LiveEventToastCard extends StatefulWidget {
  /// Avatar or emoji shown at the left edge.
  final Widget leading;

  /// Rendered in the accent colour, immediately before [title]. Used for the
  /// buddy's name on the check-in banner; null for generic pushes.
  final String? accentPrefix;
  final String title;
  final String? subtitle;
  final VoidCallback onDismissed;

  const LiveEventToastCard({
    super.key,
    required this.leading,
    this.accentPrefix,
    required this.title,
    this.subtitle,
    required this.onDismissed,
  });

  @override
  State<LiveEventToastCard> createState() => _LiveEventToastCardState();
}

class _LiveEventToastCardState extends State<LiveEventToastCard>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<Offset> _slide;
  late final AnimationController _progress;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOut));

    // Doubles as the auto-dismiss timer and the bottom progress line's
    // driver, so the line always reflects the real time left.
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _dismiss();
      });

    _entrance.forward();
    _progress.forward();
  }

  void _dismiss() {
    if (_dismissing) return;
    _dismissing = true;
    _progress.stop();
    _entrance.reverse().whenComplete(widget.onDismissed);
  }

  @override
  void dispose() {
    _entrance.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final accent = context.watch<AccentThemeProvider>().palette.accentIcon;
    final textColor = c.readableForeground(c.claySurface);

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _entrance,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragEnd: (details) {
                  if ((details.primaryVelocity ?? 0) < -100) _dismiss();
                },
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: c.claySurface,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: c.clayShadow(),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                        child: Row(
                          children: [
                            widget.leading,
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  RichText(
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    text: TextSpan(
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      children: [
                                        if (widget.accentPrefix != null)
                                          TextSpan(
                                            text: widget.accentPrefix,
                                            style: TextStyle(color: accent),
                                          ),
                                        TextSpan(
                                          text: widget.title,
                                          style: TextStyle(color: textColor),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (widget.subtitle != null &&
                                      widget.subtitle!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.subtitle!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12, color: c.inkMuted),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _progress,
                        builder: (_, __) => LayoutBuilder(
                          builder: (context, constraints) => Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              height: 2,
                              width: constraints.maxWidth * (1 - _progress.value),
                              color: accent.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
