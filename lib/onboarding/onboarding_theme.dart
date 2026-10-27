import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

const kObBlue = Color(0xFF3B82F6);
const kObPurple = Color(0xFF8B5CF6);
const kGradientColors = [kObBlue, kObPurple];
const kGradient = LinearGradient(
  colors: kGradientColors,
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);
const kGradientDiag = LinearGradient(
  colors: kGradientColors,
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// Fixed height for gradient band — looks correct on phone AND desktop.
// The safe area top is added on top of this.
const double kObHeaderContentHeight = 72.0;

// ── Progress header band (post-signup screens) ─────────────────────────────
class ObHeader extends StatelessWidget {
  final int step;
  final int totalSteps;
  final String label;

  const ObHeader({
    super.key,
    required this.step,
    required this.totalSteps,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: kGradientDiag),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Step $step of $totalSteps',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70)),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: step / totalSteps,
                  minHeight: 4,
                  backgroundColor: Colors.white24,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom nav (post-signup screens) ──────────────────────────────────────
class ObBottomNav extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final Widget? nextChild;
  final bool isLoading;

  const ObBottomNav({
    super.key,
    this.onBack,
    this.onNext,
    this.nextChild,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -4)),
        ],
      ),
      child: Row(
        children: [
          if (onBack != null)
            TextButton.icon(
              onPressed: onBack,
              icon:
                  Icon(Icons.arrow_back, size: 18, color: Colors.grey[500]),
              label: Text('Back',
                  style:
                      TextStyle(color: Colors.grey[500], fontSize: 15)),
            ),
          const Spacer(),
          _GradButton(
            onTap: isLoading ? null : onNext,
            isLoading: isLoading,
            child: nextChild ??
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Next',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward,
                        color: Colors.white, size: 18),
                  ],
                ),
          ),
        ],
      ),
    );
  }
}

// ── Gradient pill button ───────────────────────────────────────────────────
class ObGradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;
  final IconData? icon;

  const ObGradientButton({
    super.key,
    required this.label,
    this.onTap,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: _GradButton(
        onTap: isLoading ? null : onTap,
        isLoading: isLoading,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
            ],
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Ghost outline button ───────────────────────────────────────────────────
class ObGhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const ObGhostButton({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: kObBlue.withValues(alpha: 0.4), width: 1.5),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(label,
            style: const TextStyle(
                color: kObBlue,
                fontSize: 15,
                fontWeight: FontWeight.w500)),
      ),
    );
  }
}

// ── Shared text field ──────────────────────────────────────────────────────
/// Emerald Ink input: 52 high, 16 radius, 1.5px outline, 2px accent on focus.
/// There is no outline token yet; `info` is the closest hue to the mockup's.
InputDecoration obInputDecoration(
  BuildContext context, {
  String? hint,
  Widget? prefixIcon,
  BoxConstraints? prefixIconConstraints,
  Widget? suffixIcon,
  String? errorText,
  String? helperText,
}) {
  final c = AppColors.of(context);
  final cs = Theme.of(context).colorScheme;
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width));
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: c.subtleText),
    prefixIcon: prefixIcon,
    prefixIconConstraints: prefixIconConstraints,
    suffixIcon: suffixIcon,
    errorText: errorText,
    errorStyle: TextStyle(color: c.danger, fontSize: 13),
    errorMaxLines: 3,
    helperText: helperText,
    helperStyle: TextStyle(color: c.success, fontWeight: FontWeight.w500),
    filled: true,
    fillColor: c.inputFill,
    border: border(c.info, 1.5),
    enabledBorder: border(c.info, 1.5),
    focusedBorder: border(cs.primary, 2),
    errorBorder: border(c.danger, 1.5),
    focusedErrorBorder: border(c.danger, 2),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}

class ObFieldLabel extends StatelessWidget {
  final String label;
  final bool optional;
  const ObFieldLabel(this.label, {super.key, this.optional = false});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: onSurface)),
        if (optional) ...[
          const SizedBox(width: 6),
          Text('(optional)',
              style: TextStyle(fontSize: 13, color: c.subtleText)),
        ],
      ],
    );
  }
}

class ObTextField extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final String? errorText;
  final String? helperText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final bool optional;
  final List<TextInputFormatter>? inputFormatters;

  const ObTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.errorText,
    this.helperText,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.optional = false,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ObFieldLabel(label, optional: optional),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          inputFormatters: inputFormatters,
          cursorColor: cs.primary,
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          style: TextStyle(fontSize: 16, color: cs.onSurface),
          decoration: obInputDecoration(
            context,
            hint: hint,
            prefixIcon: Icon(icon, color: c.subtleText, size: 20),
            suffixIcon: suffixIcon,
            errorText: errorText,
            helperText: helperText,
          ),
        ),
      ],
    );
  }
}

/// 48x48 icon button for a field's show/hide toggle.
class ObVisibilityButton extends StatelessWidget {
  final bool shown;
  final String showLabel;
  final String hideLabel;
  final VoidCallback onPressed;
  const ObVisibilityButton({
    super.key,
    required this.shown,
    required this.showLabel,
    required this.hideLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      tooltip: shown ? hideLabel : showLabel,
      icon: Icon(shown ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 20, color: AppColors.of(context).subtleText),
      onPressed: onPressed,
    );
  }
}

