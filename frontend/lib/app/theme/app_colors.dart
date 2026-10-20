import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary palette (WhatsApp-style teal green)
  static const Color primary = Color(0xFF008069);
  static const Color primaryLight = Color(0xFF00A884);
  static const Color primaryDark = Color(0xFF005C4B);

  // Secondary palette
  static const Color secondary = Color(0xFF00ACC1);
  static const Color secondaryLight = Color(0xFF26C6DA);
  static const Color secondaryDark = Color(0xFF00838F);

  // Accent
  static const Color accent = Color(0xFFFF6F00);
  static const Color accentLight = Color(0xFFFF8F00);

  // Backgrounds
  static const Color background = Color(0xFFF6F6F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF0F2F5);

  // Chat wallpaper (WhatsApp-style beige)
  static const Color chatBackground = Color(0xFFEFE7DE);

  // Text
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  // Muted text must remain readable against white surfaces (WCAG AA body text).
  static const Color textHint = Color(0xFF667085);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Status
  static const Color error = Color(0xFFD32F2F);
  static const Color success = Color(0xFF388E3C);
  static const Color warning = Color(0xFFF57F17);
  static const Color info = Color(0xFF0288D1);

  // Chat specific (WhatsApp-style bubbles)
  static const Color sentBubble = Color(0xFFD9FDD3);
  static const Color receivedBubble = Color(0xFFFFFFFF);
  static const Color sentBubbleText = Color(0xFF111B21);
  static const Color receivedBubbleText = Color(0xFF111B21);

  // Status indicators
  static const Color online = Color(0xFF4CAF50);
  static const Color offline = Color(0xFFB0BEC5);
  static const Color away = Color(0xFFFF9800);

  // Other
  static const Color divider = Color(0xFFE8ECF4);
  static const Color shadow = Color(0x1A000000);
  static const Color overlay = Color(0x80000000);

  // Language colors
  static const Color kinyarwandaColor = Color(0xFF009688);
  static const Color englishColor = Color(0xFF1565C0);
  static const Color frenchColor = Color(0xFF7B1FA2);
  static const Color swahiliColor = Color(0xFF2E7D32);

  // Gradient
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondary],
  );

  static const LinearGradient callGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0D1B2A), Color(0xFF1565C0)],
  );
}
