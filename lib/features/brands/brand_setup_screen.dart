import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/pg_back_scope.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../data/models/brand.dart';
import '../../data/models/verification_request.dart';
import '../../data/repositories/providers.dart';
import '../verification/verification_card.dart';

class BrandSetupScreen extends ConsumerStatefulWidget {
  final bool fromOnboarding;
  const BrandSetupScreen({super.key, this.fromOnboarding = false});
  @override
  ConsumerState<BrandSetupScreen> createState() => _BrandSetupScreenState();
}

class _BrandSetupScreenState extends ConsumerState<BrandSetupScreen> {
  final _name = TextEditingController();
  final _since = TextEditingController();
  final _about = TextEditingController();
  BrandCategory _category = BrandCategory.treats;
  BrandDelivery _delivery = BrandDelivery.cityWide;
  String _logoUrl = '';
  final List<BrandProduct> _products = [];
  bool _verified = false;
  bool _seeded = false;
  bool _saving = false;
  bool _uploadingLogo = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _since.dispose();
    _about.dispose();
    super.dispose();
  }

  void _seed(Brand b) {
    _name.text = b.name;
    _since.text = b.sinceYear > 0 ? '${b.sinceYear}' : '';
    _about.text = b.about;
    _category = b.category;
    _delivery = b.delivery;
    _logoUrl = b.logoUrl;
    _products
      ..clear()
      ..addAll(b.products);
    _verified = b.verified;
  }

  Future<void> _pickLogo() async {
    if (_uploadingLogo) return;
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    try {
      final bytes = await ref.read(imagePickerServiceProvider).pickImage();
      if (!mounted || bytes == null) return;
      setState(() { _uploadingLogo = true; _error = null; });
      final url = await ref.read(storageRepositoryProvider).uploadImage(
          path: 'brands/$uid/logo_${DateTime.now().millisecondsSinceEpoch}.jpg', bytes: bytes);
      if (mounted) setState(() => _logoUrl = url);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't upload that photo. Please try again.");
    } finally {
      if (mounted && _uploadingLogo) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _editProduct([int? index]) async {
    final result = await showModalBottomSheet<BrandProduct>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.pg.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _ProductSheet(initial: index == null ? null : _products[index], emoji: _category.emoji),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _products.add(result);
      } else {
        _products[index] = result;
      }
    });
  }

  /// Null when [text] is a sensible founding year (or blank); else the error.
  static String? _sinceError(String text) {
    if (text.isEmpty) return null;
    final y = int.tryParse(text);
    if (y == null || y < 1950 || y > DateTime.now().year) return 'Enter the year you started, like 2021.';
    return null;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final since = _since.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter your brand name.');
      return;
    }
    final sinceError = _sinceError(since);
    if (sinceError != null) {
      setState(() => _error = sinceError);
      return;
    }
    if (_products.isEmpty) {
      setState(() => _error = 'Add at least one product.');
      return;
    }
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    setState(() { _saving = true; _error = null; });
    try {
      final profile = await ref.read(userRepositoryProvider).watchUser(uid).first;
      await ref.read(brandRepositoryProvider).upsertBrand(Brand(
            uid: uid, name: name, area: profile?.area ?? '', category: _category,
            about: _about.text.trim(), logoUrl: _logoUrl, delivery: _delivery,
            sinceYear: int.tryParse(since) ?? 0, products: List.of(_products), verified: _verified));
      if (mounted) _exit();
    } catch (_) {
      if (mounted) setState(() { _saving = false; _error = "Couldn't save your brand. Please try again."; });
    }
  }

  void _exit() => context.go(widget.fromOnboarding ? Routes.home : Routes.services);

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    ref.listen(currentBrandProvider, (prev, next) {
      if (!_seeded && next.hasValue && next.value != null) {
        setState(() => _seed(next.value!));
        _seeded = true;
      }
    });

    // Rebuilds on text edits so PgBackScope's confirm reflects the current
    // dirty state — see HostSetupScreen for why.
    return ListenableBuilder(
      listenable: Listenable.merge([_name, _since, _about]),
      builder: (context, _) => PgBackScope(
        confirmWhen: () =>
            _products.isNotEmpty ||
            _logoUrl.isNotEmpty ||
            _name.text.trim().isNotEmpty ||
            _about.text.trim().isNotEmpty,
        confirmMessage: "Your brand isn't saved yet. Leaving now discards it.",
        // Reached from onboarding via context.go, which leaves nothing to pop.
        upToIfEmpty: Routes.location,
        child: Scaffold(
          backgroundColor: c.surface,
          body: SafeArea(
            child: Column(children: [
              Builder(builder: (ctx) =>
                PgAppBar(title: 'List your brand', onBack: () => PgBackScope.pop(ctx))),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 30),
                  children: [
                    Text('Show pet parents what you make. They order by messaging you.',
                        style: PgText.inter(14, FontWeight.w400, color: c.muted, height: 1.5)),
                    const SizedBox(height: 16),
                    Row(children: [
                      GestureDetector(
                        key: const Key('brand-logo'),
                        onTap: _uploadingLogo ? null : _pickLogo,
                        child: SizedBox(width: 84, height: 84,
                          child: _uploadingLogo
                              ? Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: c.surface2,
                                    borderRadius: BorderRadius.circular(18), border: Border.all(color: c.border)),
                                  child: const SizedBox(width: 22, height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.5)))
                              : PgImageSlot(radius: 18, emoji: _category.emoji, imageUrl: _logoUrl)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Logo', style: PgText.label(context)),
                        const SizedBox(height: 3),
                        Text(_logoUrl.isEmpty ? 'Optional — tap to add' : 'Tap to change',
                          style: PgText.inter(12.5, FontWeight.w400, color: c.muted)),
                      ])),
                    ]),
                    const SizedBox(height: 16),
                    PgTextField(label: 'Brand name', controller: _name, hint: 'Bark & Bake'),
                    const SizedBox(height: 16),
                    Text('What you sell', style: PgText.label(context)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 9, runSpacing: 9, children: [
                      for (final cat in BrandCategory.values)
                        _SelectChip(label: '${cat.emoji} ${cat.label}', selected: _category == cat,
                            onTap: () => setState(() => _category = cat)),
                    ]),
                    const SizedBox(height: 16),
                    Text('Delivery', style: PgText.label(context)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 9, runSpacing: 9, children: [
                      for (final d in BrandDelivery.values)
                        _SelectChip(label: d.label, selected: _delivery == d,
                            onTap: () => setState(() => _delivery = d)),
                    ]),
                    const SizedBox(height: 16),
                    PgTextField(label: 'Started in (year, optional)', controller: _since,
                        keyboardType: TextInputType.number, hint: '2021'),
                    const SizedBox(height: 14),
                    PgTextField(label: 'About your brand', controller: _about,
                        hint: 'What makes your products special', maxLines: 3),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(child: Text('Products', style: PgText.label(context))),
                      Text('${_products.length}/${Brand.maxProducts}',
                        style: PgText.inter(12.5, FontWeight.w600,
                            color: _products.isEmpty ? c.heart : c.brand)),
                    ]),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _products.length; i++) _productRow(c, i),
                    if (_products.length < Brand.maxProducts)
                      GestureDetector(
                        key: const Key('add-product'),
                        onTap: () => _editProduct(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: c.surface2,
                            borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.add, color: c.brand, size: 20),
                            const SizedBox(width: 6),
                            Text('Add product', style: PgText.inter(13.5, FontWeight.w700, color: c.brand)),
                          ]),
                        ),
                      ),
                    const SizedBox(height: 18),
                    // Optional, as for pros and hosts: an unverified brand still
                    // lists, it just doesn't get the badge.
                    const VerificationCard(kind: VerificationKind.brand),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_error != null) ...[
                    Text(_error!, textAlign: TextAlign.center,
                        style: PgText.inter(13, FontWeight.w600, color: c.heart)),
                    const SizedBox(height: 10),
                  ],
                  PgPrimaryButton(label: _saving ? 'Saving…' : 'Save brand',
                    onPressed: _saving ? () {} : _save),
                  if (widget.fromOnboarding) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _saving ? null : () => context.go(Routes.home),
                      child: Text('Set up later',
                        style: PgText.inter(13.5, FontWeight.w600, color: c.muted))),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _productRow(PgColors c, int i) {
    final p = _products[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        PgImageSlot(size: 48, radius: 11, emoji: _category.emoji, imageUrl: p.photoUrl),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: PgText.inter(13.5, FontWeight.w600, color: c.text)),
          Text('₹${p.price}', style: PgText.poppins(13, FontWeight.w800, color: c.brand)),
        ])),
        IconButton(
          key: Key('edit-product-$i'), tooltip: 'Edit',
          onPressed: () => _editProduct(i),
          icon: Icon(Icons.edit_outlined, color: c.muted, size: 20)),
        IconButton(
          key: Key('remove-product-$i'), tooltip: 'Remove',
          onPressed: () => setState(() => _products.removeAt(i)),
          icon: Icon(Icons.close, color: c.muted, size: 20)),
      ]),
    );
  }
}

