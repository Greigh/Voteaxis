import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Shared surface language.
///
/// Before this existed every screen grew its own card, its own section label
/// and its own action tile, so the same idea looked different depending on
/// where you met it. Reach for these first; add to this file rather than to a
/// screen when something new is needed twice.

/// Radii, so cards nest predictably instead of each picking a number.
class AppRadius {
  AppRadius._();

  static const card = 18.0;
  static const inner = 12.0;
  static const control = 13.0;
  static const hero = 20.0;
  static const pill = 999.0;
}

/// A quiet mono rule naming what the next few cards are for.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.label, {super.key, this.trailing});

  final String label;

  /// An optional action parked on the right of the rule.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Semantics(
      header: true,
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.ibmPlexMono(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: AppColors.inkMuted,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: trailing == null
          ? text
          : Row(children: [text, const Spacer(), trailing!]),
    );
  }
}

/// The standard white card. [title] and [subtitle] give every card the same
/// heading rhythm instead of each screen inventing its own.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 14),
    this.onTap,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(
            title!,
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: GoogleFonts.manrope(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: AppColors.inkMuted,
              ),
            ),
          ],
          const SizedBox(height: 14),
        ],
        child,
      ],
    );

    // The Material carries the surface colour so a ListTile or InkWell inside
    // can still paint its ink; a coloured box in between would swallow it.
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: AppColors.ink.withValues(alpha: 0.06)),
    );
    final framed = Container(
      width: double.infinity,
      padding: padding,
      decoration: decoration,
      child: body,
    );

    return Material(
      color: AppColors.sheet,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: onTap == null
          ? framed
          : InkWell(
              borderRadius: BorderRadius.circular(AppRadius.card),
              onTap: onTap,
              child: framed,
            ),
    );
  }
}

/// The dark card. Used sparingly — one per screen, for the thing the screen
/// exists to say.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadius.hero),
      ),
      child: child,
    );
  }
}

/// A square in a two-up grid. A stack of identical full-width buttons reads as
/// a list of chores; a grid reads as a choice.
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.emphasize = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  /// Fills the tile with ink — for the one action the screen wants you to take.
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final foreground = emphasize ? AppColors.sheet : AppColors.ink;
    return Material(
      color: emphasize ? AppColors.ink : AppColors.sheet,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: emphasize
                  ? AppColors.ink
                  : AppColors.ink.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(height: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: GoogleFonts.manrope(
                        fontSize: 11.5,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        color: emphasize
                            ? AppColors.sheet.withValues(alpha: 0.7)
                            : AppColors.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one thing a screen wants you to do next: full width, ink filled.
class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    super.key,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.icon = Icons.arrow_forward_rounded,
  });

  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 20, 22),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: AppColors.sheet,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: AppColors.sheet.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.sheet.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.sheet),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A full-width tappable row: icon, title, one line of why, chevron.
class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasize = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Tints the row — for something waiting on the user, like a saved quiz.
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: emphasize
          ? AppColors.liberal.withValues(alpha: 0.08)
          : AppColors.sheet,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: emphasize
                  ? AppColors.liberal.withValues(alpha: 0.25)
                  : AppColors.ink.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 26,
                color: emphasize ? AppColors.liberal : AppColors.ink,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.ink.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The same row shape with nothing to tap — for explaining, not navigating.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.sheet,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.parchment,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.ink),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A short bordered control that sits above the thing it controls.
class ControlButton extends StatelessWidget {
  const ControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.sheet : AppColors.ink;
    return Material(
      color: selected ? AppColors.ink : AppColors.sheet,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(
              color: selected
                  ? AppColors.ink
                  : AppColors.ink.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ),
              if (badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$badge',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.sheet,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The line people quote back at us, pulled out of the prose.
class Callout extends StatelessWidget {
  const Callout(this.text, {super.key, this.tone = CalloutTone.accent});

  final String text;
  final CalloutTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      CalloutTone.accent => AppColors.accent,
      CalloutTone.warning => AppColors.conservative,
      CalloutTone.quiet => AppColors.mist,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Text(
        text,
        style: GoogleFonts.manrope(
          fontSize: 13,
          height: 1.45,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

enum CalloutTone { accent, warning, quiet }

/// A small static label chip. Not a filter — see the screens' own FilterChip
/// for anything tappable.
class PillChip extends StatelessWidget {
  const PillChip(this.label, {super.key, this.color, this.dense = false});

  final String label;
  final Color? color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? AppColors.parchment).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: dense ? 11 : 12,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

/// A number with its label — the paired readouts on compare screens.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.accent = false,
    this.valueSize = 20,
  });

  final String label;
  final String value;
  final String? caption;

  /// Marks the one tile the screen is really about.
  final bool accent;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent
            ? AppColors.accent.withValues(alpha: 0.12)
            : AppColors.parchment.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.ibmPlexMono(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: valueSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppColors.ink,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              style: GoogleFonts.manrope(
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w500,
                color: AppColors.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Nothing to show. Always says why, and always offers the way out.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 26, color: AppColors.inkMuted),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: AppColors.inkMuted,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

/// Mono caption for scope notes, counts and scale legends.
class MonoNote extends StatelessWidget {
  const MonoNote(
    this.text, {
    super.key,
    this.color,
    this.size = 10,
    this.maxLines = 1,
  });

  final String text;
  final Color? color;
  final double size;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.ibmPlexMono(
        fontSize: size,
        letterSpacing: 0.8,
        color: color ?? AppColors.inkMuted,
      ),
    );
  }
}
