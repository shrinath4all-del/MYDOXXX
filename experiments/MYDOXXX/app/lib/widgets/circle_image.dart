import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../utils/responsive.dart';
import 'master_image.dart';

/// A round frame: soft tinted ring with a white edge and a light shadow. The
/// picture inside fills the whole circle (cropped to it, never a square
/// showing inside a circle).
class CircleFrame extends StatelessWidget {
  final double size;
  final Widget child;

  const CircleFrame({super.key, required this.size, required this.child});

  @override
  Widget build(BuildContext context) {
    final size = Responsive.scale(context, this.size);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primarySoft,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(child: SizedBox.expand(child: child)),
    );
  }
}

/// A picture from `images_master` by [imageKey], shown to fill a circle of
/// [size]. [icon] shows (centred, on the tinted circle) until a picture is
/// available.
class CircleImage extends StatelessWidget {
  final String imageKey;
  final double size;
  final IconData icon;
  final Color iconColor;

  const CircleImage({
    super.key,
    required this.imageKey,
    this.size = 92,
    this.icon = Icons.medical_services_outlined,
    this.iconColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return CircleFrame(
      size: size,
      child: MasterImage(
        imageKey: imageKey,
        fit: BoxFit.cover,
        placeholder: Center(child: Icon(icon, color: iconColor, size: size * 0.45)),
      ),
    );
  }
}

/// A provider's own profile photo (from their profile) filling a round
/// frame. Until they add one, the role's picture from `images_master`
/// ([roleKey]) shows, then the [icon].
class ProviderAvatar extends StatelessWidget {
  final String? photoUrl;
  final String roleKey;
  final IconData icon;
  final double size;

  const ProviderAvatar({
    super.key,
    required this.photoUrl,
    required this.roleKey,
    this.icon = Icons.person_rounded,
    this.size = 68,
  });

  @override
  Widget build(BuildContext context) {
    final url = (photoUrl ?? '').trim();
    if (!url.startsWith('http')) {
      return CircleImage(imageKey: roleKey, size: size, icon: icon);
    }
    return CircleFrame(
      size: size,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => Center(
            child: Icon(icon, color: AppColors.primary, size: size * 0.45)),
        errorWidget: (_, __, ___) => CircleImage(
            imageKey: roleKey, size: size, icon: icon),
      ),
    );
  }
}

/// A round profile picture that never ends up blank: while the picture loads,
/// if its link is missing, or if it fails (404, no network), [fallback] (an
/// initial letter or an icon) shows instead.
class SafeAvatar extends StatelessWidget {
  final String? imageUrl;
  final double? radius;
  final Color? backgroundColor;
  final Widget fallback;

  const SafeAvatar({
    super.key,
    required this.imageUrl,
    required this.fallback,
    this.radius,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final url = (imageUrl ?? '').trim();
    final r = radius ?? 20;
    return CircleAvatar(
      radius: r,
      backgroundColor: backgroundColor,
      child: url.startsWith('http')
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: url,
                width: r * 2,
                height: r * 2,
                fit: BoxFit.cover,
                placeholder: (_, __) => Center(child: fallback),
                errorWidget: (_, __, ___) => Center(child: fallback),
              ),
            )
          : Center(child: fallback),
    );
  }
}
