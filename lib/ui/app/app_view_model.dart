import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_constants.dart';
import '../../data/repositories/app_repository.dart';
import '../../data/services/photo_cache_service.dart';
import '../../data/services/photo_transfer_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/purchase_service.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/capture_entitlement.dart';
import '../../domain/models/daily_photo.dart';
import '../../domain/models/public_user.dart';

class AppViewModel extends ChangeNotifier {
  AppViewModel(
    this._repository, [
    this._purchaseService,
    PhotoCacheService? photoCache,
    this._preferences,
    this._notificationService,
  ]) : _photoCache = photoCache ?? PhotoCacheService();

  final AppRepository _repository;
  final PurchaseService? _purchaseService;
  final PhotoCacheService _photoCache;
  final SharedPreferences? _preferences;
  final NotificationService? _notificationService;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  AppUser? _user;
  List<DailyPhoto> _photos = const [];
  List<DailyPhoto> _feed = const [];
  List<DailyPhoto> _friendsFeed = const [];
  List<PublicUser> _publicUsers = const [];
  Set<String> _followingIds = const {};
  bool _initializing = true;
  bool _busy = false;
  bool _purchaseBusy = false;
  bool _purchasesInitialized = false;
  ProductDetails? _premiumProduct;
  String? _error;
  var _photoCacheGeneration = 0;

  AppUser? get user => _user;
  List<DailyPhoto> get photos => List.unmodifiable(_photos);
  PhotoCacheService get photoCache => _photoCache;
  List<DailyPhoto> get feed => List.unmodifiable(_feed);
  List<DailyPhoto> get friendsFeed => List.unmodifiable(_friendsFeed);
  List<PublicUser> get publicUsers => List.unmodifiable(_publicUsers);
  bool isFollowing(String userId) => _followingIds.contains(userId);
  bool get initializing => _initializing;
  bool get busy => _busy;
  bool get purchaseBusy => _purchaseBusy;
  ProductDetails? get premiumProduct => _premiumProduct;
  String? get error => _error;
  bool get isAuthenticated => _repository.currentAuthUser != null;
  bool get isPremiumTestAccount =>
      _user?.email.trim().toLowerCase() == AppConstants.premiumTestAccountEmail;
  bool get premiumTestEnabled =>
      _preferences?.getBool(AppConstants.premiumTestOverrideKey) ?? false;
  CaptureEntitlement? get entitlement {
    final user = _user;
    if (user == null) return null;
    return CaptureEntitlement.evaluate(
      user: user,
      photos: _photos,
      premiumOverride: isPremiumTestAccount ? premiumTestEnabled : null,
    );
  }

