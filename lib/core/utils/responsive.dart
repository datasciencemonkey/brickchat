import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

enum DeviceType {
  mobile,
  tablet,
  desktop,
}

class Responsive {
  static DeviceType getDeviceType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width < AppConstants.mobileBreakpoint) {
      return DeviceType.mobile;
    } else if (width < AppConstants.tabletBreakpoint) {
      return DeviceType.tablet;
    } else {
      return DeviceType.desktop;
    }
  }

  static bool isMobile(BuildContext context) =>
      getDeviceType(context) == DeviceType.mobile;

  static bool isTablet(BuildContext context) =>
      getDeviceType(context) == DeviceType.tablet;

  static bool isDesktop(BuildContext context) =>
      getDeviceType(context) == DeviceType.desktop;

  static bool isTabletOrDesktop(BuildContext context) =>
      !isMobile(context);

  static T responsiveValue<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    final deviceType = getDeviceType(context);

    switch (deviceType) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet ?? mobile;
      case DeviceType.desktop:
        return desktop ?? tablet ?? mobile;
    }
  }

  static double responsiveWidth(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    return responsiveValue(
      context,
      mobile: mobile,
      tablet: tablet,
      desktop: desktop,
    );
  }

  static EdgeInsets responsivePadding(
    BuildContext context, {
    required EdgeInsets mobile,
    EdgeInsets? tablet,
    EdgeInsets? desktop,
  }) {
    return responsiveValue(
      context,
      mobile: mobile,
      tablet: tablet,
      desktop: desktop,
    );
  }

  static int responsiveColumns(BuildContext context) {
    return responsiveValue(
      context,
      mobile: 1,
      tablet: 2,
      desktop: 3,
    );
  }

  static double getMaxWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (isDesktop(context)) {
      return width * 0.8;
    } else if (isTablet(context)) {
      return width * 0.9;
    } else {
      return width;
    }
  }

  static bool shouldShowSidebar(BuildContext context) {
    return isTabletOrDesktop(context);
  }

  static bool shouldUseSingleColumnLayout(BuildContext context) {
    return isMobile(context);
  }

  static double getSidebarWidth(BuildContext context) {
    return responsiveValue(
      context,
      mobile: 280,
      tablet: 300,
      desktop: 320,
    );
  }

  static double getChatInputHeight(BuildContext context) {
    return responsiveValue(
      context,
      mobile: 50,
      tablet: 56,
      desktop: 60,
    );
  }

  static double getAppBarHeight(BuildContext context) {
    return responsiveValue(
      context,
      mobile: 56,
      tablet: 64,
      desktop: 72,
    );
  }
}

extension ResponsiveContext on BuildContext {
  DeviceType get deviceType => Responsive.getDeviceType(this);
  bool get isMobile => Responsive.isMobile(this);
  bool get isTablet => Responsive.isTablet(this);
  bool get isDesktop => Responsive.isDesktop(this);
  bool get isTabletOrDesktop => Responsive.isTabletOrDesktop(this);
  bool get shouldShowSidebar => Responsive.shouldShowSidebar(this);
  bool get shouldUseSingleColumnLayout => Responsive.shouldUseSingleColumnLayout(this);
  double get sidebarWidth => Responsive.getSidebarWidth(this);
  double get chatInputHeight => Responsive.getChatInputHeight(this);
  double get appBarHeight => Responsive.getAppBarHeight(this);
  double get maxWidth => Responsive.getMaxWidth(this);

  T responsiveValue<T>({
    required T mobile,
    T? tablet,
    T? desktop,
  }) =>
      Responsive.responsiveValue(
        this,
        mobile: mobile,
        tablet: tablet,
        desktop: desktop,
      );
}