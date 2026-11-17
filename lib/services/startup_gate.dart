/// Which screen the app opens on, decided from what is known locally and
/// what the onboarding read has said so far (cache-first plan, phase 4).
library;

/// The start-up onboarding read, as far as it has got.
enum StartupReadResult {
  /// Not back yet.
  pending,

  /// A definite answer: the account finished onboarding.
  complete,

  /// A definite answer: no profile row, or onboarding not finished.
  notOnboarded,

  /// The read failed or timed out. Says nothing about the account.
  unknown,
}

enum StartupScreen {
  /// The plain spinner, as before.
  spinner,
  home,

  /// The onboarding flow (resume), as before.
  onboarding,

  /// The welcome splash, as before.
  splash,
}

/// Home is built at once only when a session exists locally AND the saved
/// copy belongs to that same user AND says that user finished onboarding.
/// Otherwise the screen is today's: a spinner until the read answers, Home
/// for complete, onboarding for not onboarded, the splash for unknown.
///
/// With the saved flag, an unknown read stays on Home: a failed or offline
/// read is never a reason to show the welcome splash, and a definite
/// not-onboarded still routes to onboarding.
StartupScreen decideStartupScreen({
  required String? sessionUserId,
  required String? savedOwnerId,
  required bool savedOnboarded,
  required StartupReadResult read,
}) {
  if (sessionUserId == null) return StartupScreen.splash;
  final saved = savedOnboarded && savedOwnerId == sessionUserId;
  return switch (read) {
    StartupReadResult.pending => saved ? StartupScreen.home : StartupScreen.spinner,
    StartupReadResult.complete => StartupScreen.home,
    StartupReadResult.notOnboarded => StartupScreen.onboarding,
    StartupReadResult.unknown => saved ? StartupScreen.home : StartupScreen.splash,
  };
}
