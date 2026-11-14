part of '../home_screen.dart';
 
// ── Simple data class for menu items ─────────────────────────────
/// Renders a count, capping anything over 99 as "99+" with a dotted
/// underline, and revealing the exact number in a tooltip on tap.
///
/// Shared by all four numeric displays on the profile page — the three
/// Lifetime Stats blocks and every "This Month's Top Categories" count — so
/// the cap rule lives in exactly one place rather than being re-decided per
/// field. Three-digit values are real here, not an edge case: Century Lifter
/// is 100 workouts and Century Club is a 100-day streak, and buddy counts can
/// pass 99 on a well-connected account.
///
/// The 44x44 minimum tap target is reserved for EVERY value, not just capped
/// ones, so a row's height never depends on whether its number happened to
/// cross 99 — otherwise a card with one capped and one uncapped stat would
/// render them at different heights.
// Public (not _CappedCount) for the same reason resolveStatusSlot/StatusSlot
// are: this file's widget tests reach it directly, and Dart privacy is
// library-level so a private class is untestable from test/.
class CappedCount extends StatefulWidget {
  const CappedCount({super.key, required this.value, required this.style});

  final int value;
  final TextStyle style;

  static const int cap = 99;

  @override
  State<CappedCount> createState() => _CappedCountState();
}

class _CappedCountState extends State<CappedCount> {
  OverlayEntry? _entry;

  @override
  void dispose() {
    // The entry lives in the Overlay, not in this subtree, so it does not go
    // away with the widget — it has to be removed by hand or it outlives the
    // page (e.g. tapping a value then navigating away).
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  void _showOverlay() {
    // Re-entrancy guard, not a toggle the user can reach: while the bubble is
    // open its full-screen catcher sits above this widget and takes the tap
    // first, so a second tap on the value closes it via onDismiss. This only
    // stops a second entry ever being inserted.
    if (_entry != null) {
      _removeOverlay();
      return;
    }

    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.maybeOf(context);
    final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || overlayBox == null) return;

    // Anchor in overlay coordinates: the top and bottom edges of the 44x44
    // tap target, plus its horizontal centre.
    final top = box.localToGlobal(Offset(box.size.width / 2, 0),
        ancestor: overlayBox);
    final bottom = box.localToGlobal(
        Offset(box.size.width / 2, box.size.height),
        ancestor: overlayBox);

    _entry = OverlayEntry(
      builder: (_) => _CappedCountBubble(
        value: widget.value,
        anchorX: top.dx,
        anchorTop: top.dy,
        anchorBottom: bottom.dy,
        overlaySize: overlayBox.size,
        onDismiss: _removeOverlay,
      ),
    );
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    final capped = widget.value > CappedCount.cap;

    final label = Text(
      capped ? '${CappedCount.cap}+' : '${widget.value}',
      textAlign: TextAlign.center,
      style: capped
          ? widget.style.copyWith(
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
              decorationColor: widget.style.color?.withValues(alpha: 0.6),
            )
          : widget.style,
    );

    final target = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      child: Center(child: label),
    );

    if (!capped) return target;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _showOverlay,
      child: target,
    );
  }
}

/// The themed bubble [CappedCount] puts in the Overlay, replacing the
/// framework Tooltip it used to use.
///
/// Same OverlayEntry approach as LiveEventToast (the app's existing custom
/// overlay), but dismissal is a tap rather than a timer: a full-screen
/// transparent catcher sits behind the bubble, so a tap anywhere outside
/// removes it immediately. There is no auto-dismiss duration at all.
class _CappedCountBubble extends StatelessWidget {
  const _CappedCountBubble({
    required this.value,
    required this.anchorX,
    required this.anchorTop,
    required this.anchorBottom,
    required this.overlaySize,
    required this.onDismiss,
  });

  final int value;
  final double anchorX;
  final double anchorTop;
  final double anchorBottom;
  final Size overlaySize;
  final VoidCallback onDismiss;

  static const double _tailW = 12;
  static const double _tailH = 6;
  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final bg = appColors.cardBackground;

    // Sits above the value by default; flips below only when there is not
    // enough room above, so a value scrolled near the top still shows.
    final below = anchorTop < 96;

    // Fractional alignment rather than an absolute left offset: inside a
    // full-width band, Alignment(-1) puts the child's LEFT edge at the screen
    // edge and Alignment(1) its RIGHT edge, so a wide bubble near an edge is
    // clamped on-screen for free. The tail is only 12px wide, so the same
    // fraction still lands it essentially on the value itself.
    final fx = ((anchorX / overlaySize.width) * 2 - 1).clamp(-1.0, 1.0);

    final bubble = Align(
      alignment: Alignment(fx, 0),
      heightFactor: 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          // The cards underneath use this same cardBackground token, so
          // without an outline the bubble melts into whichever card it
          // happens to cover.
          border: Border.all(color: appColors.cardBorder),
          boxShadow: appColors.clayShadow(),
        ),
        child: Text(
          '$value',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: appColors.readableForeground(bg),
          ),
        ),
      ),
    );

    final tail = Align(
      alignment: Alignment(fx, 0),
      heightFactor: 1,
      child: CustomPaint(
        size: const Size(_tailW, _tailH),
        painter: _BubbleTailPainter(color: bg, pointingDown: !below),
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Tap-away catcher. Behind the bubble in paint order, so taps on the
          // bubble itself are absorbed by it and do not dismiss.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            // Anchoring the BOTTOM of the column to the value's top edge means
            // the bubble stacks upward without needing to know its height.
            top: below ? anchorBottom + _gap : null,
            bottom: below ? null : overlaySize.height - anchorTop + _gap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: below ? [tail, bubble] : [bubble, tail],
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({required this.color, required this.pointingDown});

  final Color color;
  final bool pointingDown;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointingDown) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width / 2, size.height);
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width / 2, 0);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BubbleTailPainter old) =>
      old.color != color || old.pointingDown != pointingDown;
}
