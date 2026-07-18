import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pet_aggregator_app/data/models/app_user.dart';
import 'package:pet_aggregator_app/data/models/pet_profile.dart';
import 'package:pet_aggregator_app/data/models/user_profile.dart';
import 'package:pet_aggregator_app/data/models/booking.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/data/models/swipe.dart';
import 'package:pet_aggregator_app/data/repositories/auth_repository.dart';
import 'package:pet_aggregator_app/data/repositories/booking_repository.dart';
import 'package:pet_aggregator_app/data/repositories/user_repository.dart';
import 'package:pet_aggregator_app/data/repositories/pet_repository.dart';
import 'package:pet_aggregator_app/data/repositories/pro_repository.dart';
import 'package:pet_aggregator_app/data/repositories/swipe_repository.dart';
import 'package:pet_aggregator_app/data/models/homestay.dart';
import 'package:pet_aggregator_app/data/repositories/homestay_repository.dart';
import 'package:pet_aggregator_app/data/models/homestay_booking.dart';
import 'package:pet_aggregator_app/data/repositories/homestay_booking_repository.dart';
import 'package:pet_aggregator_app/data/models/post.dart';
import 'package:pet_aggregator_app/data/repositories/post_repository.dart';
import 'package:pet_aggregator_app/data/models/chat.dart';
import 'package:pet_aggregator_app/data/repositories/chat_repository.dart';
import 'package:pet_aggregator_app/data/repositories/preferences_repository.dart';
import 'package:pet_aggregator_app/data/models/review.dart';
import 'package:pet_aggregator_app/data/repositories/review_repository.dart';

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
  Future<void> markNotificationsSeen(String uid) async {
    final u = _users[uid];
    if (u != null) {
      _users[uid] = u.copyWith(notifsSeenAt: DateTime.now().millisecondsSinceEpoch);
      _ctrl(uid).add(_users[uid]);
    }
  }

  @override
  Future<void> setPhotoUrl(String uid, String url) async {
    final u = _users[uid];
    if (u != null) {
      _users[uid] = u.copyWith(photoUrl: url);
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
  Stream<int> watchMyWoofCount(String uid) async* {
    int count() => _swipes.where((s) => s.fromUid == uid && s.direction == SwipeDirection.woof).length;
    yield count();
    yield* _controller.stream.map((_) => count());
  }

  @override
  Future<bool> hasReciprocalWoof({required String otherUid, required String myUid}) async =>
      _swipes.any((s) =>
          s.fromUid == otherUid && s.ownerId == myUid && s.direction == SwipeDirection.woof);
}

class InMemoryProRepository implements ProRepository {
  final Map<String, Pro> _pros = {};
  final _controller = StreamController<List<Pro>>.broadcast();

  InMemoryProRepository([List<Pro>? seed]) {
    if (seed != null) {
      for (final p in seed) {
        _pros[p.uid] = p;
      }
    }
  }

  List<Pro> _list() => _pros.values.toList();

  @override
  Future<void> upsertPro(Pro pro) async {
    _pros[pro.uid] = pro;
    _controller.add(_list());
  }

  @override
  Stream<Pro?> watchPro(String uid) async* {
    yield _pros[uid];
    yield* _controller.stream.map((_) => _pros[uid]);
  }

  @override
  Stream<List<Pro>> watchPros() async* {
    yield _list();
    yield* _controller.stream.map((_) => _list());
  }
}

class InMemoryBookingRepository implements BookingRepository {
  final List<Booking> _bookings = [];
  final _controller = StreamController<List<Booking>>.broadcast();

  @override
  Future<void> createBooking(Booking booking) async {
    final stamped = booking.createdAt != 0 ? booking
        : Booking.fromMap(booking.id, {...booking.toMap(), 'createdAt': DateTime.now().millisecondsSinceEpoch});
    _bookings.add(stamped);
    _controller.add(List.of(_bookings));
  }

  @override
  Stream<List<Booking>> watchMyBookings(String parentId) async* {
    List<Booking> mine() => _bookings.where((b) => b.parentId == parentId).toList();
    yield mine();
    yield* _controller.stream.map((_) => mine());
  }
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

class InMemoryHomestayRepository implements HomestayRepository {
  final Map<String, Homestay> _homestays = {};
  final _controller = StreamController<List<Homestay>>.broadcast();

  InMemoryHomestayRepository([List<Homestay>? seed]) {
    if (seed != null) {
      for (final h in seed) {
        _homestays[h.uid] = h;
      }
    }
  }

  List<Homestay> _list() => _homestays.values.toList();

  @override
  Future<void> upsertHomestay(Homestay homestay) async {
    _homestays[homestay.uid] = homestay;
    _controller.add(_list());
  }

  @override
  Stream<Homestay?> watchHomestay(String uid) async* {
    yield _homestays[uid];
    yield* _controller.stream.map((_) => _homestays[uid]);
  }

  @override
  Stream<List<Homestay>> watchHomestays() async* {
    yield _list();
    yield* _controller.stream.map((_) => _list());
  }
}

class InMemoryHomestayBookingRepository implements HomestayBookingRepository {
  final List<HomestayBooking> _bookings = [];
  final _controller = StreamController<List<HomestayBooking>>.broadcast();

  @override
  Future<void> createHomestayBooking(HomestayBooking booking) async {
    final stamped = booking.createdAt != 0 ? booking
        : HomestayBooking.fromMap(booking.id, {...booking.toMap(), 'createdAt': DateTime.now().millisecondsSinceEpoch});
    _bookings.add(stamped);
    _controller.add(List.of(_bookings));
  }

  @override
  Stream<List<HomestayBooking>> watchMyHomestayBookings(String guestId) async* {
    List<HomestayBooking> mine() => _bookings.where((b) => b.guestId == guestId).toList();
    yield mine();
    yield* _controller.stream.map((_) => mine());
  }
}

class InMemoryPostRepository implements PostRepository {
  final List<Post> _posts = [];
  final Map<String, List<Comment>> _comments = {};
  final _postsCtrl = StreamController<List<Post>>.broadcast();
  final Map<String, StreamController<List<Comment>>> _commentCtrls = {};
  int _seq = 0;

  InMemoryPostRepository([List<Post>? seed]) {
    if (seed != null) _posts.addAll(seed);
  }

  StreamController<List<Comment>> _cctrl(String postId) =>
      _commentCtrls.putIfAbsent(postId, () => StreamController<List<Comment>>.broadcast());

  List<Post> _sortedPosts() => [..._posts]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<Post> createPost(Post post) async {
    final created = Post.fromMap('post_${_seq++}', post.toMap());
    _posts.add(created);
    _postsCtrl.add(_sortedPosts());
    return created;
  }

  @override
  Stream<List<Post>> watchPosts() async* {
    yield _sortedPosts();
    yield* _postsCtrl.stream;
  }

  @override
  Future<void> addComment(String postId, Comment comment) async {
    final list = _comments.putIfAbsent(postId, () => []);
    list.add(Comment.fromMap('c_${_seq++}', comment.toMap()));
    _cctrl(postId).add([...list]);
    final i = _posts.indexWhere((p) => p.id == postId);
    if (i >= 0) {
      _posts[i] = Post.fromMap(_posts[i].id, {..._posts[i].toMap(), 'replyCount': _posts[i].replyCount + 1});
      _postsCtrl.add(_sortedPosts());
    }
  }

  @override
  Stream<List<Comment>> watchComments(String postId) async* {
    List<Comment> sorted() =>
        [...(_comments[postId] ?? const <Comment>[])]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    yield sorted();
    yield* _cctrl(postId).stream.map((_) => sorted());
  }
}

class InMemoryPreferencesRepository implements PreferencesRepository {
  ThemeMode _mode;
  InMemoryPreferencesRepository([this._mode = ThemeMode.system]);

  @override
  ThemeMode get themeMode => _mode;

  @override
  Future<void> setThemeMode(ThemeMode mode) async => _mode = mode;
}

class InMemoryChatRepository implements ChatRepository {
  final Map<String, Chat> _chats = {};
  final Map<String, List<Message>> _messages = {};
  final _chatsCtrl = StreamController<List<Chat>>.broadcast();
  final Map<String, StreamController<List<Message>>> _msgCtrls = {};
  int _seq = 0;

  StreamController<List<Message>> _mctrl(String chatId) =>
      _msgCtrls.putIfAbsent(chatId, () => StreamController<List<Message>>.broadcast());

  @override
  Future<Chat> openChat({required String myUid, required String myName,
      required String otherUid, required String otherName}) async {
    final id = Chat.chatIdFor(myUid, otherUid);
    final existing = _chats[id];
    if (existing != null) return existing;
    final chat = Chat(id: id, participants: [myUid, otherUid]..sort(),
        names: {myUid: myName, otherUid: otherName},
        lastRead: <String, int>{},
        createdAt: DateTime.now().millisecondsSinceEpoch);
    _chats[id] = chat;
    _chatsCtrl.add(_chats.values.toList());
    return chat;
  }

  @override
  Stream<List<Chat>> watchMyChats(String uid) async* {
    List<Chat> mine() => _chats.values.where((c) => c.participants.contains(uid)).toList()
      ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    yield mine();
    yield* _chatsCtrl.stream.map((_) => mine());
  }

  @override
  Stream<List<Message>> watchMessages(String chatId) async* {
    List<Message> msgs() =>
        [...(_messages[chatId] ?? const <Message>[])]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    yield msgs();
    yield* _mctrl(chatId).stream.map((_) => msgs());
  }

  @override
  Future<void> sendMessage({required String chatId, required String senderId, required String text}) async {
    final masked = maskPhones(text);
    final now = DateTime.now().millisecondsSinceEpoch;
    final list = _messages.putIfAbsent(chatId, () => []);
    list.add(Message(id: 'm_${_seq++}', senderId: senderId, text: masked, createdAt: now));
    _mctrl(chatId).add([...list]);
    final c = _chats[chatId];
    if (c != null) {
      _chats[chatId] = Chat.fromMap(chatId,
          {...c.toMap(), 'lastMessage': masked, 'lastMessageAt': now, 'lastSenderId': senderId});
      _chatsCtrl.add(_chats.values.toList());
    }
  }

  @override
  Future<void> markRead({required String chatId, required String uid}) async {
    final c = _chats[chatId];
    if (c != null) {
      // Mutate the existing Chat's lastRead map in place (rather than
      // replacing the Chat entry) so any already-fetched `Chat` reference
      // (e.g. one held by a screen that navigated in via `extra`) observes
      // the read-cursor update immediately, without needing to re-fetch.
      c.lastRead[uid] = DateTime.now().millisecondsSinceEpoch;
      _chatsCtrl.add(_chats.values.toList());
    }
  }
}

class InMemoryReviewRepository implements ReviewRepository {
  final Map<String, Review> _reviews = {};                    // keyed by reviewId (== bookingId)
  final Map<String, ({double rating, int count})> _agg = {};  // keyed by targetId
  final _ctrl = StreamController<List<Review>>.broadcast();

  ({double rating, int count}) aggregateFor(String targetId) =>
      _agg[targetId] ?? (rating: 0.0, count: 0);

  @override
  Future<void> submitReview(Review review) async {
    if (_reviews.containsKey(review.bookingId)) return; // idempotent
    _reviews[review.bookingId] = Review.fromMap(review.bookingId, review.toMap());
    final cur = aggregateFor(review.targetId);
    final newCount = cur.count + 1;
    final newRating = (cur.rating * cur.count + review.stars) / newCount;
    _agg[review.targetId] = (rating: newRating, count: newCount);
    _ctrl.add(_reviews.values.toList());
  }

  @override
  Stream<List<Review>> watchReviews(String targetId) async* {
    List<Review> forTarget() => _reviews.values.where((r) => r.targetId == targetId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    yield forTarget();
    yield* _ctrl.stream.map((_) => forTarget());
  }

  @override
  Stream<Set<String>> watchMyReviewedBookingIds(String uid) async* {
    Set<String> mine() =>
        _reviews.values.where((r) => r.authorId == uid).map((r) => r.bookingId).toSet();
    yield mine();
    yield* _ctrl.stream.map((_) => mine());
  }
}
