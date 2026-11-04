import 'package:flutter/material.dart';

import '../../services/care_physician_service.dart';
import '../../theme/app_theme.dart';
import '../../constants/app_colors.dart';

/// Colours and small building blocks of the care physician screens.
class CpColors {
  static const ink = AppColors.ink;
  static const muted = AppColors.muted;
  static const line = AppColors.line;
  static const page = AppColors.page;
  static const chip = AppColors.chip;
  static const green = AppColors.success;
  static const red = AppColors.danger;
  static const navy = AppColors.navy;

  /// Duty colour (price, icon tile, claim button): shades of the app blue;
  /// red only for urgent duties.
  static Color duty(String? type, {bool urgent = false}) {
    if (urgent) return red;
    switch (type) {
      case 'icu':
        return AppColors.navy;
      case 'ward':
        return AppColors.blue;
      case 'specialty':
        return AppColors.violet;
      case 'casualty':
        return AppColors.orange;
      case 'home':
        return AppColors.accent;
      default:
        return AppTheme.primaryTeal;
    }
  }
}

BoxDecoration cpCard() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: CpColors.line),
    );

/// Gradient hero card (earnings, job count).
class CpHero extends StatelessWidget {
  final String label;
  final String value;
  final String? valueSuffix;
  final String note;
  const CpHero(
      {super.key,
      required this.label,
      required this.value,
      this.valueSuffix,
      required this.note});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.navy]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text.rich(TextSpan(children: [
              TextSpan(
                  text: value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800)),
              if (valueSuffix != null)
                TextSpan(
                    text: ' $valueSuffix',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
            ])),
            const SizedBox(height: 6),
            Text(note,
                style: const TextStyle(color: AppColors.primarySoft, fontSize: 12)),
          ],
        ),
      );
}

/// Grey info pill: "📅 Tomorrow".
class CpInfo extends StatelessWidget {
  final String text;
  final Color? color;
  final Color? background;
  const CpInfo(this.text, {super.key, this.color, this.background});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: background ?? CpColors.chip,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color ?? AppColors.slate)),
      );
}

/// Red "URGENT" / green "VERIFIED" style tag.
class CpTag extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;
  const CpTag(this.text, this.color, {super.key, this.filled = true});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: filled ? Colors.white : color)),
      );
}

/// Square emoji tile on cards.
class CpEmojiTile extends StatelessWidget {
  final String emoji;
  final Color color;
  final double size;
  const CpEmojiTile(this.emoji, this.color, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(emoji, style: TextStyle(fontSize: size * 0.45)),
      );
}

/// Horizontally scrolling filter chips.
class CpFilterChips extends StatelessWidget {
  final Map<String, String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  const CpFilterChips(
      {super.key,
      required this.options,
      required this.selected,
      required this.onSelected});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          for (final e in options.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(e.value),
                selected: selected == e.key,
                showCheckmark: false,
                onSelected: (_) => onSelected(e.key),
                selectedColor: CpColors.navy,
                backgroundColor: Colors.white,
                side: BorderSide(
                    color: selected == e.key ? CpColors.navy : CpColors.line),
                shape: const StadiumBorder(),
                labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: selected == e.key ? Colors.white : CpColors.ink),
              ),
            ),
        ]),
      );
}

/// A selectable tile of the profile wizard (grid of options).
class CpOptionTile extends StatelessWidget {
  final String emoji;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  const CpOptionTile({
    super.key,
    required this.emoji,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? AppColors.primaryTint : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
              color: selected ? CpColors.navy : CpColors.line,
              width: selected ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.all(10),
              // text wraps at the tile's width; if a long name and a large
              // font still don't fit the height, the content shrinks a
              // little instead of overflowing
              child: LayoutBuilder(
                builder: (context, c) => Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: c.maxWidth,
                      child: _content(),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );

  Widget _content() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Text(title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: CpColors.ink)),
          if (subtitle != null)
            Text(subtitle!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: CpColors.muted)),
        ],
      );
}

/// Grey chips of a profile section ("🫁 Intubation").
class CpChipWrap extends StatelessWidget {
  final List<String> items;
  final String empty;
  const CpChipWrap(this.items, {super.key, this.empty = 'Not set'});

  @override
  Widget build(BuildContext context) => items.isEmpty
      ? Text(empty, style: const TextStyle(fontSize: 12, color: CpColors.muted))
      : Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: CpColors.chip,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: CpColors.line),
              ),
              child: Text(t,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textBody)),
            ),
        ]);
}

/// Labels of a profile list: "🫁 Intubation".
List<String> cpLabels(dynamic raw, Map<String, (String, String)> options) {
  return [
    for (final k in CarePhysicianService.listOf(raw))
      if (options[k] != null) '${options[k]!.$1} ${options[k]!.$2}' else k
  ];
}

/// Empty / info message with an emoji.
class CpEmpty extends StatelessWidget {
  final String emoji;
  final String text;
  final Widget? action;
  const CpEmpty(this.emoji, this.text, {super.key, this.action});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 34)),
          const SizedBox(height: 10),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: CpColors.muted, height: 1.4)),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ]),
      );
}
