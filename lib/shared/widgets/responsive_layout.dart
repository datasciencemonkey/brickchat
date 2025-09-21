import 'package:flutter/material.dart';
import '../../core/utils/responsive.dart';

class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  @override
  Widget build(BuildContext context) {
    return context.responsiveValue(
      mobile: mobile,
      tablet: tablet,
      desktop: desktop,
    );
  }
}

class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    super.key,
    required this.builder,
  });

  final Widget Function(BuildContext context, DeviceType deviceType) builder;

  @override
  Widget build(BuildContext context) {
    return builder(context, context.deviceType);
  }
}

class ResponsiveScaffold extends StatelessWidget {
  const ResponsiveScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.sidebar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.drawer,
    this.endDrawer,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? sidebar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final Widget? endDrawer;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    if (context.shouldUseSingleColumnLayout) {
      return Scaffold(
        appBar: appBar,
        body: body,
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
        drawer: drawer ?? sidebar,
        endDrawer: endDrawer,
        backgroundColor: backgroundColor,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      );
    }

    return Scaffold(
      appBar: appBar,
      body: Row(
        children: [
          if (sidebar != null && context.shouldShowSidebar) ...[
            SizedBox(
              width: context.sidebarWidth,
              child: sidebar!,
            ),
            const VerticalDivider(width: 1),
          ],
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      drawer: drawer,
      endDrawer: endDrawer,
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    );
  }
}

class ResponsiveContainer extends StatelessWidget {
  const ResponsiveContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.maxWidth,
    this.centerContent = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? maxWidth;
  final bool centerContent;

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      padding: padding ?? context.responsiveValue(
        mobile: const EdgeInsets.all(16),
        tablet: const EdgeInsets.all(24),
        desktop: const EdgeInsets.all(32),
      ),
      margin: margin,
      constraints: maxWidth != null
          ? BoxConstraints(maxWidth: maxWidth!)
          : BoxConstraints(maxWidth: context.maxWidth),
      child: child,
    );

    if (centerContent && context.isDesktop) {
      content = Center(child: content);
    }

    return content;
  }
}

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.spacing = 16.0,
    this.runSpacing = 16.0,
    this.mobileColumns = 1,
    this.tabletColumns = 2,
    this.desktopColumns = 3,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;

  @override
  Widget build(BuildContext context) {
    final columns = context.responsiveValue(
      mobile: mobileColumns,
      tablet: tabletColumns,
      desktop: desktopColumns,
    );

    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      children: children.map((child) {
        return SizedBox(
          width: (MediaQuery.of(context).size.width -
                  (spacing * (columns - 1))) / columns,
          child: child,
        );
      }).toList(),
    );
  }
}