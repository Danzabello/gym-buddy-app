import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
              color: Colors.black.withOpacity(0.05),
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
          side: BorderSide(color: kObBlue.withOpacity(0.4), width: 1.5),
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
    this.optional = false,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151))),
            if (optional) ...[
              const SizedBox(width: 6),
              Text('(optional)',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400])),
            ],
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          onChanged: onChanged,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400]),
            prefixIcon:
                Icon(icon, color: const Color(0xFF6B7280), size: 20),
            suffixIcon: suffixIcon,
            errorText: errorText,
            helperText: helperText,
            helperStyle: const TextStyle(
                color: Color(0xFF10B981), fontWeight: FontWeight.w500),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kObBlue, width: 2)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red)),
            focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red, width: 2)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
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
                : Colors.white.withOpacity(0.35),
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
              color: kObBlue.withOpacity(0.3),
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