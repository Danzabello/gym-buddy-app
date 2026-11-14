part of '../home_screen.dart';

  // ── Custom nav bar ─────────────────────────────────────────────────────────

class _GymBuddyNavBar extends StatelessWidget {
    final int selectedIndex;
    final ValueChanged<int> onTabSelected;

    const _GymBuddyNavBar({
      required this.selectedIndex,
      required this.onTabSelected,
    });

    @override
    Widget build(BuildContext context) {
      final c = AppColors.of(context);
      // Same clay language as the cards above it: raised slab, dual shadow,
      // rounded top so the bar reads as part of one surface system.
      final inactiveColor = c.inkMuted;
      final activeColor = c.readableForeground(c.claySurface);

      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [c.claySurfaceLight, c.claySurface],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          boxShadow: c.clayShadow(),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Schedule (logical 0)
              _NavIcon(
                icon: Icons.calendar_today_outlined,
                activeIcon: Icons.calendar_today,
                isActive: selectedIndex == 0,
                color: selectedIndex == 0 ? activeColor : inactiveColor,
                semanticLabel: 'Schedule',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTabSelected(0);
                },
              ),
              // Buddies (logical 1)
              _NavIcon(
                icon: Icons.people_outline,
                activeIcon: Icons.people,
                isActive: selectedIndex == 1,
                color: selectedIndex == 1 ? activeColor : inactiveColor,
                semanticLabel: 'Buddies',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTabSelected(1);
                },
              ),
              // 🔥 Streaks — centre hero (logical 2)
              _FireNavButton(
                isActive: selectedIndex == 2,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  onTabSelected(2);
                },
              ),
              // Shop (logical 3)
              _NavIcon(
                icon: Icons.shopping_bag_outlined,
                activeIcon: Icons.shopping_bag,
                isActive: selectedIndex == 3,
                color: selectedIndex == 3 ? activeColor : inactiveColor,
                semanticLabel: 'Shop',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTabSelected(3);
                },
              ),
              // Profile (logical 4)
              _NavIcon(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                isActive: selectedIndex == 4,
                color: selectedIndex == 4 ? activeColor : inactiveColor,
                semanticLabel: 'Profile',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTabSelected(4);
                },
              ),
              ],
            ),
          ),
        ),
      );
    }
  }

class _NavIcon extends StatelessWidget {

    final IconData icon;
    final IconData activeIcon;
    final bool isActive;
    final Color color;
    final String semanticLabel;
    final VoidCallback onTap;

    const _NavIcon({
      required this.icon,
      required this.activeIcon,
      required this.isActive,
      required this.color,
      required this.semanticLabel,
      required this.onTap,
    });

    @override
    Widget build(BuildContext context) {
      return Semantics(
        label: semanticLabel,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Icon(
                isActive ? activeIcon : icon,
                color: color,
                size: 26,
              ),
            ),
          ),
        ),
      );
    }
  }

class _FireNavButton extends StatelessWidget {

    final bool isActive;
    final VoidCallback onTap;

    const _FireNavButton({required this.isActive, required this.onTap});

    @override
    Widget build(BuildContext context) {
      final c = AppColors.of(context);
      return Semantics(
        label: 'Streaks',
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Transform.translate(
            offset: const Offset(0, -10),
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                // Same action gradient as the Check In CTA, so the hero button
                // and the hero action read as one thing.
                gradient: LinearGradient(
                  colors: c.actionGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: c.clayShadow(inset: isActive),
              ),
              child: Center(
                child: Icon(Icons.local_fire_department,
                    color: c.readableForeground(c.streakOrange), size: 32),
              ),
            ),
          ),
        ),
      );
    }
  }
