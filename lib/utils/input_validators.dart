// lib/utils/input_validators.dart
//
// Centralised input validation for Gym Buddy.
// Use these validators + formatters everywhere user text is accepted.
// OWASP Mobile Top 10 — M4 (Insufficient Input/Output Validation)

import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONSTANTS — single source of truth for all field limits
// ─────────────────────────────────────────────────────────────────────────────

class InputLimits {
  InputLimits._();

  // Auth
  static const int emailMax = 254;       // RFC 5321 hard limit
  static const int passwordMin = 8;      // raised from 6 — OWASP recommendation
  static const int passwordMax = 128;    // prevent bcrypt DoS

  // Profile
  static const int usernameMin = 3;
  static const int usernameMax = 20;
  static const int displayNameMin = 1;
  static const int displayNameMax = 40;

  // Onboarding
  static const int ageMin = 16;          // Fitness app minimum
  static const int ageMax = 120;

  // Workout
  static const int notesMax = 500;       // notes field — DB column limit
  static const int workoutNameMax = 80;

  // Search
  static const int searchMax = 50;
}

// ─────────────────────────────────────────────────────────────────────────────
// VALIDATORS — return a String error message or null on success
// ─────────────────────────────────────────────────────────────────────────────

class InputValidators {
  InputValidators._();

  // ── Email ─────────────────────────────────────────────────────────────────

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    if (v.length > InputLimits.emailMax) {
      return 'Email is too long (max ${InputLimits.emailMax} characters)';
    }
    // Basic structural check — Supabase validates fully server-side
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  // ── Password ──────────────────────────────────────────────────────────────

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < InputLimits.passwordMin) {
      return 'At least ${InputLimits.passwordMin} characters required';
    }
    if (v.length > InputLimits.passwordMax) {
      return 'Password is too long (max ${InputLimits.passwordMax} characters)';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    final err = password(value);
    if (err != null) return err;
    if (value != original) return 'Passwords do not match';
    return null;
  }

  // ── Username ──────────────────────────────────────────────────────────────

  static String? username(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Username is required';
    if (v.length < InputLimits.usernameMin) {
      return 'At least ${InputLimits.usernameMin} characters required';
    }
    if (v.length > InputLimits.usernameMax) {
      return 'Max ${InputLimits.usernameMax} characters';
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v)) {
      return 'Letters, numbers, and underscores only';
    }
    if (v.startsWith('_') || v.endsWith('_')) {
      return 'Cannot start or end with underscore';
    }
    return null;
  }

  // ── Display name ──────────────────────────────────────────────────────────

  static String? displayName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Display name is required';
    if (v.length > InputLimits.displayNameMax) {
      return 'Max ${InputLimits.displayNameMax} characters';
    }
    // Block null bytes and control characters
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(v)) {
      return 'Display name contains invalid characters';
    }
    return null;
  }

  // ── Age ───────────────────────────────────────────────────────────────────

  static String? age(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Age is required';
    final n = int.tryParse(v);
    if (n == null) return 'Enter a valid number';
    if (n < InputLimits.ageMin) return 'Must be at least ${InputLimits.ageMin} years old';
    if (n > InputLimits.ageMax) return 'Enter a valid age';
    return null;
  }

  // ── Workout notes ─────────────────────────────────────────────────────────

  static String? workoutNotes(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null; // notes are optional
    if (v.length > InputLimits.notesMax) {
      return 'Notes too long (max ${InputLimits.notesMax} characters)';
    }
    if (RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]').hasMatch(v)) {
      return 'Notes contain invalid characters';
    }
    return null;
  }

  // ── Search query ──────────────────────────────────────────────────────────

  /// Sanitises a search query — strips leading @, trims, enforces max length.
  /// Returns the clean query string (empty string = no search).
  static String sanitiseSearch(String raw) {
    var v = raw.trim();
    if (v.startsWith('@')) v = v.substring(1);
    if (v.length > InputLimits.searchMax) v = v.substring(0, InputLimits.searchMax);
    return v;
  }

  // ── Generic payload guard ─────────────────────────────────────────────────

  /// Hard-truncates any string before it hits the DB.
  /// Use as a last line of defence in service layer inserts.
  static String? truncate(String? value, int maxLength) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length > maxLength ? trimmed.substring(0, maxLength) : trimmed;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INPUT FORMATTERS — drop-in Flutter InputFormatter lists per field type
// ─────────────────────────────────────────────────────────────────────────────

class InputFormatters {
  InputFormatters._();

  static List<TextInputFormatter> get username => [
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
        LengthLimitingTextInputFormatter(InputLimits.usernameMax),
      ];

  static List<TextInputFormatter> get displayName => [
        LengthLimitingTextInputFormatter(InputLimits.displayNameMax),
      ];

  static List<TextInputFormatter> get email => [
        LengthLimitingTextInputFormatter(InputLimits.emailMax),
        FilteringTextInputFormatter.deny(RegExp(r'\s')), // no spaces in email
      ];

  static List<TextInputFormatter> get password => [
        LengthLimitingTextInputFormatter(InputLimits.passwordMax),
      ];

  static List<TextInputFormatter> get age => [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3), // max "120"
      ];

  static List<TextInputFormatter> get workoutNotes => [
        LengthLimitingTextInputFormatter(InputLimits.notesMax),
      ];

  static List<TextInputFormatter> get search => [
        LengthLimitingTextInputFormatter(InputLimits.searchMax),
      ];
}