  int get streak {
    if (_photos.isEmpty) return 0;
    final days = _photos
        .map(
          (photo) => DateTime(
            photo.capturedAt.year,
            photo.capturedAt.month,
            photo.capturedAt.day,
          ),
        )
        .toSet();
    var cursor = DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);
    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var count = 0;
    while (days.contains(cursor)) {
      count++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  Future<void> initialize() async {
    _subscriptions.add(_repository.authStateChanges.listen(_onAuthChanged));
    await _onAuthChanged(_repository.currentAuthUser);
  }

  Future<void> _onAuthChanged(auth.User? user) async {
    _photoCacheGeneration++;
    await _cancelDataSubscriptions();
    _user = null;
    _photos = const [];
    _feed = const [];
    _friendsFeed = const [];
    _publicUsers = const [];
    _followingIds = const {};
    if (user != null) {
      try {
        await _repository.ensureCurrentUser();
      } catch (error) {
        _error = error.toString();
      }
      _subscriptions.add(
        _repository.watchCurrentUser().listen((value) {
          _user = value;
          notifyListeners();
        }),
      );
      _subscriptions.add(
        _repository.watchMyPhotos().listen((value) {
          _setOwnPhotos(value, user.uid);
        }),
      );
      _subscriptions.add(
        _repository.watchFeed().listen((value) {
          _feed = value;
          notifyListeners();
        }),
      );
      _subscriptions.add(
        _repository.watchPublicUsers().listen((value) {
          _publicUsers = value
              .where((publicUser) => publicUser.id != user.uid)
              .map(
                (publicUser) => publicUser.copyWith(
                  isFollowing: _followingIds.contains(publicUser.id),
                ),
              )
              .toList();
          notifyListeners();
        }),
      );
      try {
        _followingIds = await _repository.getFollowingIds();
        _publicUsers = _publicUsers
            .map(
              (publicUser) => publicUser.copyWith(
                isFollowing: _followingIds.contains(publicUser.id),
              ),
            )
            .toList();
        _friendsFeed = await _repository.loadFriendsFeed();
      } catch (error) {
        _error = error.toString();
      }
      unawaited(_initializePurchases());
    }
    _initializing = false;
    notifyListeners();
  }

  Future<void> signInWithGoogle() => _run(_repository.signInWithGoogle);
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) =>
      _run(() => _repository.signInWithEmail(email: email, password: password));
  Future<void> registerWithEmail({
    required String email,
    required String password,
  }) => _run(
    () => _repository.registerWithEmail(email: email, password: password),
  );
  Future<void> sendPasswordResetEmail(String email) =>
      _run(() => _repository.sendPasswordResetEmail(email));
  bool get currentUserUsesPassword => _repository.currentUserUsesPassword;
  Future<void> signOut() => _run(_repository.signOut);
  Future<void> savePhoto(File file) =>
      _run(() => _savePhoto(file, DateTime.now()));
  Future<void> savePhotoAt(File file, DateTime capturedAt) =>
      _run(() => _savePhoto(file, capturedAt));

  Future<void> ensureOwnPhotosLocal() async {
    final ownerId = _repository.currentAuthUser?.uid;
    if (ownerId == null) return;
    final generation = ++_photoCacheGeneration;
    final prepared = await _photoCache.prepareOwnPhotos(_photos);
    if (generation != _photoCacheGeneration ||
        _repository.currentAuthUser?.uid != ownerId) {
      return;
    }
    _photos = prepared;
    notifyListeners();
  }

  Future<void> saveImportedPhotos(
    Iterable<PhotoImportItem> items, {
    void Function(int completed, int total)? onProgress,
  }) => _run(() async {
    final imported = items.toList(growable: false);
    var completed = 0;
    for (
      var start = 0;
      start < imported.length;
      start += AppConstants.transferBatchSize
    ) {
      final end = (start + AppConstants.transferBatchSize).clamp(
        0,
        imported.length,
      );
      await Future.wait([
        for (final item in imported.sublist(start, end))
          _savePhoto(item.file, item.capturedAt),
      ]);
      completed = end;
      onProgress?.call(completed, imported.length);
    }
  });

  Future<void> deletePhoto(DailyPhoto photo) => _run(() async {
    await _repository.deletePhoto(photo);
    await _photoCache.deleteLocal(photo);
  });
  Future<void> deleteAllPhotos() => _run(() async {
    final photos = _photos;
    await _repository.deleteAllPhotos();
    await Future.wait(photos.map(_photoCache.deleteLocal));
  });

