import 'package:flutter/material.dart';

/// Shared avatar data — mirrors the starter/earnable lists baked into
/// AvatarPickerScreen (lib/widgets/avatar_picker_screen.dart), duplicated
/// here so the Wardrobe screens can render the same catalog without
/// touching that file (its onboarding usage must stay byte-for-byte as-is).
class AvatarCatalogEntry {
  final String id;
  final String emoji;
  final String name;
  final Color color;
  final Color borderColor;
  final bool isStarter;
  final String? unlockReq;

  const AvatarCatalogEntry({
    required this.id,
    required this.emoji,
    required this.name,
    required this.color,
    required this.borderColor,
    required this.isStarter,
    this.unlockReq,
  });
}

const List<AvatarCatalogEntry> avatarCatalog = [
  AvatarCatalogEntry(
    id: 'lion', emoji: '🦁', name: 'Lion',
    color: Color(0xFFD85A30), borderColor: Color(0xFFC07010), isStarter: true,
  ),
  AvatarCatalogEntry(
    id: 'wolf', emoji: '🐺', name: 'Wolf',
    color: Color(0xFF185FA5), borderColor: Color(0xFF5889B7), isStarter: true,
  ),
  AvatarCatalogEntry(
    id: 'bear', emoji: '🐻', name: 'Bear',
    color: Color(0xFF0F6E56), borderColor: Color(0xFF108B6C), isStarter: true,
  ),
  AvatarCatalogEntry(
    id: 'eagle', emoji: '🦅', name: 'Eagle',
    color: Color(0xFF185FA5), borderColor: Color(0xFF5889B7), isStarter: false,
    unlockReq: '30-day streak',
  ),
  AvatarCatalogEntry(
    id: 'shark', emoji: '🦈', name: 'Shark',
    color: Color(0xFF185FA5), borderColor: Color(0xFF5889B7), isStarter: false,
    unlockReq: '60-day streak',
  ),
  AvatarCatalogEntry(
    id: 'gorilla', emoji: '🦍', name: 'Gorilla',
    color: Color(0xFF0F6E56), borderColor: Color(0xFF108B6C), isStarter: false,
    unlockReq: '100-day streak',
  ),
  AvatarCatalogEntry(
    id: 'tiger', emoji: '🐯', name: 'Tiger',
    color: Color(0xFFD85A30), borderColor: Color(0xFFC07010), isStarter: false,
    unlockReq: '50 co-ops',
  ),
  AvatarCatalogEntry(
    id: 'buffalo', emoji: '🦬', name: 'Buffalo',
    color: Color(0xFF0F6E56), borderColor: Color(0xFF108B6C), isStarter: false,
    unlockReq: 'Level 5',
  ),
  AvatarCatalogEntry(
    id: 'robot', emoji: '🤖', name: 'Robot',
    color: Color(0xFF185FA5), borderColor: Color(0xFF5889B7), isStarter: false,
    unlockReq: 'Level 10',
  ),
  AvatarCatalogEntry(
    id: 'flexed', emoji: '💪', name: 'Flex',
    color: Color(0xFFD85A30), borderColor: Color(0xFFC07010), isStarter: false,
    unlockReq: '90-day streak',
  ),
  AvatarCatalogEntry(
    id: 'weightlifter', emoji: '🏋️', name: 'Lifter',
    color: Color(0xFF0F6E56), borderColor: Color(0xFF108B6C), isStarter: false,
    unlockReq: '100 co-ops',
  ),
  AvatarCatalogEntry(
    id: 'runner', emoji: '🏃', name: 'Runner',
    color: Color(0xFF185FA5), borderColor: Color(0xFF5889B7), isStarter: false,
    unlockReq: '150 co-ops',
  ),
];

AvatarCatalogEntry avatarCatalogById(String id) =>
    avatarCatalog.firstWhere((a) => a.id == id, orElse: () => avatarCatalog.first);
