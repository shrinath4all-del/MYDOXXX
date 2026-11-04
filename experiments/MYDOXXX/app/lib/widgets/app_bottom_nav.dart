import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// One tab of [AppBottomNav].
class AppNavItem {
  final IconData icon;
  final String label;

  /// A red count on the tab (e.g. chats with unread messages); 0 hides it.
  final int badge;
  const AppNavItem(this.icon, this.label, {this.badge = 0});
}

/// Floating bottom bar: a white rounded pill lifted off the screen edge (a
/// gap at the sides and below, soft shadow), icons only. The selected tab is
/// raised in a filled circle above the bar. The label is kept for screen
/// readers and long-press. Keeps clear of the phone's gesture bar and stays
/// centred and narrow on tablets.
class AppBottomNav extends StatelessWidget {
  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color color;

  const AppBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.color = AppColors.brand,
  });

  static const double barHeight = 60;
  static const double _bubble = 52;
  static const double _lift = 22;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final width = MediaQuery.sizeOf(context).width;
    // floats above the screen edge: a gap at the sides and below
    final side = width < 360 ? 12.0 : 18.0;
    return Padding(
      // room for the raised circle above the bar; below it the gap plus the
      // phone's gesture bar
      padding: EdgeInsets.fromLTRB(side, _lift, side, bottom + 12),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            height: barHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(barHeight / 2),
              border: Border.all(color: AppColors.line),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: 0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(children: [
              for (var i = 0; i < items.length; i++) Expanded(child: _tab(i)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _tab(int i) {
    final item = items[i];
    final selected = i == currentIndex;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: Tooltip(
        message: item.label,
        child: InkResponse(
          onTap: () => onTap(i),
          radius: 36,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              // raised circle for the selected tab, plain icon otherwise
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                top: selected ? -_lift : (barHeight - 28) / 2,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: selected ? _bubble : 28,
                  height: selected ? _bubble : 28,
                  decoration: BoxDecoration(
                    color: selected ? color : Colors.transparent,
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(color: Colors.white, width: 4)
                        : null,
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : null,
                  ),
                  child: Badge(
                    isLabelVisible: item.badge > 0,
                    backgroundColor: AppColors.unread,
                    textColor: Colors.white,
                    label: Text(item.badge > 99 ? '99+' : '${item.badge}'),
                    child: Icon(item.icon,
                        size: selected ? 25 : 26,
                        color: selected ? Colors.white : AppColors.muted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
