import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../constants/app_colors.dart';

/// Building blocks shared by the agency Control Rooms (care physician and
/// physio): header with period switch, numbered sections, stat cards,
/// filter chips and list rows. Everything adapts from small phones (320 px)
/// to desktop; content is capped at [ControlRoomColors.maxWidth].
class ControlRoomColors {
  static const ink = AppColors.ink;
  static const muted = AppColors.muted;
  static const border = AppColors.line;
  static const page = AppColors.chip;
  static const green = AppColors.successDark;
  static const orange = AppColors.warning;
  static const red = AppColors.danger;
  static const indigo = AppColors.indigo;
  static const blue = AppTheme.primaryTeal;
  static const teal = AppTheme.accentTeal;

  static const double maxWidth = 1200;
}

BoxDecoration controlRoomBox() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: ControlRoomColors.border),
    );

/// Centers [child] and caps its width on large screens.
class MaxWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const MaxWidth(
      {super.key, required this.child, this.maxWidth = ControlRoomColors.maxWidth});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// Today / This week / This month.
class PeriodSwitch extends StatelessWidget {
  final String period;
  final ValueChanged<String> onChanged;
  final bool compact;
  const PeriodSwitch(
      {super.key,
      required this.period,
      required this.onChanged,
      this.compact = false});

  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          const ButtonSegment(value: 'today', label: Text('Today')),
          ButtonSegment(
              value: 'week', label: Text(compact ? 'Week' : 'This week')),
          ButtonSegment(
              value: 'month', label: Text(compact ? 'Month' : 'This month')),
        ],
        selected: {period},
        showSelectedIcon: false,
        onSelectionChanged: (v) => onChanged(v.first),
      );
}

/// Agency name, a summary line and the period switch. Stacks on phones.
class ControlRoomHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String period;
  final ValueChanged<String> onPeriod;

  /// Small line above the title.
  final String brand;
  const ControlRoomHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.period,
    required this.onPeriod,
    this.brand = 'MedConnect × Partner Agency',
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: controlRoomBox(),
        child: LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 560;
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(brand,
                  style:
                      TextStyle(fontSize: 11, color: ControlRoomColors.muted)),
              const SizedBox(height: 2),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: ControlRoomColors.ink)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 12, color: ControlRoomColors.muted)),
            ],
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                text,
                const SizedBox(height: 12),
                PeriodSwitch(
                    period: period, onChanged: onPeriod, compact: c.maxWidth < 380),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: 12),
              PeriodSwitch(period: period, onChanged: onPeriod),
            ],
          );
        }),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
                color: ControlRoomColors.muted)),
      );
}

/// Cards in as many equal columns as fit (at least 2, at most one row).
class StatGrid extends StatelessWidget {
  final List<Widget> cards;
  final double minCardWidth;
  const StatGrid({super.key, required this.cards, this.minCardWidth = 190});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols =
            (c.maxWidth / minCardWidth).floor().clamp(2, cards.length).toInt();
        const gap = 10.0;
        final w = (c.maxWidth - (cols - 1) * gap) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final card in cards) SizedBox(width: w, child: card)],
        );
      });
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String? hint;
  const StatCard(
      {super.key,
      required this.label,
      required this.value,
      required this.color,
      this.hint});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 96),
        padding: const EdgeInsets.all(14),
        decoration: controlRoomBox(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: ControlRoomColors.muted)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            ),
            if (hint != null)
              Text(hint!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10, color: ControlRoomColors.muted)),
          ],
        ),
      );
}

/// Horizontally scrolling buttons under the header.
class QuickLinks extends StatelessWidget {
  final List<(IconData, String, VoidCallback)> links;
  const QuickLinks({super.key, required this.links});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (icon, label, onTap) in links)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton.icon(
                  onPressed: onTap,
                  icon: Icon(icon, size: 18),
                  label: Text(label),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    iconColor: ControlRoomColors.ink,
                    foregroundColor: ControlRoomColors.ink,
                    // the app theme makes buttons full width; in a sideways
                    // scrolling row that is infinite and the page fails
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// Filter chips that scroll sideways on small screens.
class FilterBar extends StatelessWidget {
  final Map<String, String> filters;
  final String selected;
  final ValueChanged<String> onSelected;
  const FilterBar(
      {super.key,
      required this.filters,
      required this.selected,
      required this.onSelected});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final e in filters.entries)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(e.value),
                  selected: selected == e.key,
                  selectedColor: ControlRoomColors.ink,
                  labelStyle: TextStyle(
                      color: selected == e.key
                          ? Colors.white
                          : ControlRoomColors.ink,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                  showCheckmark: false,
                  onSelected: (_) => onSelected(e.key),
                ),
              ),
          ],
        ),
      );
}

class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  const StatusBadge(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      );
}

/// One row of a list: badge, title + detail lines, and an amount or action.
/// Wide screens: badge in its own column. Phones: badge above the title.
/// Widths at which lists turn into a table with column headings.
const double kTableMinWidth = 900;
const double _kBadgeWidth = 130;
const double _kTrailingWidth = 100;

/// One column of a list shown as a table on wide screens: heading + flex.
typedef TableColumn = (String heading, int flex);

