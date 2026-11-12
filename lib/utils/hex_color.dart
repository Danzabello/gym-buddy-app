import 'package:flutter/material.dart';

/// `#RRGGBB` or `RRGGBB` as an opaque colour. A malformed value (a bad
/// `shop_items.color_hex` row) gives transparent instead of throwing in build.
Color hexToColor(String hex) {
  final rgb = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return rgb == null ? Colors.transparent : Color(0xFF000000 | rgb);
}
