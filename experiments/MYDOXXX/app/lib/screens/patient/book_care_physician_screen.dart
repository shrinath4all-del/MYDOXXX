import '../../services/lab_device.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/form_utils.dart';
import '../../utils/safe_cast.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/user_model.dart';
import '../../services/care_physician_service.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../../utils/responsive.dart';
import '../../utils/stream_cache.dart';
import '../../utils/validators.dart';
import '../agency/control_room_widgets.dart' show formatInr;
import '../care_physician/cp_widgets.dart';
import '../../constants/app_colors.dart';
import '../../services/images_master.dart';
import '../../widgets/circle_image.dart';
import '../../widgets/verified_badge.dart';
import '../../widgets/app_dialog.dart';
import '../../utils/display_names.dart';

typedef _Cp = CarePhysicianService;

/// Same colour as the doctor booking screen.
const _teal = AppTheme.primaryTeal;

/// Icon of a home-visit service (Firestore field `icon`).
IconData serviceIcon(String? key) => switch (key) {
      'add' || 'plus' || 'catheter' => Icons.add_rounded,
      'shield' || 'wound' => Icons.shield_outlined,
      'check' || 'stitch' => Icons.check_rounded,
      'drop' || 'water_drop' || 'iv' => Icons.water_drop_outlined,
      'air' || 'suction' => Icons.air_rounded,
      'heart' || 'bedsore' => Icons.favorite_border_rounded,
      'injection' || 'vaccines' => Icons.vaccines_outlined,
      'healing' => Icons.healing_outlined,
      'medication' => Icons.medication_outlined,
      'monitor' => Icons.monitor_heart_outlined,
      _ => Icons.medical_services_outlined,
    };

/// Picture of a home-visit service, like the doctor category pictures.
/// Firestore field 'image' (a web link or an 'assets/...' path) wins;
/// otherwise one of the app's doctor pictures; the icon if none loads.
Widget serviceImage(Map<String, dynamic> service, {double size = 96}) {
  final image = (service['image'] ?? '').toString().trim();
  final icon = serviceIcon(service['icon']?.toString());
  final iconWidget = Center(
      child: Icon(icon, color: AppTheme.primaryTeal, size: size * 0.45));
  Widget fallback(BuildContext _, Object __, StackTrace? ___) => iconWidget;
  if (image.startsWith('http')) {
    return CircleFrame(
      size: size,
      child: Image(
          image: CachedNetworkImageProvider(image),
          fit: BoxFit.cover,
          errorBuilder: fallback),
    );
  }
  if (image.isNotEmpty) {
    return CircleFrame(
      size: size,
      child: Image.asset(image, fit: BoxFit.cover, errorBuilder: fallback),
    );
  }
  // images_master picture for this service
  return CircleImage(
    imageKey: ImagesMaster.careService((service['name'] ?? '').toString()),
    size: size,
    icon: icon,
  );
}

/// Patient: book a care physician home visit. Same layout as the other
/// booking screens (title, banner, grid of services with prices); services
/// and prices are live from Firestore 'care_physician_services'.
class BookCarePhysicianScreen extends StatefulWidget {
  final UserModel patient;
  const BookCarePhysicianScreen({super.key, required this.patient});

  @override
  State<BookCarePhysicianScreen> createState() =>
      _BookCarePhysicianScreenState();
}

class _BookCarePhysicianScreenState extends State<BookCarePhysicianScreen> {
  final StreamCache _streams = StreamCache();
  bool _showVisits = false;
  String _liveAreaName = 'Nearby Patient Area';
  // the patient's live area (like the doctor / nurse bookings); null until
  // located, or if location is off (then the patient picks an area)
  String? _liveArea;
  Position? _position;
  List<String> _areas = [];
  StreamSubscription? _areasSub;

  @override
  void initState() {
    super.initState();
    _areasSub =
        FirestoreService.nameMasterStream('location_master').listen((a) {
      if (mounted) setState(() => _areas = a);
    }, onError: (_) {});
    LocationService.getCurrentLocation().then((area) async {
      Position? pos;
      try {
        pos = await LabLocation.getLastKnownPosition();
      } catch (_) {}
      if (!mounted || area.trim().isEmpty) return;
      final located = !LocationService.isError(area);
      setState(() {
        _liveAreaName = area;
        if (located) _liveArea = area;
        _position = pos;
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _areasSub?.cancel();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.danger : AppColors.successDark,
    ));
  }

  /// The patient's area as one of the master areas (care physicians pick
  /// areas from the same list).
  String? get _defaultArea {
    for (final raw in [_liveAreaName, widget.patient.city ?? '']) {
      final text = raw.toLowerCase();
      if (text.isEmpty) continue;
      for (final a in _areas) {
        if (text == a.toLowerCase() || text.contains(a.toLowerCase())) {
          return a;
        }
      }
    }
    return null;
  }

  void _openBooking(Map<String, dynamic> service) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => _BookingSheet(
        service: service,
        patient: widget.patient,
        areas: _areas,
        liveArea: _liveArea,
        position: _position,
        initialArea: _defaultArea,
        onBooked: () {
          _snack('Visit requested. We are finding a care physician near you.');
          setState(() => _showVisits = true);
        },
      ),
    );
  }

