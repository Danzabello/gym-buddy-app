import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/invite_service.dart';
import '../theme/app_theme.dart';
import '../utils/debug_logger.dart';
import 'onboarding_account.dart';
import 'onboarding_draft.dart';
import 'onboarding_host.dart';
import 'onboarding_max.dart';
import 'onboarding_theme.dart';

const kInviteInvalid =
    "That invite isn't valid or has expired. Ask your buddy for a new link.";
const kInviteMalformed = 'Codes have 8 letters and numbers.';
const kInviteOffline =
    "Couldn't check the code. Check your connection and try again.";
const kInviteRateLimited = 'Too many tries. Wait a few minutes and try again.';
const kProfileSaveFailed = 'Could not save profile. Please try again.';

/// What the buddy step needs from the outside world, so tests can hand it
/// fakes.
class BuddyDeps {
  /// The code a link or the install referrer left for this step, if any.
  final Future<String?> Function() pendingCode;
  final Future<void> Function() clearPendingCode;

  /// The early row write a Join needs: onboarding_completed stays false.
  final Future<void> Function(OnboardingDraft) saveRow;

  /// The main button: the row with onboarding_completed true, then setup.
  final Future<void> Function(OnboardingDraft) finish;
  final Future<InviteRedeemResult> Function(String code) redeem;
  final Future<String> Function(String inviterId) inviterName;

  const BuddyDeps({
    required this.pendingCode,
    required this.clearPendingCode,
    required this.saveRow,
    required this.finish,
    required this.redeem,
    required this.inviterName,
  });

  factory BuddyDeps.live() {
    final invites = InviteService();
    return BuddyDeps(
      pendingCode: invites.pendingInviteCode,
      clearPendingCode: invites.clearPendingInviteCode,
      saveRow: (d) => writeOnboardingProfileRow(d, completed: false),
      finish: saveOnboardingProfile,
      redeem: invites.redeem,
      inviterName: invites.inviterName,
    );
  }
}

/// Step 5: who to start with. The main button writes the profile with
/// onboarding_completed true, then either shares an invite link or leaves
/// Coach Max as the buddy; Coach Max is set up for everyone either way. A
/// Join (a typed code, or a code a link left) writes the row first, with
/// onboarding_completed false, and pairs at once.
class BuddyStep extends StatefulWidget {
  final BuddyDeps? deps;
  const BuddyStep({super.key, this.deps});

  @override
  State<BuddyStep> createState() => _BuddyStepState();
}

class _BuddyStepState extends State<BuddyStep> {
  late final BuddyDeps _deps = widget.deps ?? BuddyDeps.live();
  final _code = TextEditingController();
  bool _busy = false;

  /// A code from a link or the referrer, waiting for "Join your buddy".
  String? _pending;
  bool _fieldOpen = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final draft = OnbScope.read(context).draft;
    if (draft.pairedWith != null) return;
    _deps.pendingCode().then((code) {
      if (!mounted || code == null || draft.pairedWith != null) return;
      setState(() {
        _pending = code;
        draft.buddy = BuddyChoice.invite;
      });
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    try {
      final link = await InviteService().createInviteLink();
      if (link == null) {
        _toast('Could not create an invite link. You can send one from Friends any time.');
        return;
      }
      await SharePlus.instance.share(ShareParams(
        text:
            "Join me on Gym Buddy! We'll keep each other accountable and build streaks together.\n\n$link",
        subject: 'Join me on Gym Buddy!',
      ));
    } catch (e) {
      debugLog('Onboarding invite share failed: $e');
      _toast('Could not open the share sheet. You can send an invite from Friends any time.');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _saveFailed() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text(kProfileSaveFailed),
        backgroundColor: AppColors.of(context).danger));
  }

