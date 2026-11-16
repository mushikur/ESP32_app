import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

class ScreenCanvas extends StatelessWidget {
  const ScreenCanvas({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(.8, -1.25),
          radius: 1.45,
          colors: [AppColors.backgroundGlow, AppColors.background],
          stops: [0, .78],
        ),
      ),
      child: child,
    );
  }
}

class ScreenScroll extends StatelessWidget {
  const ScreenScroll({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {this.color, super.key});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        height: 1.25,
        letterSpacing: 1.5,
        color: color ?? AppColors.cyan,
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class IconTile extends StatelessWidget {
  const IconTile(this.icon, {this.color, this.size = 44, super.key});

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? AppColors.cyan;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          border: Border.all(color: color.withValues(alpha: .17)),
          borderRadius: BorderRadius.circular(size * .31),
        ),
        child: Icon(icon, color: color, size: size * .48),
      ),
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          IconTile(icon, size: 56),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center, style: text.titleLarge),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: AppColors.muted),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}
