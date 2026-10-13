import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;

import '../../config/app_constants.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/daily_photo.dart';
import '../../domain/models/public_user.dart';
import '../services/auth_service.dart';
import '../services/firebase_data_service.dart';
import 'app_repository.dart';

class FirebaseAppRepository implements AppRepository {
  FirebaseAppRepository(this._authService, this._dataService);

  final AuthService _authService;
  final FirebaseDataService _dataService;

  @override
  Stream<auth.User?> get authStateChanges => _authService.authStateChanges;

  @override
  auth.User? get currentAuthUser => _authService.currentUser;

  @override
  Future<void> signInWithGoogle() async {
    await _authService.signInWithGoogle();
  }

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _authService.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  @override
  Future<void> registerWithEmail({
    required String email,
    required String password,
  }) async {
    await _authService.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  @override
  Future<void> sendPasswordResetEmail(String email) =>
      _authService.sendPasswordResetEmail(email);

  @override
  bool get currentUserUsesPassword => _authService.currentUserUsesPassword;

  @override
  Future<void> signOut() => _authService.signOut();

  @override
  Future<void> ensureCurrentUser() async {
    final user = currentAuthUser;
    if (user == null) return;
    await _dataService.createUserIfMissing(
      userId: user.uid,
      name: user.displayName ?? user.email?.split('@').first ?? 'FaceMorph',
      email: user.email ?? '',
      photoUrl: user.photoURL,
    );
  }

  @override
  Stream<AppUser?> watchCurrentUser() {
    final user = currentAuthUser;
    if (user == null) return Stream.value(null);
    return _dataService.watchUser(user.uid).map((snapshot) {
      final data = snapshot.data();
      if (data == null) return null;
      return AppUser(
        id: snapshot.id,
        displayName: data['displayName'] as String? ?? '',
        email: data['email'] as String? ?? '',
        photoUrl: data['photoUrl'] as String?,
        isPublic: data['isPublic'] as bool? ?? AppConstants.defaultPublicPhotos,
        trialStartedAt: _date(data['trialStartedAt']) ?? DateTime.now(),
        premiumUntil: _date(data['premiumUntil']),
      );
    });
  }

  @override
  Stream<List<DailyPhoto>> watchMyPhotos() {
    final user = currentAuthUser;
    if (user == null) return Stream.value(const []);
    return _dataService
        .watchUserPhotos(user.uid)
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => _photo(doc, user.uid)).toList(),
        );
  }

  @override
  Stream<List<DailyPhoto>> watchFeed() {
    final currentUserId = currentAuthUser?.uid;
    return _dataService.watchPublicFeed().map(
      (snapshot) =>
          snapshot.docs.map((doc) => _photo(doc, currentUserId)).toList(),
    );
  }

  @override
  Stream<List<PublicUser>> watchPublicUsers() =>
      _dataService.watchPublicUsers().map(
        (snapshot) => snapshot.docs
            .map(
              (doc) => PublicUser(
                id: doc.id,
                displayName: doc.data()['displayName'] as String? ?? '',
                photoUrl: doc.data()['photoUrl'] as String?,
                isFollowing: false,
              ),
            )
            .toList(),
      );

  @override
  Future<Set<String>> getFollowingIds() async {
    final user = currentAuthUser;
    if (user == null) return const {};
    final snapshot = await _dataService.getFollowing(user.uid);
    return snapshot.docs.map((doc) => doc.id).toSet();
  }

  @override
  Future<List<DailyPhoto>> loadFriendsFeed() async {
    final user = currentAuthUser;
    if (user == null) return const [];
    final followingIds = await getFollowingIds();
    if (followingIds.isEmpty) return const [];

    final photos = <DailyPhoto>[];
    for (final ownerId in followingIds) {
      final snapshot = await _dataService.getPublicPhotosByOwner(ownerId);
      photos.addAll(snapshot.docs.map((doc) => _photo(doc, user.uid)));
    }
    photos.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return photos.take(60).toList();
  }

  @override
  Future<void> savePhoto(File alignedPhoto, DateTime capturedAt) async {
    final authUser = currentAuthUser;
    if (authUser == null) throw StateError('Authentication required');
    final userSnapshot = await _dataService.watchUser(authUser.uid).first;
    final data = userSnapshot.data();
    if (data == null) throw StateError('User profile missing');
    final upload = await _dataService.uploadPhoto(
      file: alignedPhoto,
      capturedAt: capturedAt,
    );
    await _dataService.savePhotoDocument(
      userId: authUser.uid,
      ownerName: data['displayName'] as String? ?? '',
      ownerAvatarUrl: data['photoUrl'] as String?,
      imageUrl: upload['url']! as String,
      storagePath: upload['storagePath']! as String,
      capturedAt: capturedAt,
      isPublic: data['isPublic'] as bool? ?? AppConstants.defaultPublicPhotos,
    );
  }

  @override
  Future<void> deletePhoto(DailyPhoto photo) async {
    final user = currentAuthUser;
    if (user == null || photo.ownerId != user.uid) {
      throw StateError('Only your own photos can be deleted.');
    }
    await _dataService.deletePhoto(photoId: photo.id);
  }

  @override
  Future<void> deleteAllPhotos() async {
    if (currentAuthUser == null) return;
    await FirebaseFunctions.instanceFor(
      region: 'europe-west1',
    ).httpsCallable('deleteAllPhotos').call();
  }

  @override
  Future<void> updateVisibility(bool isPublic) async {
    final user = currentAuthUser;
    if (user == null) return;
    await _dataService.updateVisibility(user.uid, isPublic);
  }

  @override
  Future<void> toggleLike(String photoId) async {
    final user = currentAuthUser;
    if (user == null) return;
    await _dataService.toggleLike(photoId: photoId, userId: user.uid);
  }

  @override
  Future<void> toggleFollow(String userId) async {
    final user = currentAuthUser;
    if (user == null) return;
    await _dataService.toggleFollow(followerId: user.uid, followedId: userId);
  }

  @override
  Future<void> deleteAccount({String? password}) async {
    final user = currentAuthUser;
    if (user == null) return;
    await _authService.reauthenticate(password: password);
    await FirebaseFunctions.instanceFor(
      region: 'europe-west1',
    ).httpsCallable('deleteAccount').call();
    await _authService.signOut();
  }

  static DateTime? _date(Object? value) => switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    DateTime date => date,
    _ => null,
  };

  static DailyPhoto _photo(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
    String? currentUserId,
  ) {
    final data = snapshot.data();
    final likedBy = List<String>.from(data['likedBy'] as List? ?? const []);
    return DailyPhoto(
      id: snapshot.id,
      ownerId: data['ownerId'] as String? ?? '',
      ownerName: data['ownerName'] as String? ?? '',
      ownerAvatarUrl: data['ownerAvatarUrl'] as String?,
      imageUrl: data['imageUrl'] as String? ?? '',
      storagePath: data['storagePath'] as String?,
      capturedAt: _date(data['capturedAt']) ?? DateTime.now(),
      isPublic: data['isPublic'] as bool? ?? AppConstants.defaultPublicPhotos,
      likeCount: data['likeCount'] as int? ?? likedBy.length,
      isLiked: currentUserId != null && likedBy.contains(currentUserId),
      isOwned: currentUserId != null && data['ownerId'] == currentUserId,
    );
  }
}
