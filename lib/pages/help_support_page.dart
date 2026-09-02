import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/menu_card.dart';

// Hosted on GitHub Pages from docs/ -- same origin as invite.html.
const String _kTermsUrl =
    'https://danzabello.github.io/gym-buddy-app/terms.html';
const String _kPrivacyUrl =
    'https://danzabello.github.io/gym-buddy-app/privacy-policy.html';

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  Future<void> _openLegalUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        // Inherits transparent bg + foreground from appBarTheme
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Help & Support',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          buildMenuCard(context, [
            MenuItem(
              icon: Icons.privacy_tip_outlined,
              iconColor: appColors.subtleText,
              color: appColors.sectionBackground,
              label: 'Privacy Policy',
              onTap: () => _openLegalUrl(_kPrivacyUrl),
            ),
            MenuItem(
              icon: Icons.description_outlined,
              iconColor: appColors.subtleText,
              color: appColors.sectionBackground,
              label: 'Terms of Service',
              onTap: () => _openLegalUrl(_kTermsUrl),
            ),
          ]),
        ],
      ),
    );
  }
}
