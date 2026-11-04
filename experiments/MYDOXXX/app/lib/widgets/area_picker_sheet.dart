import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../constants/app_colors.dart';
import 'app_search_field.dart';

/// Area chooser shown from the bottom: a search box and a scrolling list,
/// never taller than ~70% of the screen (the area master has 150+ areas).
/// Returns the picked area, [AreaPickerSheet.useGps] when the user taps
/// "Use Live GPS Location", or null when dismissed.
class AreaPickerSheet extends StatefulWidget {
  final List<String> areas;
  final String? selected;
  final bool showGps;

  const AreaPickerSheet({
    super.key,
    required this.areas,
    this.selected,
    this.showGps = true,
  });

  /// Returned when the user wants their live GPS location.
  static const String useGps = '__gps__';

  static Future<String?> show(
    BuildContext context, {
    required List<String> areas,
    String? selected,
    bool showGps = true,
  }) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          maxWidth: 640,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (_) => AreaPickerSheet(
            areas: areas, selected: selected, showGps: showGps),
      );

  @override
  State<AreaPickerSheet> createState() => _AreaPickerSheetState();
}

class _AreaPickerSheetState extends State<AreaPickerSheet> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = widget.areas
        .where((a) => q.isEmpty || a.toLowerCase().contains(q))
        .toList();
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.lineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(children: [
              Icon(Icons.location_on_rounded,
                  color: AppTheme.primaryTeal, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text('Select Service Location',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkNavy)),
              ),
            ]),
          ),
          if (widget.showGps)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: CircleAvatar(
                backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.1),
                child: const Icon(Icons.my_location_rounded,
                    color: AppTheme.primaryTeal),
              ),
              title: const Text('Use Live GPS Location',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Detect your current area',
                  style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(context, AreaPickerSheet.useGps),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: AppSearchField(
              controller: _searchCtrl,
              hint: 'Search area',
              dense: true,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Flexible(
            child: shown.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No area matches your search.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textMuted)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final area = shown[i];
                      final selected = area == widget.selected;
                      return ListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        title: Text(area,
                            style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: selected
                                    ? AppTheme.primaryTeal
                                    : AppTheme.darkNavy)),
                        trailing: selected
                            ? const Icon(Icons.check_rounded,
                                color: AppTheme.primaryTeal)
                            : null,
                        onTap: () => Navigator.pop(context, area),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
