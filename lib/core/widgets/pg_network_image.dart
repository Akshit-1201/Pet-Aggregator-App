import 'package:flutter/material.dart';

/// Every network image in Pawgo goes through here.
///
/// The point is `cacheWidth`/`cacheHeight`. Uploads are capped at 1080px wide
/// (`ImagePickerServiceImpl`), and without a decode hint Flutter decodes all of
/// that into memory no matter how small the widget is — a 54px avatar row was
/// holding a full 1080×1080 bitmap, roughly 4.6 MB each, for every visible row.
/// Decoding to the size actually drawn cuts that by orders of magnitude and is
/// the difference between a smooth Discover deck and a janky one on a mid-range
/// phone.
///
/// The hint is in **physical pixels**, so it multiplies by the device pixel
/// ratio — passing logical pixels would decode a blurry image on a 3x screen.
class PgNetworkImage extends StatelessWidget {
  final String url;

  /// Logical size of the box this fills. When null, the parent's constraints
  /// are measured instead.
  final double? width, height;

  final BoxFit fit;
  final Widget Function(BuildContext) placeholder;

  const PgNetworkImage({
    super.key,
    required this.url,
    required this.placeholder,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);

    Widget build(double? logicalW, double? logicalH) {
      // Round up: decoding slightly larger than the box keeps it crisp, while
      // decoding smaller is visibly soft.
      int? px(double? logical) =>
          (logical == null || !logical.isFinite || logical <= 0)
              ? null
              : (logical * dpr).ceil();

      return Image.network(
        url,
        // The measured value is used for layout too, so a caller that passed
        // `double.infinity` (fill the parent) still gets a real decode hint
        // instead of silently falling back to full resolution.
        width: logicalW,
        height: logicalH,
        fit: fit,
        cacheWidth: px(logicalW),
        cacheHeight: px(logicalH),
        // gaplessPlayback stops the placeholder flashing when a URL changes
        // (swiping a gallery, or a pet row rebuilding).
        gaplessPlayback: true,
        loadingBuilder: (ctx, child, progress) =>
            progress == null ? child : placeholder(ctx),
        errorBuilder: (ctx, _, _) => placeholder(ctx),
      );
    }

    final fixed = (width?.isFinite ?? false) && (height?.isFinite ?? false);
    if (fixed) return build(width, height);

    // Null or infinite in at least one axis — measure what the parent actually
    // gives us rather than guessing, so a full-bleed hero still gets a hint.
    return LayoutBuilder(
      builder: (_, constraints) {
        double? resolve(double? given, bool bounded, double max) {
          if (given != null && given.isFinite) return given;
          return bounded ? max : null;
        }

        return build(
          resolve(width, constraints.hasBoundedWidth, constraints.maxWidth),
          resolve(height, constraints.hasBoundedHeight, constraints.maxHeight),
        );
      },
    );
  }
}
