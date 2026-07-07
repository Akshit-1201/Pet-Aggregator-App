import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/pg_app_bar.dart';
import '../../core/widgets/pg_buttons.dart';
import '../../core/widgets/pg_field.dart';
import '../../core/widgets/pg_image_slot.dart';
import '../../core/widgets/pg_toggle.dart';
import '../../data/models/pet_profile.dart';

class CreatePetScreen extends StatefulWidget {
  const CreatePetScreen({super.key});
  @override
  State<CreatePetScreen> createState() => _CreatePetScreenState();
}

class _CreatePetScreenState extends State<CreatePetScreen> {
  Species _species = Species.dog;
  bool _vaccinated = true;

  static const _speciesLabel = {
    Species.dog: '🐶 Dog', Species.cat: '🐱 Cat', Species.other: '🐦 Other',
  };

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
                  const PgImageSlot(size: 110, circle: true, emoji: '📸'),
                  const SizedBox(height: 10),
                  Text('Upload a cute photo 📸', style: PgText.inter(13, FontWeight.w600, color: c.brand)),
                ])),
                const SizedBox(height: 14),
                const PgField(label: 'Pet name', value: 'Bruno'),
                const SizedBox(height: 14),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                  Expanded(child: PgField(label: 'Breed', value: 'Labrador')),
                  SizedBox(width: 12),
                  SizedBox(width: 104, child: PgField(label: 'Age', value: '2 yrs')),
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
                            color: _species == s ? c.brand : c.border,
                            width: _species == s ? 2 : 1),
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
                  decoration: BoxDecoration(
                    color: c.brandSoft, borderRadius: BorderRadius.circular(14)),
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
            decoration: BoxDecoration(
              color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: PgPrimaryButton(
              label: 'Finish & explore Pawgo', onPressed: () => context.go(Routes.home)),
          ),
        ]),
      ),
    );
  }
}
