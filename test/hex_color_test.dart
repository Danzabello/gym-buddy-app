import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/utils/hex_color.dart';

void main() {
  test('hexToColor parses with and without the hash', () {
    expect(hexToColor('#50C878'), const Color(0xFF50C878));
    expect(hexToColor('50c878'), const Color(0xFF50C878));
  });

  test('hexToColor gives transparent for a malformed value', () {
    expect(hexToColor('not-a-colour'), Colors.transparent);
    expect(hexToColor(''), Colors.transparent);
  });
}
