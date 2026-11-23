import '../../models/cp_duty_skills.dart';
import 'dart:async';
import '../../utils/form_utils.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/care_physician_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/responsive.dart';
import '../../utils/validators.dart';
import '../../widgets/area_multi_select_field.dart';
import 'cp_widgets.dart';
import '../../constants/app_colors.dart';

typedef _Cp = CarePhysicianService;

/// Build your profile: 1 Credentials · 2 Procedures · 3 Role & specialty ·
/// 4 Where you work. Areas and hospitals are live from Firestore.
class CarePhysicianProfileWizard extends StatefulWidget {
  final Map<String, dynamic> profile;

  /// Tests pass the area / hospital lists instead of Firestore.
  @visibleForTesting
  final List<String>? testAreas;
  @visibleForTesting
  final List<String>? testHospitals;
  @visibleForTesting
  final int initialStep;

  const CarePhysicianProfileWizard({
    super.key,
    required this.profile,
    this.testAreas,
    this.testHospitals,
    this.initialStep = 0,
  });

  @override
  State<CarePhysicianProfileWizard> createState() =>
      _CarePhysicianProfileWizardState();
}

class _CarePhysicianProfileWizardState
    extends State<CarePhysicianProfileWizard> {
  static const _titles = [
    'Credentials',
    'Procedures',
    'Role & specialty',
    'Where you work',
  ];

  final _formKey = GlobalKey<FormState>();
  late int _step = widget.initialStep;
  bool _saving = false;

  late final _first = TextEditingController(
      text: (widget.profile['firstName'] ??
              (widget.profile['name'] ?? '').toString().split(' ').first)
          .toString());
  late final _last = TextEditingController(
      text: (widget.profile['lastName'] ??
              (widget.profile['name'] ?? '')
                  .toString()
                  .split(' ')
                  .skip(1)
                  .join(' '))
          .toString());
  late final _regNo =
      TextEditingController(text: (widget.profile['regNo'] ?? '').toString());
  late final _years = TextEditingController(
      text: (widget.profile['experienceYears'] ?? '').toString());
  late String? _qualification =
      _Cp.qualifications.containsKey(widget.profile['qualification'])
          ? widget.profile['qualification'].toString()
          : null;
  late final Set<String> _procedures =
      _Cp.listOf(widget.profile['procedures']).toSet();
  late final Set<String> _ageGroups =
      _Cp.listOf(widget.profile['ageGroups']).toSet();
  late final Set<String> _specialties =
      _Cp.listOf(widget.profile['specialties']).toSet();
  late final Set<String> _dutyTypes =
      _Cp.listOf(widget.profile['dutyTypes']).toSet();
  late final Set<String> _areas = _Cp.listOf(widget.profile['areas']).toSet();
  // the skills ticked under each duty type (ward, ICU, casualty, specialty)
  late final Map<String, Set<String>> _dutySkills = {
    for (final k in cpDutySkills.keys) k: cpSkillsOf(widget.profile, k).toSet()
  };
  late final Set<String> _hospitals =
      _Cp.listOf(widget.profile['preferredHospitals']).toSet();

  List<String> _allAreas = [];
  List<String> _allHospitals = [];
  bool _listsLoaded = false;
  StreamSubscription? _areasSub;
  StreamSubscription? _hospitalsSub;

  /// Furthest step reached (procedures are optional: done once passed).
  late int _reached = widget.initialStep;

  /// Whether each step is complete, from what is filled in.
  List<bool> get _stepDone => [
        _first.text.trim().isNotEmpty &&
            _regNo.text.trim().isNotEmpty &&
            _years.text.trim().isNotEmpty &&
            _qualification != null,
        _procedures.isNotEmpty || _reached > 1,
        _dutyTypes.isNotEmpty,
        _areas.isNotEmpty,
      ];

  @override
  void initState() {
    super.initState();
    _servicesSub = _Cp.servicesOrCached().listen((l) {
      if (mounted) setState(() => _serviceList = l);
    }, onError: (_) {
      if (mounted) setState(() => _serviceList = const []);
    });
    // the progress bar follows what is typed
    for (final c in [_first, _regNo, _years]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
    if (widget.testAreas != null) {
      _allAreas = widget.testAreas!;
      _allHospitals = widget.testHospitals ?? const [];
      _listsLoaded = true;
      return;
    }
    _areasSub = FirestoreService.nameMasterStream('location_master').listen(
        (a) {
      if (mounted) {
        setState(() {
          _allAreas = a;
          _listsLoaded = true;
        });
      }
    }, onError: (_) {
      if (mounted) setState(() => _listsLoaded = true);
    });
    _hospitalsSub = FirestoreService.hospitalsListStream().listen((h) {
      if (mounted) {
        setState(() => _allHospitals = [
              for (final x in h) (x['name'] ?? x['hospital'] ?? '').toString()
            ]);
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _servicesSub?.cancel();
    _areasSub?.cancel();
    _hospitalsSub?.cancel();
    for (final c in [_first, _last, _regNo, _years]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String msg, {bool error = true}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.danger : AppColors.successDark,
      ));

  bool _validStep() {
    switch (_step) {
      case 0:
        if (!FormUtils.validate(_formKey)) return false;
        if (_qualification == null) {
          _snack('Pick your qualification.');
          return false;
        }
        return true;
      case 2:
        if (_dutyTypes.isEmpty) {
          _snack('Pick at least one duty type you want.');
          return false;
        }
        return true;
      case 3:
        if (_areas.isEmpty) {
          _snack('Pick at least one area you want to work in.');
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _next() {
    if (!_validStep()) return;
    if (_step < 3) {
      setState(() {
        _step++;
        if (_step > _reached) _reached = _step;
      });
    } else {
      _save();
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final first = _first.text.trim(), last = _last.text.trim();
    final regNo = _regNo.text.trim();
    if (await _Cp.regNoTaken(regNo, widget.profile['uid'].toString())) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'This medical registration number is already registered with another account.'),
        backgroundColor: AppColors.danger,
      ));
      return;
    }
    // Saving the profile never changes the verification status; only
    // replacing a mandatory document sends it back for admin approval.
    try {
      await _Cp.updateProfile(widget.profile['uid'].toString(), {
        'firstName': first,
        'lastName': last,
        'name': '$first $last'.trim(),
        'regNo': regNo,
        'regNoKey': Validators.registrationKey(regNo),
        'qualification': _qualification,
        'experienceYears': int.tryParse(_years.text.trim()) ?? 0,
        'experience': _years.text.trim(),
        'procedures': _procedures.toList(),
        'procedureNames': [
          for (final id in _procedures)
            if (_Cp.procedures[id] != null) _Cp.procedures[id]!.$2
        ],
        'ageGroups': _ageGroups.toList(),
        'specialties': _specialties.toList(),
        'dutyTypes': _dutyTypes.toList(),
        // skills only for the duty types kept
        'dutySkills': {
          for (final k in _dutyTypes)
            if (cpDutySkills.containsKey(k)) k: _dutySkills[k]!.toList()
        },
        'areas': _areas.toList(),
        'preferredHospitals': _hospitals.toList(),
      });
      if (!mounted) return;
      _snack('Profile saved.', error: false);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(ErrorMessages.of(e, action: 'save your profile'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(children: [
            _top(),
            Expanded(
              child: Form(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: switch (_step) {
                    0 => _credentials(),
                    1 => _proceduresStep(),
                    2 => _roleStep(),
                    _ => _whereStep(),
                  },
                ),
              ),
            ),
            _bottom(),
          ]),
        ),
      ),
    );
  }

  Widget _top() => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [AppColors.primaryTint, Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter),
          border: Border(bottom: BorderSide(color: CpColors.line)),
        ),
        child: Column(children: [
          Row(children: [
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () =>
                  _step == 0 ? Navigator.pop(context) : setState(() => _step--),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Build your profile',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: CpColors.ink)),
                  Text('Step ${_step + 1} of 4 · ${_titles[_step]}',
                      style:
                          const TextStyle(fontSize: 12, color: CpColors.muted)),
                ],
              ),
            ),
            const Text('🩺', style: TextStyle(fontSize: 24)),
          ]),
          const SizedBox(height: 10),
          _progress(),
        ]),
      );

  /// Horizontal progress: every step with a tick once complete, and the
  /// share of the profile that is filled in. Earlier / reached steps can be
  /// opened by tapping them.
  Widget _progress() {
    final done = _stepDone;
    final count = done.where((d) => d).length;
    final pct = (count * 100 / done.length).round();
    return Column(children: [
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: count / done.length,
              minHeight: 6,
              backgroundColor: CpColors.line,
              color: pct == 100 ? CpColors.green : CpColors.navy,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('$pct% complete',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: CpColors.ink)),
      ]),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < _titles.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(top: 13),
                color: done[i - 1] ? CpColors.green : CpColors.line,
              ),
            ),
          _stepDot(i, done[i]),
        ],
      ]),
    ]);
  }

  Widget _stepDot(int i, bool done) {
    final current = i == _step;
    final canOpen = i <= _reached && !_saving;
    final color = done
        ? CpColors.green
        : current
            ? CpColors.navy
            : CpColors.muted;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: canOpen && !current ? () => setState(() => _step = i) : null,
      child: SizedBox(
        width: 66,
        child: Column(children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? CpColors.green : Colors.white,
              border: Border.all(color: color, width: current ? 2.5 : 1.5),
            ),
            child: done
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : Text('${i + 1}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: color)),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(_titles[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                    color: current ? CpColors.ink : CpColors.muted)),
          ),
        ]),
      ),
    );
  }

  Widget _bottom() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: CpColors.line))),
        child: Row(children: [
          if (_step > 0) ...[
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _saving ? null : () => setState(() => _step--),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: 3,
            child: ElevatedButton(
              onPressed: _saving ? null : _next,
              style: ElevatedButton.styleFrom(
                backgroundColor: CpColors.navy,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                  _saving
                      ? 'Saving…'
                      : (_step == 3 ? 'Save profile' : 'Continue'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
        ]),
      );

  // -------------------------------------------------------------- helpers

  Widget _heading(String text, {String? note}) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: CpColors.ink)),
            if (note != null) ...[
              const SizedBox(height: 4),
              Text(note,
                  style: const TextStyle(fontSize: 12, color: CpColors.muted)),
            ],
          ],
        ),
      );

  /// Grid of option tiles, 3 per row on phones (more on wider screens).
  Widget _grid(List<Widget> tiles, {double minTile = 100, double height = 100}) =>
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: Responsive.grid(context,
            minTileWidth: minTile,
            tileHeight: height,
            spacing: 10,
            minColumns: 3,
            maxColumns: 5),
        children: tiles,
      );

  /// The duty type whose skills are open (one at a time).
  String? _openDuty;

  /// A duty card: one with skills opens / closes its skills; one without
  /// skills (e.g. home care visit) is chosen or unchosen.
  void _tapDuty(String key) => setState(() {
        if (cpDutySkills.containsKey(key)) {
          _openDuty = _openDuty == key ? null : key;
        } else {
          _dutyTypes.contains(key) ? _dutyTypes.remove(key) : _dutyTypes.add(key);
        }
      });

  /// A duty with skills is chosen while at least one of its skills is.
  void _changeSkills(String duty, void Function(Set<String>) fn) =>
      setState(() {
        final picked = _dutySkills[duty]!;
        fn(picked);
        picked.isEmpty ? _dutyTypes.remove(duty) : _dutyTypes.add(duty);
      });

  void _toggle(Set<String> set, String key) => setState(
      () => set.contains(key) ? set.remove(key) : set.add(key));

  // ---------------------------------------------------------------- steps

  List<Widget> _credentials() => [
        _heading('Your name'),
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _first,
              validator: (v) => Validators.personName(v, label: 'first name'),
              decoration: const InputDecoration(hintText: 'First name'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: _last,
              validator: (v) => Validators.personName(v, label: 'last name'),
              decoration: const InputDecoration(hintText: 'Last name'),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        _heading('Medical registration number',
            note:
                'We verify this against the council register before you can claim ICU or procedure-gated duties.'),
        TextFormField(
          controller: _regNo,
          validator: Validators.medicalRegistration,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            LengthLimitingTextInputFormatter(Validators.medicalRegistrationLength),
          ],
          decoration: const InputDecoration(hintText: '12 letters/numbers, e.g. MMC201908421'),
        ),
        const SizedBox(height: 16),
        _heading('Qualification'),
        _grid([
          for (final e in _Cp.qualifications.entries)
            CpOptionTile(
              emoji: '🎓',
              title: e.value.$1,
              subtitle: e.value.$2,
              selected: _qualification == e.key,
              onTap: () => setState(() => _qualification = e.key),
            ),
        ], height: 116),
        const SizedBox(height: 16),
        _heading('Years of experience'),
        TextFormField(
          controller: _years,
          keyboardType: TextInputType.number,
          inputFormatters: Validators.digitsInput(2),
          validator: Validators.experience,
          decoration: const InputDecoration(hintText: 'e.g. 4'),
        ),
      ];

  // the service list, kept as it arrives (the step can be opened again)
  List<Map<String, dynamic>>? _serviceList;
  StreamSubscription<List<Map<String, dynamic>>>? _servicesSub;

  List<Widget> _proceduresStep() => [
        _heading('Services you can perform',
            note:
                'The same services patients book at home. Pick everything you are competent and willing to do unsupervised. Patients\' requests for these services come to you.'),
        // the same services patients book at home (one list for both)
        if (_serviceList == null)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()))
        else if (_serviceList!.isEmpty)
          const Text('No services are listed yet.')
        else
          _grid([
            for (final x in _serviceList!)
              CpOptionTile(
                emoji: '🩺',
                title: x['name'].toString(),
                selected: _procedures.contains(x['id'].toString()),
                onTap: () => _toggle(_procedures, x['id'].toString()),
              ),
          ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warningSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('⚠️'),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Only select procedures you are genuinely trained to perform. Hospitals rely on this list when assigning critical duties.',
                    style: TextStyle(fontSize: 12, color: AppColors.warningDeep)),
              ),
            ],
          ),
        ),
      ];

  List<Widget> _roleStep() => [
        _heading('Patient age groups you prefer'),
        _grid([
          for (final e in _Cp.ageGroups.entries)
            CpOptionTile(
              emoji: e.value.$1,
              title: e.value.$2,
              selected: _ageGroups.contains(e.key),
              onTap: () => _toggle(_ageGroups, e.key),
            ),
        ], minTile: 70, height: 92),
        const SizedBox(height: 18),
        _heading('Specialty interests · optional'),
        _grid([
          for (final e in _Cp.specialties.entries)
            CpOptionTile(
              emoji: e.value.$1,
              title: e.value.$2,
              selected: _specialties.contains(e.key),
              onTap: () => _toggle(_specialties, e.key),
            ),
        ], minTile: 70, height: 92),
        const SizedBox(height: 18),
        _heading('Duty types you want',
            note:
                'Tap a duty to choose the skills you have for it. A duty without skills (like a home care visit) is chosen by tapping it.'),
        for (final e in _Cp.dutyTypes.entries) ...[
          _dutyCard(e.key, e.value.$1, e.value.$2, e.value.$3),
          if (_openDuty == e.key && cpDutySkills.containsKey(e.key))
            _skillsBox(e.key),
        ],
      ];

  /// One duty type as a card (no checkbox): chosen cards are blue.
  Widget _dutyCard(String key, String emoji, String title, String note) {
    final hasSkills = cpDutySkills.containsKey(key);
    final chosen = _dutyTypes.contains(key);
    final open = _openDuty == key;
    final count = hasSkills ? _dutySkills[key]!.length : 0;
    final total = hasSkills
        ? cpDutySkills[key]!.fold<int>(0, (n, g) => n + g.$2.length)
        : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: chosen ? AppColors.primaryTint : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
              color: chosen || open ? CpColors.navy : CpColors.line,
              width: chosen ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _tapDuty(key),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, color: CpColors.ink)),
                    Text(note,
                        style: const TextStyle(
                            fontSize: 12, color: CpColors.muted)),
                    if (hasSkills)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                            count == 0
                                ? (chosen
                                    ? 'No skills chosen yet · tap to choose'
                                    : '$total skills · tap to choose')
                                : '$count of $total skills chosen',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: count > 0
                                    ? CpColors.navy
                                    : AppColors.muted)),
                      ),
                  ],
                ),
              ),
              if (hasSkills)
                Icon(
                    open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: CpColors.navy),
            ]),
          ),
        ),
      ),
    );
  }

  /// The skills of one duty type, in groups, to tick.
  Widget _skillsBox(String duty) {
    final picked = _dutySkills[duty]!;
    final groups = cpDutySkills[duty]!;
    final all = [for (final g in groups) ...g.$2];
    final allPicked = all.every(picked.contains);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.page,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CpColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
                '${_Cp.dutyLabel(duty)} skills · ${picked.length} of ${all.length}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: CpColors.ink)),
          ),
          TextButton(
            onPressed: () => _changeSkills(
                duty, (p) => allPicked ? p.clear() : p.addAll(all)),
            child: Text(allPicked ? 'Clear all' : 'Select all'),
          ),
        ]),
        for (final g in groups) ...[
          if (groups.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: Text(g.$1,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: CpColors.muted)),
            ),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in g.$2)
              FilterChip(
                label: Text(s, style: const TextStyle(fontSize: 12)),
                selected: picked.contains(s),
                visualDensity: VisualDensity.compact,
                onSelected: (_) => _changeSkills(
                    duty, (p) => p.contains(s) ? p.remove(s) : p.add(s)),
              ),
          ]),
        ],
      ]),
    );
  }

  List<Widget> _whereStep() {
    // keep chosen values visible even if the master list changed
    final areas = {..._allAreas, ..._areas}.toList();
    final hospitals = {..._allHospitals, ..._hospitals}.toList();
    return [
      _heading('Areas you want to work in'),
      if (!_listsLoaded)
        const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()))
      else if (areas.isEmpty)
        const Text('No areas set up yet. Please contact support.',
            style: TextStyle(color: CpColors.muted))
      else
        AreaMultiSelectField(
          accent: CpColors.navy,
          areas: areas,
          selected: _areas,
          onChanged: (v) => setState(() => _areas
            ..clear()
            ..addAll(v)),
        ),
      const SizedBox(height: 18),
      _heading('Preferred hospitals · optional',
          note:
              "You'll be shown first for duties at these hospitals — but you can still see and claim shifts anywhere in your areas."),
      if (hospitals.isEmpty)
        const Text('No hospitals listed yet.',
            style: TextStyle(color: CpColors.muted))
      else
        for (final h in hospitals)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color:
                  _hospitals.contains(h) ? AppColors.primaryTint : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                    color: _hospitals.contains(h) ? CpColors.navy : CpColors.line),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _toggle(_hospitals, h),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(children: [
                    const Text('🏥'),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(h,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600))),
                    Icon(
                      _hospitals.contains(h)
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      color: _hospitals.contains(h) ? CpColors.navy : AppColors.muted,
                    ),
                  ]),
                ),
              ),
            ),
          ),
    ];
  }
}
