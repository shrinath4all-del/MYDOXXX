import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// What to do with the profile photo.
enum PhotoAction { change, remove }

/// Tapping the profile photo: with a photo, offer "Change" or "Remove"
/// (removing brings back the default icon); without one, go straight to
/// picking a photo. Returns null when dismissed.
Future<PhotoAction?> askPhotoAction(BuildContext context,
    {required bool hasPhoto}) async {
  if (!hasPhoto) return PhotoAction.change;
  return showModalBottomSheet<PhotoAction>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: const Text('Change photo'),
              onTap: () => Navigator.pop(ctx, PhotoAction.change),
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('Remove photo',
                  style: TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(ctx, PhotoAction.remove),
            ),
          ],
        ),
      ),
    ),
  );
}
