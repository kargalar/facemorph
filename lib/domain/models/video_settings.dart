import '../../config/app_constants.dart';

class VideoSettings {
  VideoSettings({
    double photoSeconds = AppConstants.videoDefaultPhotoSeconds,
    this.smoothTransition = false,
  }) : photoDuration = Duration(
         milliseconds: (validate(photoSeconds) * 100).round() * 10,
       );

  final Duration photoDuration;
  final bool smoothTransition;

  double get photoSeconds => photoDuration.inMilliseconds / 1000;

  // Keep every photo boundary on an output frame, including 0.01-second steps.
  int get frameRate {
    final base = 100 ~/ (photoDuration.inMilliseconds ~/ 10).gcd(100);
    return base * (AppConstants.videoOutputFrameRate / base).ceil();
  }

  Duration duration(int count) => photoDuration * count;

  static double validate(double seconds) {
    if (!seconds.isFinite ||
        seconds < AppConstants.videoMinPhotoSeconds ||
        seconds > AppConstants.videoMaxPhotoSeconds) {
      throw ArgumentError.value(seconds, 'photoSeconds');
    }
    return seconds;
  }
}
