abstract final class AppConstants {
  static const appName = 'FaceMorph';
  static const premiumProductId = 'oneframe_premium_monthly';
  static const premiumTestAccountEmail = 'm.islam0422@gmail.com';
  static const premiumTestOverrideKey = 'premium_test_override';
  static const privacyPolicyUrl =
      'https://app-documents-bway-2026.web.app/legal/facemorph/privacy-policy';
  static const termsOfUseUrl =
      'https://app-documents-bway-2026.web.app/legal/facemorph/terms-of-service';
  static const accountDeletionUrl =
      'https://app-documents-bway-2026.web.app/delete-request?app=facemorph';
  static const cloudFunctionsBaseUrl =
      'https://europe-west1-phototimelapse-20260901.cloudfunctions.net';
  static Uri get uploadPhotoEndpoint =>
      Uri.parse('$cloudFunctionsBaseUrl/uploadPhoto');
  static Uri get deletePhotoEndpoint =>
      Uri.parse('$cloudFunctionsBaseUrl/deletePhoto');
  static const trialDays = 14;
  static const premiumDailyLimit = 1;
  static const freeWeeklyLimit = 1;
  static const defaultReminderHour = 20;
  static const defaultReminderMinute = 0;
  static const defaultPublicPhotos = false;
  static const faceOutputWidth = 1080;
  static const faceOutputHeight = 1350;
  // The face should occupy roughly one third of the saved frame height. The
  // crop is still limited by the source image, so this never creates empty
  // pixels or stretches the photo.
  static const faceTargetHeightRatio = 0.30;
  static const faceEyeHeightRatio = 0.38;
  static const faceRotationThreshold = 1.0;
  static const faceJpegQuality = 100;
  static const faceLiveMinSize = 0.10;
  static const faceImageMinSize = 0.12;
  static const photoBorderRadius = 20.0;
  static const cameraPreviewBorderRadius = 28.0;
  static const frontFlashDuration = Duration(milliseconds: 140);
  static const alignmentHorizontalHintThreshold = 0.045;
  static const alignmentVerticalHintThreshold = 0.05;
  static const alignmentDistanceHintThreshold = 0.055;
  static const alignmentYawHintThreshold = 9.0;
  static const alignmentRollHintThreshold = 5.0;
  static const alignmentReadyScore = 80;
  static const alignmentReferenceMinimumScore = 80;
  static const alignmentTargetFaceCenterX = 0.5;
  static const alignmentTargetFaceCenterY = 0.46;
  // The first-frame guide should keep the face comfortably close to camera.
  // The live guide should bring the face a little closer than the old target.
  static const alignmentTargetFaceWidth = 0.50;
  static const alignmentTargetFaceHeight = 0.60;
  static const alignmentTargetLeftEyeX = 0.42;
  static const alignmentTargetRightEyeX = 0.58;
  static const alignmentTargetEyeY = 0.38;
  static const alignmentTargetMouthLeftX = 0.44;
  static const alignmentTargetMouthRightX = 0.56;
  static const alignmentTargetMouthY = 0.61;
  static const alignmentTargetMouthX = 0.5;
  static const alignmentTargetMouthCenterY = 0.62;
  static const alignmentTargetEyeDistance = 0.16;
  static const alignmentEyeScaleWeight = 2.0;
  static const alignmentFaceScaleWeight = 1.0;
  static const alignmentFaceCenterWeight = 0.5;
  static const faceLiveAnalysisInterval = Duration(milliseconds: 120);
  static const faceGuideWidthFactor = 0.76;
  static const faceGuideMaxWidth = 320.0;
  static const faceGuideAspectRatio = 1.28;
  static const faceGuideCenterYFactor = 0.44;
  static const transferBatchSize = 4;
  static const transferRequestTimeout = Duration(seconds: 60);
  static const videoDefaultPhotoSeconds = 0.2;
  static const videoMinPhotoSeconds = 0.01;
  static const videoMaxPhotoSeconds = 1.0;
  static const videoOutputFrameRate = 30;
  static const videoOutputWidth = 720;
  static const videoOutputHeight = 900;
  static const videoDownloadBatchSize = 4;
  static const largeScreenBreakpoint = 720.0;
  static const maxContentWidth = 980.0;
}
