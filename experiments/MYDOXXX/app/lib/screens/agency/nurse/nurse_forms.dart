import '../../../services/app_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../utils/form_utils.dart';
import '../../../utils/safe_cast.dart';
import '../../../services/nurse_staffing_service.dart';
import 'package:flutter/material.dart';

import '../../../services/care_agency_service.dart';
import '../../../services/pricing_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/error_messages.dart';
import '../../../utils/validators.dart';
import '../../../utils/responsive.dart';
import 'nurse_control_room_screen.dart' show formatInr;
import '../../../constants/app_colors.dart';

import '../../../widgets/app_search_field.dart';

const _muted = AppColors.muted;

void _snack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? AppColors.danger : AppColors.successDark,
  ));
}

InputDecoration _dec(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );

/// Side padding: 16 on phones, centred ~720 px column on tablets / desktop.
EdgeInsets nursePagePadding(BuildContext context,
    {double top = 16, double bottom = 16, double maxWidth = 720}) {
  final w = MediaQuery.sizeOf(context).width;
  final side = w > maxWidth + 32 ? (w - maxWidth) / 2 : 16.0;
  return EdgeInsets.fromLTRB(side, top, side, bottom);
}

String _hmOf(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

// =========================================================== agency settings

/// Agency name, city and the money split (must add up to 100%).
Future<void> showNurseAgencySettingsDialog(
    BuildContext context, Map<String, dynamic> agency) async {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(text: (agency['name'] ?? '').toString());
  final city = TextEditingController(text: (agency['city'] ?? '').toString());
  final phone = TextEditingController(text: (agency['phone'] ?? '').toString());
  final doctor = TextEditingController(
      text: (toNum(agency['splitDoctorPct']) ?? 80).toString());
  final agencyPct = TextEditingController(
      text: (toNum(agency['splitAgencyPct']) ?? 15).toString());
  final app = TextEditingController(
      text: (toNum(agency['splitAppPct']) ?? 5).toString());

  String? pct(String? v) {
    final n = num.tryParse((v ?? '').trim());
    return n == null || n < 0 || n > 100 ? '0–100' : null;
  }

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Partner settings'),
      content: SizedBox(
        width: Responsive.dialogWidth(context),
        child: Form(
          key: formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              TextFormField(
                  controller: name,
                  validator: (v) => Validators.orgName(v, label: 'partner name'),
                  decoration: _dec('Partner name')),
              const SizedBox(height: 10),
              TextFormField(
                  controller: city,
                  validator: Validators.city,
                  decoration: _dec('City')),
              const SizedBox(height: 10),
              TextFormField(
                  controller: phone,
                  // the login number: only the admin changes it
                  enabled: false,
                  decoration: _dec('Mobile number (set by admin)')),
              const SizedBox(height: 16),
              const Text('MONEY SPLIT OF EACH DUTY (%)',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _muted)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: TextFormField(
                        controller: doctor,
                        validator: pct,
                        keyboardType: TextInputType.number,
                        decoration: _dec('Nurse'))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextFormField(
                        controller: agencyPct,
                        validator: pct,
                        keyboardType: TextInputType.number,
                        decoration: _dec('Profit'))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextFormField(
                        controller: app,
                        validator: pct,
                        keyboardType: TextInputType.number,
                        decoration: _dec('App'))),
              ]),
              const SizedBox(height: 6),
              const Text(
                  'Use the percentages from your partner agreement. New duties use the new split.',
                  style: TextStyle(fontSize: 11, color: _muted)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            if (!FormUtils.validate(formKey)) return;
            final d = num.parse(doctor.text),
                a = num.parse(agencyPct.text),
                p = num.parse(app.text);
            if (d + a + p != 100) {
              _snack(ctx, 'Nurse + Profit + App must add up to 100%.',
                  error: true);
              return;
            }
            try {
              await AppDatabase.instance
                  .collection('agencies')
                  .doc(agency['id'].toString())
                  .set({
                'name': name.text.trim(),
                'organisation': name.text.trim(),
                'city': city.text.trim(),
                'splitDoctorPct': d,
                'splitAgencyPct': a,
                'splitAppPct': p,
                'updatedAt': DateTime.now().toIso8601String(),
              }, SetOptions(merge: true));
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              if (ctx.mounted) {
                _snack(ctx, ErrorMessages.of(e, action: 'save the settings'),
                    error: true);
              }
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

// ================================================================ doctors

class NurseAgencyDoctorsScreen extends StatefulWidget {
  final Map<String, dynamic> agency;
  @visibleForTesting
  final Stream<List<Map<String, dynamic>>>? testDoctors;
  @visibleForTesting
  final Stream<List<Map<String, dynamic>>>? testHospitals;
  const NurseAgencyDoctorsScreen(
      {super.key, required this.agency, this.testDoctors, this.testHospitals});

  @override
  State<NurseAgencyDoctorsScreen> createState() => _AgencyDoctorsScreenState();
}

class _AgencyDoctorsScreenState extends State<NurseAgencyDoctorsScreen> {
  late final _doctors = widget.testDoctors ??
      CareAgencyService.doctorsStream(widget.agency['id'].toString());
  late final _hospitals = widget.testHospitals ??
      CareAgencyService.hospitalsStream(widget.agency['id'].toString());
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nurses')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _doctors,
        builder: (context, snap) {
          if (snap.hasError) {
            return LoadErrorView(error: snap.error, what: 'nurses');
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final today = CareAgencyService.dateKey(DateTime.now());
          final q = _search.toLowerCase();
          final list = snap.data!
              .where((d) =>
                  q.isEmpty ||
                  '${d['name']} ${d['phone']} ${d['regNo']}'
                      .toLowerCase()
                      .contains(q))
              .toList();
          return ListView(
            padding: nursePagePadding(context, top: 12, bottom: 96),
            children: [
              AppSearchField(
                controller: _searchCtrl,
                hint: 'Search name, phone or reg. no.',
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 8),
              Text(
                  '${snap.data!.where((d) => d['active'] != false).length} active of ${snap.data!.length}',
                  style: const TextStyle(color: _muted, fontSize: 12)),
              const SizedBox(height: 8),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No nurses yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted)),
                ),
              for (final d in list)
                Card(
                  child: ListTile(
                    onTap: () => _edit(d),
                    leading: CircleAvatar(
                      backgroundColor: d['active'] == false
                          ? AppColors.line
                          : AppTheme.pastelBlue,
                      child: Icon(Icons.medical_services_outlined,
                          color: d['active'] == false
                              ? AppColors.muted
                              : AppTheme.primaryTeal),
                    ),
                    title: Text((d['name'] ?? '').toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text([
                      d['qualification'] ?? '',
                      if ((d['phone'] ?? '').toString().isNotEmpty) d['phone'],
                      d['placementType'] == 'permanent'
                          ? 'Permanent at ${d['permanentHospitalName'] ?? 'hospital'}'
                          : 'Pool',
                      if (CareAgencyService.isOnLeave(d, today)) 'On leave',
                      if (d['active'] == false) 'Inactive',
                      d['userUid'] != null ? 'App linked' : 'Not on app yet',
                    ].join(' · ')),
                    trailing: const Icon(Icons.edit_outlined),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(Map<String, dynamic>? doctor) async {
    final hospitals =
        await _hospitals.first.catchError((_) => <Map<String, dynamic>>[]);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _DoctorForm(
          agencyId: widget.agency['id'].toString(),
          doctor: doctor,
          hospitals: hospitals),
    ));
  }
}

class _DoctorForm extends StatefulWidget {
  final String agencyId;
  final Map<String, dynamic>? doctor;
  final List<Map<String, dynamic>> hospitals;
  const _DoctorForm(
      {required this.agencyId, this.doctor, required this.hospitals});

  @override
  State<_DoctorForm> createState() => _DoctorFormState();
}

class _DoctorFormState extends State<_DoctorForm> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, dynamic> d = widget.doctor ?? {};
  late final _name = TextEditingController(text: (d['name'] ?? '').toString());
  late final _phone =
      TextEditingController(text: (d['phone'] ?? '').toString());
  late final _regNo =
      TextEditingController(text: (d['regNo'] ?? '').toString());
  late String _qualification =
      NurseStaffingService.qualifications.keys.contains(d['qualification'])
          ? d['qualification']
          : 'GNM';
  late String _placement =
      d['placementType'] == 'permanent' ? 'permanent' : 'pool';
  late String? _hospitalId = (d['permanentHospitalId'] as String?);
  late String? _since = (d['permanentSince'] as String?);
  late String? _leaveFrom = (d['leaveFrom'] as String?);
  late String? _leaveTo = (d['leaveTo'] as String?);
  late bool _active = d['active'] != false;
  bool _saving = false;

  Future<String?> _pickDate(String? current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: CareAgencyService.parseKey(current) ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    return picked == null ? current : CareAgencyService.dateKey(picked);
  }

  Future<void> _save() async {
    if (!FormUtils.validate(_formKey)) return;
    if (_placement == 'permanent' && _hospitalId == null) {
      _snack(context, 'Choose the hospital for a permanent placement.',
          error: true);
      return;
    }
    if ((_leaveFrom == null) != (_leaveTo == null) ||
        (_leaveFrom != null && _leaveFrom!.compareTo(_leaveTo!) > 0)) {
      _snack(context, 'Set both leave dates, "from" before "to".', error: true);
      return;
    }
    setState(() => _saving = true);
    final hospital = widget.hospitals
        .where((h) => h['id'] == _hospitalId)
        .cast<Map<String, dynamic>?>()
        .firstWhere((_) => true, orElse: () => null);
    try {
      await CareAgencyService.saveDoctor(
          widget.agencyId,
          {
            'name': _name.text.trim(),
            'phone': _phone.text.trim(),
            'qualification': _qualification,
            'regNo': _regNo.text.trim(),
            'placementType': _placement,
            'permanentHospitalId':
                _placement == 'permanent' ? _hospitalId : null,
            'permanentHospitalName':
                _placement == 'permanent' ? (hospital?['name']) : null,
            'permanentSince': _placement == 'permanent' ? _since : null,
            'leaveFrom': _leaveFrom,
            'leaveTo': _leaveTo,
            'active': _active,
          },
          id: widget.doctor?['id']);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(context, ErrorMessages.of(e, action: 'save the nurse'),
            error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget dateField(String label, String? value, ValueChanged<String?> set) =>
        InkWell(
          onTap: () async => set(await _pickDate(value)),
          child: InputDecorator(
            decoration: _dec(label).copyWith(
              suffixIcon: value == null
                  ? const Icon(Icons.calendar_today, size: 18)
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => set(null)),
            ),
            child: Text(value ?? '—'),
          ),
        );

    return Scaffold(
      appBar: AppBar(
          title: Text(widget.doctor == null ? 'Add nurse' : 'Edit nurse')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: nursePagePadding(context),
          children: [
            TextFormField(
                controller: _name,
                validator: (v) =>
                    Validators.personName(v, label: 'nurse name'),
                decoration: _dec('Full name', hint: 'Dr. Priya Deshmukh')),
            const SizedBox(height: 12),
            TextFormField(
                controller: _phone,
                validator: Validators.mobile,
                inputFormatters: Validators.phoneInput,
                keyboardType: TextInputType.phone,
                decoration: _dec('Mobile number',
                    hint: 'Same number the nurse logs in with')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  menuMaxHeight: 320,
                  value: _qualification,
                  isExpanded: true,
                  decoration: _dec('Qualification'),
                  items: [
                    for (final q in NurseStaffingService.qualifications.keys)
                      DropdownMenuItem(value: q, child: Text(q)),
                  ],
                  onChanged: (v) => setState(() => _qualification = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                    controller: _regNo,
                    validator: Validators.registrationNumber,
                    decoration: _dec('Reg. no.')),
              ),
            ]),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pool', label: Text('Pool (locum)')),
                ButtonSegment(value: 'permanent', label: Text('Permanent')),
              ],
              selected: {_placement},
              onSelectionChanged: (v) => setState(() => _placement = v.first),
            ),
            if (_placement == 'permanent') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                menuMaxHeight: 320,
                value: widget.hospitals.any((h) => h['id'] == _hospitalId)
                    ? _hospitalId
                    : null,
                isExpanded: true,
                decoration: _dec('Permanent at hospital'),
                items: [
                  for (final h in widget.hospitals)
                    DropdownMenuItem(
                        value: h['id'] as String,
                        child: Text('${h['name']} · ${h['area'] ?? ''}')),
                ],
                onChanged: (v) => setState(() => _hospitalId = v),
              ),
              if (widget.hospitals.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Add the hospital first under Hospitals.',
                      style: TextStyle(color: AppColors.danger, fontSize: 12)),
                ),
              const SizedBox(height: 12),
              dateField(
                  'Permanent since', _since, (v) => setState(() => _since = v)),
            ],
            const SizedBox(height: 16),
            const Text('LEAVE',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold, color: _muted)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: dateField('From', _leaveFrom,
                      (v) => setState(() => _leaveFrom = v))),
              const SizedBox(width: 12),
              Expanded(
                  child: dateField(
                      'To', _leaveTo, (v) => setState(() => _leaveTo = v))),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active with partner'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  minimumSize: const Size(double.infinity, 48)),
              child: Text(_saving ? 'Saving…' : 'Save nurse'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================== hospitals

class NurseAgencyHospitalsScreen extends StatefulWidget {
  final Map<String, dynamic> agency;
  @visibleForTesting
  final Stream<List<Map<String, dynamic>>>? testHospitals;
  const NurseAgencyHospitalsScreen(
      {super.key, required this.agency, this.testHospitals});

  @override
  State<NurseAgencyHospitalsScreen> createState() => _AgencyHospitalsScreenState();
}

class _AgencyHospitalsScreenState extends State<NurseAgencyHospitalsScreen> {
  late final _hospitals = widget.testHospitals ??
      CareAgencyService.hospitalsStream(widget.agency['id'].toString());

  Future<void> _edit(Map<String, dynamic>? h) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: (h?['name'] ?? '').toString());
    final area = TextEditingController(text: (h?['area'] ?? '').toString());
    final contact =
        TextEditingController(text: (h?['contactName'] ?? '').toString());
    final phone =
        TextEditingController(text: (h?['contactPhone'] ?? '').toString());
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(h == null ? 'Add hospital' : 'Edit hospital'),
        content: SizedBox(
          width: Responsive.dialogWidth(context),
          child: Form(
            key: formKey,
            child: ListView(shrinkWrap: true, children: [
              TextFormField(
                  controller: name,
                  validator: (v) =>
                      Validators.orgName(v, label: 'hospital name'),
                  decoration: _dec('Hospital name')),
              const SizedBox(height: 10),
              TextFormField(
                  controller: area,
                  validator: (v) => Validators.required(v, 'the area'),
                  decoration: _dec('Area', hint: 'Kothrud, Pune')),
              const SizedBox(height: 10),
              TextFormField(
                  controller: contact,
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? null
                      : Validators.personName(v, label: 'contact name'),
                  decoration: _dec('Contact person (optional)')),
              const SizedBox(height: 10),
              TextFormField(
                  controller: phone,
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? null
                      : Validators.contactNumber(v),
                  inputFormatters: Validators.phoneInput,
                  decoration: _dec('Contact phone (optional)')),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (!FormUtils.validate(formKey)) return;
              try {
                await CareAgencyService.saveHospital(
                    widget.agency['id'].toString(),
                    {
                      'name': name.text.trim(),
                      'area': area.text.trim(),
                      'contactName': contact.text.trim(),
                      'contactPhone': phone.text.trim(),
                    },
                    id: h?['id']);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  _snack(ctx, ErrorMessages.of(e, action: 'save the hospital'),
                      error: true);
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hospitals')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _hospitals,
        builder: (context, snap) {
          if (snap.hasError) {
            return LoadErrorView(error: snap.error, what: 'hospitals');
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.data!.isEmpty) {
            return const Center(
                child: Text('No hospitals yet.',
                    style: TextStyle(color: _muted)));
          }
          return ListView(
            padding: nursePagePadding(context, top: 12, bottom: 96),
            children: [
              for (final h in snap.data!)
                Card(
                  child: ListTile(
                    onTap: () => _edit(h),
                    leading: const Icon(Icons.local_hospital_outlined,
                        color: AppTheme.primaryTeal),
                    title: Text((h['name'] ?? '').toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text([
                      h['area'] ?? '',
                      if ((h['contactName'] ?? '').toString().isNotEmpty)
                        h['contactName'],
                      if ((h['contactPhone'] ?? '').toString().isNotEmpty)
                        h['contactPhone'],
                    ].join(' · ')),
                    trailing: const Icon(Icons.edit_outlined),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================ duty form

class NurseDutyFormScreen extends StatefulWidget {
  final Map<String, dynamic> agency;

  /// Pre-select this doctor (from a "No job" row).
  final String? doctorId;

  /// Reassign: same hospital, type, unit, shift and rate as this duty.
  final Map<String, dynamic>? copyFrom;

  @visibleForTesting
  final Stream<List<Map<String, dynamic>>>? testDoctors;
  @visibleForTesting
  final Stream<List<Map<String, dynamic>>>? testHospitals;

  const NurseDutyFormScreen(
      {super.key,
      required this.agency,
      this.doctorId,
      this.copyFrom,
      this.testDoctors,
      this.testHospitals});

  @override
  State<NurseDutyFormScreen> createState() => _DutyFormScreenState();
}

class _DutyFormScreenState extends State<NurseDutyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final String _agencyId = widget.agency['id'].toString();
  late final _doctorsStream =
      widget.testDoctors ?? CareAgencyService.doctorsStream(_agencyId);
  late final _hospitalsStream =
      widget.testHospitals ?? CareAgencyService.hospitalsStream(_agencyId);

  late String? _doctorId = widget.doctorId;
  late String? _hospitalId = (widget.copyFrom?['hospitalId'] as String?);
  late String _type = (widget.copyFrom?['type'] ?? 'locum').toString();
  late String _unit = (widget.copyFrom?['unit'] ?? 'ward').toString();
  late DateTime _day =
      CareAgencyService.parseKey(widget.copyFrom?['date']) ?? DateTime.now();
  late TimeOfDay _start = _todOf(widget.copyFrom?['shiftStart']) ??
      const TimeOfDay(hour: 8, minute: 0);
  late TimeOfDay _end = _todOf(widget.copyFrom?['shiftEnd']) ??
      const TimeOfDay(hour: 20, minute: 0);
  late final _rate = TextEditingController(
      text: (widget.copyFrom?['baseRate'] ?? widget.copyFrom?['hospitalRate'])
              ?.toString() ??
          '');
  PricingSettings _pricing = PricingService.current;
  Set<String> _busy = {};
  bool _saving = false;

  static TimeOfDay? _todOf(dynamic raw) {
    final t = CareAgencyService.asTime(raw);
    return t == null ? null : TimeOfDay.fromDateTime(t);
  }

  @override
  void initState() {
    super.initState();
    _loadBusy();
    PricingService.load().then((p) {
      if (mounted) setState(() => _pricing = p);
    });
  }

  /// Doctors who already have a duty on the chosen day.
  Future<void> _loadBusy() async {
    try {
      final key = CareAgencyService.dateKey(_day);
      final duties =
          await CareAgencyService.dutiesStream(_agencyId, key, key).first;
      if (!mounted) return;
      setState(() => _busy = {
            for (final d in duties)
              if (d['status'] != 'cancelled' && d['status'] != 'absent')
                d['doctorId'].toString()
          });
    } catch (_) {}
  }

  Future<void> _save(List<Map<String, dynamic>> doctors,
      List<Map<String, dynamic>> hospitals) async {
    if (!FormUtils.validate(_formKey)) return;
    final doctor = doctors.firstWhere((d) => d['id'] == _doctorId);
    final hospital = hospitals.firstWhere((h) => h['id'] == _hospitalId);
    setState(() => _saving = true);
    try {
      await CareAgencyService.createDuty(
        agency: widget.agency,
        doctor: doctor,
        hospital: hospital,
        type: _type,
        unit: _unit,
        day: _day,
        startHm: _hmOf(_start),
        endHm: _hmOf(_end),
        hospitalRate: num.parse(_rate.text.trim()),
      );
      if (!mounted) return;
      _snack(context, 'Duty created for ${doctor['name']}.');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(context, ErrorMessages.of(e, action: 'create the duty'),
          error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.copyFrom != null ? 'Reassign duty' : 'New duty')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _doctorsStream,
        builder: (context, dSnap) => StreamBuilder<List<Map<String, dynamic>>>(
          stream: _hospitalsStream,
          builder: (context, hSnap) {
            if (dSnap.hasError || hSnap.hasError) {
              return LoadErrorView(
                  error: dSnap.error ?? hSnap.error, what: 'the form');
            }
            if (!dSnap.hasData || !hSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final dayKey = CareAgencyService.dateKey(_day);
            final doctors = dSnap.data!
                .where((d) =>
                    d['active'] != false &&
                    !CareAgencyService.isOnLeave(d, dayKey))
                .toList();
            final hospitals = hSnap.data!;
            final base = num.tryParse(_rate.text.trim());
            final rate = base == null ? null : _pricing.billedRate(_type, base);
            final shares = rate == null
                ? null
                : CareAgencyService.split(rate, widget.agency);

            if (hospitals.isEmpty || doctors.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    hospitals.isEmpty
                        ? 'Add a hospital first (Control Room → Hospitals).'
                        : 'Add an active nurse first (Control Room → Nurses).',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _muted),
                  ),
                ),
              );
            }

            return Form(
              key: _formKey,
              child: ListView(
                padding: nursePagePadding(context),
                children: [
                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _day,
                        firstDate: DateTime(now.year, now.month, now.day),
                        lastDate: now.add(const Duration(days: 90)),
                      );
                      if (picked != null) {
                        setState(() => _day = picked);
                        _loadBusy();
                      }
                    },
                    child: InputDecorator(
                      decoration: _dec('Date').copyWith(
                          suffixIcon:
                              const Icon(Icons.calendar_today, size: 18)),
                      child: Text(dayKey),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    menuMaxHeight: 320,
                    value: doctors.any((d) => d['id'] == _doctorId)
                        ? _doctorId
                        : null,
                    isExpanded: true,
                    decoration: _dec('Nurse'),
                    validator: (v) => v == null ? 'Choose a nurse' : null,
                    items: [
                      for (final d in doctors)
                        DropdownMenuItem(
                          value: d['id'] as String,
                          enabled: !_busy.contains(d['id']),
                          child: Text(
                            '${d['name']} · ${d['qualification'] ?? ''}'
                            '${_busy.contains(d['id']) ? ' (has a duty)' : ''}'
                            '${d['placementType'] == 'permanent' ? ' · permanent' : ''}',
                            style: TextStyle(
                                color: _busy.contains(d['id'])
                                    ? AppColors.muted
                                    : null),
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _doctorId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    menuMaxHeight: 320,
                    value: hospitals.any((h) => h['id'] == _hospitalId)
                        ? _hospitalId
                        : null,
                    isExpanded: true,
                    decoration: _dec('Hospital'),
                    validator: (v) => v == null ? 'Choose a hospital' : null,
                    items: [
                      for (final h in hospitals)
                        DropdownMenuItem(
                            value: h['id'] as String,
                            child: Text('${h['name']} · ${h['area'] ?? ''}')),
                    ],
                    onChanged: (v) => setState(() => _hospitalId = v),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        menuMaxHeight: 320,
                        value: _type,
                        isExpanded: true,
                        decoration: _dec('Job type'),
                        items: [
                          for (final t in CareAgencyService.dutyTypes)
                            DropdownMenuItem(
                                value: t,
                                child: Text(CareAgencyService.typeLabels[t]!)),
                        ],
                        onChanged: (v) => setState(() => _type = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        menuMaxHeight: 320,
                        value: _unit,
                        isExpanded: true,
                        decoration: _dec('Unit'),
                        items: [
                          for (final u in CareAgencyService.units)
                            DropdownMenuItem(
                                value: u,
                                child: Text(CareAgencyService.unitLabels[u]!)),
                        ],
                        onChanged: (v) => setState(() => _unit = v!),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    for (final (label, isStart) in [
                      ('Shift start', true),
                      ('Shift end', false)
                    ]) ...[
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final t = await showTimePicker(
                                context: context,
                                initialTime: isStart ? _start : _end);
                            if (t != null) {
                              setState(() => isStart ? _start = t : _end = t);
                            }
                          },
                          child: InputDecorator(
                            decoration: _dec(label).copyWith(
                                suffixIcon:
                                    const Icon(Icons.schedule, size: 18)),
                            child: Text(_hmOf(isStart ? _start : _end)),
                          ),
                        ),
                      ),
                      if (isStart) const SizedBox(width: 12),
                    ],
                  ]),
                  if (_end.hour * 60 + _end.minute <=
                      _start.hour * 60 + _start.minute)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Night shift: ends the next morning.',
                          style: TextStyle(fontSize: 12, color: _muted)),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _rate,
                    keyboardType: TextInputType.number,
                    inputFormatters: Validators.digitsInput(6),
                    validator: (v) {
                      final n = num.tryParse((v ?? '').trim());
                      return n == null || n <= 0
                          ? 'Enter the rate billed to the hospital'
                          : null;
                    },
                    onChanged: (_) => setState(() {}),
                    decoration: _dec('Hospital rate (₹ billed for this duty)'),
                  ),
                  if (shares != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.pastelBlue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${rate != base ? 'Emergency locum +${_pricing.emergencyLocumHikePct}%: billed ${formatInr(rate!)}\n' : ''}'
                        'Nurse ${formatInr(shares.doctorPay)} · Profit ${formatInr(shares.agencyShare)} · App ${formatInr(shares.appShare)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryDark),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _saving ? null : () => _save(doctors, hospitals),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        minimumSize: const Size(double.infinity, 48)),
                    child: Text(_saving ? 'Creating…' : 'Create duty'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// =============================================================== payouts

/// Month-end: doctor payouts of the month, 'Mark paid' per doctor.
class NurseAgencyPayoutsScreen extends StatefulWidget {
  final Map<String, dynamic> agency;
  @visibleForTesting
  final Stream<List<Map<String, dynamic>>>? testDuties;
  const NurseAgencyPayoutsScreen({super.key, required this.agency, this.testDuties});

  @override
  State<NurseAgencyPayoutsScreen> createState() => _AgencyPayoutsScreenState();
}

class _AgencyPayoutsScreenState extends State<NurseAgencyPayoutsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Stream<List<Map<String, dynamic>>>? _stream;
  String _streamKey = '';

  Stream<List<Map<String, dynamic>>> _duties() {
    final from = CareAgencyService.dateKey(_month);
    final to =
        CareAgencyService.dateKey(DateTime(_month.year, _month.month + 1, 0));
    if (_stream == null || _streamKey != from) {
      _streamKey = from;
      _stream = widget.testDuties ??
          CareAgencyService.dutiesStream(
              widget.agency['id'].toString(), from, to);
    }
    return _stream!;
  }

  Future<void> _markPaid(String name, List<Map<String, dynamic>> due) async {
    final total =
        due.fold<num>(0, (s, d) => s + (toNum(d['doctorPay']) ?? 0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark paid?'),
        content: Text(
            'Mark ${formatInr(total)} for ${due.length} duties as paid to $name?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Mark paid')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CareAgencyService.markPaid(due.map((d) => d['id'].toString()));
      if (mounted) _snack(context, 'Marked paid.');
    } catch (e) {
      if (mounted) {
        _snack(context, ErrorMessages.of(e, action: 'mark it paid'),
            error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Nurse payouts')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _duties(),
        builder: (context, snap) {
          if (snap.hasError) {
            return LoadErrorView(error: snap.error, what: 'payouts');
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          // Billed duties only (not cancelled, not absent), per doctor
          final byDoctor = <String, List<Map<String, dynamic>>>{};
          for (final d in snap.data!) {
            if (d['status'] == 'cancelled' || d['status'] == 'absent') continue;
            byDoctor.putIfAbsent(d['doctorId'].toString(), () => []).add(d);
          }
          num paid = 0, due = 0;
          for (final list in byDoctor.values) {
            for (final d in list) {
              final pay = toNum(d['doctorPay']) ?? 0;
              d['payoutStatus'] == 'paid' ? paid += pay : due += pay;
            }
          }
          final rows = byDoctor.entries.toList()
            ..sort((a, b) => a.value.first['doctorName']
                .toString()
                .compareTo(b.value.first['doctorName'].toString()));

          return ListView(
            padding: nursePagePadding(context),
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(
                        () => _month = DateTime(_month.year, _month.month - 1)),
                  ),
                  Expanded(
                    child: Text('${months[_month.month - 1]} ${_month.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1)),
                  ),
                ],
              ),
              Card(
                child: ListTile(
                  title: Text('${formatInr(paid + due)} nurse payouts'),
                  subtitle:
                      Text('${formatInr(paid)} paid · ${formatInr(due)} due'),
                ),
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No billed duties this month.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted)),
                ),
              for (final e in rows)
                Builder(builder: (context) {
                  final list = e.value;
                  final name = list.first['doctorName'].toString();
                  final dueList =
                      list.where((d) => d['payoutStatus'] != 'paid').toList();
                  final dueSum = dueList.fold<num>(
                      0, (s, d) => s + (toNum(d['doctorPay']) ?? 0));
                  final paidSum = list.fold<num>(
                          0, (s, d) => s + (toNum(d['doctorPay']) ?? 0)) -
                      dueSum;
                  return Card(
                    child: ListTile(
                      title: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          '${list.length} duties · ${formatInr(paidSum)} paid · ${formatInr(dueSum)} due'),
                      trailing: dueList.isEmpty
                          ? Icon(Icons.check_circle,
                              color: AppColors.successDark)
                          : ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 40)),
                              onPressed: () => _markPaid(name, dueList),
                              child: const Text('Mark paid'),
                            ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
