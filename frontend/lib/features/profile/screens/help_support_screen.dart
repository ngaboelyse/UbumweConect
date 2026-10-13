import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';

/// Help & Support — FAQs, contact channels and legal links.
class HelpSupportScreen extends ConsumerWidget {
  const HelpSupportScreen({super.key});

  static const List<({IconData icon, String title, String body})> _faqs = [
    (
      icon: Icons.translate,
      title: 'How does automatic translation work?',
      body:
          'When you send a message, the system detects your language and translates it into the preferred language of everyone you are talking to — automatically and in real time. You never need to switch apps or copy text.',
    ),
    (
      icon: Icons.visibility_outlined,
      title: 'How do I see the original text of a message?',
      body:
          'Tap the "Translated from…" label under any message bubble. Tap again to switch back to the translation.',
    ),
    (
      icon: Icons.mic,
      title: 'How do I send a voice message?',
      body:
          'In any chat, press and hold the microphone button (or the send button when the text field is empty) to record. Release to send. The recipient receives the voice note as an audio attachment they can play.',
    ),
    (
      icon: Icons.call_outlined,
      title: 'How do calls work?',
      body:
          'Start a voice or video call from the icons at the top of any chat. Calls connect peer-to-peer over WebRTC, with automatic TURN relay fallback on restrictive networks.',
    ),
    (
      icon: Icons.group_outlined,
      title: 'Can I create group conversations?',
      body:
          'Yes. Tap the new-conversation button on the Chats screen and select "New Group". Each group member receives every message translated into their own preferred language.',
    ),
    (
      icon: Icons.language,
      title: 'How do I change my language?',
      body:
          'Go to Profile → Language Settings (or Settings → My Language) and pick from Kinyarwanda, English, French, Swahili and more. All future translations will target your new language.',
    ),
    (
      icon: Icons.lock_outline,
      title: 'Is my data secure?',
      body:
          'All communication is encrypted in transit (HTTPS/WSS). Passwords are never stored in plain text, and you can delete your account — along with access to your data — at any time from Settings.',
    ),
    (
      icon: Icons.wifi_off,
      title: 'Why are messages not sending?',
      body:
          'Make sure you have an internet connection and that the backend server is reachable. If you are on a local network, the app auto-discovers the server; try pulling down to refresh the chat list, or sign out and back in to reconnect.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Help & Support', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Search-style quick help header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.support_agent, color: Colors.white, size: 32),
                const SizedBox(height: 12),
                const Text(
                  'How can we help?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white, fontFamily: 'Poppins'),
                ),
                const SizedBox(height: 6),
                Text(
                  '${AppConstants.appName} v${AppConstants.appVersion} — ${AppConstants.appTagline}',
                  style: const TextStyle(fontSize: 13, color: Colors.white70, fontFamily: 'Poppins', height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const _SectionLabel('Frequently Asked Questions'),
          ..._faqs.map(_FaqCard.new),

          const SizedBox(height: 20),
          const _SectionLabel('Contact Us'),
          Container(
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.alternate_email_outlined, color: AppColors.primary),
                  title: const Text('Email Support', style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
                  subtitle: const Text('support@ubumweconnect.com', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint)),
                  trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
                  onTap: () => _openEmail(context),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.report_outlined, color: AppColors.primary),
                  title: const Text('Report a Problem', style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
                  subtitle: const Text('Found a bug? Tell us what happened', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint)),
                  trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
                  onTap: () => _openEmail(context, subject: 'Bug report — Ubumwe Connect'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.lightbulb_outline, color: AppColors.primary),
                  title: const Text('Suggest a Feature', style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
                  subtitle: const Text('Help us improve — share your idea', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint)),
                  trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
                  onTap: () => _openEmail(context, subject: 'Feature idea — Ubumwe Connect'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const _SectionLabel('Legal & About'),
          Container(
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.article_outlined, color: AppColors.textSecondary),
                  title: const Text('Terms of Service', style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
                  trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
                  onTap: () => _showTerms(context),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined, color: AppColors.textSecondary),
                  title: const Text('Privacy Policy', style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
                  trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
                  onTap: () => _showPrivacyPolicy(context),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: AppColors.textSecondary),
                  title: const Text('About Ubumwe Connect', style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
                  trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
                  onTap: () => _showAbout(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _openEmail(BuildContext context, {String subject = 'Support request — Ubumwe Connect'}) {
    final uri = Uri(scheme: 'mailto', path: 'support@ubumweconnect.com', queryParameters: {'subject': subject});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Compose an email to ${uri.path} — subject: "$subject"')),
    );
  }

  void _showTerms(BuildContext context) {
    _infoSheet(
      context,
      title: 'Terms of Service',
      children: const [
        Text('Last updated: January 2026', style: TextStyle(fontSize: 12, color: AppColors.textHint, fontFamily: 'Poppins')),
        SizedBox(height: 12),
        Text(
          '1. Acceptance\nBy creating a Ubumwe Connect account you agree to these terms and to use the service only for lawful communication.\n\n'
          '2. Your Account\nYou are responsible for keeping your credentials secure and for all activity under your account. You may delete your account at any time from Settings.\n\n'
          '3. Acceptable Use\nHarassment, spam, impersonation, and sharing of illegal content are prohibited. Accounts violating these rules may be suspended.\n\n'
          '4. Translations\nMachine translations are provided for convenience. While high quality, they may occasionally be imperfect — verify critical information independently.\n\n'
          '5. Changes\nWe may update these terms; continued use constitutes acceptance of the updated terms.',
          style: TextStyle(fontFamily: 'Poppins', height: 1.5, fontSize: 13),
        ),
      ],
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    _infoSheet(
      context,
      title: 'Privacy Policy',
      children: const [
        Text('Last updated: January 2026', style: TextStyle(fontSize: 12, color: AppColors.textHint, fontFamily: 'Poppins')),
        SizedBox(height: 12),
        Text(
          'Data We Collect\nAccount details (name, email, preferred language), your messages and their translations, and call metadata (duration, participants) needed to operate the service.\n\n'
          'How We Use It\nTo deliver and translate your messages, provide calls, send notifications, and improve translation quality. We do not sell your data.\n\n'
          'Message Content\nMessages are stored so your history works across devices. Content is encrypted in transit and access is restricted to conversation members.\n\n'
          'Your Rights\nYou can export or delete your account and associated access at any time from Settings → Delete Account, in line with Rwanda Data Protection Law (No. 058/2021).\n\n'
          'Contact\nPrivacy questions: privacy@ubumweconnect.com',
          style: TextStyle(fontFamily: 'Poppins', height: 1.5, fontSize: 13),
        ),
      ],
    );
  }

  void _showAbout(BuildContext context) {
    _infoSheet(
      context,
      title: 'About',
      children: [
        const Text(
          '${AppConstants.appName} — ${AppConstants.appTagline}',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Text('Version ${AppConstants.appVersion}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        const Text(
          'An AI-powered, real-time multilingual communication platform. Supported languages: Kinyarwanda, English, French, Swahili — with more on the way.',
          style: TextStyle(fontFamily: 'Poppins', height: 1.5, fontSize: 13),
        ),
      ],
    );
  }

  void _infoSheet(BuildContext context, {required String title, required List<Widget> children}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (_, scrollController) => Column(
          children: [
            Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'Poppins')),
            ),
            const Divider(height: 20),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: children,
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textHint, letterSpacing: 1.2, fontFamily: 'Poppins'),
      ),
    );
  }
}

class _FaqCard extends StatelessWidget {
  final ({IconData icon, String title, String body}) faq;
  const _FaqCard(this.faq);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          leading: Icon(faq.icon, color: AppColors.primary, size: 22),
          title: Text(faq.title, style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600)),
          iconColor: AppColors.textHint,
          collapsedIconColor: AppColors.textHint,
          children: [
            Text(
              faq.body,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
