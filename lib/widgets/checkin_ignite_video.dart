import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Plays the bundled check-in ignite clip once, then calls [onComplete].
///
/// KNOWN LIMITATION (accepted tradeoff, not an oversight): the ring is baked
/// into the mp4 as a fixed yellow-orange. It does NOT follow the accent skin
/// (Emerald Ink's green avatarRing, Signal Blue, Lime Spark). Revisit during
/// the per-theme polish pass — needs per-skin renders or a painted ring.
///
/// Reduced motion: never plays; calls [onComplete] on the next frame so the
/// flow skips straight to what the clip leads into.
class CheckinIgniteVideo extends StatefulWidget {
  static const asset = 'assets/animations/checkin_ignite.mp4';

  final double size;
  final VoidCallback? onComplete;

  const CheckinIgniteVideo({super.key, required this.size, this.onComplete});

  /// PLACEMENT PENDING SIGN-OFF: full-screen overlay on a dark scrim; a tap
  /// anywhere (video included) skips. Completes when the clip ends (or immediately under reduced motion)
  /// so callers can show what follows, e.g. the check-in SnackBar.
  static Future<void> show(BuildContext context) async {
    if (MediaQuery.of(context).disableAnimations) return;
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Skip',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, _, __) => Center(
        child: GestureDetector(
          onTap: () => Navigator.of(dialogContext).maybePop(),
          child: CheckinIgniteVideo(
            size: MediaQuery.of(dialogContext).size.shortestSide * 0.8,
            onComplete: () => Navigator.of(dialogContext).maybePop(),
          ),
        ),
      ),
    );
  }

  @override
  State<CheckinIgniteVideo> createState() => _CheckinIgniteVideoState();
}

class _CheckinIgniteVideoState extends State<CheckinIgniteVideo> {
  final _controller = VideoPlayerController.asset(CheckinIgniteVideo.asset);
  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    } else if (!_controller.value.isInitialized) {
      _start();
    }
  }

  Future<void> _start() async {
    try {
      await _controller.initialize();
    } catch (_) {
      _finish(); // a broken asset must never block the check-in flow
      return;
    }
    if (!mounted) return;
    _controller.addListener(_onTick);
    setState(() {});
    await _controller.play();
  }

  void _onTick() {
    if (_controller.value.isCompleted) _finish();
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onComplete?.call();
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Empty box until the first frame is ready, so the layout never jumps.
    // Circle clip hides the clip's navy square on any backdrop; the ring sits
    // inside the frame, so it survives the crop.
    return SizedBox.square(
      dimension: widget.size,
      child: _controller.value.isInitialized
          ? ClipOval(child: VideoPlayer(_controller))
          : null,
    );
  }
}
