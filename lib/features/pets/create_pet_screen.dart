import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_text_field.dart';
import '../../core/widgets/pg_toggle.dart';
import '../../data/models/pet_profile.dart';
import '../../data/repositories/providers.dart';

class CreatePetScreen extends ConsumerStatefulWidget {
  final bool fromOnboarding;
  const CreatePetScreen({super.key, this.fromOnboarding = false});
  @override
  ConsumerState<CreatePetScreen> createState() => _CreatePetScreenState();
}

class _CreatePetScreenState extends ConsumerState<CreatePetScreen> {
  final _name = TextEditingController();
  final _breed = TextEditingController();
  final _age = TextEditingController();
  Species _species = Species.dog;
  bool _vaccinated = true;
  bool _saving = false;
  Uint8List? _photoBytes;

  static const _speciesLabel = {
    Species.dog: '🐶 Dog', Species.cat: '🐱 Cat', Species.other: '🐦 Other',
  };

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final bytes = await ref.read(imagePickerServiceProvider).pickImage();
      if (!mounted || bytes == null) return;
      setState(() => _photoBytes = bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text("Couldn't open your photos. Please try again."),
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _finish() async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    final area = ref.read(currentUserProfileProvider).value?.area ?? '';
    final name = _name.text.trim();

    var photoUrl = '';
    final bytes = _photoBytes;
    if (bytes != null) {
      try {
        photoUrl = await ref.read(storageRepositoryProvider).uploadImage(
            path: 'pets/${uid}_${DateTime.now().millisecondsSinceEpoch}.jpg', bytes: bytes);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(
              content: Text("Couldn't upload the photo — saving without it."),
              behavior: SnackBarBehavior.floating));
        }
      }
    }

    if (!mounted) return;

    try {
      await ref.read(petRepositoryProvider).addPet(PetProfile(
            id: '', ownerId: uid, name: name, breed: _breed.text.trim(),
            ageLabel: _age.text.trim(), sex: '', area: area, species: _species,
            vaccinated: _vaccinated, accentColor: PetProfile.accentFor(name),
            photoUrl: photoUrl));
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text("Couldn't save your pet. Please try again."),
            behavior: SnackBarBehavior.floating));
      }
      return;
    }
    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pg;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(children: [
          PgAppBar(title: 'Add your pet', onBack: () => context.go(Routes.signup)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 30),
              children: [
                Center(child: Column(children: [
                  GestureDetector(
                    onTap: _pickPhoto,
                    child: _photoBytes == null
                        ? const PgImageSlot(size: 110, circle: true, emoji: '📸')
                        : ClipOval(child: Image.memory(_photoBytes!,
                            width: 110, height: 110, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const PgImageSlot(size: 110, circle: true, emoji: '📸'))),
                  ),
                  const SizedBox(height: 10),
                  Text(_photoBytes == null ? 'Upload a cute photo 📸' : 'Tap to change photo',
                    style: PgText.inter(13, FontWeight.w600, color: c.brand)),
                ])),
                const SizedBox(height: 14),
                PgTextField(label: 'Pet name', controller: _name, hint: 'Bruno'),
                const SizedBox(height: 14),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: PgTextField(label: 'Breed', controller: _breed, hint: 'Labrador')),
                  const SizedBox(width: 12),
                  SizedBox(width: 104, child: PgTextField(label: 'Age', controller: _age, hint: '2 yrs')),
                ]),
                const SizedBox(height: 14),
                Text('Species', style: PgText.label(context)),
                const SizedBox(height: 8),
                Row(children: [
                  for (final s in Species.values) ...[
                    Expanded(child: GestureDetector(
                      onTap: () => setState(() => _species = s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _species == s ? c.brandSoft : null,
                          border: Border.all(
                            color: _species == s ? c.brand : c.border, width: _species == s ? 2 : 1),
                          borderRadius: BorderRadius.circular(13)),
                        child: Text(_speciesLabel[s]!,
                          style: PgText.inter(13.5, FontWeight.w600,
                            color: _species == s ? c.brand : c.muted)),
                      ),
                    )),
                    if (s != Species.other) const SizedBox(width: 9),
                  ],
                ]),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Text('💉', style: TextStyle(fontSize: 17)),
                    const SizedBox(width: 10),
                    Text('Vaccinated', style: PgText.inter(14, FontWeight.w600, color: c.text)),
                    const Spacer(),
                    PgToggle(value: _vaccinated, onChanged: (v) => setState(() => _vaccinated = v)),
                  ]),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: PgPrimaryButton(
              label: _saving ? 'Saving…' : 'Finish & explore Pawgo',
              onPressed: _saving ? () {} : _finish),
          ),
        ]),
      ),
    );
  }
}
