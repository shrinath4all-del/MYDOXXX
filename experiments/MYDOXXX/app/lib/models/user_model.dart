import '../utils/safe_cast.dart';
import '../utils/ist_clock.dart';
class UserModel {
  final String uid;
  final String email;
  final String role; // 'patient', 'doctor', 'technician', 'nurse', 'therapist', 'hospital', 'ambulance', or 'admin'
  final String name;
  final String? profilePicUrl;
  final String? lastSeen;

  // Admin Verification & Document Fields
  final bool isVerified;
  final String? degreeCertUrl;
  final String? aadhaarUrl;
  final String? panUrl;
  final String? addressProofUrl;
  final String? registrationCertUrl;
  final String? internshipCertUrl; // Added for Therapists and others
  final String? bombayNursingCertUrl; // Hospital specific document
  final String? vehicleNumber; // Ambulance specific field

  // Shared Provider fields
  final String? category;
  final String? hospital;
  final String? organisation;
  final String? city;
  final String? mobileNumber;
  final String? experience;
  final String? qualification;
  final double? latitude;
  final double? longitude;
  /// Hospital location captured at registration: fixed, cannot be changed.
  final bool? locationLocked;
  final double? rating;
  final List<String>? preferredLocations;

  // Patient specific fields
  final String? phone;
  final String? age;
  final String? bloodGroup;
  final String? weight;
  final String? allergy;
  final String? homeAddress;
  final String? emergencyContact;
  final List<String>? preferredDoctorUids;
  final List<String>? preferredDoctorNames;
  final Map<String, String>? favoriteDoctors; // Category -> Doctor Uid
  final Map<String, String>? favoriteDoctorNames; // Category -> Doctor Name

  // Hospital specific fields
  final Map<String, List<String>>? hospitalPreferredDoctors; // Category -> List of 2 Doctor Uids
  final Map<String, List<String>>? hospitalPreferredDoctorNames; // Category -> List of 2 Doctor Names

  UserModel({
    required this.uid,
    required this.email,
    required this.role,
    required this.name,
    this.profilePicUrl,
    this.lastSeen,
    this.isVerified = false,
    this.degreeCertUrl,
    this.aadhaarUrl,
    this.panUrl,
    this.addressProofUrl,
    this.registrationCertUrl,
    this.internshipCertUrl,
    this.bombayNursingCertUrl,
    this.vehicleNumber,
    this.category,
    this.hospital,
    this.organisation,
    this.city,
    this.mobileNumber,
    this.experience,
    this.qualification,
    this.latitude,
    this.longitude,
    this.locationLocked,
    this.rating,
    this.preferredLocations,
    this.phone,
    this.age,
    this.bloodGroup,
    this.weight,
    this.allergy,
    this.homeAddress,
    this.emergencyContact,
    this.preferredDoctorUids,
    this.preferredDoctorNames,
    this.favoriteDoctors,
    this.favoriteDoctorNames,
    this.hospitalPreferredDoctors,
    this.hospitalPreferredDoctorNames,
  });

  bool get isDoctor => role == 'doctor';
  bool get isPatient => role == 'patient';
  bool get isTechnician => role == 'technician';
  bool get isNurse => role == 'nurse';
  bool get isTherapist => role == 'therapist';
  bool get isHospital => role == 'hospital';
  bool get isAmbulance => role == 'ambulance';
  bool get isAgency => role == 'agency';
  bool get isCarePhysician => role == 'care_physician';
  bool get isAdmin => role == 'admin';

