import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pet_aggregator_app/data/models/app_user.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/user_repository.dart';
import 'package:pet_aggregator_app/data/repositories/pet_repository.dart';
import 'package:pet_aggregator_app/data/repositories/swipe_repository.dart';

class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AppUser?>.broadcast();
  final Map<String, String> _passwords = {}; // email -> password
  AppUser? _current;

  /// If set, the next signUp/signIn throws this and clears it.
  AuthFailure? nextError;

  FakeAuthRepository({AppUser? initialUser}) : _current = initialUser;

  @override
  AppUser? get currentUser => _current;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  void _set(AppUser? u) {
    _current = u;
    _controller.add(u);
  }

  @override
  Future<AppUser> signUp({required String email, required String password}) async {
    if (nextError != null) {
      final e = nextError!;
      nextError = null;
      throw e;
    }
    if (_passwords.containsKey(email)) {
      throw const AuthFailure(AuthFailureType.emailInUse, 'That email is already registered.');
    }
    _passwords[email] = password;
    final u = AppUser(uid: 'uid_$email', email: email);
    _set(u);
    return u;
  }

  @override
  Future<AppUser> signIn({required String email, required String password}) async {
    if (nextError != null) {
      final e = nextError!;
      nextError = null;
      throw e;
    }
    if (_passwords[email] != password) {
      throw const AuthFailure(AuthFailureType.invalidCredentials, 'Incorrect email or password.');
    }
    final u = AppUser(uid: 'uid_$email', email: email);
    _set(u);
    return u;
  }

  @override
  Future<void> signOut() async => _set(null);
}

class InMemoryUserRepository implements UserRepository {
  final Map<String, UserProfile> _users = {};
  final Map<String, StreamController<UserProfile?>> _ctrls = {};

  StreamController<UserProfile?> _ctrl(String uid) =>
      _ctrls.putIfAbsent(uid, () => StreamController<UserProfile?>.broadcast());

  @override
  Future<void> createUser(UserProfile profile) async {
    _users[profile.uid] = profile;
    _ctrl(profile.uid).add(profile);
  }

  @override
  Future<void> updateArea(String uid, String area) async {
    final u = _users[uid];
    if (u != null) {
      _users[uid] = u.copyWith(area: area);
      _ctrl(uid).add(_users[uid]);
    }
  }

  @override
  Stream<UserProfile?> watchUser(String uid) async* {
    yield _users[uid];
    yield* _ctrl(uid).stream;
  }
}

class InMemoryPetRepository implements PetRepository {
  final List<PetProfile> _pets = [];
  final _controller = StreamController<List<PetProfile>>.broadcast();

  InMemoryPetRepository([List<PetProfile>? seed]) {
    if (seed != null) _pets.addAll(seed);
  }

  void _emit() => _controller.add(List.unmodifiable(_pets));

  List<PetProfile> _nearby(String exclude) =>
      _pets.where((p) => p.ownerId != exclude).toList();

  @override
  Stream<List<PetProfile>> watchNearbyPets({required String excludeOwnerId}) async* {
    yield _nearby(excludeOwnerId);
    yield* _controller.stream.map((_) => _nearby(excludeOwnerId));
  }

  @override
  Stream<List<PetProfile>> watchMyPets(String ownerId) async* {
    yield _pets.where((p) => p.ownerId == ownerId).toList();
    yield* _controller.stream.map((_) => _pets.where((p) => p.ownerId == ownerId).toList());
  }

  @override
  Future<void> addPet(PetProfile pet) async {
    _pets.add(pet);
    _emit();
  }
}

class InMemorySwipeRepository implements SwipeRepository {
  final List<Swipe> _swipes = [];
  final _controller = StreamController<List<Swipe>>.broadcast();

  InMemorySwipeRepository([List<Swipe>? seed]) {
    if (seed != null) _swipes.addAll(seed);
  }

  @override
  Future<void> recordSwipe(Swipe swipe) async {
    _swipes.removeWhere((s) => s.id == swipe.id);
    _swipes.add(swipe);
    _controller.add(List.of(_swipes));
  }

  @override
  Stream<Set<String>> watchSwipedPetIds(String uid) async* {
    Set<String> ids() => _swipes.where((s) => s.fromUid == uid).map((s) => s.petId).toSet();
    yield ids();
    yield* _controller.stream.map((_) => ids());
  }

  @override
  Future<bool> hasReciprocalWoof({required String otherUid, required String myUid}) async =>
      _swipes.any((s) =>
          s.fromUid == otherUid && s.ownerId == myUid && s.direction == SwipeDirection.woof);
}

List<PetProfile> fixturePets(String ownerId) => [
      PetProfile(id: 'p1', ownerId: ownerId, name: 'Bruno', breed: 'Labrador',
          ageLabel: '2 yrs', sex: 'male', area: 'Bandra West', species: Species.dog,
          vaccinated: true, accentColor: PetProfile.accentFor('Bruno')),
      PetProfile(id: 'p2', ownerId: ownerId, name: 'Mochi', breed: 'Persian cat',
          ageLabel: '1 yr', sex: 'female', area: 'Khar', species: Species.cat,
          vaccinated: true, accentColor: PetProfile.accentFor('Mochi')),
      PetProfile(id: 'p3', ownerId: ownerId, name: 'Simba', breed: 'Beagle',
          ageLabel: '3 yrs', sex: 'male', area: 'Bandra West', species: Species.dog,
          vaccinated: true, accentColor: const Color(0xFF6B8DE0)),
    ];
