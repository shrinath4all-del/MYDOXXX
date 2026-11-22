import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../constants/app_colors.dart';
import 'app_search_field.dart';

/// Preferred areas as a dropdown-style field: one compact box showing the
/// chosen areas; tapping it opens a searchable list with checkboxes (never
/// taller than ~75% of the screen). Replaces a wall of 150+ area chips.
class AreaMultiSelectField extends StatelessWidget {
  final List<String> areas;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final Color accent;
  final String hint;
  final bool loading;

  const AreaMultiSelectField({
    super.key,
    required this.areas,
    required this.selected,
    required this.onChanged,
    this.accent = AppTheme.primaryTeal,
    this.hint = 'Select areas',
    this.loading = false,
  });

  /// The text shown in the closed field.
  static String summary(Set<String> selected, String hint) {
    if (selected.isEmpty) return hint;
    final list = selected.toList();
    if (list.length <= 2) return list.join(', ');
    return '${list.take(2).join(', ')} +${list.length - 2} more';
  }

  Future<void> _open(BuildContext context) async {
    // saved areas the master no longer lists stay visible (and removable)
    final options = [
      ...areas,
      for (final a in selected)
        if (!areas.contains(a)) a,
    ];
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        maxWidth: 640,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AreaChecklistSheet(
          areas: options,
          initial: selected,
          accent: accent,
          // ticking, unticking or Clear shows on the form straight away,
          // however the sheet is closed
          onChanged: onChanged),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Center(child: CircularProgressIndicator(color: accent)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _open(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.lineStrong),
              ),
              child: Row(children: [
                Icon(Icons.place_outlined, color: accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    summary(selected, hint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: selected.isEmpty
                          ? AppTheme.textMuted
                          : AppTheme.darkNavy,
                      fontWeight:
                          selected.isEmpty ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down_rounded,
                    color: AppTheme.textMuted),
              ]),
            ),
          ),
        ),
        // chosen areas, each removable, below the field
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in selected)
                InputChip(
                  label: Text(a, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: accent.withValues(alpha: 0.10),
                  side: BorderSide(color: accent.withValues(alpha: 0.30)),
                  deleteIconColor: accent,
                  onDeleted: () => onChanged({...selected}..remove(a)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AreaChecklistSheet extends StatefulWidget {
  final List<String> areas;
  final Set<String> initial;
  final Color accent;

  const _AreaChecklistSheet({
    required this.areas,
    required this.initial,
    required this.accent,
    required this.onChanged,
  });

  final ValueChanged<Set<String>> onChanged;

  @override
  State<_AreaChecklistSheet> createState() => _AreaChecklistSheetState();
}

class _AreaChecklistSheetState extends State<_AreaChecklistSheet> {
  late final Set<String> _picked = {...widget.initial};

  /// Changes the ticks and tells the form at once.
  void _change(void Function() fn) {
    setState(fn);
    widget.onChanged({..._picked});
  }
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
            child: Row(children: [
              Expanded(
                child: Text('Select areas (${_picked.length})',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkNavy)),
              ),
              if (_picked.isNotEmpty)
                TextButton(
                  onPressed: () => _change(_picked.clear),
                  child: const Text('Clear'),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                    child: Text('No matching area.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textMuted)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: shown.length,
                    itemBuilder: (_, i) {
                      final a = shown[i];
                      return CheckboxListTile(
                        dense: true,
                        activeColor: widget.accent,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(a),
                        value: _picked.contains(a),
                        onChanged: (on) => _change(() =>
                            on == true ? _picked.add(a) : _picked.remove(a)),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: widget.accent,
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(context, _picked),
                child: const Text('Done'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
