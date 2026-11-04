import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../services/images_master.dart';

/// A picture from `images_master` by [imageKey]; the link is read from the
/// database. While it loads, or if the database has none (or it fails), the
/// [placeholder] shows (a light blue box with a picture icon when none is
/// given). [fallbackAsset] is optional and only for pictures that must work
/// with no network at all.
class MasterImage extends StatelessWidget {
  final String imageKey;
  final String? fallbackAsset;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;

  const MasterImage({
    super.key,
    required this.imageKey,
    this.fallbackAsset,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.placeholder,
  });

  Widget _empty() =>
      placeholder ??
      Container(
        width: width,
        height: height,
        color: AppColors.primarySoft,
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined, color: AppColors.primaryBorder),
      );

  Widget _fallback() => fallbackAsset == null ? _empty() : _asset(fallbackAsset!);

  Widget _asset(String path) => Image.asset(
        path,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) =>
            path == fallbackAsset ? _empty() : _fallback(),
      );

  /// Decoded at the size it is shown (not the file's full size), which is
  /// what keeps a screen of tiles quick and light on memory.
  Widget _web(String url) => LayoutBuilder(builder: (context, box) {
        final side = [
          width ?? double.infinity,
          height ?? double.infinity,
          box.maxWidth,
          box.maxHeight,
        ].where((v) => v.isFinite).fold<double>(0, (a, b) => a > b ? a : b);
        final px = side == 0
            ? null
            : (side * MediaQuery.devicePixelRatioOf(context)).round();
        return CachedNetworkImage(
          imageUrl: url,
          width: width,
          height: height,
          fit: fit,
          memCacheWidth: px,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (_, __) => _fallback(),
          errorWidget: (_, __, ___) => _fallback(),
        );
      });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, String>>(
      stream: ImagesMaster.paths(),
      initialData: ImagesMaster.latest,
      builder: (context, snap) {
        final path = snap.data?[ImagesMaster.normalize(imageKey)];
        if (path == null) return _fallback();
        if (ImagesMaster.isAsset(path)) return _asset(path);
        if (ImagesMaster.isWeb(path)) return _web(path);
        // Firebase Storage path: resolve its download link once
        return FutureBuilder<String?>(
          future: ImagesMaster.downloadUrl(path),
          builder: (context, url) =>
              url.data == null ? _fallback() : _web(url.data!),
        );
      },
    );
  }
}
