import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' as auth;

import '../../domain/models/app_user.dart';
import '../../domain/models/daily_photo.dart';
import '../../domain/models/public_user.dart';

abstract interface class AppRepository {
  Stream<auth.User?> get authStateChanges;
  auth.User? get currentAuthUser;
  Future<void> signInWithGoogle();
  Future<void> signInWithEmail({
    required String email,
    required String password,
  });
  Future<void> registerWithEmail({
    required String email,
    required String password,
  });
  Future<void> sendPasswordResetEmail(String email);
  bool get currentUserUsesPassword;
  Future<void> signOut();
  Future<void> ensureCurrentUser();
  Stream<AppUser?> watchCurrentUser();
  Stream<List<DailyPhoto>> watchMyPhotos();
  Stream<List<DailyPhoto>> watchFeed();
  Stream<List<PublicUser>> watchPublicUsers();
  Future<Set<String>> getFollowingIds();
  Future<List<DailyPhoto>> loadFriendsFeed();
  Future<void> savePhoto(File alignedPhoto, DateTime capturedAt);
  Future<void> deletePhoto(DailyPhoto photo);
  Future<void> deleteAllPhotos();
  Future<void> updateVisibility(bool isPublic);
  Future<void> toggleLike(String photoId);
  Future<void> toggleFollow(String userId);
  Future<void> deleteAccount({String? password});
}