  /// Saves the row (a team needs it), then redeems [raw]. A failed save
  /// redeems nothing and keeps a waiting code.
  Future<void> _join(String raw) async {
    if (_busy) return;
    final draft = OnbScope.of(context).draft;
    final code = normalizeInviteCode(raw);
    if (code == null) {
      setState(() => _error = kInviteMalformed);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _deps.saveRow(draft);
    } catch (e) {
      debugLog('Onboarding early profile save failed: $e');
      if (!mounted) return;
      _saveFailed();
      setState(() => _busy = false);
      return;
    }
    final result = await _deps.redeem(code);
    final name = result.status == InviteRedeemStatus.paired
        ? await _deps.inviterName(result.inviterId!)
        : null;
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (name != null) {
        draft.pairedWith = name;
        _pending = null;
        _fieldOpen = false;
        return;
      }
      _error = switch (result.status) {
        InviteRedeemStatus.rateLimited => kInviteRateLimited,
        InviteRedeemStatus.offline => kInviteOffline,
        InviteRedeemStatus.malformed => kInviteMalformed,
        _ => kInviteInvalid,
      };
      // A waiting code that will never work: show it in the field instead.
      if (_pending != null && result.status == InviteRedeemStatus.invalid) {
        _pending = null;
        draft.buddy = BuddyChoice.coachMax;
        _fieldOpen = true;
        _code.text = code;
      }
    });
  }

  Future<void> _continue() async {
    if (_busy) return;
    final host = OnbScope.of(context);
    final draft = host.draft;
    final paired = draft.pairedWith != null;
    if (!paired && _pending != null && draft.buddy == BuddyChoice.invite) {
      return _join(_pending!);
    }
    final messenger = ScaffoldMessenger.of(context);
    final danger = AppColors.of(context).danger;
    setState(() => _busy = true);
    // Coach Max or a new invite instead: the waiting code is dropped.
    if (!paired) await _deps.clearPendingCode();
    try {
      await _deps.finish(draft);
    } catch (e) {
      debugLog('Onboarding profile save failed: $e');
      messenger.showSnackBar(SnackBar(
          content: const Text(kProfileSaveFailed), backgroundColor: danger));
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!paired && draft.buddy == BuddyChoice.invite) await _share();
    if (!mounted) return;
    setState(() => _busy = false);
    host.next();
  }

  @override
  Widget build(BuildContext context) {
    final host = OnbScope.of(context);
    final draft = host.draft;
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final paired = draft.pairedWith;
    final waiting = _pending != null;
    final invite = draft.buddy == BuddyChoice.invite;
    final maxLine = paired != null
        ? 'Nice. You and $paired are a team now. Your streak starts when you both check in.'
        : _error != null
            ? "That code didn't work. Check it, or ask your buddy for a new link."
            : _fieldOpen
                ? 'Got a code from a friend? Type it in.'
                : waiting && invite
                    ? 'Someone invited you. Tap Join to team up with them.'
                    : "That's me. I'm an AI, so I never miss a day. Invite a friend any time.";
    final label = paired != null
        ? 'Continue'
        : waiting && invite
            ? 'Join your buddy'
            : invite
                ? 'Send invite link'
                : 'Start with Coach Max';
    return OnbStepFrame(
      footer: ObPrimaryButton(
        label: label,
        isLoading: _busy,
        onTap: _continue,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MaxStrip(
            anchor: host.anchors[MaxSpot.buddy]!,
            spot: MaxSpot.buddy,
            text: maxLine,
            bubbleVisible: host.bubbleVisible,
          ),
          const SizedBox(height: 20),
          Semantics(
            header: true,
            child: Text("Who's your buddy?",
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w800, color: cs.onSurface)),
          ),
          const SizedBox(height: 18),
          if (paired != null)
            _PairedCard(name: paired)
          else ...[
            _BuddyCard(
              title: waiting ? 'Join your buddy' : 'Invite a friend',
              body: waiting
                  ? 'You were invited. We will pair you up and start your streak.'
                  : 'Send a link. Your streak starts when they join.',
              selected: invite,
              onTap: () => setState(() => draft.buddy = BuddyChoice.invite),
            ),
            const SizedBox(height: 12),
            _BuddyCard(
              title: 'Coach Max',
              body: 'Always on, never misses a day.',
              ai: true,
              selected: !invite,
              onTap: () => setState(() => draft.buddy = BuddyChoice.coachMax),
            ),
            if (waiting && _error != null) ...[
              const SizedBox(height: 10),
              _ErrorText(_error!),
            ],
            if (!waiting) ...[
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => setState(() => _fieldOpen = true),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: EdgeInsets.zero,
                  foregroundColor: cs.onSurface,
                ),
                child: const Text('Have an invite code?',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline)),
              ),
            ],
            if (!waiting && _fieldOpen) ...[
              const SizedBox(height: 4),
              _codeField(context),
            ],
          ],
          const SizedBox(height: 14),
          Text(
              paired != null
                  ? 'You can add Coach Max or more friends any time later.'
                  : 'Coach Max is an AI, not a person. You can pair with a real friend any time later.',
              style: TextStyle(fontSize: 13, height: 1.35, color: c.subtleText)),
        ],
      ),
    );
  }

  Widget _codeField(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ObFieldLabel('Invite code'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _code,
                autofocus: true,
                cursorColor: cs.primary,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(8),
                  _UpperCase(),
                ],
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: _join,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: cs.onSurface),
                decoration: obInputDecoration(context, hint: '8 characters'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _busy ? null : () => _join(_code.text),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(84, 50),
                foregroundColor: cs.primary,
                side: BorderSide(color: cs.primary, width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Join',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_error != null)
          _ErrorText(_error!)
        else
          Text("It's on the page your friend's link opens.",
              style: TextStyle(fontSize: 12, color: c.subtleText)),
      ],
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue _, TextEditingValue v) =>
      v.copyWith(text: v.text.toUpperCase());
}

class _ErrorText extends StatelessWidget {
  final String text;
  const _ErrorText(this.text);

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Text(text,
            style: TextStyle(
                fontSize: 13, height: 1.4, color: AppColors.of(context).danger)),
      );
}

class _PairedCard extends StatelessWidget {
  final String name;
  const _PairedCard({required this.name});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.claySurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.primary, width: 2),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary),
            child: Icon(Icons.check_rounded,
                size: 24, color: Theme.of(context).scaffoldBackgroundColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("You're paired with $name",
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                const SizedBox(height: 4),
                Text('Your team is ready. Your streak starts when you both check in.',
                    style: TextStyle(fontSize: 14, color: c.subtleText)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BuddyCard extends StatelessWidget {
  final String title;
  final String body;
  final bool ai;
  final bool selected;
  final VoidCallback onTap;
  const _BuddyCard({
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
    this.ai = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final ink = Theme.of(context).scaffoldBackgroundColor;
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: ai ? '$title, AI. $body' : '$title. $body',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.claySurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? cs.primary : c.info,
                width: selected ? 2 : 1.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(title,
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface)),
                        ),
                        if (ai) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: c.aqua,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text('AI',
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                    color: ink)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(body,
                        style: TextStyle(fontSize: 14, color: c.subtleText)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: selected ? cs.primary : c.info, width: 2),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle, color: cs.primary),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
