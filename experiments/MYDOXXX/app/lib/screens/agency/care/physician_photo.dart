import '../../../services/app_database.dart';
import 'package:flutter/material.dart';

import '../../../widgets/circle_image.dart';

/// A care physician's profile photo (the first letter of the name when there
/// is none).
class PhysicianPhoto extends StatelessWidget {
  final String uid;
  final String name;
  final double radius;
  const PhysicianPhoto(
      {super.key, required this.uid, required this.name, this.radius = 24});

  static final Map<String, Future<String?>> _cache = {};

  Future<String?> _load() => _cache.putIfAbsent(uid, () async {
        if (uid.isEmpty) return null;
        final db = AppDatabase.instance;
        for (final col in const ['care_physicians', 'users']) {
          final d = (await db.collection(col).doc(uid).get()).data();
          final url = (d?['profilePicUrl'] ?? '').toString();
          if (url.isNotEmpty) return url;
        }
        return null;
      });

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: _load().catchError((_) => null),
        builder: (context, snap) => SafeAvatar(
          imageUrl: snap.data,
          radius: radius,
          backgroundColor: const Color(0xFFE0F2FE),
          fallback: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: radius * 0.8,
                  color: const Color(0xFF075985))),
        ),
      );
}
