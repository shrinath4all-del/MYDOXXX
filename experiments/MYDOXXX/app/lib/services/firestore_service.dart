import 'service_otp.dart';
import 'app_database.dart';
import '../utils/appointment_rules.dart';
import '../utils/safe_cast.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'physio_agency_service.dart';
import 'location_service.dart';
import 'pricing_service.dart';
import 'sos_service.dart';

import 'storage_service.dart';

class FirestoreService {
  static final FirebaseFirestore _db = AppDatabase.instance;

  // Collection references
  static CollectionReference get _categoriesRef =>
      _db.collection('category_doctors');

  static CollectionReference get _labTestsRef =>
      _db.collection('lab_tests');

  static CollectionReference get _therapiesRef =>
      _db.collection('therapies');

  /// Lab tests technicians offer, from Firestore collection 'lab_tests'.
  /// Each doc: `name` (or the doc id) and `price`. Nothing is hardcoded:
  /// a test without a price shows "Price not set" and cannot be booked.
  static Future<List<Map<String, dynamic>>> getLabTestsWithPrice() async {
    try {
      final snapshot = await _labTestsRef.get();
      final List<Map<String, dynamic>> list = [];
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        if (data['isActive'] == false) continue;
        final name = (data['name'] ?? doc.id).toString().trim();
        if (name.isEmpty) continue;
        list.add({'name': name, 'price': toNum(data['price'])?.toInt()});
      }
      list.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      return list;
    } catch (e) {
      return [];
    }
  }

  /// Therapy services patients can book, from Firestore collection 'therapies'.
  /// Each doc: `name` (String), `price` (number), optional `isActive` (bool,
  /// default true) and `order` (number). Nothing is hardcoded: services are
  /// added, priced or hidden only in Firestore.
  static Future<List<Map<String, dynamic>>> getTherapiesWithPrice() async {
    try {
      return _therapiesOf(await _therapiesRef.get());
    } catch (e) {
      return [];
    }
  }

  /// Therapies patients can book (live): active docs of 'therapies' with a
  /// name and price, in 'order'.
  static Stream<List<Map<String, dynamic>>> therapiesStream() =>
      _therapiesRef.snapshots().map(_therapiesOf);

  static List<Map<String, dynamic>> _therapiesOf(QuerySnapshot snapshot) {
    final List<Map<String, dynamic>> list = [];
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      if (data['isActive'] == false) continue;
      final name = (data['name'] ?? doc.id).toString().trim();
      final price = toNum(data['price'])?.toInt();
      if (name.isEmpty || price == null) continue;
      list.add({
        'name': name,
        'price': price,
        'order': toNum(data['order']) ?? 1 << 20,
      });
    }
    list.sort((a, b) {
      final c = (a['order'] as num).compareTo(b['order'] as num);
      return c != 0 ? c : (a['name'] as String).compareTo(b['name'] as String);
    });
    return list;
  }

  /// Get all registered technicians from the 'technicians' collection
  static Stream<List<Map<String, dynamic>>> getTechniciansStream() {
    return _db.collection('technicians').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => doc.data()..['uid'] = doc.id).toList();
    });
  }

  /// Get all registered nurses from the 'nurses' collection
  static Stream<List<Map<String, dynamic>>> getNursesStream() {
    return _db.collection('nurses').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => doc.data()..['uid'] = doc.id).toList();
    });
  }

  /// Get all registered therapists from the 'therapists' collection
  static Stream<List<Map<String, dynamic>>> getTherapistsStream() {
    return _db.collection('therapists').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => doc.data()..['uid'] = doc.id).toList();
    });
  }

  /// Check Nurse Multi-Day Availability for 3-7 Days
  static Future<bool> checkNurseMultiDayAvailability({
    required String nurseUid,
    required DateTime startDate,
    required int durationDays,
  }) async {
    try {
      final snap = await _db
          .collection('appointments')
          .where('doctorUid', isEqualTo: nurseUid)
          .get();

      final Set<String> targetDates = {};
      for (int i = 0; i < durationDays; i++) {
        final date = startDate.add(Duration(days: i));
        targetDates.add(normalizeDateKey('${date.day}/${date.month}/${date.year}'));
      }

      for (var doc in snap.docs) {
        final data = doc.data();
        final status = data['status'] ?? '';
        if (status == 'Declined' || status == 'Cancelled') continue;

        final docDate = data['date']?.toString() ?? '';
        final docDateKey = normalizeDateKey(docDate);

        if (targetDates.contains(docDateKey)) {
          return false; // Overlap found! Nurse is booked on this date!
        }

        final int numDays = toNum(data['durationDays'])?.toInt() ?? 1;
        if (numDays > 1) {
          try {
            final parts = docDate.split('/');
            if (parts.length == 3) {
              final dStart = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
              for (int j = 0; j < numDays; j++) {
                final dCurrent = dStart.add(Duration(days: j));
                final dKey = normalizeDateKey('${dCurrent.day}/${dCurrent.month}/${dCurrent.year}');
                if (targetDates.contains(dKey)) {
                  return false; // Overlap found!
                }
              }
            }
          } catch (_) {}
        }
      }
      return true; // Nurse is free on all target dates!
    } catch (_) {
      return true;
    }
  }

  /// Update Technician Offered Lab Tests Checkboxes
  static Future<void> updateTechnicianOfferedTests({
    required String technicianUid,
    required List<String> offeredTests,
  }) async {
    await _db.collection('technicians').doc(technicianUid).set({
      'offeredTests': offeredTests,
    }, SetOptions(merge: true));

  }

  /// Update User Last Seen timestamp
  static Future<void> updateUserLastSeen(String uid, String role) async {
    final now = DateTime.now().toIso8601String();
    final collection = role == 'doctor'
        ? 'doctors'
        : (role == 'technician'
            ? 'technicians'
            : (role == 'nurse' ? 'nurses' : (role == 'therapist' ? 'therapists' : 'patients')));

    await _db.collection(collection).doc(uid).set({
      'lastSeen': now,
    }, SetOptions(merge: true));

  }

  /// Update Online Status (Online / Offline)
  static Future<void> updateDoctorOnlineStatus(
      String doctorUid, bool isOnline) async {
    await _db.collection('doctors').doc(doctorUid).set({
      'isOnline': isOnline,
    }, SetOptions(merge: true));

    await _db.collection('technicians').doc(doctorUid).set({
      'isOnline': isOnline,
    }, SetOptions(merge: true));

    await _db.collection('nurses').doc(doctorUid).set({
      'isOnline': isOnline,
    }, SetOptions(merge: true));

    await _db.collection('therapists').doc(doctorUid).set({
      'isOnline': isOnline,
    }, SetOptions(merge: true));

  }

  /// Get user document stream for live last seen & profile updates
  static Stream<DocumentSnapshot<Map<String, dynamic>>> getUserStream(
      String uid, String role) {
    // Patients and admin were previously mapped to 'ambulances' by mistake
    const collections = {
      'doctor': 'doctors',
      'technician': 'technicians',
      'nurse': 'nurses',
      'therapist': 'therapists',
      'hospital': 'hospitals',
      'ambulance': 'ambulances',
      'patient': 'patients',
    };
    final collection = collections[role] ?? 'users';
    return _db.collection(collection).doc(uid).snapshots();
  }

  /// Update Profile Picture URL
  static Future<void> updateUserProfilePicUrl({
    required String uid,
    required String role,
    required String photoUrl,
  }) async {
    await _db.collection(_profileCollection(role)).doc(uid).set({
      'profilePicUrl': photoUrl,
    }, SetOptions(merge: true));
  }

  /// Role -> profile collection (patients used to fall through to
  /// 'ambulances', which created stray ambulance records).
  static String _profileCollection(String role) => const {
        'doctor': 'doctors',
        'technician': 'technicians',
        'nurse': 'nurses',
        'therapist': 'therapists',
        'hospital': 'hospitals',
        'ambulance': 'ambulances',
        'patient': 'patients',
        'care_physician': 'care_physicians',
      }[role] ??
      'users';

  /// Remove the profile photo: the app shows the default icon again and the
  /// old file is deleted from storage.
  static Future<void> removeProfilePic({
    required String uid,
    required String role,
    String? oldUrl,
  }) async {
    await _db.collection(_profileCollection(role)).doc(uid).set({
      'profilePicUrl': FieldValue.delete(),
    }, SetOptions(merge: true));
    if ((oldUrl ?? '').isNotEmpty) {
      try {
        await StorageService.deleteByUrl(oldUrl!);
      } catch (_) {
        // the record no longer points at it; a leftover file is harmless
      }
    }
  }

  /// Admin Update Provider Verification Status (Approve / Revoke)
  static Future<void> updateProviderVerificationStatus({
    required String uid,
    required String role,
    required bool isVerified,
  }) async {
    final collection = role == 'doctor'
        ? 'doctors'
        : (role == 'technician'
            ? 'technicians'
            : (role == 'nurse'
                ? 'nurses'
                : (role == 'therapist'
                    ? 'therapists'
                    : (role == 'hospital' ? 'hospitals' : 'ambulances'))));

    await _db.collection(collection).doc(uid).set({
      'isVerified': isVerified,
      'verifiedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

  }

  /// Get question set from subcollection /emergency_categories/{categoryDocId}/questions/questions_set
  static Future<Map<String, dynamic>> getCategoryQuestions(
      String categoryDocId) async {
    try {
      final snap = await _db
          .collection('emergency_categories')
          .doc(categoryDocId)
          .collection('questions')
          .doc('questions_set')
          .get();

      if (snap.exists && snap.data() != null && snap.data()!.isNotEmpty) {
        return snap.data()!;
      }

      // Seed questions_set document if it doesn't exist
      Map<String, dynamic> defaultSet = {};
      final lower = categoryDocId.toLowerCase();

      if (lower.contains('brain') || lower.contains('stroke')) {
        defaultSet = {
          'Arm weakness or numbness?': false,
          'Face drooping on one side?': false,
          'Speech slurred?': false,
          'When did it start?': '<30 min',
        };
      } else if (lower.contains('cardiac') || lower.contains('chest')) {
        defaultSet = {
          'When did the pain start?': '<30 min',
          'Sweating or breathless?': false,
          'Pain radiating to arm or jaw?': false,
        };
      } else if (lower.contains('ortho') || lower.contains('trauma')) {
        defaultSet = {
          'Is there visible bleeding or fracture?': false,
          'Is patient able to walk?': false,
        };
      } else {
        defaultSet = {
          'Is patient conscious?': true,
          'Is patient breathing normally?': true,
        };
      }

      await _db
          .collection('emergency_categories')
          .doc(categoryDocId)
          .collection('questions')
          .doc('questions_set')
          .set(defaultSet, SetOptions(merge: true));

      return defaultSet;
    } catch (_) {
      return {
        'Arm weakness or numbness?': false,
        'Face drooping on one side?': false,
        'Speech slurred?': false,
        'When did it start?': '<30 min',
      };
    }
  }

  static final List<Map<String, dynamic>> defaultEmergencyCategories = [
    {
      'id': 'cardiac',
      'title': 'Cardiac / Chest pain',
      'subtitle': 'Will route to a cath-lab-ready hospital',
      'icon': 'heart',
      'questions': [
        {
          'question': 'When did the pain start?',
          'options': ['<30 min', '30–60 min', '>1 hour']
        },
        {
          'question': 'Sweating or breathless?',
          'options': ['Yes', 'No']
        }
      ]
    },
    {
      'id': 'brain',
      'title': 'Brain / Stroke',
      'subtitle': 'Will route to a stroke-ICU-ready hospital',
      'icon': 'brain',
      'questions': [
        {
          'question': 'When did symptoms start?',
          'options': ['<1 hour', '1–3 hours', '>3 hours']
        },
        {
          'question': 'Face drooping or slurred speech?',
          'options': ['Yes', 'No']
        }
      ]
    },
    {
      'id': 'ortho',
      'title': 'Ortho / Trauma',
      'subtitle': 'Will route to an OT & fracture-ready hospital',
      'icon': 'trauma',
      'questions': [
        {
          'question': 'Is there visible bleeding or fracture?',
          'options': ['Yes', 'No']
        },
        {
          'question': 'Is patient able to walk?',
          'options': ['Yes', 'No']
        }
      ]
    },
    {
      'id': 'chest',
      'title': 'Chest / Breathing',
      'subtitle': 'Will route to an ICU & oxygen-ready hospital',
      'icon': 'lungs',
      'questions': [
        {
          'question': 'Severity of breathlessness?',
          'options': ['Mild', 'Moderate', 'Severe']
        },
        {
          'question': 'Patient has asthma/respiratory history?',
          'options': ['Yes', 'No']
        }
      ]
    },
    {
      'id': 'pregnancy',
      'title': 'Pregnancy / Obstetrics',
      'subtitle': 'Will route to a NICU & maternity-ready hospital',
      'icon': 'pregnancy',
      'questions': [
        {
          'question': 'Is patient having labor pains or bleeding?',
          'options': ['Yes', 'No']
        },
        {
          'question': 'Current trimester?',
          'options': ['1st Trimester', '2nd Trimester', '3rd Trimester']
        }
      ]
    },
    {
      'id': 'other',
      'title': 'Something else',
      'subtitle': 'Will route to nearest general emergency unit',
      'icon': 'emergency',
      'questions': [
        {
          'question': 'Is patient conscious?',
          'options': ['Yes', 'No']
        }
      ]
    },
  ];

  /// Get emergency categories & questions from Firestore 'emergency_categories'
  static Future<List<Map<String, dynamic>>> getEmergencyCategories() async {
    try {
      final snapshot = await _db.collection('emergency_categories').get();
      if (snapshot.docs.isEmpty) {
        for (final item in defaultEmergencyCategories) {
          final String docId = item['title'].toString().toLowerCase().replaceAll('/', '-').replaceAll(' ', '_');
          await _db.collection('emergency_categories').doc(docId).set({
            'title': item['title'],
            'subtitle': item['subtitle'],
            'icon': item['icon'],
            'questions': item['questions'],
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        return defaultEmergencyCategories;
      } else {
        final List<Map<String, dynamic>> list = [];
        for (var doc in snapshot.docs) {
          final data = doc.data();
          data['id'] = doc.id;
          data['title'] = data['title'] ?? doc.id;
          data['subtitle'] = data['subtitle'] ?? 'Will route to emergency ready hospital';
          data['questions'] = data['questions'] ?? [];
          list.add(data);
        }
        return list.isNotEmpty ? list : defaultEmergencyCategories;
      }
    } catch (_) {
      return defaultEmergencyCategories;
    }
  }

  /// Get list of registered hospitals from Firestore collection 'hospitals'
  static Future<List<Map<String, dynamic>>> getHospitalsList() async {
    try {
      return _hospitalsOf(await _db.collection('hospitals').get());
    } catch (_) {
      return [];
    }
  }

  /// Registered hospitals (live): only what is in 'hospitals', by name.
  static Stream<List<Map<String, dynamic>>> hospitalsListStream() =>
      _db.collection('hospitals').snapshots().map(_hospitalsOf);

  static List<Map<String, dynamic>> _hospitalsOf(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final list = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      data['uid'] = doc.id;
      final name = (data['name'] ?? data['hospital'] ?? '').toString().trim();
      if (name.isNotEmpty) list.add(data);
    }
    list.sort((a, b) => (a['name'] ?? a['hospital']).toString().toLowerCase()
        .compareTo((b['name'] ?? b['hospital']).toString().toLowerCase()));
    return list;
  }

  static final List<String> defaultLocationMaster = [
    'Balewadi',
    'Hinjewadi',
    'Baner',
    'Wakad',
    'Thergaon',
  ];

  /// Get location master list from Firestore collection 'location_master'
  static Future<List<String>> getLocationMaster() =>
      _getNameMaster('location_master');

  /// Edit-profile screens: the saved role record (it holds fields UserModel
  /// doesn't carry, like offered tests) and the area master.
  static Future<({Map<String, dynamic> data, List<String> areas})>
      loadProfileForEdit(String collection, String uid) async {
    final r = await Future.wait<Object?>([
      _db.collection(collection).doc(uid).get(),
      getLocationMaster(),
    ]);
    return (
      data: (r[0] as DocumentSnapshot<Map<String, dynamic>>).data() ??
          <String, dynamic>{},
      areas: r[1] as List<String>,
    );
  }

  /// Area chips for an edit screen: the master, plus saved areas the master
  /// no longer lists (so they can still be unticked).
  static List<String> areaOptions(List<String> master, Iterable<String> saved) =>
      [...master, for (final a in saved) if (!master.contains(a)) a];

  /// A saved list field as strings ([] when missing).
  static List<String> stringList(Object? v) => v is List
      ? v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
      : <String>[];

  /// Read a name list from a master collection. Each doc: `name` (String),
  /// optional `isActive` (bool, default true) and `order` (number).
  /// Nothing is hardcoded or auto-created — the list is exactly what is in
  /// Firestore (empty if the collection is empty).
  static Future<List<String>> _getNameMaster(String collection) async {
    try {
      return _namesOf(await _db.collection(collection).get());
    } catch (_) {
      return [];
    }
  }

  /// Live version of a master list: updates as soon as it changes.
  static Stream<List<String>> nameMasterStream(String collection) =>
      _db.collection(collection).snapshots().map(_namesOf);

  /// Qualifications chosen at registration (Firestore masters, live).
  static Stream<List<String>> nurseQualificationsStream() =>
      nameMasterStream('nurse_qualifications');
  static Stream<List<String>> technicianQualificationsStream() =>
      nameMasterStream('technician_qualifications');
  static Stream<List<String>> therapistQualificationsStream() =>
      nameMasterStream('therapist_qualifications');

  /// Doctor categories from 'category_doctors' (live).
  static Stream<List<String>> doctorCategoriesStream() =>
      _categoriesRef.snapshots().map((s) => _namesOf(
          s as QuerySnapshot<Map<String, dynamic>>));

  static List<String> _namesOf(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final docs = snapshot.docs
        .map((d) => d.data()..['_id'] = d.id)
        .where((d) => d['isActive'] != false)
        .toList()
      ..sort((a, b) {
        final oa = toNum(a['order']) ?? 1 << 20;
        final ob = toNum(b['order']) ?? 1 << 20;
        final c = oa.compareTo(ob);
        return c != 0
            ? c
            : '${a['name'] ?? a['_id']}'.compareTo('${b['name'] ?? b['_id']}');
      });
    return docs
        .map((d) => (d['name'] ?? d['_id']).toString().trim())
        .where((n) => n.isNotEmpty)
        .toList();
  }

  /// Languages providers can select — Firestore collection 'language_master'
  static Future<List<String>> getLanguageMaster() =>
      _getNameMaster('language_master');

  /// Therapist qualifications — Firestore collection 'therapist_qualifications'
  static Future<List<String>> getTherapistQualificationMaster() =>
      _getNameMaster('therapist_qualifications');

  /// Registered hospitals / clinics / centres a therapist can mark as preferred.
  /// Reads the real 'hospitals' collection only (no placeholder entries).
  /// Returns maps with `name`, `area` and `type` (grouping label).
  static Future<List<Map<String, String>>> getCareCentres() async {
    try {
      final snapshot = await _db.collection('hospitals').get();
      final List<Map<String, String>> list = [];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = (data['name'] ?? data['hospital'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final locs = data['preferredLocations'] as List<dynamic>? ?? [];
        final area = (data['city'] ??
                (locs.isNotEmpty ? locs.first : null) ??
                '')
            .toString()
            .trim();
        final type = (data['facilityType'] ?? data['type'] ?? 'Hospital')
            .toString()
            .trim();
        list.add({'name': name, 'area': area, 'type': type});
      }
      list.sort((a, b) => a['name']!.compareTo(b['name']!));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Save Patient Favorite Doctor per Category
  static Future<void> savePatientFavoriteDoctor({
    required String patientUid,
    required String category,
    required String doctorUid,
    required String doctorName,
  }) async {
    final patientDoc = await _db.collection('patients').doc(patientUid).get();
    final data = patientDoc.data() ?? {};

    Map<String, dynamic> favDocs =
        Map<String, dynamic>.from(data['favoriteDoctors'] ?? {});
    Map<String, dynamic> favNames =
        Map<String, dynamic>.from(data['favoriteDoctorNames'] ?? {});

    favDocs[category] = doctorUid;
    favNames[category] = doctorName;

    final updateMap = {
      'favoriteDoctors': favDocs,
      'favoriteDoctorNames': favNames,
    };

    await _db.collection('patients').doc(patientUid).set(updateMap, SetOptions(merge: true));
  }

  /// Save Hospital Preferred Doctors per Category (Choose 2 doctors per category)
  static Future<void> saveHospitalPreferredDoctors({
    required String hospitalUid,
    required String category,
    required List<String> doctorUids,
    required List<String> doctorNames,
  }) async {
    final doc = await _db.collection('hospitals').doc(hospitalUid).get();
    final data = doc.data() ?? {};

    Map<String, dynamic> prefDocs =
        Map<String, dynamic>.from(data['hospitalPreferredDoctors'] ?? {});
    Map<String, dynamic> prefNames =
        Map<String, dynamic>.from(data['hospitalPreferredDoctorNames'] ?? {});

    prefDocs[category] = doctorUids;
    prefNames[category] = doctorNames;

    final updateMap = {
      'hospitalPreferredDoctors': prefDocs,
      'hospitalPreferredDoctorNames': prefNames,
    };

    await _db.collection('hospitals').doc(hospitalUid).set(updateMap, SetOptions(merge: true));
  }

  static final List<String> defaultHospitalServices = [
    'Blood bank',
    'ICU',
    'NICU',
    'O ER beds free',
    'OT',
    'cath lab',
  ];

  /// Get Hospital Services list from Firestore collection 'hospital_services'
  static Future<List<String>> getHospitalServices() async {
    try {
      final snapshot = await _db.collection('hospital_services').get();
      if (snapshot.docs.isEmpty) {
        for (final service in defaultHospitalServices) {
          await _db.collection('hospital_services').doc(service).set({
            'name': service,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        return defaultHospitalServices;
      } else {
        final List<String> list = [];
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final name = data['name']?.toString() ?? doc.id;
          if (name.isNotEmpty) {
            list.add(name);
          }
        }
        list.sort();
        return list.isNotEmpty ? list : defaultHospitalServices;
      }
    } catch (_) {
      return defaultHospitalServices;
    }
  }

  /// Get doctor categories with price map from Firestore collection 'category_doctors'
  static Future<List<Map<String, dynamic>>> getDoctorCategoriesWithPrice() async {
    try {
      final snapshot = await _categoriesRef.get();
      final List<Map<String, dynamic>> list = [];
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final name = data['name']?.toString() ?? doc.id;
        final price = toNum(data['price'])?.toInt(); // null: not set
        if (name.isNotEmpty) {
          list.add({
            'name': name,
            'price': price,
          });
        }
      }
      list.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      return list;
    } catch (e) {
      return [];
    }
  }

  /// Get category names list
  static Future<List<String>> getDoctorCategories() async {
    final catList = await getDoctorCategoriesWithPrice();
    return catList.map((e) => e['name'] as String).toList();
  }

  /// Price of a category from Firestore (null while it is not set).
  static Future<int?> getCategoryPrice(String categoryName) async {
    try {
      final doc = await _categoriesRef.doc(categoryName).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        return toNum(data['price'])?.toInt();
      }
    } catch (_) {}
    return null;
  }

  /// Statuses in which an accepted emergency is still being handled.
  static const Set<String> _activeEmergencyStatuses = {
    'Confirmed',
    'In Progress',
    'Pending Ambulance Dispatch',
    'Ambulance Dispatched',
    'Patient Picked Up',
  };

  /// Current search radius of an urgent request: 4 km, then 6 km after
  /// 30 s and 8 km after 60 s (capped at 8 km).
  /// since it was broadcast, capped at 8 km.
  static double searchRadiusKm(Map<String, dynamic> request) {
    final start = _asDateTime(request['broadcastedAt']) ??
        _asDateTime(request['createdAt']) ??
        DateTime.now();
    final steps = DateTime.now().difference(start).inSeconds ~/ 30;
    return (4 + 2 * steps).clamp(4, 8).toDouble();
  }

  /// How long an urgent request keeps searching once it has been broadcast.
  static const Duration urgentRequestLifetime = Duration(minutes: 2);

  /// When an unaccepted urgent request closes (broadcast time + 2 min; a
  /// request not yet broadcast is counted from 1 min after creation).
  static DateTime urgentRequestExpiry(Map<String, dynamic> request) {
    final start = _asDateTime(request['broadcastedAt']) ??
        _asDateTime(request['createdAt'])?.add(const Duration(seconds: 60)) ??
        DateTime.now();
    return start.add(urgentRequestLifetime);
  }

  /// True for a patient urgent request nobody accepted before it ran out.
  static bool isUrgentRequestExpired(Map<String, dynamic> request) {
    // Emergency Help (SOS): the whole hospital -> doctor -> ambulance process
    // must finish within 5 minutes, otherwise the request is closed.
    if (request['consultationType'] == SosService.type) {
      const sosOpen = {
        'Pending Hospital Acceptance',
        'Pending Doctor Assignment',
        'Pending Ambulance Dispatch',
      };
      if (!sosOpen.contains((request['status'] ?? '').toString())) return false;
      return DateTime.now().isAfter(SosService.expiry(request));
    }
    if (request['autoExpire'] != true) return false;
    if (request['doctorAcceptedAt'] != null) return false;
    const open = {
      'Pending Emergency',
      'Pending Doctor Assignment',
      'Broadcasted',
      'Declined',
    };
    if (!open.contains((request['status'] ?? '').toString())) return false;
    return DateTime.now().isAfter(urgentRequestExpiry(request));
  }

  /// A hospital or doctor already accepted part of the request.
  static bool isPartlyAccepted(Map<String, dynamic> request) =>
      request['doctorAcceptedAt'] != null ||
      (request['assignedHospitalUid'] ?? '').toString().isNotEmpty;

  /// Closes a run-out urgent request. Nobody accepted: it is deleted
  /// entirely. A hospital or doctor already accepted part of it: it is kept
  /// as 'Expired' (history, and everyone involved is told by the server).
  /// Returns true if it was closed.
  static Future<bool> expireUrgentRequest(String appointmentId) async {
    final ref = _db.collection('appointments').doc(appointmentId);
    try {
      return await _db.runTransaction<bool>((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data();
        if (data == null || !isUrgentRequestExpired(data)) return false;
        if (isPartlyAccepted(data)) {
          tx.update(ref, {
            'status': 'Expired',
            'expiredStage': data['status'],
            'expiredAt': DateTime.now().toIso8601String(),
          });
        } else {
          tx.delete(ref);
        }
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  static DateTime? _asDateTime(dynamic raw) => raw is Timestamp
      ? raw.toDate()
      : DateTime.tryParse((raw ?? '').toString());

  static bool _isActiveEmergencyOf(String doctorUid, Map<String, dynamic> a) =>
      a['doctorUid'] == doctorUid &&
      a['isUrgentEmergency'] == true &&
      _activeEmergencyStatuses.contains((a['status'] ?? '').toString());

  /// Statuses of an urgent booking that is still pending or in progress.
  static const Set<String> _activeUrgentBookingStatuses = {
    'Pending Emergency',
    'Pending Doctor Assignment',
    'Broadcasted',
    'Confirmed',
    'In Progress',
    'Pending Ambulance Dispatch',
    'Ambulance Dispatched',
    'Patient Picked Up',
    'Pending Hospital Acceptance',
  };

  /// True while the patient has an urgent booking that is pending or being
  /// consulted (not yet completed / cancelled).
  static Future<bool> patientHasActiveUrgentBooking(String patientUid) async {
    try {
      final snap = await _db
          .collection('appointments')
          .where('patientUid', isEqualTo: patientUid)
          .get();
      return snap.docs.any((d) {
        final a = d.data();
        if (isUrgentRequestExpired(a)) {
          d.reference.delete(); // ran out unaccepted: close, keep nothing
          return false;
        }
        return a['isUrgentEmergency'] == true &&
            _activeUrgentBookingStatuses.contains((a['status'] ?? '').toString());
      });
    } catch (_) {
      return false;
    }
  }

  /// True while the patient has an emergency (SOS) request that is still open.
  /// Other bookings (urgent home visits, consultations) do not block a new SOS.
  static Future<bool> patientHasActiveSos(String patientUid) async {
    try {
      final snap = await _db
          .collection('appointments')
          .where('patientUid', isEqualTo: patientUid)
          .get();
      return snap.docs.any((d) => isActiveSos(d.data()));
    } catch (_) {
      return false;
    }
  }

  static const Set<String> _sosDone = {
    'Completed', 'Cancelled', 'Rejected', 'Declined', 'Closed', 'Expired',
  };

  /// An SOS emergency that is still running.
  static bool isActiveSos(Map<String, dynamic> a) =>
      a['consultationType'] == SosService.type &&
      !isUrgentRequestExpired(a) &&
      !_sosDone.contains((a['status'] ?? '').toString());

  /// The patient's running SOS emergency (newest), or null. Drives the
  /// blinking "Emergency in progress" button on the patient home.
  static Stream<Map<String, dynamic>?> patientActiveSosStream(
      String patientUid) {
    return _db
        .collection('appointments')
        .where('patientUid', isEqualTo: patientUid)
        .where('consultationType', isEqualTo: SosService.type)
        .snapshots()
        .map((snap) {
      final active = [
        for (final d in snap.docs)
          if (isActiveSos(d.data())) {...d.data(), 'appointmentId': d.id}
      ]..sort((a, b) => (b['createdAt'] ?? '')
          .toString()
          .compareTo((a['createdAt'] ?? '').toString()));
      return active.isEmpty ? null : active.first;
    });
  }

  /// UIDs of ambulances currently on a dispatch.
  static Future<Set<String>> getBusyAmbulanceUids() async {
    try {
      final snap = await _db
          .collection('appointments')
          .where('consultationType', isEqualTo: SosService.type)
          .get();
      const active = {'Ambulance Dispatched', 'Patient Picked Up'};
      return {
        for (final d in snap.docs)
          if (active.contains((d.data()['status'] ?? '').toString()))
            (d.data()['assignedAmbulanceUid'] ?? '').toString()
      }..remove('');
    } catch (_) {
      return {};
    }
  }

  /// UIDs of all doctors who currently have an uncompleted emergency.
  static Future<Set<String>> getBusyEmergencyDoctorUids() async {
    try {
      final snap = await _db
          .collection('appointments')
          .where('isUrgentEmergency', isEqualTo: true)
          .get();
      return {
        for (final d in snap.docs)
          if (_activeEmergencyStatuses.contains((d.data()['status'] ?? '').toString()))
            (d.data()['doctorUid'] ?? '').toString()
      }..remove('');
    } catch (_) {
      return {};
    }
  }

  /// True while the doctor has an accepted emergency that is not completed.
  static Future<bool> hasActiveEmergency(String doctorUid) async {
    if (doctorUid.isEmpty) return false;
    try {
      final snap = await _db
          .collection('appointments')
          .where('doctorUid', isEqualTo: doctorUid)
          .get();
      return snap.docs.any((d) => _isActiveEmergencyOf(doctorUid, d.data()));
    } catch (_) {
      return false;
    }
  }

  /// The doctor's preferred hospital with its live location, or null when
  /// the hospital isn't registered / has no location yet.
  static Future<({String name, double? lat, double? lng})?>
      getDoctorHospitalLocation(String doctorUid) async {
    try {
      final doc = await _db.collection('doctors').doc(doctorUid).get();
      final name = (doc.data()?['hospital'] ?? '').toString().trim();
      if (name.isEmpty) return null;
      final hospitals = await _db.collection('hospitals').get();
      for (final h in hospitals.docs) {
        final d = h.data();
        final hName = (d['name'] ?? d['hospital'] ?? '').toString().trim();
        if (hName.toLowerCase() == name.toLowerCase()) {
          return (
            name: hName,
            lat: toNum(d['latitude'])?.toDouble(),
            lng: toNum(d['longitude'])?.toDouble(),
          );
        }
      }
      return (name: name, lat: null, lng: null);
    } catch (_) {
      return null;
    }
  }

  /// Get all registered doctors from the 'doctors' collection
  static Stream<List<Map<String, dynamic>>> getDoctorsStream() {
    return _db.collection('doctors').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => doc.data()..['uid'] = doc.id).toList();
    });
  }

  /// Normalize date string e.g. "28/9/2026", "28/09/2026", "2026-09-28" to "YYYY-MM-DD"
  /// Normalises a typed time slot ("8:30 pm", "20:30", "8 PM") to the
  /// "hh:mm AM" format used by schedules and bookings. Null if not a time.
  static String? normalizeTimeSlot(String input) {
    final m = RegExp(r'^\s*(\d{1,2})(?:[:.](\d{2}))?\s*([aApP])?\.?\s*[mM]?\.?\s*$')
        .firstMatch(input);
    if (m == null) return null;
    var hour = int.parse(m.group(1)!);
    final minute = int.parse(m.group(2) ?? '0');
    final ampm = m.group(3)?.toUpperCase();
    if (minute > 59) return null;
    String period;
    if (ampm == null) {
      if (hour > 23) return null;
      period = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12 == 0 ? 12 : hour % 12;
    } else {
      if (hour < 1 || hour > 12) return null;
      period = ampm == 'P' ? 'PM' : 'AM';
    }
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')} $period';
  }

  /// Minutes since midnight for an "hh:mm AM" slot (for sorting slots).
  static int timeSlotMinutes(String slot) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})\s*([AP])M').firstMatch(slot.toUpperCase());
    if (m == null) return 24 * 60;
    final h = int.parse(m.group(1)!) % 12 + (m.group(3) == 'P' ? 12 : 0);
    return h * 60 + int.parse(m.group(2)!);
  }

  static String normalizeDateKey(String dateStr) {
    if (dateStr.trim().isEmpty) return '';
    try {
      if (dateStr.contains('/')) {
        final parts = dateStr.trim().split('/');
        if (parts.length == 3) {
          final day = int.parse(parts[0]).toString().padLeft(2, '0');
          final month = int.parse(parts[1]).toString().padLeft(2, '0');
          final year = parts[2].trim();
          return '$year-$month-$day';
        }
      } else if (dateStr.contains('-')) {
        final parts = dateStr.trim().split('-');
        if (parts.length == 3) {
          if (parts[0].length == 4) {
            final year = parts[0];
            final month = int.parse(parts[1]).toString().padLeft(2, '0');
            final day = int.parse(parts[2]).toString().padLeft(2, '0');
            return '$year-$month-$day';
          }
        }
      }
    } catch (_) {}
    return dateStr.trim();
  }

  /// Fetch Doctor's booked time slots on a specific date (Rule 2)
  static Future<List<String>> getDoctorBookedTimeSlots({
    required String doctorUid,
    required String date,
  }) async {
    try {
      final snap = await _db
          .collection('appointments')
          .where('doctorUid', isEqualTo: doctorUid)
          .get();

      final targetKey = normalizeDateKey(date);
      final List<String> bookedSlots = [];

      for (var doc in snap.docs) {
        final data = doc.data();
        final status = data['status'] ?? '';
        final time = data['time']?.toString() ?? '';
        final docDate = data['date']?.toString() ?? '';

        final docKey = normalizeDateKey(docDate);

        // A request this provider declined stays under their uid while it
        // is broadcast to others; it must not block their calendar.
        final List<dynamic> declinedBy =
            data['declinedBy'] as List<dynamic>? ?? [];
        if (declinedBy.contains(doctorUid)) continue;

        if (docKey == targetKey && status != 'Declined' && time.isNotEmpty) {
          bookedSlots.add(time.trim().toUpperCase());
        }
      }
      return bookedSlots;
    } catch (_) {
      return [];
    }
  }

  /// Fetch Patient's booked time slots on a specific date (Rule 1)
  static Future<List<String>> getPatientBookedTimeSlots({
    required String patientUid,
    required String date,
  }) async {
    try {
      final snap = await _db
          .collection('appointments')
          .where('patientUid', isEqualTo: patientUid)
          .get();

      final targetKey = normalizeDateKey(date);
      final List<String> bookedSlots = [];

      for (var doc in snap.docs) {
        final data = doc.data();
        final status = data['status'] ?? '';
        final time = data['time']?.toString() ?? '';
        final docDate = data['date']?.toString() ?? '';

        final docKey = normalizeDateKey(docDate);

        if (docKey == targetKey && status != 'Declined' && time.isNotEmpty) {
          bookedSlots.add(time.trim().toUpperCase());
        }
      }
      return bookedSlots;
    } catch (_) {
      return [];
    }
  }

  /// Save or update Doctor's schedule for a specific date
  static Future<void> saveDoctorDateSchedule({
    required String doctorUid,
    required String dateKey, // Format: YYYY-MM-DD
    required bool isAvailable,
    required List<String> timeSlots,
  }) async {
    await _db
        .collection('doctor_schedules')
        .doc(doctorUid)
        .collection('dates')
        .doc(dateKey)
        .set({
      'dateKey': dateKey,
      'isAvailable': isAvailable,
      'timeSlots': timeSlots,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Fetch Doctor's schedule for a specific date
  static Future<Map<String, dynamic>?> getDoctorDateSchedule({
    required String doctorUid,
    required String dateKey,
  }) async {
    try {
      final doc = await _db
          .collection('doctor_schedules')
          .doc(doctorUid)
          .collection('dates')
          .doc(dateKey)
          .get();

      if (doc.exists && doc.data() != null) {
        return doc.data();
      }
    } catch (_) {}
    return null;
  }

  /// Create a new appointment booking
  /// A hospital that is not verified yet cannot request any service. Patients
  /// and every other requester have no hospital record and pass.
  static Future<void> assertRequesterVerified(String uid) async {
    if (uid.isEmpty) return;
    final h = (await _db.collection('hospitals').doc(uid).get()).data();
    if (h != null && h['isVerified'] != true) {
      throw Exception(
          'Your hospital is not verified yet. The admin is reviewing your documents.');
    }
  }

  static Future<void> createAppointment({
    required String patientUid,
    required String patientName,
    required String doctorUid,
    required String doctorName,
    required String doctorCategory,
    required String hospital,
    required String date,
    required String time,
    required int price,
    String consultationType = 'Clinic/Visit',
    bool isUrgentEmergency = false,
    int offeredExtraAmount = 0,
    String locationName = '',
    double? patientLat,
    double? patientLng,
    String patientPhone = '',
  }) async {
    await assertRequesterVerified(patientUid);
    final docRef = _db.collection('appointments').doc();
    final otp = ServiceOtp.generate();

    final String initialStatus = isUrgentEmergency
        ? 'Pending Emergency'
        : (consultationType == 'Home Visit' ? 'Pending Home Visit' : 'Confirmed');

    await docRef.set({
      'appointmentId': docRef.id,
      'patientUid': patientUid,
      'patientName': patientName,
      'patientPhone': patientPhone,
      'doctorUid': doctorUid,
      'doctorName': doctorName,
      'doctorCategory': doctorCategory,
      'hospital': hospital,
      'date': date,
      'time': time,
      'basePrice': price - offeredExtraAmount,
      'offeredExtraAmount': offeredExtraAmount,
      'price': price,
      'locationName': locationName,
      // only a real GPS position (never the Pune map centre)
      if (patientLat != null && patientLng != null) 'patientLat': patientLat,
      if (patientLat != null && patientLng != null) 'patientLng': patientLng,
      'patientLocationKnown': patientLat != null && patientLng != null,
      'consultationType': consultationType,
      'isUrgentEmergency': isUrgentEmergency,
      'status': initialStatus,
      'paymentStatus': 'cash', // doctor collects cash at the visit
      'otp': otp,
      'hasBeenRated': false,
      'declinedBy': [],
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  /// Create Emergency Request with 20% Surcharge & GPS Coordinates
  static Future<String> createEmergencyRequest({
    required String patientUid,
    required String patientName,
    required String patientPhone,
    required String doctorUid,
    required String doctorName,
    required String doctorCategory,
    required String hospital,
    required int basePrice,
    required String locationName,
    double? patientLat,
    double? patientLng,
  }) async {
    // preview only: the server works the price out again
    final int surcharge =
        PricingService.current.urgentSurcharge(basePrice) ?? 0;
    final int totalPrice = basePrice + surcharge;
    final docRef = _db.collection('appointments').doc();
    final otp = ServiceOtp.generate();

    final now = DateTime.now();
    final dateStr = '${now.day}/${now.month}/${now.year}';
    final timeStr =
        'ASAP (${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')})';

    final data = {
      'appointmentId': docRef.id,
      'patientUid': patientUid,
      'patientName': patientName,
      'patientPhone': patientPhone,
      'doctorUid': doctorUid,
      'doctorName': doctorName,
      'doctorCategory': doctorCategory,
      'hospital': hospital,
      'date': dateStr,
      'time': timeStr,
      'basePrice': basePrice,
      'emergencySurcharge': surcharge,
      'price': totalPrice,
      'locationName': locationName,
      // only a real GPS position (never the Pune map centre)
      if (patientLat != null && patientLng != null) 'patientLat': patientLat,
      if (patientLat != null && patientLng != null) 'patientLng': patientLng,
      'patientLocationKnown': patientLat != null && patientLng != null,
      'consultationType': 'Emergency Dispatch',
      'isUrgentEmergency': true,
      'status': 'Pending Emergency',
      'paymentStatus': 'cash', // doctor collects cash at the visit
      'otp': otp,
      'hasBeenRated': false,
      'declinedBy': [],
      'createdAt': DateTime.now().toIso8601String(),
    };

    await docRef.set(data);
    return docRef.id;
  }

  /// Stream single appointment status for patient live tracking
  static Stream<DocumentSnapshot<Map<String, dynamic>>> getAppointmentStream(
      String appointmentId) {
    return _db.collection('appointments').doc(appointmentId).snapshots();
  }

  /// Provider responds to a request (Accept / Decline).
  /// Returns false when the request could not be accepted because another
  /// provider already took it (first accept wins) or it is no longer open.
  static Future<bool> respondToEmergencyRequest({
    required String appointmentId,
    required bool accept,
    String? respondingDoctorUid,
    String? respondingDoctorName,
  }) async {
    final uid = respondingDoctorUid ?? '';
    if (accept) {
      return acceptProviderRequest(
        appointmentId: appointmentId,
        providerUid: uid,
        providerName: respondingDoctorName ?? 'Doctor',
      );
    }
    await declineProviderRequest(appointmentId: appointmentId, providerUid: uid);
    return true;
  }

  /// Statuses in which a request is still waiting for a provider.
  static const Set<String> _openRequestStatuses = {
    'Pending Home Visit',
    'Pending Emergency',
    'Pending Doctor Assignment',
    'Broadcasted',
  };

  /// Atomically claim an open request for any provider role.
  /// The first provider to accept gets the booking; everyone after that
  /// gets false and the booking is not touched.
  /// False only for a provider profile that exists and is not verified.
  static Future<bool> _providerIsVerified(String uid) async {
    if (uid.isEmpty) return true;
    for (final col in const [
      'doctors', 'nurses', 'technicians', 'therapists', 'ambulances'
    ]) {
      final d = (await _db.collection(col).doc(uid).get()).data();
      if (d != null) return d['isVerified'] == true;
    }
    return true; // not a provider profile (e.g. an agency's team)
  }

  static Future<bool> acceptProviderRequest({
    required String appointmentId,
    required String providerUid,
    required String providerName,
  }) async {
    // a provider the admin has not approved yet cannot accept a request
    if (!await _providerIsVerified(providerUid)) return false;
    final docRef = _db.collection('appointments').doc(appointmentId);
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(docRef);
      final data = snap.data();
      if (data == null) return false;

      final status = (data['status'] ?? '').toString();
      final currentUid = (data['doctorUid'] ?? '').toString();
      final List<dynamic> declinedBy =
          data['declinedBy'] as List<dynamic>? ?? [];
      if (!_openRequestStatuses.contains(status)) return false;
      if (providerUid.isNotEmpty && declinedBy.contains(providerUid)) {
        return false;
      }
      // A direct home-visit request can only be accepted by the provider
      // the patient picked, until it is broadcast to everyone.
      if (status == 'Pending Home Visit' &&
          currentUid.isNotEmpty &&
          currentUid != providerUid) {
        return false;
      }
      // Blocked for 15 days after 3 absents in a month: no new bookings
      if (providerUid.isNotEmpty) {
        final provider = await tx.get(
            _db.collection(_providerCollectionOf(data)).doc(providerUid));
        if (isProviderBlocked(provider.data() ?? {})) return false;
        // offline providers get no new requests
        if (status == 'Broadcasted' &&
            (provider.data() ?? const {})['isOnline'] == false) {
          return false;
        }
        // Physio request in its agency window: only that agency's
        // on-duty physios can take it
        if (status == 'Broadcasted' &&
            !PhysioAgencyService.isOfferedTo(data, provider.data() ?? {},
                uid: providerUid)) {
          return false;
        }
      }

      final updates = <String, dynamic>{
        'status': 'Confirmed',
        'isBroadcast': false,
        'respondedAt': DateTime.now().toIso8601String(),
      };
      if (providerUid.isNotEmpty) {
        updates['doctorUid'] = providerUid;
        updates['doctorName'] = providerName;
      }
      tx.update(docRef, updates);
      return true;
    });
  }

  /// Decline a request. While it is still open it is broadcast to the other
  /// providers; if someone else already accepted it, only this provider's
  /// decline is recorded so the accepted booking is never undone.
  static Future<void> declineProviderRequest({
    required String appointmentId,
    required String providerUid,
  }) async {
    final docRef = _db.collection('appointments').doc(appointmentId);
    final routing = await _physioRoutingIfNeeded(docRef);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final data = snap.data();
      if (data == null) return;

      final status = (data['status'] ?? '').toString();
      final updates = <String, dynamic>{
        'respondedAt': DateTime.now().toIso8601String(),
      };
      if (providerUid.isNotEmpty) {
        updates['declinedBy'] = FieldValue.arrayUnion([providerUid]);
      }
      // Emergency Help (SOS): a decline only removes this provider. The
      // request stays in its stage and the search widens by the timer
      // (4 -> 6 -> 8 km), never because someone declined.
      if (data['consultationType'] == SosService.type) {
        tx.update(docRef, updates);
        return;
      }
      if (_openRequestStatuses.contains(status)) {
        updates['status'] = 'Broadcasted';
        updates['isBroadcast'] = true;
        if (data['broadcastedAt'] == null) {
          updates['broadcastedAt'] = DateTime.now().toIso8601String();
        }
        if (routing != null && data['routingStage'] == null) {
          updates.addAll(routing);
        }
      }
      tx.update(docRef, updates);
    });
  }

  /// Broadcast a waiting request to all nearby providers of its role.
  /// Only applies while nobody has accepted it, so the patient's auto /
  /// manual broadcast can never undo an acceptance.
  static Future<void> broadcastEmergencyToAllDoctors({
    required String appointmentId,
  }) async {
    final docRef = _db.collection('appointments').doc(appointmentId);
    final routing = await _physioRoutingIfNeeded(docRef);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final status = (snap.data()?['status'] ?? '').toString();
      if (status != 'Pending Home Visit' &&
          status != 'Pending Emergency' &&
          status != 'Pending Doctor Assignment' &&
          status != 'Declined') {
        return;
      }
      tx.update(docRef, {
        'status': 'Broadcasted',
        'isBroadcast': true,
        if (snap.data()?['broadcastedAt'] == null)
          'broadcastedAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        if (routing != null && snap.data()?['routingStage'] == null) ...routing,
      });
    });
  }

  /// Agency-first routing fields for a physio request that is about to go
  /// out to everyone (null for other roles or when already routed).
  static Future<Map<String, dynamic>?> _physioRoutingIfNeeded(
      DocumentReference<Map<String, dynamic>> ref) async {
    try {
      final data = (await ref.get()).data();
      if (data == null || data['routingStage'] != null) return null;
      if (data['isTherapistRequest'] != true && data['roleTarget'] != 'therapist') {
        return null;
      }
      return await PhysioAgencyService.routingFor(
        (data['locationName'] ?? '').toString(),
        date: (data['date'] ?? '').toString(),
        time: (data['time'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Whether a provider's preferred service areas cover the patient's
  /// location (e.g. "Bibwewadi, Pune"). Strict: a Baner/Balewadi provider
  /// never matches Bibwewadi or Katraj, and an unknown patient area matches
  /// nobody.
  static bool providerServesArea(
      List<dynamic> preferredLocations, String patientLocation) {
    final full = patientLocation.toLowerCase();
    final primary = full.split(',').first.trim();
    if (primary.isEmpty) return false;
    for (final raw in preferredLocations) {
      final area = raw.toString().trim().toLowerCase();
      if (area.isEmpty) continue;
      if (full.contains(area)) return true;
      if (primary.length >= 4 && area.contains(primary)) return true;
    }
    return false;
  }

  /// Verify OTP and Start Consultation
  static Future<bool> verifyAndStartConsultation({
    required String appointmentId,
    required String enteredOtp,
  }) async {
    final lateBy = await startSessionWithOtp(
        appointmentId: appointmentId, enteredOtp: enteredOtp);
    return lateBy != null;
  }

  // ---------------------------------------------------------------------------
  // Punctuality: professional score + automatic session close
  // ---------------------------------------------------------------------------

  // Professional score rules (doctor home visits, nurse, technician, physio):
  //  - Late for duty: OTP started 30+ mins after the booked start  → -5
  //    (no penalty if the provider told the patient "Running late" first)
  //  - Absent: not started by the end of the booked slot (7-8 → by 8)  → -15
  //  - 3 absents in a calendar month → blocked for 15 days
  //    (no new requests / popups, hidden from patients)
  //  - Every 4 months (Jan, May, Sep) the score resets to 100

  static const int lateArrivalGraceMinutes = 30;
  static const int latePenaltyPoints = 5; // 5% of the 100-point score
  static const int absentPenaltyPoints = 15; // 15% of the 100-point score
  static const int absencesBeforeBlock = 3;
  static const Duration absenceBlockDuration = Duration(days: 15);
  static const int defaultProfessionalScore = 100;

  /// Session length used when a booking has a single start time
  /// (e.g. "07:00 PM" means 7 to 8) or is urgent / ASAP.
  static const Duration defaultSessionLength = Duration(hours: 1);

  /// 4-month score cycle: C1 Jan-Apr, C2 May-Aug, C3 Sep-Dec.
  static String scoreCycleKey([DateTime? at]) {
    final d = at ?? DateTime.now();
    return '${d.year}-C${(d.month - 1) ~/ 4 + 1}';
  }

  static String _monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  /// Current score; a score from an earlier 4-month cycle counts as reset.
  static int professionalScoreOf(Map<String, dynamic> provider) {
    if (provider['scoreCycle'] != scoreCycleKey()) {
      return defaultProfessionalScore;
    }
    return toNum(provider['professionalScore'])?.toInt() ??
        defaultProfessionalScore;
  }

  /// End of a 15-day block after 3 absents in a month, if still active.
  static DateTime? blockedUntil(Map<String, dynamic> provider) {
    final until = DateTime.tryParse((provider['blockedUntil'] ?? '').toString());
    if (until == null || !until.isAfter(DateTime.now())) return null;
    return until;
  }

  static bool isProviderBlocked(Map<String, dynamic> provider) =>
      blockedUntil(provider) != null;

  /// Score / absence fields after a late (-5) or absent (-15) penalty.
  static Map<String, dynamic> _penaltyUpdate(
      Map<String, dynamic> provider, int points,
      {required bool absent}) {
    final now = DateTime.now();
    final next =
        (professionalScoreOf(provider) - points).clamp(0, defaultProfessionalScore);
    final update = <String, dynamic>{
      'professionalScore': next,
      'scoreCycle': scoreCycleKey(now),
    };
    if (!absent) {
      update['lateArrivals'] = FieldValue.increment(1);
      return update;
    }
    final month = _monthKey(now);
    final absences = provider['absenceMonth'] == month
        ? (toNum(provider['absencesThisMonth'])?.toInt() ?? 0) + 1
        : 1;
    update['absenceMonth'] = month;
    update['absencesThisMonth'] = absences;
    update['totalAbsences'] = FieldValue.increment(1);
    if (absences >= absencesBeforeBlock && !isProviderBlocked(provider)) {
      update['blockedUntil'] = now.add(absenceBlockDuration).toIso8601String();
      update['blockedReason'] =
          '$absences absents in ${month.substring(5)}/${month.substring(0, 4)}';
    }
    return update;
  }

  /// Role collection of whoever serves this appointment (any booking type).
  static String _providerCollectionOf(Map<String, dynamic> a) =>
      _punctualityCollection(a) ?? 'doctors';

  /// Role collection of the provider who serves this appointment, or null
  /// when punctuality does not apply (clinic / online consultations and
  /// ambulance dispatches: the provider does not travel to the patient).
  static String? _punctualityCollection(Map<String, dynamic> a) {
    if (a['isTherapistRequest'] == true || a['roleTarget'] == 'therapist') {
      return 'therapists';
    }
    if (a['isNurseRequest'] == true || a['roleTarget'] == 'nurse') {
      return 'nurses';
    }
    if (a['isTechnicianRequest'] == true || a['roleTarget'] == 'technician') {
      return 'technicians';
    }
    final type = (a['consultationType'] ?? '').toString().toLowerCase();
    if (type.contains('home')) return 'doctors';
    return null;
  }

  static DateTime? _dateFromKey(String raw) {
    final parts = normalizeDateKey(raw).split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static DateTime? _atTime(DateTime day, String text) {
    // Pick the time out of text like ' 06:00 PM Daily'
    final m = RegExp(r'\d{1,2}(?:[:.]\d{2})?\s*(?:[AaPp]\.?[Mm]\.?)?').firstMatch(text);
    if (m == null) return null;
    final minutes = timeSlotMinutes(normalizeTimeSlot(m.group(0)!) ?? '');
    if (minutes >= 24 * 60) return null;
    return DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
  }

  /// The booked time the provider may not start before, or null when the
  /// booking may start at once (ASAP / no time). Same-day "urgent" nurse and
  /// therapy bookings have a chosen time, so they count as booked too.
  /// Multi-day bookings use today's start time.
  static DateTime? bookedStart(Map<String, dynamic> a, {DateTime? now}) {
    now ??= DateTime.now();
    final time = (a['time'] ?? '').toString();
    if (time.toUpperCase().contains('ASAP')) return null;
    var day = _dateFromKey((a['date'] ?? '').toString());
    if (day == null) return null;
    final days = toNum(a['durationDays'])?.toInt() ?? 1;
    if (days > 1) {
      final today = DateTime(now.year, now.month, now.day);
      final last = day.add(Duration(days: days - 1));
      if (!today.isBefore(day) && !today.isAfter(last)) day = today;
    }
    return _atTime(day, time.split('-').first);
  }

  /// Why the OTP cannot be used yet (null = the visit may start now).
  /// [what] names the visit in the message, e.g. 'nursing visit'.
  static String? earlyStartMessage(Map<String, dynamic> a,
      {DateTime? now, String what = 'booking'}) {
    now ??= DateTime.now();
    final start = bookedStart(a, now: now);
    if (start == null || !now.isBefore(start)) return null;
    final mins = start.difference(now).inMinutes + 1;
    final wait =
        mins >= 60 ? '${mins ~/ 60} hr ${mins % 60} mins' : '$mins mins';
    final h = start.hour % 12 == 0 ? 12 : start.hour % 12;
    final at = '${h.toString().padLeft(2, '0')}:'
        '${start.minute.toString().padLeft(2, '0')} '
        '${start.hour >= 12 ? 'PM' : 'AM'}';
    return 'This $what starts at $at on ${start.day}/${start.month}/${start.year}.\n\n'
        'Please wait $wait before verifying the OTP.';
  }

  static bool _isAsap(Map<String, dynamic> a) =>
      a['isUrgentEmergency'] == true ||
      (a['time'] ?? '').toString().toUpperCase().contains('ASAP');

  /// When the provider was expected to arrive: the booked slot start, or for
  /// urgent / ASAP bookings the moment the provider accepted.
  /// Multi-day bookings use today's slot start.
  static DateTime? expectedArrival(Map<String, dynamic> a, {DateTime? now}) {
    now ??= DateTime.now();
    if (_isAsap(a)) {
      return DateTime.tryParse(
          (a['respondedAt'] ?? a['createdAt'] ?? '').toString());
    }
    var day = _dateFromKey((a['date'] ?? '').toString());
    if (day == null) return null;
    final days = toNum(a['durationDays'])?.toInt() ?? 1;
    if (days > 1) {
      final today = DateTime(now.year, now.month, now.day);
      final last = day.add(Duration(days: days - 1));
      if (!today.isBefore(day) && !today.isAfter(last)) day = today;
    }
    final startText = (a['time'] ?? '').toString().split('-').first;
    return _atTime(day, startText);
  }

  /// When an in-progress session must be closed automatically: the end of
  /// the booked slot ("07:00 PM - 08:00 PM" → 8 PM; "07:00 PM" → 8 PM),
  /// the last day for multi-day bookings, or start + 1 hour for urgent ones.
  static DateTime? sessionEnd(Map<String, dynamic> a) {
    if (_isAsap(a)) {
      final started = DateTime.tryParse((a['startedAt'] ?? '').toString());
      return started?.add(defaultSessionLength);
    }
    final day = _dateFromKey((a['date'] ?? '').toString());
    if (day == null) return null;
    final days = toNum(a['durationDays'])?.toInt() ?? 1;
    final lastDay = day.add(Duration(days: days > 1 ? days - 1 : 0));
    final parts = (a['time'] ?? '').toString().split('-');
    final start = _atTime(lastDay, parts.first);
    if (start == null) return null;
    if (parts.length > 1) {
      final end = _atTime(lastDay, parts[1]);
      if (end != null && end.isAfter(start)) return end;
    }
    return start.add(defaultSessionLength);
  }

  /// Verifies the patient's OTP and starts the session.
  /// Returns null if the OTP is wrong, otherwise how many minutes late the
  /// provider started (0 when on time). Starting more than
  /// [lateArrivalGraceMinutes] late on a home visit reduces the provider's
  /// professional score by [latePenaltyPoints].
  static Future<int?> startSessionWithOtp({
    required String appointmentId,
    required String enteredOtp,
  }) async {
    final docRef = _db.collection('appointments').doc(appointmentId);
    final snap = await docRef.get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;

    // No login can start a booking before its booked time (multi-day
    // bookings: before today's start time), also a same-day "urgent" nurse
    // or therapy booking with a chosen time. Only ASAP bookings start at once.
    final now = DateTime.now();
    final early = earlyStartMessage(data, now: now);
    if (early != null) throw Exception(early);

    // Online payment: the visit starts only once the patient has paid
    if (data['paymentStatus'] == 'pending') {
      throw Exception(
          'The patient has not paid yet. Ask them to tap "Pay" in My Bookings, then enter the OTP.');
    }

    // A cancelled, declined or finished booking cannot be started again
    if (AppointmentRules.isFinished(data)) {
      throw Exception('This booking is already closed, so it cannot be started.');
    }

    // The OTP is only 4 digits: after 5 wrong tries entering it is locked for
    // 15 minutes, so it cannot be guessed.
    final lockedUntil =
        DateTime.tryParse((data['otpLockedUntil'] ?? '').toString());
    if (lockedUntil != null && now.isBefore(lockedUntil)) {
      final mins = lockedUntil.difference(now).inMinutes + 1;
      throw Exception(
          'Too many wrong OTP tries. Please try again in $mins min.');
    }

    final String actualOtp = data['otp']?.toString() ?? '';
    if (actualOtp.trim() != enteredOtp.trim()) {
      final tries = (toNum(data['otpAttempts'])?.toInt() ?? 0) + 1;
      try {
        await docRef.update(tries >= 5
            ? {
                'otpAttempts': 0,
                'otpLockedUntil':
                    now.add(const Duration(minutes: 15)).toIso8601String(),
              }
            : {'otpAttempts': tries});
      } catch (_) {}
      return null;
    }

    final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final period = now.hour >= 12 ? 'PM' : 'AM';
    final timeFormatted = '${hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} $period';

    final collection = _punctualityCollection(data);
    final expected = collection == null ? null : expectedArrival(data, now: now);
    final lateBy =
        expected == null ? 0 : now.difference(expected).inMinutes.clamp(0, 1 << 30);
    // Telling the patient "Running late" in time means no score down
    final isLate =
        lateBy > lateArrivalGraceMinutes && !_toldRunningLate(data, expected);
    final providerUid = (data['doctorUid'] ?? '').toString();

    await docRef.update({
      'status': 'In Progress',
      'startedAt': now.toIso8601String(),
      'startTimeFormatted': timeFormatted,
      if (collection != null) 'lateByMinutes': lateBy,
      if (isLate) 'lateArrival': true,
    });

    // One penalty per booking, even if the OTP is entered again.
    if (isLate && providerUid.isNotEmpty && data['latePenaltyApplied'] != true) {
      final providerRef = _db.collection(collection!).doc(providerUid);
      await _db.runTransaction((tx) async {
        final appt = await tx.get(docRef);
        if (appt.data()?['latePenaltyApplied'] == true) return;
        final provider = await tx.get(providerRef);
        final update = _penaltyUpdate(
            provider.data() ?? {}, latePenaltyPoints,
            absent: false);
        tx.set(providerRef, update, SetOptions(merge: true));
        tx.update(docRef, {'latePenaltyApplied': true});
      });
    }
    return isLate ? lateBy : 0;
  }

  /// Whether the provider used "Running late" before they counted as late.
  static bool _toldRunningLate(Map<String, dynamic> a, DateTime? expected) {
    final told = DateTime.tryParse((a['runningLateNotifiedAt'] ?? '').toString());
    if (told == null) return false;
    if (expected == null) return true;
    return !told.isAfter(
        expected.add(const Duration(minutes: lateArrivalGraceMinutes)));
  }

  /// Whether "Running late" can still be used on this booking: accepted,
  /// not started, a home visit, and not yet 30 mins past the booked start.
  static bool canTellRunningLate(Map<String, dynamic> a) {
    if (a['status'] != 'Confirmed') return false;
    if (_punctualityCollection(a) == null) return false;
    if (a['runningLateNotifiedAt'] != null) return false;
    final expected = expectedArrival(a);
    if (expected == null) return true;
    return DateTime.now().isBefore(
        expected.add(const Duration(minutes: lateArrivalGraceMinutes)));
  }

  /// Provider tells the patient they will be about [minutes] late.
  /// Returns false when it is too late to tell (already counted as late).
  static Future<bool> notifyRunningLate({
    required String appointmentId,
    required int minutes,
  }) async {
    final docRef = _db.collection('appointments').doc(appointmentId);
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(docRef);
      final data = snap.data();
      if (data == null || !canTellRunningLate(data)) return false;
      tx.update(docRef, {
        'runningLateMinutes': minutes,
        'runningLateNotifiedAt': DateTime.now().toIso8601String(),
      });
      return true;
    });
  }

  /// When an accepted (not started) booking counts as Absent: the end of the
  /// booked slot on its first day, pushed back by any "Running late" minutes.
  /// Urgent / ASAP bookings: one session length after acceptance.
  static DateTime? absentDeadline(Map<String, dynamic> a) {
    DateTime? end;
    if (_isAsap(a)) {
      end = DateTime.tryParse((a['respondedAt'] ?? a['createdAt'] ?? '').toString())
          ?.add(defaultSessionLength);
    } else {
      final day = _dateFromKey((a['date'] ?? '').toString());
      if (day == null) return null;
      final parts = (a['time'] ?? '').toString().split('-');
      final start = _atTime(day, parts.first);
      if (start == null) return null;
      end = start.add(defaultSessionLength);
      if (parts.length > 1) {
        final slotEnd = _atTime(day, parts[1]);
        if (slotEnd != null && slotEnd.isAfter(start)) end = slotEnd;
      }
    }
    final told = toNum(a['runningLateMinutes'])?.toInt() ?? 0;
    return end?.add(Duration(minutes: told));
  }

  /// Marks accepted bookings the provider never started by [absentDeadline]
  /// as 'Provider Absent' and applies the -15 absent penalty (and the
  /// 15-day block on the 3rd absent of the month). Returns how many.
  static Future<int> markAbsentBookings({
    String? providerUid,
    String? patientUid,
  }) async {
    if ((providerUid ?? '').isEmpty && (patientUid ?? '').isEmpty) return 0;
    try {
      Query<Map<String, dynamic>> q = _db
          .collection('appointments')
          .where('status', isEqualTo: 'Confirmed');
      q = (providerUid ?? '').isNotEmpty
          ? q.where('doctorUid', isEqualTo: providerUid)
          : q.where('patientUid', isEqualTo: patientUid);
      final snap = await q.get();
      final now = DateTime.now();
      var marked = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        // Not paid by the visit time: cancelled, not the provider's fault
        if (data['paymentStatus'] == 'pending') {
          final start = expectedArrival(data, now: now);
          if (start != null && !now.isBefore(start)) {
            await _db.runTransaction((tx) async {
              final fresh = (await tx.get(doc.reference)).data();
              if (fresh?['status'] != 'Confirmed' ||
                  fresh?['paymentStatus'] != 'pending') {
                return;
              }
              tx.update(doc.reference, {
                'status': 'Cancelled',
                'cancelReason': 'Not paid before the visit time',
                'cancelledAt': now.toIso8601String(),
              });
            });
          }
          continue;
        }
        final collection = _punctualityCollection(data);
        final uid = (data['doctorUid'] ?? '').toString();
        if (collection == null || uid.isEmpty) continue;
        final deadline = absentDeadline(data);
        if (deadline == null || now.isBefore(deadline)) continue;

        final providerRef = _db.collection(collection).doc(uid);
        await _db.runTransaction((tx) async {
          final fresh = await tx.get(doc.reference);
          if (fresh.data()?['status'] != 'Confirmed') return;
          final provider = await tx.get(providerRef);
          final update = _penaltyUpdate(
              provider.data() ?? {}, absentPenaltyPoints,
              absent: true);
          tx.set(providerRef, update, SetOptions(merge: true));
          tx.update(doc.reference, {
            'status': 'Provider Absent',
            'providerAbsent': true,
            'absentMarkedAt': now.toIso8601String(),
          });
        });
        marked++;
      }
      return marked;
    } catch (_) {
      return 0;
    }
  }

  /// Punctuality checks run from the provider dashboards (every minute) and
  /// the patient app: absent bookings first, then overdue sessions closed.
  static Future<({int absent, int closed})> runPunctualityChecks({
    String? providerUid,
    String? patientUid,
  }) async {
    final absent = await markAbsentBookings(
        providerUid: providerUid, patientUid: patientUid);
    final closed = await autoCloseOverdueSessions(
        providerUid: providerUid, patientUid: patientUid);
    // Physio requests whose agency accept time ran out open to all physios
    await PhysioAgencyService.escalateExpired();
    return (absent: absent, closed: closed);
  }

  /// Closes sessions that are still "In Progress" after their booked end
  /// time (the provider forgot to tap Complete). Runs from the provider
  /// dashboards and the patient app; pass the provider uid or patient uid.
  static Future<int> autoCloseOverdueSessions({
    String? providerUid,
    String? patientUid,
  }) async {
    if ((providerUid ?? '').isEmpty && (patientUid ?? '').isEmpty) return 0;
    try {
      Query<Map<String, dynamic>> q = _db
          .collection('appointments')
          .where('status', isEqualTo: 'In Progress');
      q = (providerUid ?? '').isNotEmpty
          ? q.where('doctorUid', isEqualTo: providerUid)
          : q.where('patientUid', isEqualTo: patientUid);
      final snap = await q.get();
      final now = DateTime.now();
      var closed = 0;
      for (final doc in snap.docs) {
        final end = sessionEnd(doc.data());
        if (end == null || now.isBefore(end)) continue;
        await _db.runTransaction((tx) async {
          final fresh = await tx.get(doc.reference);
          if (fresh.data()?['status'] != 'In Progress') return;
          final h = end.hour > 12 ? end.hour - 12 : (end.hour == 0 ? 12 : end.hour);
          tx.update(doc.reference, {
            'status': 'Completed',
            'completedAt': end.toIso8601String(),
            'endTimeFormatted':
                '${h.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')} ${end.hour >= 12 ? 'PM' : 'AM'}',
            'autoClosed': true,
          });
        });
        closed++;
      }
      return closed;
    } catch (_) {
      return 0;
    }
  }

  /// Doctor confirms the patient paid in cash (after or while ending).
  /// The patient paid (or was refunded) online through Razorpay.
  static bool isPaidOnline(Map<String, dynamic> a) => const {
        'paid',
        'refunded',
        'refund_pending',
        'partially_refunded',
      }.contains((a['paymentStatus'] ?? '').toString());

  /// Records that the doctor took the fee in cash. A booking already paid
  /// online is never relabelled as cash (returns false, nothing changes).
  static Future<bool> markCashCollected(String appointmentId,
      {num? amount}) async {
    final ref = _db.collection('appointments').doc(appointmentId);
    return _db.runTransaction<bool>((tx) async {
      final data = (await tx.get(ref)).data();
      if (data == null || isPaidOnline(data)) return false;
      tx.update(ref, {
        'cashCollected': true,
        'cashCollectedAt': DateTime.now().toIso8601String(),
        'cashAmount': amount ?? toNum(data['price']) ?? 0,
        'paymentStatus': 'cash_collected',
      });
      return true;
    });
  }

  /// Complete Consultation. [cashCollected]: the doctor took the fee in cash.
  static Future<void> completeConsultation(String appointmentId,
      {bool cashCollected = false}) async {
    final now = DateTime.now();
    final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final period = now.hour >= 12 ? 'PM' : 'AM';
    final timeFormatted = '${hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} $period';

    await _db.collection('appointments').doc(appointmentId).update({
      'status': 'Completed',
      'completedAt': now.toIso8601String(),
      'endTimeFormatted': timeFormatted,
    });
    if (cashCollected) await markCashCollected(appointmentId);
  }

  /// Submit Doctor Rating
  /// Overall rating from real patient ratings (average of all), 0 if none.
  static double ratingAverage(Map<String, dynamic> provider) {
    final total = toNum(provider['totalRatings'])?.toInt() ?? 0;
    final rating = toNum(provider['rating'])?.toDouble();
    if (total <= 0 || rating == null) return 0;
    return rating;
  }

  /// Overall rating text: "4.5/5 (12)" with the number of ratings,
  /// or "0/5" when nobody has rated the provider yet.
  static String ratingLabel(Map<String, dynamic> provider) {
    final total = toNum(provider['totalRatings'])?.toInt() ?? 0;
    final avg = ratingAverage(provider);
    if (total <= 0) return '0/5';
    return '${avg.toStringAsFixed(1)}/5 ($total)';
  }

  static Future<void> submitDoctorRating({
    required String appointmentId,
    required String doctorUid,
    required String patientUid,
    required String patientName,
    required double rating,
    required String review,
    // Role collection that holds the provider: 'doctors' or 'therapists'
    String providerCollection = 'doctors',
  }) async {
    final doctorRef = _db.collection(providerCollection).doc(doctorUid);

    await _db.runTransaction((transaction) async {
      final docSnap = await transaction.get(doctorRef);

      // Real patient ratings only: a provider starts with no ratings
      // (no assumed 4.9 x 5 starting average).
      double ratingSum = 0.0;
      int totalRatings = 0;

      if (docSnap.exists && docSnap.data() != null) {
        final data = docSnap.data()!;
        ratingSum = toNum(data['ratingSum'])?.toDouble() ?? 0.0;
        totalRatings = toNum(data['totalRatings'])?.toInt() ?? 0;
      }

      ratingSum += rating;
      totalRatings += 1;
      final newAvg =
          double.parse((ratingSum / totalRatings).toStringAsFixed(1));

      transaction.set(
        doctorRef,
        {
          'rating': newAvg,
          'ratingSum': ratingSum,
          'totalRatings': totalRatings,
        },
        SetOptions(merge: true),
      );
    });

    await _db.collection('appointments').doc(appointmentId).update({
      'hasBeenRated': true,
      'rating': rating,
      'review': review,
      'ratedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Send Text Chat Message
  static Future<void> sendChatMessage({
    required String chatId,
    required String senderUid,
    required String senderName,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;

    final docRef = _db.collection('chats').doc(chatId).collection('messages').doc();

    await docRef.set({
      'messageId': docRef.id,
      'senderUid': senderUid,
      'senderName': senderName,
      'type': 'text',
      'text': text.trim(),
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': DateTime.now().toIso8601String(),
    });

    await _db.collection('chats').doc(chatId).set({
      'lastMessage': text.trim(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Send Media Chat Message
  static Future<void> sendMediaChatMessage({
    required String chatId,
    required String senderUid,
    required String senderName,
    required String type,
    required String mediaUrl,
    String? fileName,
  }) async {
    final docRef = _db.collection('chats').doc(chatId).collection('messages').doc();

    await docRef.set({
      'messageId': docRef.id,
      'senderUid': senderUid,
      'senderName': senderName,
      'type': type,
      'mediaUrl': mediaUrl,
      'fileName': fileName ?? 'attachment',
      'text': '[Attachment: ${type.toUpperCase()}]',
      'createdAt': DateTime.now().toIso8601String(),
    });

    await _db.collection('chats').doc(chatId).set({
      'lastMessage': '[${type.toUpperCase()}]',
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Delete Chat Message
  static Future<void> deleteChatMessage({
    required String chatId,
    required String messageId,
  }) async {
    await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }

  /// Get Chat Messages Stream
  static Stream<List<Map<String, dynamic>>> getChatMessagesStream(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['messageId'] = doc.id;
        return data;
      }).toList();
    });
  }

  /// Get Patient Bookings Stream
  static Stream<List<Map<String, dynamic>>> getPatientBookingsStream(
      String patientUid) {
    return _db
        .collection('appointments')
        .where('patientUid', isEqualTo: patientUid)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  static final Map<String, List<String>> emergencySpecialtyMap = {
    'cardiac / chest pain': ['cardiologist', 'general physician'],
    'brain / stroke': ['neurologist', 'neurosurgeon', 'general physician'],
    'ortho / trauma': ['orthopedic', 'trauma specialist'],
    'chest / breathing': ['pulmonologist', 'general physician'],
    'pregnancy / obstetrics': ['gynecologist / obstetrician', 'gynecologist'],
    'something else': ['general physician'],
  };

  static bool isDoctorSpecialtyMatching(String doctorCategory, String emergencyCategory) {
    final cleanDocCat = doctorCategory.toLowerCase().trim();
    final cleanEmCat = emergencyCategory.toLowerCase().trim();

    if (cleanDocCat.isEmpty || cleanEmCat.isEmpty) return true;
    // Urgent specialty bookings carry the specialty itself (for example
    // Cardiologist), rather than an SOS symptom label. Match that exact
    // category before applying the unchanged SOS taxonomy below.
    if (cleanDocCat == cleanEmCat) return true;

    final allowedSpecialties = emergencySpecialtyMap[cleanEmCat] ??
        emergencySpecialtyMap.entries
            .firstWhere(
              (e) => cleanEmCat.contains(e.key) || e.key.contains(cleanEmCat),
              orElse: () => MapEntry('', ['general physician']),
            )
            .value;

    return allowedSpecialties.any((spec) =>
        cleanDocCat.contains(spec) || spec.contains(cleanDocCat));
  }

  /// Hospital preferences are saved under doctor specialties, whereas SOS
  /// requests use symptom categories. Resolve both through the same taxonomy
  /// used by SosService.doctorCandidates. That service still verifies each
  /// doctor's actual specialty, availability and distance before preference.
  static List<String> preferredDoctorsForEmergency(
      Map<String, List<String>>? preferences, String emergencyCategory) {
    final requested = emergencyCategory.trim().toLowerCase();
    if (requested.isEmpty || preferences == null) return const [];
    final found = <String>{};
    for (final entry in preferences.entries) {
      final specialty = entry.key.trim().toLowerCase();
      if (specialty.isEmpty) continue;
      if (specialty == requested ||
          isDoctorSpecialtyMatching(specialty, requested)) {
        found.addAll(entry.value.where((uid) => uid.trim().isNotEmpty));
      }
    }
    return found.toList();
  }

  /// Get Doctor Bookings Stream
  static Stream<List<Map<String, dynamic>>> getDoctorBookingsStream(
      String doctorUid, {
      String? doctorCategory,
      List<String>? doctorLocations,
      double? doctorLat,
      double? doctorLng,
      bool doctorOnline = true,
  }) {
    List<Map<String, dynamic>> compute(
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
      // One emergency at a time: hidden until the current one is completed.
      final bool emergencyBusy = docs
          .any((d) => _isActiveEmergencyOf(doctorUid, d.data()));
      // Requests raised while he was busy are not kept pending for him: once
      // he completes, only requests created after that completion reach him.
      DateTime? lastCompleted;
      for (final d in docs) {
        final a = d.data();
        if (a['doctorUid'] != doctorUid ||
            a['isUrgentEmergency'] != true ||
            a['status'] != 'Completed') {
          continue;
        }
        final t = _asDateTime(a['completedAt']);
        if (t != null && (lastCompleted == null || t.isAfter(lastCompleted))) {
          lastCompleted = t;
        }
      }
      final List<Map<String, dynamic>> result = [];
      for (var doc in docs) {
        final data = doc.data();
        data['appointmentId'] = doc.id;

        final isTech = data['isTechnicianRequest'] == true || data['roleTarget'] == 'technician';
        final isNurse = data['isNurseRequest'] == true || data['roleTarget'] == 'nurse';
        final isTherapist = data['isTherapistRequest'] == true || data['roleTarget'] == 'therapist';
        if (isTech || isNurse || isTherapist) continue;

        final status = data['status'] ?? '';
        final docUid = data['doctorUid'] ?? '';
        final isBroadcast = data['isBroadcast'] == true;
        final List<dynamic> declinedBy = data['declinedBy'] as List<dynamic>? ?? [];

        if (declinedBy.contains(doctorUid)) continue;
        if (status == 'Declined') continue;
        if (isUrgentRequestExpired(data)) continue;
        // Offline doctor: no new requests (urgent, emergency, home visit,
        // broadcast). Appointments already assigned to him stay visible.
        if (!doctorOnline &&
            (status == 'Pending Emergency' ||
                status == 'Pending Doctor Assignment' ||
                status == 'Pending Home Visit' ||
                status == 'Broadcasted')) {
          continue;
        }

        if (docUid == doctorUid) {
          // A still-pending emergency addressed to a doctor who is busy (or
          // that was raised before he completed his last one) is not kept
          // for him; it goes to other free doctors instead.
          final bool pendingEmergency = status == 'Pending Emergency' ||
              status == 'Pending Doctor Assignment';
          if (pendingEmergency) {
            if (emergencyBusy) continue;
            if (lastCompleted != null) {
              final created = _asDateTime(data['createdAt']);
              if (created == null || created.isBefore(lastCompleted)) continue;
            }
          }
          result.add(data);
          continue;
        }

        // Emergency Help (SOS): preferred doctors first, then the doctors whose
        // hospital is near the assigned hospital, 4 -> 6 -> 8 km.
        if (data['consultationType'] == SosService.type &&
            status == 'Pending Doctor Assignment') {
          if (emergencyBusy) continue;
          if (lastCompleted != null) {
            final created = _asDateTime(data['createdAt']);
            if (created == null || created.isBefore(lastCompleted)) continue;
          }
          final cands = (data['sosDoctorCandidatesKm'] as Map?)?.cast<String, dynamic>() ?? {};
          // Distance from the assigned hospital to the doctor's LIVE location;
          // the saved list is only the fallback when no live position is known.
          final hLat = toNum(data['assignedHospitalLat'])?.toDouble();
          final hLng = toNum(data['assignedHospitalLng'])?.toDouble();
          double? dist;
          if (doctorLat != null && doctorLng != null && hLat != null && hLng != null) {
            dist = SosService.distanceKm(hLat, hLng, doctorLat, doctorLng);
            // moved into range since the list was made: still the right specialty
            if (!cands.containsKey(doctorUid) &&
                doctorCategory != null &&
                doctorCategory.isNotEmpty) {
              final emCat = (data['emergencyCategory'] ?? data['doctorCategory'] ?? '').toString();
              if (!isDoctorSpecialtyMatching(doctorCategory, emCat)) continue;
            }
          } else {
            dist = toNum(cands[doctorUid])?.toDouble();
          }
          if (dist == null) continue;
          final phase = SosService.doctorPhase(data);
          if (phase.preferredOnly) {
            final pref = (data['preferredDoctorUids'] as List?) ?? const [];
            if (!pref.contains(doctorUid)) continue;
          } else if (dist > phase.radius) {
            continue;
          }
          result.add(data);
          continue;
        }

        final bool isEmergencyDoctorRequest =
            status == 'Pending Doctor Assignment' ||
            status == 'Pending Emergency' ||
            (isBroadcast && status == 'Broadcasted');

        if (isEmergencyDoctorRequest) {
          if (emergencyBusy) continue;
          if (lastCompleted != null) {
            final created = _asDateTime(data['createdAt']);
            if (created == null || created.isBefore(lastCompleted)) continue;
          }
          final String emCategory = (data['emergencyCategory'] ?? data['doctorCategory'] ?? '').toString();
          final List<dynamic> targetUids = data['targetDoctorUids'] as List<dynamic>? ?? [];
          // Free doctors (hospital distance in km, up to 8 km) worked out when
          // the patient requested. The search radius grows 4 -> 6 -> 8 km, one
          // step per minute the request stays unaccepted.
          final Map<String, dynamic> candidates =
              (data['candidateDistancesKm'] as Map?)?.cast<String, dynamic>() ?? {};
          final bool hasCandidates = candidates.isNotEmpty;
          if (hasCandidates) {
            final dist = toNum(candidates[doctorUid])?.toDouble();
            if (dist == null || dist > searchRadiusKm(data)) continue;
          }

          // Phase 2A: If Hospital set target preferred doctors and request is not yet broadcasted to all:
          if (targetUids.isNotEmpty && !isBroadcast) {
            if (!targetUids.contains(doctorUid)) {
              continue; // Skip doctors not in hospital's preferred list!
            }
          } else if (!hasCandidates && data['autoExpire'] == true) {
            continue; // Book Doctor urgent request: only 4 -> 6 -> 8 km candidates
          } else if (!hasCandidates) {
            // Phase 2B: Fallback / Broadcast to remaining doctors -> Check 4 km radius from patient live location!
            if (doctorLat != null && doctorLng != null) {
              final double pLat = toNum(data['patientLat'])?.toDouble() ?? LocationService.defaultLat;
              final double pLng = toNum(data['patientLng'])?.toDouble() ?? LocationService.defaultLng;

              final double distanceMeters = Geolocator.distanceBetween(pLat, pLng, doctorLat, doctorLng);
              final double distanceKm = distanceMeters / 1000.0;

              if (distanceKm > 4.0) {
                continue; // Skip doctors beyond 4 km radius!
              }
            }
          }

          if (doctorCategory != null && doctorCategory.isNotEmpty) {
            final bool matchesTaxonomy = isDoctorSpecialtyMatching(doctorCategory, emCategory);
            if (!matchesTaxonomy) continue;
          }

          result.add(data);
        }
      }
      return result;
    }

    // Only what this list can show is downloaded: the doctor's own bookings
    // (also used for "busy") and the requests still waiting for a doctor.
    // Re-evaluated every 15 s so a growing search radius reaches doctors
    // even when no appointment document changes.
    final appointments = _db.collection('appointments');
    return _withPeriodicRefresh([
      appointments.where('doctorUid', isEqualTo: doctorUid).snapshots(),
      appointments
          .where('status', whereIn: const [
            'Pending Doctor Assignment',
            'Pending Emergency',
            'Broadcasted',
          ])
          .snapshots(),
    ], compute);
  }

  /// Merges [sources] (each booking once) and recomputes on every change and
  /// every 15 s.
  static Stream<List<Map<String, dynamic>>> _withPeriodicRefresh(
    List<Stream<QuerySnapshot<Map<String, dynamic>>>> sources,
    List<Map<String, dynamic>> Function(
            List<QueryDocumentSnapshot<Map<String, dynamic>>>)
        compute,
  ) {
    late StreamController<List<Map<String, dynamic>>> controller;
    final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    Timer? timer;
    final last = List<QuerySnapshot<Map<String, dynamic>>?>.filled(
        sources.length, null);
    void emit() {
      if (controller.isClosed || last.any((l) => l == null)) return;
      final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
        for (final snap in last)
          for (final d in snap!.docs) d.id: d,
      };
      controller.add(compute(byId.values.toList()));
    }

    controller = StreamController<List<Map<String, dynamic>>>(
      onListen: () {
        for (var i = 0; i < sources.length; i++) {
          subs.add(sources[i].listen((snap) {
            last[i] = snap;
            emit();
          }, onError: controller.addError));
        }
        timer = Timer.periodic(const Duration(seconds: 15), (_) => emit());
      },
      onCancel: () async {
        timer?.cancel();
        for (final sub in subs) {
          await sub.cancel();
        }
      },
    );
    return controller.stream;
  }

  /// Get Technician Bookings Stream
  static Stream<List<Map<String, dynamic>>> getTechnicianBookingsStream(
      String technicianUid, List<String> preferredLocations) {
    // only technician bookings are downloaded (not every booking in the app)
    return _db
        .collection('appointments')
        .where('roleTarget', isEqualTo: 'technician')
        .snapshots()
        .map((snapshot) {
      final List<Map<String, dynamic>> result = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['appointmentId'] = doc.id;

        final isTech = data['isTechnicianRequest'] == true || data['roleTarget'] == 'technician';
        if (!isTech) continue;

        final status = data['status'] ?? '';
        final techUid = data['doctorUid'] ?? '';
        final isBroadcast = data['isBroadcast'] == true;
        final List<dynamic> declinedBy = data['declinedBy'] as List<dynamic>? ?? [];
        final String locationName = (data['locationName'] ?? '').toString().toLowerCase();

        // Kept (flagged) so the dashboard can tell it apart; never shown.
        if (declinedBy.contains(technicianUid)) {
          data['declinedByMe'] = true;
          result.add(data);
          continue;
        }
        if (status == 'Declined') continue;

        // Direct requests: the patient picked this provider, always show.
        if (techUid == technicianUid) {
          result.add(data);
          continue;
        }

        // Open broadcasts: only inside this provider's preferred areas.
        if (isBroadcast && status == 'Broadcasted') {
          if (preferredLocations.isNotEmpty &&
              !providerServesArea(preferredLocations, locationName)) {
            continue;
          }
          result.add(data);
        }
      }
      return result;
    });
  }

  /// Get Nurse Bookings Stream
  static Stream<List<Map<String, dynamic>>> getNurseBookingsStream(
      String nurseUid, List<String> preferredLocations) {
    // only nurse bookings are downloaded (not every booking in the app)
    return _db
        .collection('appointments')
        .where('roleTarget', isEqualTo: 'nurse')
        .snapshots()
        .map((snapshot) {
      final List<Map<String, dynamic>> result = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['appointmentId'] = doc.id;

        final isNurse = data['isNurseRequest'] == true || data['roleTarget'] == 'nurse';
        if (!isNurse) continue;

        final status = data['status'] ?? '';
        final targetUid = data['doctorUid'] ?? '';
        final isBroadcast = data['isBroadcast'] == true;
        final List<dynamic> declinedBy = data['declinedBy'] as List<dynamic>? ?? [];
        final String locationName = (data['locationName'] ?? '').toString().toLowerCase();

        // Kept (flagged) so the dashboard can tell it apart; never shown.
        if (declinedBy.contains(nurseUid)) {
          data['declinedByMe'] = true;
          result.add(data);
          continue;
        }
        if (status == 'Declined') continue;

        // Direct requests: the patient picked this provider, always show.
        if (targetUid == nurseUid) {
          result.add(data);
          continue;
        }

        // Open broadcasts: only inside this provider's preferred areas.
        if (isBroadcast && status == 'Broadcasted') {
          if (preferredLocations.isNotEmpty &&
              !providerServesArea(preferredLocations, locationName)) {
            continue;
          }
          result.add(data);
        }
      }
      return result;
    });
  }

  /// Get Therapist / Physio Bookings Stream.
  ///
  /// Requests a patient sent directly to this therapist are always included —
  /// the patient already chose them, so the area filter only applies to
  /// open broadcasts. Requests this therapist declined are included with
  /// `declinedByMe: true` so the dashboard can tell them apart; callers
  /// must not show them as actionable.
  static Stream<List<Map<String, dynamic>>> getTherapistBookingsStream(
      String therapistUid, List<String> preferredLocations,
      {Map<String, dynamic> physio = const {}}) {
    // only therapist bookings are downloaded (not every booking in the app)
    return _db
        .collection('appointments')
        .where('roleTarget', isEqualTo: 'therapist')
        .snapshots()
        .map((snapshot) {
      final List<Map<String, dynamic>> result = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['appointmentId'] = doc.id;

        final isTherapist = data['isTherapistRequest'] == true || data['roleTarget'] == 'therapist';
        if (!isTherapist) continue;

        final status = data['status'] ?? '';
        final targetUid = data['doctorUid'] ?? '';
        final isBroadcast = data['isBroadcast'] == true;
        final List<dynamic> declinedBy = data['declinedBy'] as List<dynamic>? ?? [];
        final String locationName = (data['locationName'] ?? '').toString().toLowerCase();

        if (declinedBy.contains(therapistUid)) {
          data['declinedByMe'] = true;
          result.add(data);
          continue;
        }

        if (targetUid == therapistUid) {
          result.add(data);
          continue;
        }

        if (isBroadcast && status == 'Broadcasted') {
          // Agency window: only that agency's on-duty physios, whatever
          // their own areas (the agency serves the area)
          if (PhysioAgencyService.isAgencyWindowOpen(data)) {
            // only the agency physios free in the booked time slot
            if (!PhysioAgencyService.isOfferedTo(data, physio,
                uid: therapistUid)) {
              continue;
            }
            data['fromMyAgency'] = true;
            result.add(data);
            continue;
          }
          if (preferredLocations.isNotEmpty &&
              !providerServesArea(preferredLocations, locationName)) {
            continue;
          }
          result.add(data);
        }
      }
      return result;
    });
  }

  /// Atomically claim a pending / broadcasted therapist request.
  /// Returns false if another provider already took it or it was cancelled.
  static Future<bool> acceptTherapistRequest({
    required String appointmentId,
    required String therapistUid,
    required String therapistName,
  }) =>
      acceptProviderRequest(
        appointmentId: appointmentId,
        providerUid: therapistUid,
        providerName: therapistName,
      );

  /// Patient side: send a waiting therapist request to all nearby therapists.
  /// Never undoes an acceptance that happened just before.
  static Future<void> broadcastTherapistRequest(String appointmentId) =>
      broadcastEmergencyToAllDoctors(appointmentId: appointmentId);

  /// Decline a therapist request (broadcast to others while still open).
  static Future<void> declineTherapistRequest({
    required String appointmentId,
    required String therapistUid,
  }) =>
      declineProviderRequest(
        appointmentId: appointmentId,
        providerUid: therapistUid,
      );

  /// `users/{uid}` is a small account record: role, email and name, plus the
  /// phone push tokens (`fcmTokens`, saved by PushService). Profiles live
  /// only in their role collection (doctors, nurses, patients, ...) and are
  /// not copied here.
  ///
  /// Used by: role lookup at login/startup, the admin account, and the
  /// incoming-call Cloud Function (reads fcmTokens).
  static Future<void> saveAccountRecord(
      Map<String, dynamic> profile, String uid) {
    return _db.collection('users').doc(uid).set({
      if (profile['role'] != null) 'role': profile['role'],
      if (profile['email'] != null) 'email': profile['email'],
      if (profile['name'] != null) 'name': profile['name'],
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Merge profile/status fields into a provider's role doc.
  static Future<void> updateProviderFields(
      String collection, String uid, Map<String, dynamic> data) async {
    await _db.collection(collection).doc(uid).set(data, SetOptions(merge: true));
  }

  /// Merge arbitrary profile/status fields into the therapist's docs.
  static Future<void> updateTherapistFields(
      String therapistUid, Map<String, dynamic> data) async {
    await _db
        .collection('therapists')
        .doc(therapistUid)
        .set(data, SetOptions(merge: true));
  }

  /// Whether a therapist's offered therapies cover the therapy a patient
  /// picked from the `therapies` catalogue. Catalogue names ("Neuro Therapy",
  /// "Speech Therapist") and profile chips ("Neuro physiotherapy") differ,
  /// so match on keywords. Generic physiotherapy matches every therapist.
  static bool therapistOffersTherapy(
      List<dynamic> offered, String? therapyName) {
    if (offered.isEmpty || therapyName == null) return true;
    final wanted = therapyName.toLowerCase();
    final offeredLower = offered.map((e) => e.toString().toLowerCase()).toList();

    if (offeredLower.any((o) => o == wanted)) return true;

    const keywordGroups = <List<String>>[
      ['neuro'],
      ['ortho'],
      ['pediatric', 'paediatric'],
      ['speech'],
      ['occupational'],
      ['respiratory', 'cardio'],
      ['psycho'],
      ['sport'],
      ['geriatric'],
      ['pelvic'],
      ['post-surgical', 'surgical'],
    ];
    for (final group in keywordGroups) {
      if (group.any(wanted.contains)) {
        return offeredLower.any((o) => group.any(o.contains));
      }
    }
    // "Physiotherapist", "Adult Physiotherapy" and other general requests.
    return true;
  }

  /// Get Doctor's Attended Patients Stream
  /// Notifications built from live bookings, newest first. Each item has
  /// 'id', 'title', 'body', 'at' (ISO time) and 'kind'.
  ///
  /// Provider: new requests, open offers nearby, patient ratings, sessions
  /// closed automatically, late starts and absents.
  /// Patient: accepted, provider running late, started, completed (rate),
  /// provider absent, declined.
  static List<Map<String, String>> bookingNotifications(
    List<Map<String, dynamic>> bookings, {
    required String uid,
    required bool forPatient,
    bool includeOffers = true,
  }) {
    final out = <Map<String, String>>[];
    void add(Map<String, dynamic> b, String kind, String title, String body,
        Object? at) {
      final when = (at ?? b['createdAt'] ?? '').toString();
      if (when.isEmpty) return;
      out.add({
        'id': '${b['appointmentId'] ?? ''}:$kind',
        'kind': kind,
        'title': title,
        'body': body,
        'at': when,
      });
    }

    for (final b in bookings) {
      final status = (b['status'] ?? '').toString();
      final patient = (b['patientName'] ?? 'Patient').toString();
      final provider = (b['doctorName'] ?? 'Your provider').toString();
      final area = (b['locationName'] ?? '').toString().split(',').first.trim();
      final slot = '${b['date'] ?? ''} @ ${b['time'] ?? ''}';

      if (forPatient) {
        if (b['patientUid'] != uid) continue;
        if (status == 'Confirmed') {
          add(b, 'accepted', '$provider accepted your booking', slot,
              b['respondedAt']);
        }
        if (status == 'Confirmed' && b['runningLateMinutes'] != null) {
          add(b, 'late', '$provider is running late',
              'About ${b['runningLateMinutes']} mins late for $slot',
              b['runningLateNotifiedAt']);
        }
        if (status == 'In Progress') {
          add(b, 'started', 'Your session with $provider has started', slot,
              b['startedAt']);
        }
        if (status == 'Completed') {
          add(
              b,
              'completed',
              b['autoClosed'] == true
                  ? 'Session with $provider closed at the booked end time'
                  : 'Session with $provider completed',
              b['hasBeenRated'] == true
                  ? 'Thank you for your rating'
                  : 'Tap My Bookings to rate $provider',
              b['completedAt']);
        }
        if (status == 'Provider Absent') {
          add(b, 'absent', '$provider did not arrive',
              'Booking for $slot was missed. Please book again.',
              b['absentMarkedAt']);
        }
        if (status == 'Declined') {
          add(b, 'declined', 'Your request was declined',
              'Please choose another provider.', b['respondedAt']);
        }
        continue;
      }

      // Provider
      final mine = b['doctorUid'] == uid;
      final declinedByMe =
          (b['declinedBy'] as List<dynamic>? ?? const []).contains(uid);
      if (declinedByMe) continue;
      if (includeOffers &&
          mine &&
          (status == 'Pending Home Visit' || status == 'Pending Emergency')) {
        add(b, 'request', 'New request from $patient', slot, b['createdAt']);
      }
      if (includeOffers && status == 'Broadcasted' && !mine) {
        add(b, 'offer', 'Open request${area.isEmpty ? '' : ' near $area'}',
            slot, b['broadcastedAt'] ?? b['updatedAt'] ?? b['createdAt']);
      }
      if (!mine) continue;
      // A patient booked a normal appointment with this doctor
      if (status == 'Confirmed' &&
          b['isUrgentEmergency'] != true &&
          b['consultationType'] != 'SOS Emergency Pipeline') {
        add(b, 'booked', 'New appointment booked by $patient', slot,
            b['createdAt']);
      }
      if (status == 'Completed' && b['hasBeenRated'] == true) {
        final stars = toNum(b['rating'])?.toInt();
        add(b, 'rated', '$patient rated you${stars == null ? '' : ' $stars★'}',
            (b['review'] ?? '').toString().isEmpty
                ? slot
                : '"${b['review']}"',
            b['ratedAt'] ?? b['completedAt']);
      }
      if (status == 'Completed' && b['autoClosed'] == true) {
        add(b, 'autoClosed', 'Session with $patient closed automatically',
            'The booked time ended before you tapped Complete.',
            b['completedAt']);
      }
      if (b['latePenaltyApplied'] == true) {
        add(b, 'lateStart', 'Late start: professional score -$latePenaltyPoints%',
            'Started ${b['lateByMinutes'] ?? ''} mins late with $patient',
            b['startedAt']);
      }
      if (status == 'Provider Absent') {
        add(b, 'absent',
            'Marked absent: professional score -$absentPenaltyPoints%',
            'Booking with $patient ($slot) was not started in time.',
            b['absentMarkedAt']);
      }
    }
    out.sort((a, b) => b['at']!.compareTo(a['at']!));
    return out;
  }

  /// Earnings from this provider's bookings completed in the last 30 days
  /// (price incl. urgent surcharge), from a live bookings list.
  static double earningsLast30Days(
      List<Map<String, dynamic>> bookings, String providerUid) {
    final since = DateTime.now().subtract(const Duration(days: 30));
    var total = 0.0;
    for (final b in bookings) {
      if (b['doctorUid'] != providerUid || b['status'] != 'Completed') continue;
      final done =
          DateTime.tryParse((b['completedAt'] ?? b['createdAt'] ?? '').toString());
      if (done == null || done.isBefore(since)) continue;
      // Paid online: the provider's 90% share (the app keeps 10%)
      total += ((b['providerShare'] ?? b['price']) as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  static Stream<List<Map<String, dynamic>>> getDoctorAttendedPatientsStream(
      String doctorUid) {
    return _db
        .collection('appointments')
        .where('doctorUid', isEqualTo: doctorUid)
        .snapshots()
        .map((snapshot) {
      // Only patients this provider actually treated (completed visits),
      // not requests they declined or that are still pending.
      final Map<String, Map<String, dynamic>> patientMap = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['status'] != 'Completed') continue;
        final pUid = (data['patientUid'] ?? '').toString();
        if (pUid.isEmpty) continue;
        final doneAt =
            (data['completedAt'] ?? data['createdAt'] ?? '').toString();

        final existing = patientMap[pUid];
        if (existing == null) {
          patientMap[pUid] = {
            'patientUid': pUid,
            'patientName': data['patientName'] ?? 'Patient',
            'patientPhone': data['patientPhone'] ?? '',
            'lastConsultation': data['date'] ?? '',
            'lastCompletedAt': doneAt,
            'visits': 1,
          };
        } else {
          existing['visits'] = (existing['visits'] as int) + 1;
          if (doneAt.compareTo(existing['lastCompletedAt'] as String) > 0) {
            existing['lastConsultation'] = data['date'] ?? '';
            existing['lastCompletedAt'] = doneAt;
          }
        }
      }
      final list = patientMap.values.toList()
        ..sort((a, b) => (b['lastCompletedAt'] as String)
            .compareTo(a['lastCompletedAt'] as String));
      return list;
    });
  }

  /// Whether chat is open between a patient and a provider: some booking
  /// between the two has started and is within the 24-hour chat window. Used
  /// when a chat is opened from a notification, which skips the booking
  /// screen's own check.
  static Future<bool> chatAllowedBetween(String uidA, String uidB) async {
    try {
      for (final pair in [(uidA, uidB), (uidB, uidA)]) {
        final snap = await _db
            .collection('appointments')
            .where('patientUid', isEqualTo: pair.$1)
            .where('doctorUid', isEqualTo: pair.$2)
            .get();
        // a finished consultation: the chat itself shows the time / recharge
        if (snap.docs.any(
            (d) => AppointmentRules.statusOf(d.data()) == 'Completed')) {
          return true;
        }
      }
    } catch (_) {
      // can't check (offline): don't block someone who was already chatting
      return true;
    }
    return false;
  }

  /// Get Patient's Consulted Doctors Stream
  static Stream<List<Map<String, dynamic>>> getPatientConsultedDoctorsStream(
      String patientUid) {
    return _db
        .collection('appointments')
        .where('patientUid', isEqualTo: patientUid)
        .snapshots()
        .map((snapshot) {
      // Only doctors the patient actually consulted (a finished
      // consultation); chat opens when it ends and is free for 24 h.
      final Map<String, Map<String, dynamic>> doctorMap = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (AppointmentRules.statusOf(data) != 'Completed') continue;
        final dUid = data['doctorUid'] ?? '';
        final dName = data['doctorName'] ?? 'Doctor';
        final dCat = data['doctorCategory'] ?? 'Specialist';
        final dHosp = data['hospital'] ?? '';

        if (dUid.isNotEmpty && doctorMap.containsKey(dUid)) {
          // chat stays open if any visit is active or ended less than 24 h ago
          if (AppointmentRules.chatOpen(data)) doctorMap[dUid]!['chatOpen'] = true;
        }
        if (dUid.isNotEmpty && !doctorMap.containsKey(dUid)) {
          doctorMap[dUid] = {
            'doctorUid': dUid,
            'doctorName': dName,
            'doctorCategory': dCat,
            'hospital': dHosp,
            'lastConsultation': data['date'] ?? '',
            'chatOpen': AppointmentRules.chatOpen(data),
          };
        }
      }
      return doctorMap.values.toList();
    });
  }

  /// Seed initial dummy doctors
  static Future<void> seedInitialDoctorsIfEmpty() async {
    try {
      final snapshot = await _db.collection('doctors').limit(1).get();

      if (snapshot.docs.isEmpty) {
        final sampleDoctors = [
          {
            'name': 'Dr. Elizabeth Amelia',
            'category': 'Cardiologist',
            'hospital': 'City Heart Care Hospital',
            'mobileNumber': '+1 234 567 890',
            'email': 'elizabeth@mydox.com',
            'role': 'doctor',
            'isOnline': true,
            'rating': 4.9,
            'ratingSum': 24.5,
            'totalRatings': 5,
            'experience': '8 years',
            'latitude': LocationService.defaultLat,
            'longitude': LocationService.defaultLng,
          },
          {
            'name': 'Dr. David Jones',
            'category': 'Neurologist',
            'hospital': 'Neuro Specialist Clinic',
            'mobileNumber': '+1 345 678 901',
            'email': 'david@mydox.com',
            'role': 'doctor',
            'isOnline': true,
            'rating': 4.8,
            'ratingSum': 24.0,
            'totalRatings': 5,
            'experience': '10 years',
            'latitude': 18.5256,
            'longitude': 73.8640,
          },
        ];

        for (final docData in sampleDoctors) {
          final docRef = _db.collection('doctors').doc();
          final data = {
            ...docData,
            'uid': docRef.id,
            'createdAt': DateTime.now().toIso8601String(),
          };
          await docRef.set(data);
        }
      }
    } catch (e) {
      // Ignore if offline
    }
  }
}
