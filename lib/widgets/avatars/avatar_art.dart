import 'package:flutter/widgets.dart';

import 'animated_bear.dart';

/// Art fills this share of the avatar circle. Measured: at 16/32/40 the bear's
/// ears lose < 0.02% of their pixels to a ClipOval, so no per-size shrink.
const _artRatio = 0.86;

/// The illustration for [id], sized to fit an avatar circle of [size], or null
/// when that species has no art yet (callers fall back to the emoji).
///
/// A new species is one painter file plus one `case` here.
Widget? avatarArt(String? id, {required double size, bool animate = false}) {
  switch (id) {
    case 'bear':
      return AnimatedBear(size: size * _artRatio, animate: animate);
  }
  return null;
}
