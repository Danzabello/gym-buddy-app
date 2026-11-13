import 'package:flutter/material.dart';

/// `#RRGGBB` or `RRGGBB` as an opaque colour. A malformed value (a bad
/// `shop_items.color_hex` row) gives transparent instead of throwing in build.
Color hexToColor(String hex) {
  final digits = hex.replaceFirst('#', '');
  final rgb = digits.length == 6 ? int.tryParse(digits, radix: 16) : null;
  return rgb == null || rgb < 0 ? Colors.transparent : Color(0xFF000000 | rgb);
}