/// A list row: badge, title and detail lines (amount / action on the right).
/// Phones: badge and amount on top, details below. Tablets: badge column,
/// details, amount. Wide screens with [cells]: one table row, one value per
/// column (see [ListPanel.columns]).
class ListRow extends StatelessWidget {
  final Widget badge;
  final String title;
  final List<String> lines;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Values for the table columns (wide screens), same order as the
  /// panel's columns.
  final List<String>? cells;
  const ListRow({
    super.key,
    required this.badge,
    required this.title,
    this.lines = const [],
    this.trailing,
    this.onTap,
    this.cells,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: LayoutBuilder(builder: (context, c) {
            final columns = _TableScope.of(context);
            if (cells != null &&
                columns != null &&
                c.maxWidth >= kTableMinWidth - 28) {
              return Row(
                children: [
                  SizedBox(
                      width: _kBadgeWidth,
                      child:
                          Align(alignment: Alignment.centerLeft, child: badge)),
                  for (var i = 0; i < columns.length; i++)
                    Expanded(
                      flex: columns[i].$2,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(i < cells!.length ? cells![i] : '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    i == 0 ? FontWeight.bold : FontWeight.normal,
                                color: i == 0
                                    ? ControlRoomColors.ink
                                    : ControlRoomColors.muted)),
                      ),
                    ),
                  SizedBox(
                      width: _kTrailingWidth,
                      child: Align(
                          alignment: Alignment.centerRight,
                          child: trailing ?? const SizedBox.shrink())),
                ],
              );
            }
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: ControlRoomColors.ink)),
                for (final l in lines)
                  Text(l,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: ControlRoomColors.muted)),
              ],
            );
            if (c.maxWidth >= 560) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                      width: _kBadgeWidth,
                      child: Align(alignment: Alignment.centerLeft, child: badge)),
                  Expanded(child: details),
                  if (trailing != null) ...[const SizedBox(width: 8), trailing!],
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // badge on the left, amount / action on the right
                    Expanded(
                        child: Align(
                            alignment: Alignment.centerLeft, child: badge)),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing!,
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                details,
              ],
            );
          }),
        ),
      );
}

/// Gives rows of a [ListPanel] its table columns.
class _TableScope extends InheritedWidget {
  final List<TableColumn> columns;
  const _TableScope({required this.columns, required super.child});

  static List<TableColumn>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TableScope>()?.columns;

  @override
  bool updateShouldNotify(_TableScope old) => old.columns != columns;
}

/// White panel with dividers between rows, or an empty message. With
/// [columns], wide screens show it as a table with a heading row.
class ListPanel extends StatefulWidget {
  final List<Widget> rows;
  final String emptyText;
  final List<TableColumn>? columns;
  final String trailingHeading;

  /// Rows shown before "View all" (null = all rows).
  final int? initialRows;
  const ListPanel({
    super.key,
    required this.rows,
    required this.emptyText,
    this.columns,
    this.trailingHeading = '',
    this.initialRows,
  });

  @override
  State<ListPanel> createState() => _ListPanelState();
}

class _ListPanelState extends State<ListPanel> {
  bool _all = false;

  List<Widget> get rows => widget.rows;
  String get emptyText => widget.emptyText;
  List<TableColumn>? get columns => widget.columns;
  String get trailingHeading => widget.trailingHeading;

  static const _heading = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.4,
      color: ControlRoomColors.muted);

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: controlRoomBox(),
        child: Text(emptyText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: ControlRoomColors.muted)),
      );
    }
    final limit = widget.initialRows;
    final cut = limit != null && rows.length > limit;
    final shown = cut && !_all ? rows.take(limit).toList() : rows;
    final body = Column(children: [
      for (var i = 0; i < shown.length; i++) ...[
        if (i > 0) const Divider(height: 1),
        shown[i],
      ],
      if (cut) ...[
        const Divider(height: 1),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => setState(() => _all = !_all),
            icon: Icon(
                _all ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            label: Text(
                _all ? 'Show first $limit' : 'View all (${rows.length})'),
          ),
        ),
      ],
    ]);
    return Container(
      decoration: controlRoomBox(),
      clipBehavior: Clip.antiAlias,
      child: columns == null
          ? body
          : LayoutBuilder(builder: (context, c) {
              if (c.maxWidth < kTableMinWidth) return body;
              return _TableScope(
                columns: columns!,
                child: Column(children: [
                  Container(
                    color: ControlRoomColors.page,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      const SizedBox(
                          width: _kBadgeWidth,
                          child: Text('STATUS', style: _heading)),
                      for (final col in columns!)
                        Expanded(
                            flex: col.$2,
                            child: Text(col.$1, style: _heading)),
                      SizedBox(
                          width: _kTrailingWidth,
                          child: Text(trailingHeading,
                              textAlign: TextAlign.right, style: _heading)),
                    ]),
                  ),
                  const Divider(height: 1),
                  body,
                ]),
              );
            }),
    );
  }
}

/// Indian digit grouping: 2840000 -> ₹28,40,000.
String formatInr(num v) {
  final n = v.round();
  final s = n.abs().toString();
  final sign = n < 0 ? '-' : '';
  if (s.length <= 3) return '₹$sign$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '₹$sign${parts.join(',')},$last3';
}

String hhmm(DateTime? t) => t == null
    ? '—'
    : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String longDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct',
    'Nov', 'Dec'
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

const Map<String, String> periodLabels = {
  'today': 'today',
  'week': 'this week',
  'month': 'this month',
};