// ── Value prop progress dots ───────────────────────────────────────────────
class ObProgressDots extends StatelessWidget {
  final int count;
  final int active;

  const ObProgressDots(
      {super.key, required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 20 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white
                : Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

// ── Internal gradient button wrapper ──────────────────────────────────────
class _GradButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  final bool isLoading;

  const _GradButton(
      {required this.onTap, required this.child, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: kGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: kObBlue.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : child,
      ),
    );
  }
}

// ── Fade+slide page route — use instead of MaterialPageRoute ──────────────
class FadeSlideRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  FadeSlideRoute({required this.page})
      : super(
          pageBuilder: (_, __, ___) => page,
          transitionDuration: const Duration(milliseconds: 400),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (_, animation, secondaryAnimation, child) {
            final fade = CurvedAnimation(
                parent: animation, curve: Curves.easeOut);
            final slide = Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
                parent: animation, curve: Curves.easeOutCubic));
            final fadeOut = Tween<double>(begin: 1.0, end: 0.0)
                .animate(CurvedAnimation(
                    parent: secondaryAnimation, curve: Curves.easeIn));
            return FadeTransition(
              opacity: fadeOut,
              child: SlideTransition(
                position: slide,
                child: FadeTransition(opacity: fade, child: child),
              ),
            );
          },
        );
}

// ── Emerald Ink primary CTA ────────────────────────────────────────────────
/// Darker shade of the CTA fill for the bottom shadow; derived from the token.
Color obCtaShadow(Color cta) {
  final hsl = HSLColor.fromColor(cta);
  return hsl.withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0)).toColor();
}

class ObPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;

  const ObPrimaryButton(
      {super.key, required this.label, this.onTap, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fg = c.readableForeground(c.streakOrange);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: onTap == null
            ? null
            : [
                BoxShadow(
                    color: obCtaShadow(c.streakOrange),
                    offset: const Offset(0, 4)),
              ],
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: c.streakOrange,
          foregroundColor: fg,
          disabledBackgroundColor: c.streakOrange.withValues(alpha: 0.5),
          elevation: 0,
          minimumSize: const Size.fromHeight(56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18)),
        ),
        child: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: fg, strokeWidth: 2.5))
            : Text(label,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
    );
  }
}


/// 48x48 clay back button.
class ObBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const ObBackButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      excludeSemantics: true,
      child: Material(
        color: AppColors.of(context).claySurface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(Icons.chevron_left_rounded,
                size: 28, color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
      ),
    );
  }
}

/// Eyebrow (optional), 30 bold headline and 16 body shared by the auth and
/// onboarding step screens.
class ObHeading extends StatelessWidget {
  final bool eyebrow;
  final String title;
  final String body;
  const ObHeading({super.key, this.eyebrow = false, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow) ...[
          Text('GYM BUDDY',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: cs.primary)),
          const SizedBox(height: 12),
        ],
        Semantics(
          header: true,
          child: Text(title,
              style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w700, color: cs.onSurface)),
        ),
        const SizedBox(height: 8),
        Text(body, style: TextStyle(fontSize: 16, height: 1.4, color: c.subtleText)),
      ],
    );
  }
}

/// Top row of an onboarding step: back button, "Step N of 5", progress bar.
class ObStepHeader extends StatelessWidget {
  final int step;
  final int totalSteps;
  final VoidCallback? onBack;
  const ObStepHeader({super.key, required this.step, this.totalSteps = 5, this.onBack});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        child: Row(
          children: [
            if (onBack != null) ...[
              ObBackButton(onTap: onBack!),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Semantics(
                label: 'Step $step of $totalSteps',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Step $step of $totalSteps',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: c.subtleText)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: step / totalSteps,
                        minHeight: 8,
                        backgroundColor: c.claySurface,
                        valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pinned primary action at the bottom of an onboarding step.
class ObStepFooter extends StatelessWidget {
  final VoidCallback? onNext;
  final String label;
  final bool isLoading;
  const ObStepFooter(
      {super.key, required this.onNext, this.label = 'Continue', this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: ObPrimaryButton(label: label, onTap: onNext, isLoading: isLoading),
      ),
    );
  }
}

/// Inline error box for form-level messages.
class ObErrorBanner extends StatelessWidget {
  final String message;
  const ObErrorBanner(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.tint(c.danger),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.danger.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: c.danger, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message,
                  style: TextStyle(fontSize: 14, color: c.danger)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Text button with an accent-green bold tail, e.g. "Already have an account? Sign in".
class ObLinkButton extends StatelessWidget {
  final String lead;
  final String action;
  final VoidCallback onTap;
  const ObLinkButton({super.key, required this.lead, required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: Text.rich(
          TextSpan(
            style: TextStyle(fontSize: 15, color: c.subtleText),
            children: [
              TextSpan(text: lead),
              TextSpan(
                  text: action,
                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
