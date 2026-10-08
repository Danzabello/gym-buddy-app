import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/pages/notice_screens.dart';

double _ratio(Color a, Color b) {
  final l = [a.computeLuminance(), b.computeLuminance()]..sort();
  return (l[1] + 0.05) / (l[0] + 0.05);
}

void main() {
  const green = Color(0xFF10B981);
  test('darkens the green on a light card to 4.5:1', () {
    expect(_ratio(readableOn(green, Colors.white), Colors.white), greaterThanOrEqualTo(4.5));
  });
  test('leaves the green alone on a dark card', () {
    expect(readableOn(green, const Color(0xFF0B1F1A)), green);
  });
}