  factory UserModel.fromMap(Map<String, dynamic> map, String docId) {
    return UserModel(
      uid: docId,
      email: map['email'] ?? '',
      role: map['role'] ?? 'patient',
      name: map['name'] ?? '',
      profilePicUrl: map['profilePicUrl'],
      lastSeen: map['lastSeen'],
      isVerified: map['isVerified'] == true || map['role'] == 'patient' || map['role'] == 'admin',
      degreeCertUrl: map['degreeCertUrl'],
      aadhaarUrl: map['aadhaarUrl'],
      panUrl: map['panUrl'],
      addressProofUrl: map['addressProofUrl'],
      registrationCertUrl: map['registrationCertUrl'],
      internshipCertUrl: map['internshipCertUrl'],
      bombayNursingCertUrl: map['bombayNursingCertUrl'],
      vehicleNumber: map['vehicleNumber'],
      category: map['category'],
      hospital: map['hospital'],
      organisation: map['organisation'],
      city: map['city'],
      mobileNumber: map['mobileNumber'] ?? map['phone'],
      experience: map['experience']?.toString(),
      qualification: map['qualification'],
      latitude: toNum(map['latitude'])?.toDouble(),
      longitude: toNum(map['longitude'])?.toDouble(),
      locationLocked: map['locationLocked'] == true,
      rating: toNum(map['rating'])?.toDouble(),
      preferredLocations: (map['preferredLocations'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      phone: map['phone'],
      age: map['age']?.toString(),
      bloodGroup: map['bloodGroup'],
      weight: map['weight']?.toString(),
      allergy: map['allergy'],
      homeAddress: map['homeAddress'],
      emergencyContact: map['emergencyContact'],
      preferredDoctorUids: (map['preferredDoctorUids'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      preferredDoctorNames: (map['preferredDoctorNames'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      favoriteDoctors: (map['favoriteDoctors'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v.toString())),
      favoriteDoctorNames: (map['favoriteDoctorNames'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v.toString())),
      hospitalPreferredDoctors: (map['hospitalPreferredDoctors'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as List<dynamic>).map((e) => e.toString()).toList())),
      hospitalPreferredDoctorNames: (map['hospitalPreferredDoctorNames'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as List<dynamic>).map((e) => e.toString()).toList())),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'role': role,
      'name': name,
      'isVerified': isVerified,
      if (profilePicUrl != null) 'profilePicUrl': profilePicUrl,
      if (lastSeen != null) 'lastSeen': lastSeen,
      if (degreeCertUrl != null) 'degreeCertUrl': degreeCertUrl,
      if (aadhaarUrl != null) 'aadhaarUrl': aadhaarUrl,
      if (panUrl != null) 'panUrl': panUrl,
      if (addressProofUrl != null) 'addressProofUrl': addressProofUrl,
      if (registrationCertUrl != null) 'registrationCertUrl': registrationCertUrl,
      if (internshipCertUrl != null) 'internshipCertUrl': internshipCertUrl,
      if (bombayNursingCertUrl != null) 'bombayNursingCertUrl': bombayNursingCertUrl,
      if (vehicleNumber != null) 'vehicleNumber': vehicleNumber,
      if (category != null) 'category': category,
      if (hospital != null) 'hospital': hospital,
      if (organisation != null) 'organisation': organisation,
      if (city != null) 'city': city,
      if (mobileNumber != null) 'mobileNumber': mobileNumber,
      if (experience != null) 'experience': experience,
      if (qualification != null) 'qualification': qualification,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationLocked == true) 'locationLocked': true,
      if (rating != null) 'rating': rating,
      if (preferredLocations != null)
        'preferredLocations': preferredLocations,
      if (phone != null) 'phone': phone,
      if (age != null) 'age': age,
      if (bloodGroup != null) 'bloodGroup': bloodGroup,
      if (weight != null) 'weight': weight,
      if (allergy != null) 'allergy': allergy,
      if (homeAddress != null) 'homeAddress': homeAddress,
      if (emergencyContact != null) 'emergencyContact': emergencyContact,
      if (preferredDoctorUids != null)
        'preferredDoctorUids': preferredDoctorUids,
      if (preferredDoctorNames != null)
        'preferredDoctorNames': preferredDoctorNames,
      if (favoriteDoctors != null) 'favoriteDoctors': favoriteDoctors,
      if (favoriteDoctorNames != null) 'favoriteDoctorNames': favoriteDoctorNames,
      if (hospitalPreferredDoctors != null) 'hospitalPreferredDoctors': hospitalPreferredDoctors,
      if (hospitalPreferredDoctorNames != null) 'hospitalPreferredDoctorNames': hospitalPreferredDoctorNames,
      'updatedAt': IstClock.now().toIso8601String(),
    };
  }
}
