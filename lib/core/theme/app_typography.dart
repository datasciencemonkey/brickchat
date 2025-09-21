import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract class AppTypography {
  static const double _letterSpacingTight = -0.025;
  static const double _letterSpacingNormal = 0.0;
  static const double _letterSpacingWide = 0.025;

  static const double _lineHeightTight = 1.0;
  static const double _lineHeightNormal = 1.5;

  static TextTheme get textTheme => GoogleFonts.interTextTheme(
        TextTheme(
          displayLarge: GoogleFonts.inter(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            letterSpacing: _letterSpacingTight,
            height: _lineHeightTight,
          ),
          displayMedium: GoogleFonts.inter(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: _letterSpacingTight,
            height: _lineHeightTight,
          ),
          displaySmall: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            letterSpacing: _letterSpacingTight,
            height: _lineHeightTight,
          ),
          headlineLarge: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: _letterSpacingNormal,
            height: _lineHeightTight,
          ),
          headlineMedium: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: _letterSpacingNormal,
            height: _lineHeightTight,
          ),
          headlineSmall: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            letterSpacing: _letterSpacingNormal,
            height: _lineHeightTight,
          ),
          titleLarge: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            letterSpacing: _letterSpacingNormal,
            height: _lineHeightNormal,
          ),
          titleMedium: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: _letterSpacingWide,
            height: _lineHeightNormal,
          ),
          titleSmall: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: _letterSpacingWide,
            height: _lineHeightNormal,
          ),
          bodyLarge: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            letterSpacing: _letterSpacingNormal,
            height: _lineHeightNormal,
          ),
          bodyMedium: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            letterSpacing: _letterSpacingNormal,
            height: _lineHeightNormal,
          ),
          bodySmall: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            letterSpacing: _letterSpacingNormal,
            height: _lineHeightNormal,
          ),
          labelLarge: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: _letterSpacingWide,
            height: _lineHeightNormal,
          ),
          labelMedium: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: _letterSpacingWide,
            height: _lineHeightNormal,
          ),
          labelSmall: GoogleFonts.inter(
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

  static TextStyle get chatMessage => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: _letterSpacingNormal,
        height: _lineHeightNormal,
      );

  static TextStyle get chatMessageTime => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        letterSpacing: _letterSpacingNormal,
        height: _lineHeightNormal,
      );

  static TextStyle get chatMessageAuthor => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: _letterSpacingWide,
        height: _lineHeightNormal,
      );
}

extension AppTypographyContext on BuildContext {
  TextTheme get textTheme => Theme.of(this).textTheme;
}