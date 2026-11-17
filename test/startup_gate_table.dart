import 'package:gym_buddy_app/services/startup_gate.dart';

typedef GateRow = ({String name, String? session, String? owner, bool flag, StartupReadResult read, StartupScreen expected});

/// Every case of decideStartupScreen worth naming; the expected screens are
/// written out, not derived.
const List<GateRow> startupGateTable = [
  (name: 'saved flag for this user, read pending', session: 'u1', owner: 'u1', flag: true, read: StartupReadResult.pending, expected: StartupScreen.home),
  (name: 'saved flag for this user, read complete', session: 'u1', owner: 'u1', flag: true, read: StartupReadResult.complete, expected: StartupScreen.home),
  (name: 'saved flag for this user, read notOnboarded', session: 'u1', owner: 'u1', flag: true, read: StartupReadResult.notOnboarded, expected: StartupScreen.onboarding),
  (name: 'saved flag for this user, read unknown', session: 'u1', owner: 'u1', flag: true, read: StartupReadResult.unknown, expected: StartupScreen.home),
  (name: 'no saved flag, read pending', session: 'u1', owner: 'u1', flag: false, read: StartupReadResult.pending, expected: StartupScreen.spinner),
  (name: 'saved flag but another user id, read pending', session: 'u1', owner: 'u2', flag: true, read: StartupReadResult.pending, expected: StartupScreen.spinner),
  (name: 'saved flag but no saved owner, read pending', session: 'u1', owner: null, flag: true, read: StartupReadResult.pending, expected: StartupScreen.spinner),
  (name: 'no session, read pending', session: null, owner: 'u1', flag: true, read: StartupReadResult.pending, expected: StartupScreen.splash),
  (name: 'no session and nothing saved, read pending', session: null, owner: null, flag: false, read: StartupReadResult.pending, expected: StartupScreen.splash),
  (name: 'no saved flag, read complete', session: 'u1', owner: 'u1', flag: false, read: StartupReadResult.complete, expected: StartupScreen.home),
  (name: 'saved flag but another user id, read complete', session: 'u1', owner: 'u2', flag: true, read: StartupReadResult.complete, expected: StartupScreen.home),
  (name: 'saved flag but no saved owner, read complete', session: 'u1', owner: null, flag: true, read: StartupReadResult.complete, expected: StartupScreen.home),
  (name: 'no session, read complete', session: null, owner: 'u1', flag: true, read: StartupReadResult.complete, expected: StartupScreen.splash),
  (name: 'no session and nothing saved, read complete', session: null, owner: null, flag: false, read: StartupReadResult.complete, expected: StartupScreen.splash),
  (name: 'no saved flag, read notOnboarded', session: 'u1', owner: 'u1', flag: false, read: StartupReadResult.notOnboarded, expected: StartupScreen.onboarding),
  (name: 'saved flag but another user id, read notOnboarded', session: 'u1', owner: 'u2', flag: true, read: StartupReadResult.notOnboarded, expected: StartupScreen.onboarding),
  (name: 'saved flag but no saved owner, read notOnboarded', session: 'u1', owner: null, flag: true, read: StartupReadResult.notOnboarded, expected: StartupScreen.onboarding),
  (name: 'no session, read notOnboarded', session: null, owner: 'u1', flag: true, read: StartupReadResult.notOnboarded, expected: StartupScreen.splash),
  (name: 'no session and nothing saved, read notOnboarded', session: null, owner: null, flag: false, read: StartupReadResult.notOnboarded, expected: StartupScreen.splash),
  (name: 'no saved flag, read unknown', session: 'u1', owner: 'u1', flag: false, read: StartupReadResult.unknown, expected: StartupScreen.splash),
  (name: 'saved flag but another user id, read unknown', session: 'u1', owner: 'u2', flag: true, read: StartupReadResult.unknown, expected: StartupScreen.splash),
  (name: 'saved flag but no saved owner, read unknown', session: 'u1', owner: null, flag: true, read: StartupReadResult.unknown, expected: StartupScreen.splash),
  (name: 'no session, read unknown', session: null, owner: 'u1', flag: true, read: StartupReadResult.unknown, expected: StartupScreen.splash),
  (name: 'no session and nothing saved, read unknown', session: null, owner: null, flag: false, read: StartupReadResult.unknown, expected: StartupScreen.splash),
];
