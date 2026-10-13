import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phototimelapse/core/l10n/app_strings.dart';
import 'package:phototimelapse/domain/models/app_user.dart';
import 'package:phototimelapse/domain/models/capture_entitlement.dart';
import 'package:phototimelapse/domain/models/daily_photo.dart';

void main() {
  final now = DateTime(2026, 9, 1, 12);

  test('new users receive fourteen days of daily capture access', () {
    final entitlement = CaptureEntitlement.evaluate(
      user: _user(trialStartedAt: now.subtract(const Duration(days: 2))),
      photos: const [],
      now: now,
    );

    expect(entitlement.isPremium, isTrue);
    expect(entitlement.canCapture, isTrue);
    expect(entitlement.daysLeftInTrial, 12);
  });

  test('premium users can capture only once each day', () {
    final entitlement = CaptureEntitlement.evaluate(
      user: _user(trialStartedAt: now.subtract(const Duration(days: 2))),
      photos: [_photo(now.subtract(const Duration(hours: 1)))],
      now: now,
    );

    expect(entitlement.canCapture, isFalse);
    expect(entitlement.nextCaptureAt, DateTime(2026, 9, 2));
  });

  test('free users can capture once per Monday-based week', () {
    final entitlement = CaptureEntitlement.evaluate(
      user: _user(trialStartedAt: now.subtract(const Duration(days: 30))),
      photos: [_photo(DateTime(2026, 8, 31, 18))],
      now: now,
    );

    expect(entitlement.isPremium, isFalse);
    expect(entitlement.canCapture, isFalse);
    expect(entitlement.nextCaptureAt, DateTime(2026, 9, 7));
  });

  test('premium override controls the plan for test mode', () {
    final premium = CaptureEntitlement.evaluate(
      user: _user(trialStartedAt: now.subtract(const Duration(days: 30))),
      photos: const [],
      now: now,
      premiumOverride: true,
    );
    final free = CaptureEntitlement.evaluate(
      user: _user(trialStartedAt: now.subtract(const Duration(days: 2))),
      photos: const [],
      now: now,
      premiumOverride: false,
    );

    expect(premium.isPremium, isTrue);
    expect(premium.daysLeftInTrial, 0);
    expect(free.isPremium, isFalse);
  });

  test('the app uses English on every device', () {
    expect(const AppStrings(Locale('tr')).today, 'Today');
    expect(const AppStrings(Locale('de')).today, 'Today');
    expect(
      resolveAppLocale([const Locale('en'), const Locale('tr')]),
      const Locale('en'),
    );
    expect(
      resolveAppLocale([const Locale('tr'), const Locale('en')]),
      const Locale('en'),
    );
  });
}

AppUser _user({required DateTime trialStartedAt}) => AppUser(
  id: 'user',
  displayName: 'User',
  email: 'user@example.com',
  photoUrl: null,
  isPublic: true,
  trialStartedAt: trialStartedAt,
);

DailyPhoto _photo(DateTime capturedAt) => DailyPhoto(
  id: capturedAt.toIso8601String(),
  ownerId: 'user',
  ownerName: 'User',
  ownerAvatarUrl: null,
  imageUrl: '',
  capturedAt: capturedAt,
  isPublic: true,
  likeCount: 0,
);
