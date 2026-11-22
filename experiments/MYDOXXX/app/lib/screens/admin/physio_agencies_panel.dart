import 'package:flutter/material.dart';
import '../../utils/form_utils.dart';
import '../../utils/safe_cast.dart';

import '../../services/firestore_service.dart';
import '../../services/physio_agency_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../../utils/validators.dart';
import '../../utils/responsive.dart';
import '../../utils/stream_cache.dart';
import '../../widgets/agency_type_picker.dart';
import '../../widgets/area_multi_select_field.dart';
import '../../constants/app_colors.dart';

/// Admin: agencies partnered with the app. Only the admin adds agencies
/// (name, mobile number, type, areas); the agency then logs in with that
/// mobile number.
///
/// Physio agency: gets the physio requests in its areas first (for its accept
/// time), through its on-duty physios; then the request opens to all physios
/// in the area. Care physician agency: runs doctor duties in its Control Room.
class PhysioAgenciesPanel extends StatefulWidget {
  const PhysioAgenciesPanel({super.key});

  @override
  State<PhysioAgenciesPanel> createState() => _PhysioAgenciesPanelState();
}

class _PhysioAgenciesPanelState extends State<PhysioAgenciesPanel> {
  late final Stream<List<Map<String, dynamic>>> _agencies =
      PhysioAgencyService.allAgenciesStream();
  // one team listener per agency, kept across redraws
  final _streams = StreamCache();

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.danger : AppColors.successDark,
    ));
  }

  Future<void> _edit([Map<String, dynamic>? agency]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AgencyDialog(agency: agency),
    );
    if (saved == true) {
      _snack(agency == null ? 'Agency added.' : 'Agency updated.');
    }
  }

  Future<void> _setActive(Map<String, dynamic> a, bool active) async {
    try {
      await PhysioAgencyService.setAgencyActive(a['id'].toString(), active);
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'update the agency'), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final name = (a['name'] ?? 'this agency').toString();
    final isCare = a['agencyType'] == 'care_physician' || a['agencyType'] == 'nurse' || a['agencyType'] == 'technician';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $name?'),
        content: Text(isCare
            ? 'The agency can no longer log in. Its doctors, hospitals and '
                'duties (including payout records) are deleted. This cannot '
                'be undone.'
            : 'The agency can no longer log in and gets no more requests. '
                'Its physios stay on the app as freelancers with their '
                'profile, ratings and history. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PhysioAgencyService.deleteAgency(a['id'].toString());
      _snack('$name deleted.');
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'delete the agency'), error: true);
    }
  }

  Future<void> _remove(Map<String, dynamic> physio, String agencyName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from agency?'),
        content: Text(
            '${physio['name'] ?? 'This physio'} leaves $agencyName and becomes '
            'freelance. Their profile, ratings and history are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PhysioAgencyService.removeFromAgency(physio['uid'].toString());
      _snack('Removed from $agencyName.');
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'remove the physio'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _agencies,
      builder: (context, snap) {
        if (snap.hasError) {
          return LoadErrorView(error: snap.error, what: 'agencies');
        }
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryTeal));
        }
        final agencies = snap.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const Text(
              'Only the admin adds agencies. The agency logs in with the '
              'mobile number saved here. Physio agencies: requests in their '
              'areas go to their on-duty physios first; if none accepts within '
              'the accept time, all physios in the area get them.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_business_rounded, size: 18),
              label: const Text('Add agency'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
            const SizedBox(height: 12),
            if (agencies.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: Text('No agencies yet.',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkNavy)),
                ),
              ),
            for (final a in agencies) _agencyCard(a),
          ],
        );
      },
    );
  }

  Widget _agencyCard(Map<String, dynamic> a) {
    final active = a['active'] == true;
    final isCare = a['agencyType'] == 'care_physician' || a['agencyType'] == 'nurse' || a['agencyType'] == 'technician';
    final name = (a['name'] ?? 'Agency').toString();
    final phone = (a['phone'] ?? a['mobileNumber'] ?? '').toString();
    final areas = PhysioAgencyService.areasOf(a);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: active ? AppColors.successLight : AppColors.lineStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkNavy)),
              ),
              Text(active ? 'Receives requests' : 'Paused',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: active ? AppColors.successDeep : AppColors.muted)),
              Switch(
                value: active,
                activeColor: AppColors.successDark,
                onChanged: (v) => _setActive(a, v),
              ),
            ],
          ),
          Text(
            [
              isCare ? 'Care physician agency' : 'Physio agency',
              if (phone.isNotEmpty) phone,
              if (!isCare) ...[
                'Accept time ${PhysioAgencyService.acceptWindowOf(a)} min',
                'Commission ${(toNum(a['commissionPct']) ?? PhysioAgencyService.defaultCommissionPct).toString()}%',
              ],
            ].join(' · '),
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: areas.isEmpty
                ? [
                    const Text('No areas set',
                        style: TextStyle(fontSize: 12, color: AppColors.danger))
                  ]
                : [
                    for (final area in areas)
                      Chip(
                        label: Text(area, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
          ),
          if (!isCare)
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _streams.get('team_${a['id']}',
                () => PhysioAgencyService.teamStream(a['id'].toString())),
            builder: (context, snap) {
              final team = snap.data ?? const [];
              final onDuty = team
                  .where((p) =>
                      PhysioAgencyService.isOnAgencyDuty(p, a['id'].toString()))
                  .length;
              return ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Team: ${team.length} physios · $onDuty on duty',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
                children: [
                  if (team.isEmpty)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          'Physios join from their dashboard ("Join an agency").',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textMuted)),
                    ),
                  for (final p in team)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text((p['name'] ?? 'Physio').toString()),
                      subtitle: Text('${p['workMode'] ?? 'freelance'} · '
                          '${p['isVerified'] == true ? 'verified' : 'not verified'} · '
                          'Rating ${FirestoreService.ratingLabel(p)}'),
                      trailing: TextButton(
                        onPressed: () => _remove(p, name),
                        child: const Text('Remove',
                            style: TextStyle(color: AppColors.danger)),
                      ),
                    ),
                ],
              );
            },
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _delete(a),
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Delete'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  iconColor: AppColors.danger,
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _edit(a),
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: const Text('Edit'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgencyDialog extends StatefulWidget {
  final Map<String, dynamic>? agency;
  const _AgencyDialog({this.agency});

  @override
  State<_AgencyDialog> createState() => _AgencyDialogState();
}

class _AgencyDialogState extends State<_AgencyDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name =
      TextEditingController(text: widget.agency?['name']?.toString() ?? '');
  late final _email =
      TextEditingController(text: widget.agency?['email']?.toString() ?? '');
  late final _phone = TextEditingController(
      text: (widget.agency?['phone'] ?? widget.agency?['mobileNumber'] ?? '')
          .toString());
  late String _type = switch ((widget.agency?['agencyType'] ?? 'physio').toString()) {
    'care_physician' => 'care_physician',
    'nurse' => 'nurse',
    'technician' => 'technician',
    _ => 'physio',
  };
  late final _commission = TextEditingController(
      text: ((widget.agency?['commissionPct'] as num?) ??
              PhysioAgencyService.defaultCommissionPct)
          .toString());
  late final _window = TextEditingController(
      text: (widget.agency == null
              ? PhysioAgencyService.defaultAcceptWindowMin
              : PhysioAgencyService.acceptWindowOf(widget.agency!))
          .toString());
  late Set<String> _areas = widget.agency == null
      ? {}
      : PhysioAgencyService.areasOf(widget.agency!).toSet();
  late bool _active = widget.agency?['active'] ?? true;
  List<String> _allAreas = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    FirestoreService.getLocationMaster().then((all) {
      if (!mounted) return;
      setState(() => _allAreas = {...all, ..._areas}.toList()..sort());
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _commission, _window]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _range(String? v, num min, num max, String what) {
    final n = num.tryParse((v ?? '').trim());
    if (n == null || n < min || n > max) return '$what must be $min–$max';
    return null;
  }

  Future<void> _save() async {
    if (!FormUtils.validate(_formKey)) return;
    if (_areas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pick at least one area.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await PhysioAgencyService.saveAgency(
        id: widget.agency?['id'],
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text,
        agencyType: _type,
        areas: _areas.toList()..sort(),
        commissionPct: double.parse(_commission.text.trim()),
        acceptWindowMin: int.parse(_window.text.trim()),
        active: _active,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ErrorMessages.of(e, action: 'save the agency')),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.agency == null ? 'Add agency' : 'Edit agency'),
      content: SizedBox(
        width: Responsive.dialogWidth(context),
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              const _Label('AGENCY NAME'),
              TextFormField(
                controller: _name,
                validator: (v) => Validators.orgName(v, label: 'agency name'),
                decoration:
                    const InputDecoration(hintText: 'e.g. Apex Physio Agency'),
              ),
              const SizedBox(height: 14),
              const _Label('EMAIL (USED TO LOG IN)'),
              TextFormField(
                controller: _email,
                validator: Validators.email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                    hintText: 'agency@example.com',
                    helperText: widget.agency == null ||
                            (widget.agency?['ownerUid'] ?? '').toString().isEmpty
                        ? 'A link to choose the password is emailed to the agency.'
                        : null),
              ),
              const SizedBox(height: 14),
              const _Label('MOBILE NUMBER'),
              TextFormField(
                controller: _phone,
                validator: Validators.mobile,
                inputFormatters: Validators.phoneInput,
                keyboardType: TextInputType.phone,
                decoration:
                    const InputDecoration(hintText: '+91 98765 43210'),
              ),
              const SizedBox(height: 14),
              const _Label('TYPE OF AGENCY'),
              AgencyTypePicker(
                value: _type,
                onChanged: (t) => setState(() => _type = t),
              ),
              if (_type != 'care_physician') ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _window,
                        validator: (v) => _range(v, 1, 60, 'Accept time'),
                        inputFormatters: Validators.digitsInput(2),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Accept time (min)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _commission,
                        validator: (v) => _range(v, 0, 60, 'Commission'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration:
                            const InputDecoration(labelText: 'Commission %'),
                      ),
                    ),
                  ],
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              const SizedBox(height: 4),
              const _Label('AREA'),
              AreaMultiSelectField(
                loading: _allAreas.isEmpty,
                areas: _allAreas,
                selected: _areas,
                onChanged: (v) => setState(() => _areas = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style:
              ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.darkNavy)),
      );
}

