import '../../config/app_constants.dart';
import 'app_user.dart';
import 'daily_photo.dart';

class CaptureEntitlement {
  const CaptureEntitlement({
    required this.isPremium,
    required this.canCapture,
    required this.nextCaptureAt,
    required this.daysLeftInTrial,
  });

  factory CaptureEntitlement.evaluate({
    required AppUser user,
    required List<DailyPhoto> photos,
    DateTime? now,
    bool? premiumOverride,
  }) {
    final current = now ?? DateTime.now();
    final trialEnd = user.trialStartedAt.add(
      const Duration(days: AppConstants.trialDays),
    );
    final premiumEnd = user.premiumUntil;
    final effectiveEnd = premiumEnd != null && premiumEnd.isAfter(trialEnd)
        ? premiumEnd
        : trialEnd;
    final premium = premiumOverride ?? effectiveEnd.isAfter(current);
    final daysLeft = premium
        ? premiumOverride == true
              ? 0
              : (effectiveEnd.difference(current).inHours / 24).ceil()
        : 0;

    if (premium) {
      final start = DateTime(current.year, current.month, current.day);
      final hasToday = photos.any((photo) => !photo.capturedAt.isBefore(start));
      return CaptureEntitlement(
        isPremium: true,
        canCapture: !hasToday,
        nextCaptureAt: hasToday ? start.add(const Duration(days: 1)) : current,
        daysLeftInTrial: daysLeft,
      );
    }

    final weekStart = DateTime(
      current.year,
      current.month,
      current.day,
    ).subtract(Duration(days: current.weekday - DateTime.monday));
    final hasThisWeek = photos.any(
      (photo) => !photo.capturedAt.isBefore(weekStart),
    );
    return CaptureEntitlement(
      isPremium: false,
      canCapture: !hasThisWeek,
      nextCaptureAt: hasThisWeek
          ? weekStart.add(const Duration(days: 7))
          : current,
      daysLeftInTrial: 0,
    );
  }

  final bool isPremium;
  final bool canCapture;
  final DateTime nextCaptureAt;
  final int daysLeftInTrial;
}
