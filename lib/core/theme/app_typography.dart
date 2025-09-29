import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract class AppTypography {
  static const double _letterSpacingTight = -0.025;
  static const double _letterSpacingNormal = 0.0;
  static const double _letterSpacingWide = 0.025;

  static const double _lineHeightTight = 1.0;
  static const double _lineHeightNormal = 1.5;

  static TextTheme get textTheme => GoogleFonts.dmSansTextTheme(
        TextTheme(
          displayLarge: GoogleFonts.dmSans(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            letterSpacing: _letterSpacingTight,
            height: _lineHeightTight,
          ),
          displayMedium: GoogleFonts.dmSans(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: _letterSpacingTight,
            height: _lineHeightTight,
          ),
          displaySmall: GoogleFonts.dmSans(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            letterSpacing: _letterSpacingTight,
            height: _lineHeightTight,
          ),
          headlineLarge: GoogleFonts.dmSans(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: _letterSpacingNormal,
            height: _lineHeightTight,
          ),
          headlineMedium: GoogleFonts.dmSans(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: _letterSpacingNormal,
            height: _lineHeightTight,
          ),
          headlineSmall: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            letterSpacing: _letterSpacingNormal,
            height: _lineHeightTight,
          ),
          titleLarge: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            letterSpacing: _letterSpacingNormal,
            height: _lineHeightNormal,
          ),
          titleMedium: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: _letterSpacingWide,
            height: _lineHeightNormal,
          ),
          titleSmall: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: _letterSpacingWide,
            height: _lineHeightNormal,
          ),
          bodyLarge: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            letterSpacing: _letterSpacingNormal,
            height: _lineHeightNormal,
          ),
          bodyMedium: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            letterSpacing: _letterSpacingNormal,
            height: _lineHeightNormal,
          ),
          bodySmall: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            letterSpacing: _letterSpacingNormal,
            height: _lineHeightNormal,
          ),
          labelLarge: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: _letterSpacingWide,
            height: _lineHeightNormal,
          ),
          labelMedium: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: _letterSpacingWide,
            height: _lineHeightNormal,
          ),
          labelSmall: GoogleFonts.dmSans(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: _letterSpacingWide,
            height: _lineHeightNormal,
          ),
        ),
      );

  static TextStyle get codeStyle => GoogleFonts.jetBrainsMono(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: _letterSpacingNormal,
        height: _lineHeightNormal,
      );

  static TextStyle get chatMessage => GoogleFonts.dmSans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: _letterSpacingNormal,
        height: _lineHeightNormal,
      );

  static TextStyle get chatMessageTime => GoogleFonts.dmSans(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        letterSpacing: _letterSpacingNormal,
        height: _lineHeightNormal,
      );

  static TextStyle get chatMessageAuthor => GoogleFonts.dmSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: _letterSpacingWide,
        height: _lineHeightNormal,
      );
}

extension AppTypographyContext on BuildContext {
  TextTheme get textTheme => Theme.of(this).textTheme;
}