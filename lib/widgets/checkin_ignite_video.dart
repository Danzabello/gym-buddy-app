import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Plays the bundled check-in ignite clip once, circle-clipped, then holds the
/// final frame and calls [onComplete]. [CheckinIgniteVideoState.skip] jumps
/// straight to that final frame (reach it through a GlobalKey).
///
/// KNOWN LIMITATION (accepted tradeoff, not an oversight): the ring is baked
/// into the mp4 as a fixed yellow-orange. It does NOT follow the accent skin
/// (Emerald Ink's green avatarRing, Signal Blue, Lime Spark). Revisit during
/// the per-theme polish pass — needs per-skin renders or a painted ring.
///
/// Reduced motion: never plays; shows the static final frame.
class CheckinIgniteVideo extends StatefulWidget {
  static const asset = 'assets/animations/checkin_ignite.mp4';

  final double size;
  final VoidCallback? onComplete;

  const CheckinIgniteVideo({super.key, required this.size, this.onComplete});

  @override
  State<CheckinIgniteVideo> createState() => CheckinIgniteVideoState();
}

class CheckinIgniteVideoState extends State<CheckinIgniteVideo> {
  final _controller = VideoPlayerController.asset(CheckinIgniteVideo.asset);
  bool _started = false;
  bool _skipped = false;
  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _skipped = MediaQuery.of(context).disableAnimations;
    _start();
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
    if (_skipped) {
      await _showFinalFrame();
    } else {
      await _controller.play();
    }
  }

  /// Jump to the final frame and hold it. Safe before init completes.
  void skip() {
    if (_skipped) return;
    _skipped = true;
    if (_controller.value.isInitialized) _showFinalFrame();
  }

  Future<void> _showFinalFrame() async {
    await _controller.pause();
    await _controller.seekTo(_controller.value.duration);
    _finish();
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
