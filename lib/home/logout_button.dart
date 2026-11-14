part of '../home_screen.dart';

/// The Log Out control. A repeat tap while a log out is running is ignored.
class LogoutButton extends StatefulWidget {
  final Future<void> Function() onLogout;
  const LogoutButton({super.key, required this.onLogout});

  @override
  State<LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<LogoutButton> {
  final _once = RunOnce();

  @override
  void dispose() {
    _once.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _once.run(widget.onLogout),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE53935).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.3), width: 1.5),
        ),
        child: const Center(
          child: Text(
            'Log Out',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE53935),
            ),
          ),
        ),
      ),
    );
  }
}
