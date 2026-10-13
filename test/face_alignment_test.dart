import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:phototimelapse/data/services/face_alignment_service.dart';
import 'package:phototimelapse/config/app_constants.dart';

void main() {
  const target = FaceReference.generic();

  test('single pass fixes tilted eyes for normal and mirrored photos', () {
    for (final mirrored in [false, true]) {
      final source = img.Image(width: 100, height: 125);
      source.setPixelRgb(20, 30, 255, 0, 0);
      source.setPixelRgb(60, 50, 0, 255, 0);
      final aligned = alignEyeAnchors(
        source,
        leftX: 20,
        leftY: 30,
        rightX: 60,
        rightY: 50,
        width: 100,
        height: 100,
        mirrorImage: mirrored,
      );
      expect(aligned.getPixel(mirrored ? 58 : 42, 38).r, 255);
      expect(aligned.getPixel(mirrored ? 42 : 58, 38).g, 255);
      final repeated = alignEyeAnchors(
        aligned,
        leftX: 42,
        leftY: 38,
        rightX: 58,
        rightY: 38,
        width: 100,
        height: 100,
      );
      expect(repeated.getPixel(mirrored ? 58 : 42, 38).r, 255);
      expect(repeated.getPixel(mirrored ? 42 : 58, 38).g, 255);
    }
  });

  test('eye transform preserves anchors, scale and padding near an edge', () {
    for (final offset in [0, 20]) {
      final source = img.Image(width: 100, height: 100);
      img.fill(source, color: img.ColorRgb8(255, 255, 255));
      source.setPixelRgb(2 + offset, 5 + offset, 255, 0, 0);
      source.setPixelRgb(22 + offset, 15 + offset, 0, 255, 0);
      final aligned = alignEyeAnchors(
        source,
        leftX: (2 + offset).toDouble(),
        leftY: (5 + offset).toDouble(),
        rightX: (22 + offset).toDouble(),
        rightY: (15 + offset).toDouble(),
        reference: target,
        width: 100,
        height: 100,
      );
      expect(aligned.getPixel(42, 38).r, 255);
      expect(aligned.getPixel(42, 38).g, 0);
      expect(aligned.getPixel(58, 38).g, 255);
      expect(aligned.getPixel(58, 38).r, 0);
      expect(aligned.getPixel(0, 0).r, 0);
    }
  });

  test('different positions and eye distances share exact output anchors', () {
    for (final (leftX, rightX, eyeY) in [
      (20, 40, 25),
      (34, 66, 40),
      (15, 95, 70),
    ]) {
      final source = img.Image(width: 120, height: 120);
      source.setPixelRgb(leftX, eyeY, 255, 0, 0);
      source.setPixelRgb(rightX, eyeY, 0, 255, 0);
      final aligned = alignEyeAnchors(
        source,
        leftX: leftX.toDouble(),
        leftY: eyeY.toDouble(),
        rightX: rightX.toDouble(),
        rightY: eyeY.toDouble(),
        width: 100,
        height: 100,
      );

      expect(aligned.getPixel(42, 38).r, 255);
      expect(aligned.getPixel(58, 38).g, 255);
    }
  });

  test('alignment trial exposes six strategies', () {
    expect(FaceAlignmentAlgorithm.values, hasLength(6));
  });

  test('a pose matching the target is ready at one hundred percent', () {
    final feedback = FaceAlignmentService.calculateFeedback(
      _poseFrom(target),
      target,
    );

    expect(feedback.score, 100);
    expect(feedback.issue, FaceAlignmentIssue.ready);
  });

  test('horizontal feedback tells the user which way to move', () {
    final feedback = FaceAlignmentService.calculateFeedback(
      _poseFrom(target, faceCenterX: 0.60),
      target,
    );

    expect(feedback.issue, FaceAlignmentIssue.moveLeft);
  });

  test(
    'the first reference score ignores personal eye and mouth positions',
    () {
      final pose = _poseFrom(
        target,
        leftEyeX: 0.18,
        rightEyeX: 0.28,
        mouthX: 0.82,
        mouthY: 0.85,
        eyeDistance: 0.1,
      );

      final feedback = FaceAlignmentService.calculateFeedback(
        pose,
        target,
        compareFacialFeatures: false,
      );

      expect(feedback.score, 100);
      expect(feedback.issue, FaceAlignmentIssue.ready);
    },
  );

  test('a missing face produces a zero score', () {
    final feedback = FaceAlignmentService.calculateFeedback(null, target);

    expect(feedback.score, 0);
    expect(feedback.issue, FaceAlignmentIssue.noFace);
  });

  test('a face without landmarks gives a useful non-ready instruction', () {
    final pose = FacePose(
      faceCenterX: target.faceCenterX,
      faceCenterY: target.faceCenterY,
      faceWidth: target.faceWidth,
      faceHeight: target.faceHeight,
      leftEyeX: null,
      leftEyeY: null,
      rightEyeX: null,
      rightEyeY: null,
      mouthLeftX: null,
      mouthLeftY: null,
      mouthRightX: null,
      mouthRightY: null,
      mouthX: null,
      mouthY: null,
      eyeDistance: 0,
      roll: target.roll,
      yaw: target.yaw,
    );

    final feedback = FaceAlignmentService.calculateFeedback(pose, target);

    expect(feedback.score, lessThan(AppConstants.alignmentReadyScore));
    expect(feedback.issue, FaceAlignmentIssue.faceCamera);
  });

  test('a complete face with normal camera jitter keeps a high score', () {
    final feedback = FaceAlignmentService.calculateFeedback(
      _poseFrom(
        target,
        faceCenterX: 0.54,
        faceCenterY: 0.50,
        faceWidth: 0.50,
        faceHeight: 0.56,
        roll: 4,
        yaw: 7,
      ),
      target,
      compareFacialFeatures: false,
    );

    expect(feedback.score, greaterThan(85));
    expect(feedback.issue, FaceAlignmentIssue.ready);
  });
}

FacePose _poseFrom(
  FaceReference target, {
  double? faceCenterX,
  double? faceCenterY,
  double? faceWidth,
  double? faceHeight,
  double? leftEyeX,
  double? rightEyeX,
  double? mouthX,
  double? mouthY,
  double? eyeDistance,
  double? roll,
  double? yaw,
}) => FacePose(
  faceCenterX: faceCenterX ?? target.faceCenterX,
  faceCenterY: faceCenterY ?? target.faceCenterY,
  faceWidth: faceWidth ?? target.faceWidth,
  faceHeight: faceHeight ?? target.faceHeight,
  leftEyeX: leftEyeX ?? target.leftEyeX,
  leftEyeY: target.leftEyeY,
  rightEyeX: rightEyeX ?? target.rightEyeX,
  rightEyeY: target.rightEyeY,
  mouthLeftX: target.mouthLeftX,
  mouthLeftY: target.mouthLeftY,
  mouthRightX: target.mouthRightX,
  mouthRightY: target.mouthRightY,
  mouthX: mouthX ?? target.mouthX,
  mouthY: mouthY ?? target.mouthY,
  eyeDistance: eyeDistance ?? target.eyeDistance,
  roll: roll ?? target.roll,
  yaw: yaw ?? target.yaw,
);