  Future<void> _cancel(Map<String, dynamic> v) async {
    final ok = await AppDialog.confirm(
      context,
      icon: Icons.event_busy_rounded,
      color: AppColors.danger,
      title: 'Cancel this visit?',
      message: v['status'] == 'claimed'
          ? '${DisplayNames.doctor(v['claimedByName']?.toString())} will be told the visit is cancelled.'
          : 'We will stop looking for a care physician.',
      confirmLabel: 'Cancel visit',
      cancelLabel: 'Keep',
    );
    if (!ok) return;
    try {
      await _Cp.cancelShift(v);
      _snack('Visit cancelled.');
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'cancel the visit'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(
      child: PopScope(
        // Back from "My home visits" returns to the services
        canPop: !_showVisits,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _showVisits = false);
        },
        child: Scaffold(
          backgroundColor: AppTheme.bgLight,
          body: SafeArea(
            child: _showVisits
                ? Column(children: [
                    AppBar(
                      title: const Text('My home visits'),
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () => setState(() => _showVisits = false),
                      ),
                    ),
                    Expanded(child: _visitList()),
                  ])
                : _serviceGrid(),
          ),
        ),
      ),
    );
  }

  Widget _serviceGrid() => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streams.get('services', _Cp.servicesStream),
        builder: (context, snap) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: AppTheme.darkNavy, size: 26),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Find a Doctor for Home Care',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.darkNavy,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose a specialist for a scheduled or urgent home visit.',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                _banner(),
                const SizedBox(height: 12),
                _myVisitsButton(),
                const SizedBox(height: 16),
                if (snap.hasError)
                  LoadErrorView(error: snap.error, what: 'home-care services')
                else if (!snap.hasData)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child:
                        Center(child: CircularProgressIndicator(color: _teal)),
                  )
                else if (snap.data!.isEmpty)
                  const CpEmpty('🩺',
                      'Home-care services will appear here soon. Please check back later.')
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: snap.data!.length,
                    // columns from the screen width; tile tall enough for a
                    // two-line name at any font size
                    gridDelegate: Responsive.grid(context,
                        minTileWidth: 150, tileHeight: 246),
                    itemBuilder: (context, i) => ServiceGridTile(
                      service: snap.data![i],
                      onTap: () => _openBooking(snap.data![i]),
                    ),
                  ),
              ],
            ),
          );
        },
      );

  Widget _banner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.navy, AppColors.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: _teal.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _liveAreaName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Doctor Visit at Home',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Verified care physicians come to your home for dressing, catheter, IV and more.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.add_home_work_outlined,
                color: Colors.white, size: 40),
          ),
        ]),
      );

  Widget _myVisitsButton() => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streams.get(
            'visits', () => _Cp.posterShiftsStream(widget.patient.uid)),
        builder: (context, snap) {
          final active = (snap.data ?? const [])
              .where((v) =>
                  _Cp.isHomeVisit(v) &&
                  const {'open', 'claimed', 'on_duty'}.contains(v['status']))
              .length;
          return OutlinedButton.icon(
            onPressed: () => setState(() => _showVisits = true),
            icon: const Icon(Icons.event_note_rounded, color: _teal),
            label: Text(
                active == 0
                    ? 'My home visits'
                    : 'My home visits ($active active)',
                style:
                    const TextStyle(color: _teal, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              side: BorderSide(color: _teal.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          );
        },
      );

  Widget _visitList() => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streams.get(
            'visits', () => _Cp.posterShiftsStream(widget.patient.uid)),
        builder: (context, snap) {
          if (snap.hasError) {
            return LoadErrorView(error: snap.error, what: 'your visits');
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: _teal));
          }
          final visits = snap.data!.where(_Cp.isHomeVisit).toList();
          if (visits.isEmpty) {
            return const CpEmpty('🏠', 'You have not booked a home visit yet.');
          }
          final now = DateTime.now();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              for (final v in visits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: VisitCard(
                    visit: v,
                    now: now,
                    onCancel: () => _cancel(v),
                    onCall: (phone) =>
                        labLaunchUrl(Uri(scheme: 'tel', path: phone)),
                  ),
                ),
            ],
          );
        },
      );
}

