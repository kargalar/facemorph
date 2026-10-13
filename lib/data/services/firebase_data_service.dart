import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../config/app_constants.dart';

class FirebaseDataService {
  FirebaseDataService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> userRef(String userId) =>
      _firestore.collection('users').doc(userId);

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchUser(String userId) =>
      userRef(userId).snapshots();

  Future<void> createUserIfMissing({
    required String userId,
    required String name,
    required String email,
    String? photoUrl,
  }) async {
    final reference = userRef(userId);
    if ((await reference.get()).exists) return;
    await reference.set({
      'displayName': name,
      'email': email,
      'photoUrl': photoUrl,
      'isPublic': AppConstants.defaultPublicPhotos,
      'trialStartedAt': FieldValue.serverTimestamp(),
      'premiumUntil': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchUserPhotos(String userId) =>
      _firestore
          .collection('photos')
          .where('ownerId', isEqualTo: userId)
          .orderBy('capturedAt', descending: true)
          .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPublicFeed() => _firestore
      .collection('photos')
      .where('isPublic', isEqualTo: true)
      .orderBy('capturedAt', descending: true)
      .limit(60)
      .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPublicUsers() => _firestore
      .collection('users')
      .where('isPublic', isEqualTo: true)
      .limit(60)
      .snapshots();

  CollectionReference<Map<String, dynamic>> followingRef(String userId) =>
      userRef(userId).collection('following');

  CollectionReference<Map<String, dynamic>> followersRef(String userId) =>
      userRef(userId).collection('followers');

  Future<QuerySnapshot<Map<String, dynamic>>> getFollowing(String userId) =>
      followingRef(userId).get();

  Future<QuerySnapshot<Map<String, dynamic>>> getPublicPhotosByOwner(
    String userId,
  ) => _firestore
      .collection('photos')
      .where('ownerId', isEqualTo: userId)
      .where('isPublic', isEqualTo: true)
      .limit(60)
      .get();

  Future<void> toggleFollow({
    required String followerId,
    required String followedId,
  }) async {
    if (followerId == followedId) return;
    final following = followingRef(followerId).doc(followedId);
    final follower = followersRef(followedId).doc(followerId);
    final existing = await following.get();
    final batch = _firestore.batch();
    if (existing.exists) {
      batch.delete(following);
      batch.delete(follower);
    } else {
      batch.set(following, {'createdAt': FieldValue.serverTimestamp()});
      batch.set(follower, {'createdAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
  }

  Future<Map<String, dynamic>> uploadPhoto({
    required File file,
    required DateTime capturedAt,
  }) async {
    final dayKey = DateFormat('yyyy-MM-dd').format(capturedAt);
    final request =
        http.StreamedRequest('POST', AppConstants.uploadPhotoEndpoint)
          ..headers['Content-Type'] = 'image/jpeg'
          ..headers['X-Photo-Day-Key'] = dayKey
          ..headers['X-Captured-At'] = capturedAt.toUtc().toIso8601String()
          ..headers['Content-Length'] = '${await file.length()}';
    final responseFuture = _sendAuthorized(request);
    try {
      await request.sink.addStream(file.openRead());
    } finally {
      await request.sink.close();
    }
    final response = await responseFuture;
    _throwForError(response);
    final data = jsonDecode(response.body);
    final url = data is Map<String, dynamic> ? data['url'] : null;
    final returnedPath = data is Map<String, dynamic>
        ? data['storagePath']
        : null;
    if (url is! String ||
        url.isEmpty ||
        returnedPath is! String ||
        returnedPath.isEmpty) {
      throw StateError('Invalid photo upload response.');
    }
    return {'url': url, 'storagePath': returnedPath};
  }

  Future<void> savePhotoDocument({
    required String userId,
    required String ownerName,
    required String? ownerAvatarUrl,
    required String imageUrl,
    required String storagePath,
    required DateTime capturedAt,
    required bool isPublic,
  }) async {
    final dayKey = DateFormat('yyyy-MM-dd').format(capturedAt);
    final photo = _firestore.collection('photos').doc('${userId}_$dayKey');
    final data = {
      'ownerId': userId,
      'ownerName': ownerName,
      'ownerAvatarUrl': ownerAvatarUrl,
      'imageUrl': imageUrl,
      'storagePath': storagePath,
      'capturedAt': Timestamp.fromDate(capturedAt),
      'dayKey': dayKey,
      'isPublic': isPublic,
      'likeCount': 0,
      'likedBy': <String>[],
    };
    if ((await photo.get()).exists) {
      // Keep likes intact when a same-day import/capture replaces the image.
      await photo.update({
        'ownerName': ownerName,
        'ownerAvatarUrl': ownerAvatarUrl,
        'imageUrl': imageUrl,
        'storagePath': storagePath,
        'capturedAt': Timestamp.fromDate(capturedAt),
        'dayKey': dayKey,
        'isPublic': isPublic,
      });
    } else {
      await photo.set(data);
    }
  }

  Future<void> updateVisibility(String userId, bool isPublic) async {
    await userRef(userId).update({'isPublic': isPublic});
    final photos = await _firestore
        .collection('photos')
        .where('ownerId', isEqualTo: userId)
        .get();
    for (var start = 0; start < photos.docs.length; start += 450) {
      final batch = _firestore.batch();
      final end = (start + 450).clamp(0, photos.docs.length);
      for (final photo in photos.docs.sublist(start, end)) {
        batch.update(photo.reference, {'isPublic': isPublic});
      }
      await batch.commit();
    }
  }

  Future<void> toggleLike({
    required String photoId,
    required String userId,
  }) async {
    final reference = _firestore.collection('photos').doc(photoId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final data = snapshot.data();
      if (data == null) return;
      final likedBy = List<String>.from(data['likedBy'] as List? ?? const []);
      final isLiked = likedBy.remove(userId);
      if (!isLiked) likedBy.add(userId);
      transaction.update(reference, {
        'likedBy': likedBy,
        'likeCount': likedBy.length,
      });
    });
  }

  Future<void> deletePhoto({required String photoId}) async {
    final request = http.Request('POST', AppConstants.deletePhotoEndpoint)
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'photoId': photoId});
    final response = await _sendAuthorized(request);
    _throwForError(response);
  }

  Future<http.Response> _sendAuthorized(http.BaseRequest request) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Authentication required');
    }
    request.headers['Authorization'] = 'Bearer $token';
    final client = http.Client();
    try {
      final response = await client
          .send(request)
          .timeout(AppConstants.transferRequestTimeout);
      return await http.Response.fromStream(
        response,
      ).timeout(AppConstants.transferRequestTimeout);
    } finally {
      client.close();
    }
  }

  static void _throwForError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    var message = 'Photo storage request failed: ${response.statusCode}';
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic> && data['error'] is String) {
        message = data['error'] as String;
      }
    } on FormatException {
      // Keep the status-based message.
    }
    throw StateError(message);
  }
}
