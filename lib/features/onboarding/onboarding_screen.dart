import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_page_dots.dart';
import '../../core/widgets/pg_image_slot.dart';

class _Page {
  final String title, body;
  final List<Color> gradient;
  const _Page(this.title, this.body, this.gradient);
}

const _pages = [
  _Page('Find playmates just around the corner',
      'Discover pets and parents near you, send a friendly Woof 👋 and set up a playdate at the park.',
      [Color(0xFFFDF1D8), Color(0xFFFAE3B0)]),
  _Page('Trusted walkers, sitters & groomers',
      'Book verified pros near you, pay in-app and rate them after — all in a few taps.',
      [Color(0xFFE0F5EF), Color(0xFFBFEBDD)]),
  _Page('Homestays with verified hosts',
      'Going away? Find a loving, vetted home to board your pet — like Airbnb, built on trust and reviews.',
      [Color(0xFFEDE6FB), Color(0xFFD6C8F5)]),
  _Page('A community that has your back',
      'Ask questions, share advice, post lost & found — your neighbourhood pet circle, always on.',
      [Color(0xFFDCEBFB), Color(0xFFBBD8F7)]),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  void _toWelcome() => context.go(Routes.welcome);
  void _next() {
    if (_index == _pages.length - 1) {
      _toWelcome();
    } else {
      _controller.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Scaffold(
      backgroundColor: c.surface,
      body: PageView.builder(
        controller: _controller,
        itemCount: _pages.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) {
          final p = _pages[i];
          final isLast = i == _pages.length - 1;
          return Column(children: [
            SizedBox(
              height: 460,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: p.gradient),
                ),
                alignment: Alignment.center,
                child: Transform.rotate(
                  angle: (i.isEven ? -4 : 4) * 3.1416 / 180,
                  child: Container(
                    width: 236, height: 300, padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: c.shadow),
                    child: const PgImageSlot(radius: 20, emoji: '🐶'),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30, 34, 30, 30),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.title, style: PgText.poppins(27, FontWeight.w800, color: c.text, ls: -0.5)),
                  const SizedBox(height: 14),
                  Text(p.body, style: PgText.inter(14.5, FontWeight.w400, color: c.muted, height: 1.55)),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: PgPageDots(count: _pages.length, index: i),
                  ),
                  if (isLast)
                    PgPrimaryButton(label: 'Get started', onPressed: _toWelcome)
                  else
                    Row(children: [
                      GestureDetector(
                        onTap: _toWelcome,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                          child: Text('Skip', style: PgText.inter(14, FontWeight.w600, color: c.muted)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: PgPrimaryButton(label: 'Next', onPressed: _next)),
                    ]),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