/// A home-care service in the grid: icon, name, price (same tile as the
/// lab test / therapy / doctor category grids).
class ServiceGridTile extends StatelessWidget {
  final Map<String, dynamic> service;
  final VoidCallback onTap;
  const ServiceGridTile(
      {super.key, required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = (service['name'] ?? '').toString();
    final price = toNum(service['price'])?.toInt() ?? 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
            )
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            serviceImage(service, size: 96),
            const SizedBox(height: 8),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '₹$price onwards',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryTeal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Booking bottom sheet: same layout as the other home-visit sheets.
class _BookingSheet extends StatefulWidget {
  final Map<String, dynamic> service;
  final UserModel patient;
  final List<String> areas;
  final String? liveArea;
  final Position? position;
  final String? initialArea;
  final VoidCallback onBooked;
  const _BookingSheet({
    required this.service,
    required this.patient,
    required this.areas,
    required this.liveArea,
    required this.position,
    required this.initialArea,
    required this.onBooked,
  });

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _date = _firstDay;
  String? _time;
  late String? _area = widget.areas.contains(widget.initialArea)
      ? widget.initialArea
      : null;
  // pick the area by hand only when the live location is not known
  // the area is always asked, from the location_master list
  late bool _pickArea = true;
  late final _address =
      TextEditingController(text: widget.patient.homeAddress ?? '');
  final _notes = TextEditingController();
  bool _saving = false;

  int get _price => toNum(widget.service['price'])?.round() ?? 0;

  /// Today if a time is still bookable, otherwise tomorrow.
  DateTime get _firstDay {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return _timesFor(today).isEmpty
        ? today.add(const Duration(days: 1))
        : today;
  }

  /// Times at least 1 h from now.
  static List<String> _timesFor(DateTime day) {
    final soonest = DateTime.now().add(const Duration(hours: 1));
    return [
      for (final t in _Cp.visitTimes())
        if (_Cp.shiftStart({'date': _Cp.dateKey(day), 'start': t})!
            .isAfter(soonest))
          t
    ];
  }

  @override
  void dispose() {
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// "The doctor will reach between 6:00 PM and 6:45 PM" (travel buffer).
  Widget _reachWindow() {
    final draft = {'date': _Cp.dateKey(_date), 'start': _time!};
    return Row(children: [
      const Icon(Icons.directions_car_filled_outlined,
          color: AppTheme.textMuted, size: 18),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
            'The doctor will reach between ${_Cp.clock(_Cp.shiftStart(draft))} and ${_Cp.clock(_Cp.reachBy(draft))}.',
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
      ),
    ]);
  }

  Future<void> _book() async {
    if (!FormUtils.validate(_formKey)) return;
    if (_time == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pick a time slot for the visit.'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      await _Cp.requestHomeVisit(
        patient: {
          'uid': widget.patient.uid,
          'name': widget.patient.name,
          'phone': widget.patient.phone ?? widget.patient.mobileNumber ?? '',
        },
        service: widget.service,
        date: _Cp.dateKey(_date),
        start: _time!,
        area: _area!,
        address: _address.text.trim(),
        notes: _notes.text.trim(),
        lat: widget.position?.latitude,
        lng: widget.position?.longitude,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onBooked();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ErrorMessages.of(e, action: 'book the visit')),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        // the error goes away as soon as the address is typed
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Request Care Physician Visit',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _teal,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 10),

              // Summary
              Row(children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: _teal.withValues(alpha: 0.15),
                  child: Icon(serviceIcon(service['icon']?.toString()),
                      color: _teal),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((service['name'] ?? '').toString(),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      const Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          VerifiedBadge(),
                          Text('Home visit',
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.textMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${formatInr(_price)}+',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _teal,
                    ),
                  ),
                ),
              ]),

              const SizedBox(height: 18),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _teal.withValues(alpha: 0.3)),
                ),
                child: const Row(children: [
                  Icon(Icons.home_work_rounded, color: _teal, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Home Visit: your request goes to every care physician in your area who does this service and has no duty at that time. The first to accept comes to your home. Pay the doctor after the visit.',
                      style: TextStyle(
                        color: _teal,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 16),

              const Text('Your Area',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  menuMaxHeight: 320,
                  // ignore: deprecated_member_use
                  value: widget.areas.contains(_area) ? _area : null,
                  isExpanded: true,
                  hint: const Text('Select your area'),
                  items: [
                    for (final a in widget.areas)
                      DropdownMenuItem(value: a, child: Text(a)),
                  ],
                  validator: (v) => v == null ? 'Pick your area' : null,
                  onChanged: (v) => setState(() {
                    _area = v;
                    _time = null;
                  }),
                ),

              const SizedBox(height: 16),

              const Text('Select Date for Visit',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: _firstDay,
                    lastDate: now.add(const Duration(days: 30)),
                  );
                  if (picked != null) {
                    setState(() {
                      _date = picked;
                      _time = null;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.lineStrong),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_today, color: _teal, size: 18),
                    const SizedBox(width: 10),
                    Text('${_date.day}/${_date.month}/${_date.year}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    const Icon(Icons.arrow_drop_down, color: AppColors.muted),
                  ]),
                ),
              ),

              const SizedBox(height: 16),

              const Text('Select Time Slot',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_area == null)
                const Text('Pick your area first.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13))
              else if (_timesFor(_date).isEmpty)
                const Text('No time slots left for this date.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in _timesFor(_date))
                      ChoiceChip(
                        label: Text(_Cp.slotLabel2h(t)),
                        selected: _time == t,
                        selectedColor: _teal,
                        labelStyle: TextStyle(
                          color: _time == t ? Colors.white : AppTheme.darkNavy,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (_) => setState(() => _time = t),
                      ),
                  ],
                ),

              const SizedBox(height: 16),

              if (_time != null) ...[
                const SizedBox(height: 10),
                _reachWindow(),
              ],

              const SizedBox(height: 16),

              const Text('Home Address',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _address,
                maxLines: 2,
                validator: (v) => Validators.address(v, label: 'home address'),
                decoration: const InputDecoration(
                    hintText: 'Flat / house, building, street, landmark'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                    hintText: 'Anything the doctor should know? (optional)'),
              ),

              const SizedBox(height: 24),

              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _teal),
                onPressed: _saving || _time == null ? null : _book,
                child: Text(_saving
                    ? 'Requesting…'
                    : 'Request Home Visit (${formatInr(_price)} onwards)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A booked home visit and its progress.
class VisitCard extends StatelessWidget {
  final Map<String, dynamic> visit;
  final DateTime now;
  final VoidCallback onCancel;
  final ValueChanged<String> onCall;
  const VisitCard({
    super.key,
    required this.visit,
    required this.now,
    required this.onCancel,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final status = (visit['status'] ?? '').toString();
    final doctor = (visit['claimedByName'] ?? '').toString();
    final phone = (visit['claimedByPhone'] ?? '').toString();
    final (label, color, note) = switch (status) {
      'open' => (
          'FINDING A DOCTOR',
          AppColors.warning,
          'We are finding a care physician near you.'
        ),
      'claimed' => (
          'CONFIRMED',
          AppColors.blue,
          '$doctor${(visit['claimedAgencyName'] ?? '').toString().isEmpty ? '' : ' (${visit['claimedAgencyName']})'} '
              'is coming — reaches by ${_Cp.clock(_Cp.reachBy(visit))}.'
        ),
      'on_duty' => ('DOCTOR ARRIVED', CpColors.green, '$doctor is with you.'),
      'completed' => (
          'COMPLETED',
          CpColors.green,
          'Visit completed by $doctor.'
        ),
      'absent' => (
          'DOCTOR DID NOT COME',
          CpColors.red,
          'Sorry — the doctor did not come. Please book again.'
        ),
      'unfilled' => (
          'NO DOCTOR AVAILABLE',
          CpColors.red,
          'Sorry — no doctor could take this visit. Please book again.'
        ),
      _ => ('CANCELLED', CpColors.muted, 'This visit was cancelled.'),
    };
    final start = _Cp.shiftStart(visit);
    final canCancel = (status == 'open' || status == 'claimed') &&
        start != null &&
        start.isAfter(now);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: _teal.withValues(alpha: 0.12),
              child: Icon(serviceIcon(visit['serviceIcon']?.toString()),
                  color: _teal, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text((visit['serviceName'] ?? '').toString(),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkNavy)),
            ),
            CpTag(label, color, filled: false),
          ]),
          const SizedBox(height: 8),
          Text(
              '${_Cp.dayLabel(visit, now)} · ${_Cp.timeRange(visit)} · ${visit['area'] ?? ''}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          const SizedBox(height: 6),
          Text(note, style: const TextStyle(fontSize: 13)),
          if (phone.isNotEmpty && (status == 'claimed' || status == 'on_duty'))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: () => onCall(phone),
                icon: const Icon(Icons.call_rounded, size: 18),
                label: Text('Call $phone'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              ),
            ),
          if (canCancel)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onCancel,
                child: const Text('Cancel visit',
                    style: TextStyle(color: AppColors.danger)),
              ),
            ),
        ],
      ),
    );
  }
}