/// Add or edit one product. Pops the finished [BrandProduct], or nothing on
/// dismiss. The photo uploads as soon as it's picked, like listing photos.
class _ProductSheet extends ConsumerStatefulWidget {
  final BrandProduct? initial;
  final String emoji;
  const _ProductSheet({this.initial, required this.emoji});
  @override
  ConsumerState<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends ConsumerState<_ProductSheet> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _price = TextEditingController(
      text: widget.initial == null ? '' : '${widget.initial!.price}');
  late String _photoUrl = widget.initial?.photoUrl ?? '';
  bool _uploading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null || _uploading) return;
    try {
      final bytes = await ref.read(imagePickerServiceProvider).pickImage();
      if (!mounted || bytes == null) return;
      setState(() { _uploading = true; _error = null; });
      final url = await ref.read(storageRepositoryProvider).uploadImage(
          path: 'brands/$uid/p_${DateTime.now().millisecondsSinceEpoch}.jpg', bytes: bytes);
      if (mounted) setState(() => _photoUrl = url);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't upload that photo. Please try again.");
    } finally {
      if (mounted && _uploading) setState(() => _uploading = false);
    }
  }

  void _done() {
    final name = _name.text.trim();
    final price = int.tryParse(_price.text.trim()) ?? 0;
    if (name.isEmpty) {
      setState(() => _error = 'Enter a product name.');
      return;
    }
    if (price <= 0) {
      setState(() => _error = 'Enter a price greater than 0.');
      return;
    }
    Navigator.of(context).pop(BrandProduct(
      id: widget.initial?.id ?? 'p${DateTime.now().millisecondsSinceEpoch}',
      name: name, price: price, photoUrl: _photoUrl,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.initial == null ? 'Add a product' : 'Edit product',
              style: PgText.poppins(18, FontWeight.w800, color: c.text)),
            const SizedBox(height: 14),
            GestureDetector(
              key: const Key('product-photo'),
              onTap: _uploading ? null : _pickPhoto,
              child: SizedBox(height: 120, width: double.infinity,
                child: _uploading
                    ? Container(alignment: Alignment.center,
                        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(14)),
                        child: const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5)))
                    : Stack(fit: StackFit.expand, children: [
                        PgImageSlot(radius: 14, emoji: widget.emoji, imageUrl: _photoUrl),
                        if (_photoUrl.isEmpty)
                          Align(alignment: Alignment.bottomCenter, child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text('Tap to add a photo',
                              style: PgText.inter(12, FontWeight.w600, color: c.muted)))),
                      ])),
            ),
            const SizedBox(height: 14),
            PgTextField(label: 'Product name', controller: _name, hint: 'Peanut butter bones'),
            const SizedBox(height: 12),
            PgTextField(label: 'Price (₹)', controller: _price,
                keyboardType: TextInputType.number, hint: '249'),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: PgText.inter(13, FontWeight.w600, color: c.heart)),
            ],
            const SizedBox(height: 16),
            PgPrimaryButton(label: widget.initial == null ? 'Add product' : 'Save product', onPressed: _done),
          ]),
        ),
      ),
    );
  }
}

class _SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SelectChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? c.brandSoft : c.surface,
          border: Border.all(color: selected ? c.brand : c.border, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(13)),
        child: Text(label,
          style: PgText.inter(13, FontWeight.w600, color: selected ? c.brand : c.text)),
      ),
    );
  }
}
