import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_network_image.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_page_dots.dart';

/// The home's photos as a swipeable header.
///
/// A bare PageView reads as a single photo — nothing tells you to swipe — so
/// this shows a "1/4" counter and page dots, and opens a full-screen viewer on
/// tap. Falls back to the home-type emoji when a listing has no photos (older
/// listings; new ones must attach 3–5).
class HomeGallery extends StatefulWidget {
  final List<String> photoUrls;
  final String emoji;
  final double height;

  /// Distance from the bottom for the page dots. Callers that draw a card
  /// overlapping the bottom of the gallery (the host profile pulls its detail
  /// card up over it) must raise this so the dots stay visible.
  final double dotsBottomInset;

  const HomeGallery({
    super.key, required this.photoUrls, required this.emoji, this.height = 220,
    this.dotsBottomInset = 12,
  });

  @override
  State<HomeGallery> createState() => _HomeGalleryState();
}

class _HomeGalleryState extends State<HomeGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open(int initialPage) => Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PhotoViewerScreen(
            photoUrls: widget.photoUrls, initialPage: initialPage, emoji: widget.emoji),
      ));

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final urls = widget.photoUrls;
    if (urls.isEmpty) {
      return SizedBox(
        height: widget.height, width: double.infinity,
        child: PgImageSlot(radius: 0, emoji: widget.emoji),
      );
    }
    return SizedBox(
      height: widget.height, width: double.infinity,
      child: Stack(children: [
        PageView(
          controller: _controller,
          onPageChanged: (i) => setState(() => _page = i),
          children: [
            for (var i = 0; i < urls.length; i++)
              GestureDetector(
                key: Key('gallery-photo-$i'),
                onTap: () => _open(i),
                child: PgImageSlot(radius: 0, emoji: widget.emoji, imageUrl: urls[i]),
              ),
          ],
        ),
        if (urls.length > 1) ...[
          // The photo runs under the status bar, so the counter needs the same
          // SafeArea treatment the back button gets or it renders behind the clock.
          Positioned(
            top: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                  child: Text('${_page + 1}/${urls.length}',
                      style: PgText.inter(12, FontWeight.w700, color: Colors.white)),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: widget.dotsBottomInset, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                    color: c.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20)),
                child: PgPageDots(count: urls.length, index: _page),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Full-screen, pinch-to-zoom photo viewer.
class PhotoViewerScreen extends StatefulWidget {
  final List<String> photoUrls;
  final int initialPage;
  final String emoji;
  const PhotoViewerScreen({
    super.key, required this.photoUrls, this.initialPage = 0, this.emoji = '🏡',
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _controller;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    _controller = PageController(initialPage: widget.initialPage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.photoUrls;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              for (final url in urls)
                InteractiveViewer(
                  minScale: 1, maxScale: 4,
                  child: Center(
                    // contain, not cover: this is the full-screen viewer, where
                    // cropping the photo would defeat the point of opening it.
                    child: PgNetworkImage(url: url, fit: BoxFit.contain,
                        placeholder: (_) => Text(widget.emoji,
                            style: const TextStyle(fontSize: 56))),
                  ),
                ),
            ],
          ),
          Positioned(
            top: 8, left: 8,
            child: GestureDetector(
              key: const Key('close-photo-viewer'),
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40, height: 40, alignment: Alignment.center,
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 22),
              ),
            ),
          ),
          if (urls.length > 1)
            Positioned(
              top: 16, right: 16,
              child: Text('${_page + 1} / ${urls.length}',
                  style: PgText.inter(13, FontWeight.w700, color: Colors.white)),
            ),
        ]),
      ),
    );
  }
}
