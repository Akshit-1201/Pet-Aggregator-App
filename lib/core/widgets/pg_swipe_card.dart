import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../../data/models/pet_profile.dart';
import 'pg_image_slot.dart';

class PgSwipeCard extends StatefulWidget {
  final PetProfile pet;
  final VoidCallback onWoof;
  final VoidCallback onPass;
  const PgSwipeCard(
      {super.key, required this.pet, required this.onWoof, required this.onPass});

  @override
  State<PgSwipeCard> createState() => _PgSwipeCardState();
}

class _PgSwipeCardState extends State<PgSwipeCard> with SingleTickerProviderStateMixin {
  static const _threshold = 110.0;
  late final AnimationController _controller;
  Animation<Offset>? _anim;
  Offset _drag = Offset.zero;
  VoidCallback? _pending;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 240))
      ..addListener(() {
        if (_anim != null) setState(() => _drag = _anim!.value);
      })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          final cb = _pending;
          _pending = null;
          if (cb != null) cb();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(Offset target, {VoidCallback? then}) {
    _anim = Tween(begin: _drag, end: target)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _pending = then;
    _controller.forward(from: 0);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_controller.isAnimating) return;
    setState(() => _drag += d.delta);
  }

  void _onPanEnd(DragEndDetails d) {
    final w = MediaQuery.of(context).size.width;
    if (_drag.dx > _threshold) {
      _animateTo(Offset(w * 1.5, _drag.dy), then: widget.onWoof);
    } else if (_drag.dx < -_threshold) {
      _animateTo(Offset(-w * 1.5, _drag.dy), then: widget.onPass);
    } else {
      _animateTo(Offset.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    final woofOpacity = (_drag.dx / _threshold).clamp(0.0, 1.0);
    final passOpacity = (-_drag.dx / _threshold).clamp(0.0, 1.0);
    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Transform.translate(
        offset: _drag,
        child: Transform.rotate(
          angle: _drag.dx / 1400,
          child: Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: c.border),
              boxShadow: c.shadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              Expanded(
                child: Stack(children: [
                  Positioned.fill(
                    child: PgImageSlot(radius: 0, emoji: '🐶', imageUrl: widget.pet.photoUrl)),
                  Positioned(
                    top: 22, left: 20,
                    child: Opacity(opacity: passOpacity, child: _stamp('PASS', const Color(0xFFF2547B))),
                  ),
                  Positioned(
                    top: 22, right: 20,
                    child: Opacity(opacity: woofOpacity, child: _stamp('WOOF!', c.brand)),
                  ),
                  Positioned(
                    left: 16, bottom: 16,
                    child: Row(children: [
                      if (widget.pet.vaccinated) _pill('✓ Vaccinated', c.brand),
                      const SizedBox(width: 8),
                      _pill('📍 ${widget.pet.area}', c.blue),
                    ]),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic, children: [
                    Text(widget.pet.name, style: PgText.poppins(24, FontWeight.w800, color: c.text, ls: -0.4)),
                    const SizedBox(width: 8),
                    Text(widget.pet.ageLabel, style: PgText.inter(16, FontWeight.w600, color: c.muted)),
                  ]),
                  const SizedBox(height: 5),
                  Text('${widget.pet.breed} · ${widget.pet.sex} · ${widget.pet.area}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: PgText.inter(14, FontWeight.w400, color: c.muted)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _stamp(String text, Color color) => Transform.rotate(
        angle: text == 'PASS' ? -0.24 : 0.24,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: color, width: 4),
            borderRadius: BorderRadius.circular(12)),
          child: Text(text, style: PgText.poppins(26, FontWeight.w800, color: color)),
        ),
      );

  Widget _pill(String text, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xE6FFFFFF), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: PgText.inter(12, FontWeight.w700, color: fg)),
      );
}
