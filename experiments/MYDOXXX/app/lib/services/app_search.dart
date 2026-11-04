import 'care_physician_service.dart';
import 'firestore_service.dart';
import '../utils/display_names.dart';

/// What a search result opens.
enum SearchKind { service, specialty, doctor, labTest, therapy, careService }

class SearchItem {
  final SearchKind kind;
  final String title;
  final String subtitle;

  /// What to open: the service id, category, test or therapy name.
  final String target;

  /// Extra words that should find this item (synonyms).
  final String keywords;

  const SearchItem(this.kind, this.title,
      {this.subtitle = '', String? target, this.keywords = ''})
      : target = target ?? title;
}

/// Patient search over everything bookable: services, doctor specialities,
/// doctors by name, lab tests, therapies and home-care services.
class AppSearch {
  AppSearch._();

  /// The main services (always searchable, even offline).
  static const List<SearchItem> services = [
    SearchItem(SearchKind.service, 'Doctors',
        subtitle: 'Book a doctor', target: 'doctor',
        keywords: 'consultation clinic physician specialist appointment'),
    SearchItem(SearchKind.service, 'Nurses',
        subtitle: 'Home nursing', target: 'nurse',
        keywords: 'nursing home care injection elderly attendant'),
    SearchItem(SearchKind.service, 'Technician',
        subtitle: 'Lab tests at home', target: 'technician',
        keywords: 'lab test blood sample ecg x-ray pathology'),
    SearchItem(SearchKind.service, 'Therapist',
        subtitle: 'Therapy sessions', target: 'therapist',
        keywords: 'physiotherapy physio speech therapy rehab'),
    SearchItem(SearchKind.service, 'Care Physician',
        subtitle: 'Doctor home visit', target: 'care_physician',
        keywords: 'home visit wound dressing catheter iv'),
    SearchItem(SearchKind.service, 'Emergency SOS',
        subtitle: 'Hospital, doctor and ambulance', target: 'sos',
        keywords: 'ambulance emergency accident urgent help'),
  ];

  static String _norm(String s) => s.toLowerCase().trim();

  /// Items matching every word of [query]; names that start with the query
  /// come first, then names containing it, then other matches.
  static List<SearchItem> filter(String query, List<SearchItem> items,
      {int limit = 20}) {
    final words =
        _norm(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];
    final q = _norm(query);
    final hits = <(int, SearchItem)>[];
    for (final it in items) {
      final title = _norm(it.title);
      final hay = '$title ${_norm(it.subtitle)} ${_norm(it.keywords)}';
      if (!words.every(hay.contains)) continue;
      final rank = title.startsWith(q)
          ? 0
          : title.contains(q)
              ? 1
              : 2;
      hits.add((rank, it));
    }
    hits.sort((a, b) => a.$1 != b.$1
        ? a.$1.compareTo(b.$1)
        : a.$2.title.length.compareTo(b.$2.title.length));
    return [for (final h in hits.take(limit)) h.$2];
  }

  /// Everything searchable, from Firestore (each list on its own so one
  /// failing source doesn't empty the search).
  static Future<List<SearchItem>> loadIndex() async {
    Future<List<T>> safe<T>(Future<List<T>> f) => f.catchError((_) => <T>[]);
    final results = await Future.wait<List<SearchItem>>([
      safe(FirestoreService.getDoctorCategories().then((list) => [
            for (final c in list)
              SearchItem(SearchKind.specialty, c, subtitle: 'Speciality'),
          ])),
      safe(FirestoreService.getDoctorsStream().first.then((list) => [
            for (final d in list)
              if (d['isVerified'] == true &&
                  (d['name'] ?? '').toString().isNotEmpty)
                SearchItem(
                  SearchKind.doctor,
                  DisplayNames.doctor(d['name'].toString()),
                  subtitle: [
                    (d['category'] ?? '').toString(),
                    (d['hospital'] ?? '').toString(),
                  ].where((s) => s.isNotEmpty).join(' · '),
                  target: (d['category'] ?? '').toString(),
                ),
          ])),
      safe(FirestoreService.getLabTestsWithPrice().then((list) => [
            for (final t in list)
              SearchItem(SearchKind.labTest, (t['name'] ?? '').toString(),
                  subtitle: 'Lab test at home'),
          ])),
      safe(FirestoreService.getTherapiesWithPrice().then((list) => [
            for (final t in list)
              SearchItem(SearchKind.therapy, (t['name'] ?? '').toString(),
                  subtitle: 'Therapy'),
          ])),
      safe(CarePhysicianService.servicesStream().first.then((list) => [
            for (final s in list)
              SearchItem(SearchKind.careService, (s['name'] ?? '').toString(),
                  subtitle: 'Care physician home visit'),
          ])),
    ]);
    return [
      ...services,
      for (final list in results)
        for (final it in list)
          if (it.title.trim().isNotEmpty) it,
    ];
  }
}