  Future<void> setPublic(bool value) async {
    final previous = _user;
    if (previous == null) return;
    _user = previous.copyWith(isPublic: value);
    notifyListeners();
    try {
      await _repository.updateVisibility(value);
    } catch (_) {
      _user = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> toggleFollow(String userId) async {
    final currentUser = _user;
    if (currentUser == null || currentUser.id == userId) return;
    final wasFollowing = _followingIds.contains(userId);
    final updatedFollowing = {..._followingIds};
    if (wasFollowing) {
      updatedFollowing.remove(userId);
    } else {
      updatedFollowing.add(userId);
    }
    _followingIds = updatedFollowing;
    _publicUsers = _publicUsers
        .map(
          (publicUser) => publicUser.id == userId
              ? publicUser.copyWith(isFollowing: !wasFollowing)
              : publicUser,
        )
        .toList();
    notifyListeners();
    try {
      await _repository.toggleFollow(userId);
      _friendsFeed = await _repository.loadFriendsFeed();
      notifyListeners();
    } catch (error) {
      _followingIds = wasFollowing
          ? {..._followingIds, userId}
          : ({..._followingIds}..remove(userId));
      _publicUsers = _publicUsers
          .map(
            (publicUser) => publicUser.id == userId
                ? publicUser.copyWith(isFollowing: wasFollowing)
                : publicUser,
          )
          .toList();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteAccount({String? password}) => _run(() async {
    final photos = _photos;
    await _repository.deleteAccount(password: password);
    await Future.wait(photos.map(_photoCache.deleteLocal));
  });

  void _setOwnPhotos(List<DailyPhoto> photos, String ownerId) {
    final generation = ++_photoCacheGeneration;
    _photos = photos;
    notifyListeners();
    unawaited(_prepareOwnPhotos(photos, ownerId, generation));
  }

  Future<void> _prepareOwnPhotos(
    List<DailyPhoto> photos,
    String ownerId,
    int generation,
  ) async {
    final prepared = await _photoCache.prepareOwnPhotos(photos);
    if (generation != _photoCacheGeneration ||
        _repository.currentAuthUser?.uid != ownerId) {
      return;
    }
    _photos = prepared;
    notifyListeners();
  }

  Future<void> _savePhoto(File file, DateTime capturedAt) async {
    final ownerId = _repository.currentAuthUser?.uid;
    if (ownerId == null) throw StateError('Authentication required');
    await _photoCache.cacheOwnPhoto(
      source: file,
      ownerId: ownerId,
      capturedAt: capturedAt,
    );
    await _repository.savePhoto(file, capturedAt);
    try {
      await _notificationService?.skipTodayForPhoto(capturedAt);
    } catch (_) {
      // A reminder scheduling failure must not make a saved photo look failed.
    }
  }

  Future<bool> buyPremium() async {
    final service = _purchaseService;
    final product = _premiumProduct;
    if (service == null || product == null || _purchaseBusy) return false;
    _purchaseBusy = true;
    notifyListeners();
    try {
      return await service.buy(product);
    } finally {
      _purchaseBusy = false;
      notifyListeners();
    }
  }

  Future<void> restorePurchases() async {
    final service = _purchaseService;
    if (service == null || _purchaseBusy) return;
    _purchaseBusy = true;
    notifyListeners();
    try {
      await service.restore();
    } finally {
      _purchaseBusy = false;
      notifyListeners();
    }
  }

  Future<void> setPremiumTestEnabled(bool enabled) async {
    if (!isPremiumTestAccount) return;
    await _preferences?.setBool(AppConstants.premiumTestOverrideKey, enabled);
    notifyListeners();
  }

  Future<void> toggleLike(String photoId) =>
      _run(() => _repository.toggleLike(photoId), showBusy: false);

  Future<void> _run(
    Future<void> Function() action, {
    bool showBusy = true,
  }) async {
    if (showBusy) {
      _busy = true;
      _error = null;
      notifyListeners();
    }
    try {
      await action();
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      if (showBusy) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _cancelDataSubscriptions() async {
    if (_subscriptions.length <= 1) return;
    final dataSubscriptions = _subscriptions.skip(1).toList();
    _subscriptions.removeRange(1, _subscriptions.length);
    for (final subscription in dataSubscriptions) {
      await subscription.cancel();
    }
  }

  Future<void> _initializePurchases() async {
    final service = _purchaseService;
    if (service == null) return;
    if (!_purchasesInitialized) {
      _purchasesInitialized = true;
      _purchaseSubscription = service.purchases.listen(_handlePurchases);
    }
    try {
      _premiumProduct = await service.loadPremiumProduct();
      notifyListeners();
    } catch (_) {
      // The store can be unavailable during startup or before Play setup.
    }
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    final service = _purchaseService;
    if (service == null) return;
    for (final purchase in purchases) {
      if (purchase.productID != AppConstants.premiumProductId) continue;
      try {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          await service.verify(purchase);
        }
      } catch (error) {
        _error = error.toString();
        notifyListeners();
      } finally {
        if (purchase.pendingCompletePurchase) {
          await service.complete(purchase);
        }
      }
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_purchaseSubscription?.cancel() ?? Future<void>.value());
    super.dispose();
  }
}
