import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import '../../config/app_constants.dart';

typedef _ProcessedImage = ({Uint8List bytes, int width, int height});

class FaceNotFoundException implements Exception {}

enum FaceAlignmentAlgorithm {
  eyeAnchor,
  faceBox,
  eyeDistance,
  eyeMouth,
  balanced,
  eyeHeadSize,
}

enum FaceAlignmentIssue {
  noFace,
  faceCamera,
  moveLeft,
  moveRight,
  moveUp,
  moveDown,
  moveCloser,
  moveAway,
  turnLeft,
  turnRight,
  rotateLeft,
  rotateRight,
  fineTune,
  ready,
}

class FaceAlignmentFeedback {
  const FaceAlignmentFeedback({required this.score, required this.issue});

  final int score;
  final FaceAlignmentIssue issue;

  bool get isReady => issue == FaceAlignmentIssue.ready;
}

class FaceContourPoint {
  const FaceContourPoint(this.x, this.y);

  final double x;
  final double y;
}

/// Facial landmarks normalized to the upright camera image (0..1).
class FacePose {
  const FacePose({
    required this.faceCenterX,
    required this.faceCenterY,
    required this.faceWidth,
    required this.faceHeight,
    required this.leftEyeX,
    required this.leftEyeY,
    required this.rightEyeX,
    required this.rightEyeY,
    required this.mouthLeftX,
    required this.mouthLeftY,
    required this.mouthRightX,
    required this.mouthRightY,
    required this.mouthX,
    required this.mouthY,
    required this.eyeDistance,
    required this.roll,
    required this.yaw,
    this.leftEyeContour = const [],
    this.rightEyeContour = const [],
    this.upperLipContour = const [],
    this.lowerLipContour = const [],
  });

  final double faceCenterX;
  final double faceCenterY;
  final double faceWidth;
  final double faceHeight;
  final double? leftEyeX;
  final double? leftEyeY;
  final double? rightEyeX;
  final double? rightEyeY;
  final double? mouthLeftX;
  final double? mouthLeftY;
  final double? mouthRightX;
  final double? mouthRightY;
  final double? mouthX;
  final double? mouthY;
  final double eyeDistance;
  final double roll;
  final double yaw;
  final List<FaceContourPoint> leftEyeContour;
  final List<FaceContourPoint> rightEyeContour;
  final List<FaceContourPoint> upperLipContour;
  final List<FaceContourPoint> lowerLipContour;

  bool get hasEyeLandmarks =>
      leftEyeX != null &&
      leftEyeY != null &&
      rightEyeX != null &&
      rightEyeY != null;

  bool get hasMouthLandmarks => mouthX != null && mouthY != null;

  bool get hasLandmarks => hasEyeLandmarks && hasMouthLandmarks;
}

class FaceReference {
  const FaceReference({
    required this.faceCenterX,
    required this.faceCenterY,
    required this.faceWidth,
    required this.faceHeight,
    required this.leftEyeX,
    required this.leftEyeY,
    required this.rightEyeX,
    required this.rightEyeY,
    required this.mouthLeftX,
    required this.mouthLeftY,
    required this.mouthRightX,
    required this.mouthRightY,
    required this.mouthX,
    required this.mouthY,
    required this.eyeDistance,
    required this.roll,
    required this.yaw,
    this.leftEyeContour = const [],
    this.rightEyeContour = const [],
    this.upperLipContour = const [],
    this.lowerLipContour = const [],
  });

  const FaceReference.generic()
    : faceCenterX = AppConstants.alignmentTargetFaceCenterX,
      faceCenterY = AppConstants.alignmentTargetFaceCenterY,
      faceWidth = AppConstants.alignmentTargetFaceWidth,
      faceHeight = AppConstants.alignmentTargetFaceHeight,
      leftEyeX = AppConstants.alignmentTargetLeftEyeX,
      leftEyeY = AppConstants.alignmentTargetEyeY,
      rightEyeX = AppConstants.alignmentTargetRightEyeX,
      rightEyeY = AppConstants.alignmentTargetEyeY,
      mouthLeftX = AppConstants.alignmentTargetMouthLeftX,
      mouthLeftY = AppConstants.alignmentTargetMouthY,
      mouthRightX = AppConstants.alignmentTargetMouthRightX,
      mouthRightY = AppConstants.alignmentTargetMouthY,
      mouthX = AppConstants.alignmentTargetMouthX,
      mouthY = AppConstants.alignmentTargetMouthCenterY,
      eyeDistance = AppConstants.alignmentTargetEyeDistance,
      roll = 0,
      yaw = 0,
      leftEyeContour = const [],
      rightEyeContour = const [],
      upperLipContour = const [],
      lowerLipContour = const [];

  final double faceCenterX;
  final double faceCenterY;
  final double faceWidth;
  final double faceHeight;
  final double leftEyeX;
  final double leftEyeY;
  final double rightEyeX;
  final double rightEyeY;
  final double mouthLeftX;
  final double mouthLeftY;
  final double mouthRightX;
  final double mouthRightY;
  final double mouthX;
  final double mouthY;
  final double eyeDistance;
  final double roll;
  final double yaw;
  final List<FaceContourPoint> leftEyeContour;
  final List<FaceContourPoint> rightEyeContour;
  final List<FaceContourPoint> upperLipContour;
  final List<FaceContourPoint> lowerLipContour;

  factory FaceReference.fromPose(FacePose pose) {
    if (!pose.hasLandmarks) {
      throw ArgumentError('A complete face pose is required as a reference.');
    }
    return FaceReference(
      faceCenterX: pose.faceCenterX,
      faceCenterY: pose.faceCenterY,
      faceWidth: pose.faceWidth,
      faceHeight: pose.faceHeight,
      leftEyeX: pose.leftEyeX!,
      leftEyeY: pose.leftEyeY!,
      rightEyeX: pose.rightEyeX!,
      rightEyeY: pose.rightEyeY!,
      mouthLeftX: pose.mouthLeftX ?? pose.mouthX!,
      mouthLeftY: pose.mouthLeftY ?? pose.mouthY!,
      mouthRightX: pose.mouthRightX ?? pose.mouthX!,
      mouthRightY: pose.mouthRightY ?? pose.mouthY!,
      mouthX: pose.mouthX!,
      mouthY: pose.mouthY!,
      eyeDistance: pose.eyeDistance,
      roll: pose.roll,
      yaw: pose.yaw,
      leftEyeContour: pose.leftEyeContour,
      rightEyeContour: pose.rightEyeContour,
      upperLipContour: pose.upperLipContour,
      lowerLipContour: pose.lowerLipContour,
    );
  }

  Map<String, dynamic> toJson() => {
    'faceCenterX': faceCenterX,
    'faceCenterY': faceCenterY,
    'faceWidth': faceWidth,
    'faceHeight': faceHeight,
    'leftEyeX': leftEyeX,
    'leftEyeY': leftEyeY,
    'rightEyeX': rightEyeX,
    'rightEyeY': rightEyeY,
    'mouthLeftX': mouthLeftX,
    'mouthLeftY': mouthLeftY,
    'mouthRightX': mouthRightX,
    'mouthRightY': mouthRightY,
    'mouthX': mouthX,
    'mouthY': mouthY,
    'eyeDistance': eyeDistance,
    'roll': roll,
    'yaw': yaw,
    'leftEyeContour': _contourToJson(leftEyeContour),
    'rightEyeContour': _contourToJson(rightEyeContour),
    'upperLipContour': _contourToJson(upperLipContour),
    'lowerLipContour': _contourToJson(lowerLipContour),
  };

  factory FaceReference.fromJson(Map<String, dynamic> json) {
    double value(String key) => (json[key] as num).toDouble();
    List<FaceContourPoint> contour(String key) => _contourFromJson(json[key]);
    return FaceReference(
      faceCenterX: value('faceCenterX'),
      faceCenterY: value('faceCenterY'),
      faceWidth: value('faceWidth'),
      faceHeight: value('faceHeight'),
      leftEyeX: value('leftEyeX'),
      leftEyeY: value('leftEyeY'),
      rightEyeX: value('rightEyeX'),
      rightEyeY: value('rightEyeY'),
      mouthLeftX: value('mouthLeftX'),
      mouthLeftY: value('mouthLeftY'),
      mouthRightX: value('mouthRightX'),
      mouthRightY: value('mouthRightY'),
      mouthX: value('mouthX'),
      mouthY: value('mouthY'),
      eyeDistance: value('eyeDistance'),
      roll: value('roll'),
      yaw: value('yaw'),
      leftEyeContour: contour('leftEyeContour'),
      rightEyeContour: contour('rightEyeContour'),
      upperLipContour: contour('upperLipContour'),
      lowerLipContour: contour('lowerLipContour'),
    );
  }

  static List<Map<String, double>> _contourToJson(
    List<FaceContourPoint> contour,
  ) => [
    for (final point in contour) {'x': point.x, 'y': point.y},
  ];

  static List<FaceContourPoint> _contourFromJson(Object? value) {
    if (value is! List) return const [];
    return [
      for (final point in value)
        if (point is Map<String, dynamic> &&
            point['x'] is num &&
            point['y'] is num)
          FaceContourPoint(
            (point['x'] as num).toDouble(),
            (point['y'] as num).toDouble(),
          ),
    ];
  }
}

class FaceAlignmentResult {
  const FaceAlignmentResult({required this.file, required this.pose});

  final File file;
  final FacePose pose;
}

class FaceAlignmentService {
  FaceAlignmentService({this._preferences})
    : _liveDetector = _createDetector(
        minFaceSize: AppConstants.faceLiveMinSize,
        enableContours: true,
      ),
      _photoDetector = _createDetector(
        minFaceSize: AppConstants.faceImageMinSize,
        enableContours: true,
      );

  static const _referenceKey = 'oneframe.face_reference.v1';
  static const _captureReferenceKey = 'oneframe.capture_reference.v2';

  bool get hasCaptureReference =>
      _preferences?.getBool(_captureReferenceKey) == true && reference != null;

  static const _algorithmKey = 'oneframe.face_alignment_algorithm.v1';

  final SharedPreferences? _preferences;
  final FaceDetector _liveDetector;
  final FaceDetector _photoDetector;
  bool _liveDetectionBusy = false;

  static FaceDetector _createDetector({
    required double minFaceSize,
    required bool enableContours,
  }) => FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true,
      enableContours: enableContours,
      enableClassification: false,
      minFaceSize: minFaceSize,
    ),
  );

  FaceReference get targetReference {
    final stored = reference;
    return stored ?? const FaceReference.generic();
  }

  FaceAlignmentAlgorithm get alignmentAlgorithm {
    final index = _preferences?.getInt(_algorithmKey);
    if (index == null ||
        index < 0 ||
        index >= FaceAlignmentAlgorithm.values.length) {
      return FaceAlignmentAlgorithm.balanced;
    }
    return FaceAlignmentAlgorithm.values[index];
  }

  Future<void> saveAlignmentAlgorithm(FaceAlignmentAlgorithm algorithm) async {
    await _preferences?.setInt(_algorithmKey, algorithm.index);
  }

  FaceReference? get reference {
    final raw = _preferences?.getString(_referenceKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return FaceReference.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveReference(FacePose pose) async {
    if (_preferences == null || !pose.hasLandmarks) return;
    await _preferences.setString(
      _referenceKey,
      jsonEncode(FaceReference.fromPose(pose).toJson()),
    );
    await _preferences.setBool(_captureReferenceKey, true);
  }

  Future<File> align(
    String sourcePath, {
    FaceAlignmentAlgorithm? algorithm,
  }) async => (await alignWithMetadata(sourcePath, algorithm: algorithm)).file;

  Future<FacePose> analyzePhoto(String sourcePath) async {
    final face = await _detectPhotoFace(sourcePath);
    final bytes = await File(sourcePath).readAsBytes();
    final size = await Isolate.run(() => _orientedImageSize(bytes));
    final pose = _mirrorPose(_poseFromFace(face, size.$1, size.$2));
    if (!pose.hasEyeLandmarks) throw FaceNotFoundException();
    return pose;
  }

  Future<FaceAlignmentResult> alignWithMetadata(
    String sourcePath, {
    bool mirrorImage = false,
    FaceAlignmentAlgorithm? algorithm,
  }) async {
    final face = await _detectPhotoFace(sourcePath);
    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
    final bytes = await File(sourcePath).readAsBytes();
    final sourceSize = await Isolate.run(() => _orientedImageSize(bytes));
    final sourcePose = _poseFromFace(face, sourceSize.$1, sourceSize.$2);
    // The first photo defines the person's stable facial geometry. Aligning it
    // to the generic template and then aligning later photos to the original
    // photo pose made the first frame use a different target from every frame
    // after it. Use the same reference for both the first and later photos.
    final alignmentReference =
        reference ??
        (sourcePose.hasLandmarks
            ? FaceReference.fromPose(
                mirrorImage ? _mirrorPose(sourcePose) : sourcePose,
              )
            : const FaceReference.generic());
    final leftEyeX = leftEye?.x.toDouble();
    final leftEyeY = leftEye?.y.toDouble();
    final rightEyeX = rightEye?.x.toDouble();
    final rightEyeY = rightEye?.y.toDouble();
    // Image decoding and cropping stay off the UI isolate. The processing
    // result also returns the oriented dimensions, avoiding a second full
    // decode on the main isolate just to calculate normalized landmarks.
    final processed = await Isolate.run(
      () => _processImage(
        bytes: bytes,
        leftEyeX: leftEyeX,
        leftEyeY: leftEyeY,
        rightEyeX: rightEyeX,
        rightEyeY: rightEyeY,
        faceCenterX: face.boundingBox.center.dx.toDouble(),
        faceCenterY: face.boundingBox.center.dy.toDouble(),
        faceWidth: face.boundingBox.width.toDouble(),
        faceHeight: face.boundingBox.height.toDouble(),
        reference: alignmentReference,
        coordinatesNormalized: false,
        mirrorImage: mirrorImage,
      ),
    );
    // Keep pose coordinates in the mirrored space used by the live preview so
    // the first reference matches subsequent frames.
    final pose = _mirrorPose(sourcePose);

    final file = await _writeAlignedFile(processed.bytes);
    return FaceAlignmentResult(file: file, pose: pose);
  }

  Future<File> _writeAlignedFile(Uint8List bytes) async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}aligned_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<Face> _detectPhotoFace(String sourcePath) async {
    final faces = await _photoDetector.processImage(
      InputImage.fromFilePath(sourcePath),
    );
    if (faces.isEmpty) throw FaceNotFoundException();
    faces.sort((a, b) {
      final aArea = a.boundingBox.width * a.boundingBox.height;
      final bArea = b.boundingBox.width * b.boundingBox.height;
      return bArea.compareTo(aArea);
    });
    return faces.first;
  }

  Future<File> centerCrop(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    final processed = await Isolate.run(() => _centerCropImage(bytes));
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}aligned_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(processed, flush: true);
    return file;
  }

  Future<FacePose?> analyzeCameraImage({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) async {
    if (_liveDetectionBusy) return null;
    final cameraImage = _cameraInputImage(
      image: image,
      camera: camera,
      deviceOrientation: deviceOrientation,
    );
    if (cameraImage == null) return null;

    _liveDetectionBusy = true;
    try {
      final faces = await _liveDetector.processImage(cameraImage.inputImage);
      if (faces.isEmpty) return null;
      faces.sort((a, b) {
        final aArea = a.boundingBox.width * a.boundingBox.height;
        final bArea = b.boundingBox.width * b.boundingBox.height;
        return bArea.compareTo(aArea);
      });
      final pose = _poseFromFace(
        faces.first,
        cameraImage.width,
        cameraImage.height,
      );
      return camera.lensDirection == CameraLensDirection.front
          ? _mirrorPose(pose)
          : pose;
    } catch (_) {
      // A dropped frame should never stop the preview or capture flow.
      return null;
    } finally {
      _liveDetectionBusy = false;
    }
  }

  FaceAlignmentFeedback feedbackFor(
    FacePose? pose, {
    bool? compareFacialFeatures,
  }) => calculateFeedback(
    pose,
    targetReference,
    compareFacialFeatures: compareFacialFeatures ?? reference != null,
  );

  static FaceAlignmentFeedback calculateFeedback(
    FacePose? pose,
    FaceReference target, {
    bool compareFacialFeatures = true,
  }) {
    if (pose == null) {
      return const FaceAlignmentFeedback(
        score: 0,
        issue: FaceAlignmentIssue.noFace,
      );
    }
    var total = 0.0;
    var weight = 0.0;
    void add(double actual, double expected, double tolerance, double factor) {
      total += _difference(actual, expected, tolerance) * factor;
      weight += factor;
    }

    add(pose.faceCenterX, target.faceCenterX, 0.18, 1.7);
    add(pose.faceCenterY, target.faceCenterY, 0.16, 1.4);
    add(pose.faceWidth, target.faceWidth, 0.20, 1.3);
    add(pose.faceHeight, target.faceHeight, 0.22, 0.7);
    add(pose.roll, target.roll, 14, 1.1);
    add(pose.yaw, target.yaw, 18, 1.0);
    if (compareFacialFeatures) {
      if (pose.hasEyeLandmarks) {
        add(pose.leftEyeX!, target.leftEyeX, 0.12, 0.8);
        add(pose.leftEyeY!, target.leftEyeY, 0.12, 0.9);
        add(pose.rightEyeX!, target.rightEyeX, 0.12, 0.8);
        add(pose.rightEyeY!, target.rightEyeY, 0.12, 0.9);
        add(pose.eyeDistance, target.eyeDistance, 0.16, 0.8);
      } else {
        total += 1.2;
        weight += 1.2;
      }
      if (pose.hasMouthLandmarks) {
        add(pose.mouthX!, target.mouthX, 0.14, 0.9);
        add(pose.mouthY!, target.mouthY, 0.14, 1.2);
      } else {
        total += 1.2;
        weight += 1.2;
      }
    }

    final rawScore = (1 - (total / weight).clamp(0.0, 1.0)) * 100;
    final score = rawScore.round().clamp(0, 100);

    if (!pose.hasLandmarks) {
      return FaceAlignmentFeedback(
        score: math.min(score, AppConstants.alignmentReadyScore - 1),
        issue: FaceAlignmentIssue.faceCamera,
      );
    }

    final horizontalDelta = pose.faceCenterX - target.faceCenterX;
    if (horizontalDelta > AppConstants.alignmentHorizontalHintThreshold) {
      return FaceAlignmentFeedback(
        score: score,
        issue: FaceAlignmentIssue.moveLeft,
      );
    }
    if (horizontalDelta < -AppConstants.alignmentHorizontalHintThreshold) {
      return FaceAlignmentFeedback(
        score: score,
        issue: FaceAlignmentIssue.moveRight,
      );
    }

    final verticalDelta = pose.faceCenterY - target.faceCenterY;
    if (verticalDelta > AppConstants.alignmentVerticalHintThreshold) {
      return FaceAlignmentFeedback(
        score: score,
        issue: FaceAlignmentIssue.moveUp,
      );
    }
    if (verticalDelta < -AppConstants.alignmentVerticalHintThreshold) {
      return FaceAlignmentFeedback(
        score: score,
        issue: FaceAlignmentIssue.moveDown,
      );
    }

    final widthDelta = pose.faceWidth - target.faceWidth;
    if (widthDelta < -AppConstants.alignmentDistanceHintThreshold) {
      return FaceAlignmentFeedback(
        score: score,
        issue: FaceAlignmentIssue.moveCloser,
      );
    }
    if (widthDelta > AppConstants.alignmentDistanceHintThreshold) {
      return FaceAlignmentFeedback(
        score: score,
        issue: FaceAlignmentIssue.moveAway,
      );
    }

    final yawDelta = pose.yaw - target.yaw;
    if (yawDelta > AppConstants.alignmentYawHintThreshold) {
      return FaceAlignmentFeedback(
        score: score,
        issue: FaceAlignmentIssue.turnRight,
      );
    }
    if (yawDelta < -AppConstants.alignmentYawHintThreshold) {
      return FaceAlignmentFeedback(
        score: score,
        issue: FaceAlignmentIssue.turnLeft,
      );
    }

    final rollDelta = pose.roll - target.roll;
    if (rollDelta > AppConstants.alignmentRollHintThreshold) {
      return FaceAlignmentFeedback(
        score: score,
        issue: FaceAlignmentIssue.rotateLeft,
      );
    }
    if (rollDelta < -AppConstants.alignmentRollHintThreshold) {
      return FaceAlignmentFeedback(
        score: score,
        issue: FaceAlignmentIssue.rotateRight,
      );
    }

    return FaceAlignmentFeedback(
      score: score,
      issue: score >= AppConstants.alignmentReadyScore
          ? FaceAlignmentIssue.ready
          : FaceAlignmentIssue.fineTune,
    );
  }

  Future<void> dispose() async {
    await _liveDetector.close();
    await _photoDetector.close();
  }

  static double _difference(double actual, double expected, double tolerance) {
    // Face detection jitters by a few pixels between camera frames. A linear
    // penalty makes that normal noise dominate the score and creates an
    // artificial ceiling around 85. Use a soft quadratic penalty: small
    // deviations stay forgiving, while a full tolerance still costs the
    // entire component.
    final normalized = ((actual - expected).abs() / tolerance)
        .clamp(0.0, 1.0)
        .toDouble();
    return normalized * normalized;
  }

  static FacePose _mirrorPose(FacePose pose) {
    double mirror(double value) => 1 - value;
    double? mirrorNullable(double? value) =>
        value == null ? null : mirror(value);
    return FacePose(
      faceCenterX: mirror(pose.faceCenterX),
      faceCenterY: pose.faceCenterY,
      faceWidth: pose.faceWidth,
      faceHeight: pose.faceHeight,
      leftEyeX: mirrorNullable(pose.leftEyeX),
      leftEyeY: pose.leftEyeY,
      rightEyeX: mirrorNullable(pose.rightEyeX),
      rightEyeY: pose.rightEyeY,
      mouthLeftX: mirrorNullable(pose.mouthLeftX),
      mouthLeftY: pose.mouthLeftY,
      mouthRightX: mirrorNullable(pose.mouthRightX),
      mouthRightY: pose.mouthRightY,
      mouthX: mirrorNullable(pose.mouthX),
      mouthY: pose.mouthY,
      eyeDistance: pose.eyeDistance,
      roll: -pose.roll,
      yaw: -pose.yaw,
      leftEyeContour: [
        for (final point in pose.leftEyeContour)
          FaceContourPoint(mirror(point.x), point.y),
      ],
      rightEyeContour: [
        for (final point in pose.rightEyeContour)
          FaceContourPoint(mirror(point.x), point.y),
      ],
      upperLipContour: [
        for (final point in pose.upperLipContour.reversed)
          FaceContourPoint(mirror(point.x), point.y),
      ],
      lowerLipContour: [
        for (final point in pose.lowerLipContour.reversed)
          FaceContourPoint(mirror(point.x), point.y),
      ],
    );
  }

  static FacePose _poseFromFace(Face face, int imageWidth, int imageHeight) {
    final width = imageWidth.toDouble();
    final height = imageHeight.toDouble();
    final leftEye = _normalizedLandmark(
      face,
      FaceLandmarkType.leftEye,
      width,
      height,
    );
    final rightEye = _normalizedLandmark(
      face,
      FaceLandmarkType.rightEye,
      width,
      height,
    );
    final mouthLeft = _normalizedLandmark(
      face,
      FaceLandmarkType.leftMouth,
      width,
      height,
    );
    final mouthRight = _normalizedLandmark(
      face,
      FaceLandmarkType.rightMouth,
      width,
      height,
    );
    final mouthBottom = _normalizedLandmark(
      face,
      FaceLandmarkType.bottomMouth,
      width,
      height,
    );
    final mouthX = mouthLeft != null && mouthRight != null
        ? (mouthLeft.$1 + mouthRight.$1) / 2
        : mouthBottom?.$1;
    final mouthY = mouthLeft != null && mouthRight != null
        ? (mouthLeft.$2 + mouthRight.$2) / 2
        : mouthBottom?.$2;
    final leftEyeContour = _normalizedContour(
      face,
      FaceContourType.leftEye,
      width,
      height,
    );
    final rightEyeContour = _normalizedContour(
      face,
      FaceContourType.rightEye,
      width,
      height,
    );
    // ML Kit returns the four lip edges as separate polylines. Join the
    // matching outer and inner edges in opposite directions so each stored
    // contour is a real closed lip shape instead of two unrelated lines.
    final upperLipTop = _normalizedContour(
      face,
      FaceContourType.upperLipTop,
      width,
      height,
    );
    final upperLipBottom = _normalizedContour(
      face,
      FaceContourType.upperLipBottom,
      width,
      height,
    );
    final lowerLipTop = _normalizedContour(
      face,
      FaceContourType.lowerLipTop,
      width,
      height,
    );
    final lowerLipBottom = _normalizedContour(
      face,
      FaceContourType.lowerLipBottom,
      width,
      height,
    );
    final upperLipContour = [...upperLipTop, ...lowerLipBottom.reversed];
    final lowerLipContour = [...upperLipBottom, ...lowerLipTop.reversed];
    final eyeDistance = leftEye != null && rightEye != null
        ? math.sqrt(
            math.pow(rightEye.$1 - leftEye.$1, 2) +
                math.pow(rightEye.$2 - leftEye.$2, 2),
          )
        : 0.0;

    return FacePose(
      faceCenterX: face.boundingBox.center.dx / width,
      faceCenterY: face.boundingBox.center.dy / height,
      faceWidth: face.boundingBox.width / width,
      faceHeight: face.boundingBox.height / height,
      leftEyeX: leftEye?.$1,
      leftEyeY: leftEye?.$2,
      rightEyeX: rightEye?.$1,
      rightEyeY: rightEye?.$2,
      mouthLeftX: mouthLeft?.$1,
      mouthLeftY: mouthLeft?.$2,
      mouthRightX: mouthRight?.$1,
      mouthRightY: mouthRight?.$2,
      mouthX: mouthX,
      mouthY: mouthY,
      eyeDistance: eyeDistance,
      roll: face.headEulerAngleZ ?? 0,
      yaw: face.headEulerAngleY ?? 0,
      leftEyeContour: leftEyeContour,
      rightEyeContour: rightEyeContour,
      upperLipContour: upperLipContour,
      lowerLipContour: lowerLipContour,
    );
  }

  static (double, double)? _normalizedLandmark(
    Face face,
    FaceLandmarkType type,
    double width,
    double height,
  ) {
    final point = face.landmarks[type]?.position;
    if (point == null) return null;
    return (
      (point.x / width).clamp(0.0, 1.0),
      (point.y / height).clamp(0.0, 1.0),
    );
  }

  static List<FaceContourPoint> _normalizedContour(
    Face face,
    FaceContourType type,
    double width,
    double height,
  ) {
    final points = face.contours[type]?.points;
    if (points == null) return [];
    return [
      for (final point in points)
        FaceContourPoint(
          (point.x / width).clamp(0.0, 1.0),
          (point.y / height).clamp(0.0, 1.0),
        ),
    ];
  }

  static _CameraInputImage? _cameraInputImage({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) {
    final rotation = _inputImageRotation(camera, deviceOrientation);
    if (rotation == null || image.planes.isEmpty) return null;

    final isQuarterTurn = rotation.rawValue == 90 || rotation.rawValue == 270;
    final width = isQuarterTurn ? image.height : image.width;
    final height = isQuarterTurn ? image.width : image.height;

    if (Platform.isAndroid && image.format.group == ImageFormatGroup.nv21) {
      final plane = image.planes.first;
      return _CameraInputImage(
        inputImage: InputImage.fromBytes(
          bytes: plane.bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: rotation,
            format: InputImageFormat.nv21,
            bytesPerRow: plane.bytesPerRow,
          ),
        ),
        width: width,
        height: height,
      );
    }

    if (Platform.isIOS && image.format.group == ImageFormatGroup.bgra8888) {
      final plane = image.planes.first;
      return _CameraInputImage(
        inputImage: InputImage.fromBytes(
          bytes: plane.bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: rotation,
            format: InputImageFormat.bgra8888,
            bytesPerRow: plane.bytesPerRow,
          ),
        ),
        width: width,
        height: height,
      );
    }
    return null;
  }

  static InputImageRotation? _inputImageRotation(
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    const orientations = <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final sensorOrientation = camera.sensorOrientation;
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensorOrientation);
    }
    final compensation = orientations[deviceOrientation];
    if (compensation == null) return null;
    final rotation = camera.lensDirection == CameraLensDirection.front
        ? (sensorOrientation + compensation) % 360
        : (sensorOrientation - compensation + 360) % 360;
    return InputImageRotationValue.fromRawValue(rotation);
  }
}

class _CameraInputImage {
  const _CameraInputImage({
    required this.inputImage,
    required this.width,
    required this.height,
  });

  final InputImage inputImage;
  final int width;
  final int height;
}

_ProcessedImage _processImage({
  required Uint8List bytes,
  required double? leftEyeX,
  required double? leftEyeY,
  required double? rightEyeX,
  required double? rightEyeY,
  required double? faceCenterX,
  required double? faceCenterY,
  required double? faceWidth,
  required double? faceHeight,
  required FaceReference? reference,
  required bool coordinatesNormalized,
  bool mirrorImage = false,
}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image format');
  final source = img.bakeOrientation(decoded);
  if (leftEyeX == null ||
      leftEyeY == null ||
      rightEyeX == null ||
      rightEyeY == null) {
    throw FaceNotFoundException();
  }
  var sourceLeftEyeX = leftEyeX;
  var sourceLeftEyeY = leftEyeY;
  var sourceRightEyeX = rightEyeX;
  var sourceRightEyeY = rightEyeY;
  if (coordinatesNormalized) {
    sourceLeftEyeX *= source.width;
    sourceLeftEyeY *= source.height;
    sourceRightEyeX *= source.width;
    sourceRightEyeY *= source.height;
  }
  final output = alignEyeAnchors(
    source,
    leftX: sourceLeftEyeX,
    leftY: sourceLeftEyeY,
    rightX: sourceRightEyeX,
    rightY: sourceRightEyeY,
    faceCenterX: faceCenterX,
    faceCenterY: faceCenterY,
    faceWidth: faceWidth,
    faceHeight: faceHeight,
    reference: reference,
    mirrorImage: mirrorImage,
  );
  return (
    bytes: Uint8List.fromList(
      img.encodeJpg(output, quality: AppConstants.faceJpegQuality),
    ),
    width: source.width,
    height: source.height,
  );
}

(int, int) _orientedImageSize(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image format');
  final source = img.bakeOrientation(decoded);
  return (source.width, source.height);
}

/// Maps the eye pair to a fixed canvas with one similarity transform.
/// Out-of-image pixels stay black; framing never shifts the eye anchors.
img.Image alignEyeAnchors(
  img.Image source, {
  required double leftX,
  required double leftY,
  required double rightX,
  required double rightY,
  double? faceCenterX,
  double? faceCenterY,
  double? faceWidth,
  double? faceHeight,
  FaceReference? reference,
  double initialEyeDistance = AppConstants.alignmentTargetEyeDistance,
  double initialEyeY = AppConstants.alignmentTargetEyeY,
  int width = AppConstants.faceOutputWidth,
  int height = AppConstants.faceOutputHeight,
  bool mirrorImage = false,
}) {
  // Landmark names can follow anatomical rather than image left/right.
  if (leftX > rightX) {
    (leftX, rightX) = (rightX, leftX);
    (leftY, rightY) = (rightY, leftY);
  }
  final dx = rightX - leftX;
  final dy = rightY - leftY;
  final distance = math.sqrt(dx * dx + dy * dy);
  if (!distance.isFinite || distance <= 0) throw FaceNotFoundException();
  final targetDistance =
      width *
      (reference == null
          ? initialEyeDistance
          : (reference.rightEyeX - reference.leftEyeX).abs());
  if (!targetDistance.isFinite || targetDistance <= 0) {
    throw FaceNotFoundException();
  }
  final targetY =
      height *
      (reference == null
          ? initialEyeY
          : (reference.leftEyeY + reference.rightEyeY) / 2);
  final centerX = (leftX + rightX) / 2;
  final centerY = (leftY + rightY) / 2;
  final targetX =
      width *
      (reference == null
          ? AppConstants.alignmentTargetFaceCenterX
          : (reference.leftEyeX + reference.rightEyeX) / 2);
  final output = img.Image(width: width, height: height);
  // Eye spacing is stable for scale, while the face box keeps the whole head
  // size consistent. Combining both avoids making a small landmark shift
  // resize the entire head, or letting box jitter dominate the eye alignment.
  final scaleEstimates = <(double, double)>[
    (targetDistance / distance, AppConstants.alignmentEyeScaleWeight),
  ];
  if (faceWidth != null && faceWidth.isFinite && faceWidth > 0) {
    final targetFaceWidth = width * (reference?.faceWidth ?? 0);
    if (targetFaceWidth > 0 && targetFaceWidth.isFinite) {
      scaleEstimates.add((
        targetFaceWidth / faceWidth,
        AppConstants.alignmentFaceScaleWeight,
      ));
    }
  }
  if (faceHeight != null && faceHeight.isFinite && faceHeight > 0) {
    final targetFaceHeight = height * (reference?.faceHeight ?? 0);
    if (targetFaceHeight > 0 && targetFaceHeight.isFinite) {
      scaleEstimates.add((
        targetFaceHeight / faceHeight,
        AppConstants.alignmentFaceScaleWeight,
      ));
    }
  }
  var weightedLogScale = 0.0;
  var totalScaleWeight = 0.0;
  for (final (estimate, weight) in scaleEstimates) {
    if (estimate.isFinite && estimate > 0) {
      weightedLogScale += math.log(estimate) * weight;
      totalScaleWeight += weight;
    }
  }
  final scale = math.exp(weightedLogScale / totalScaleWeight);
  if (!scale.isFinite || scale <= 0) throw FaceNotFoundException();
  var alignedTargetX = targetX;
  var alignedTargetY = targetY;
  if (faceCenterX != null &&
      faceCenterY != null &&
      faceCenterX.isFinite &&
      faceCenterY.isFinite &&
      reference != null) {
    final faceOffsetX = faceCenterX - centerX;
    final faceOffsetY = faceCenterY - centerY;
    final cos = dx / distance;
    final sin = dy / distance;
    final outputOffsetX =
        (cos * faceOffsetX + sin * faceOffsetY) *
        scale *
        (mirrorImage ? -1 : 1);
    final outputOffsetY = (-sin * faceOffsetX + cos * faceOffsetY) * scale;
    final expectedFaceX = width * reference.faceCenterX;
    final expectedFaceY = height * reference.faceCenterY;
    // Give face placement and eye placement equal influence, so detector
    // variation in either anchor cannot shift the entire crop on its own.
    alignedTargetX +=
        (expectedFaceX - targetX - outputOffsetX) *
        AppConstants.alignmentFaceCenterWeight;
    alignedTargetY +=
        (expectedFaceY - targetY - outputOffsetY) *
        AppConstants.alignmentFaceCenterWeight;
  }
  final sourcePerOutput = 1 / scale;
  final a = dx / distance * sourcePerOutput;
  final b = dy / distance * sourcePerOutput;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final u = (x - alignedTargetX) * (mirrorImage ? -1 : 1);
      final v = y - alignedTargetY;
      final sx = centerX + a * u - b * v;
      final sy = centerY + b * u + a * v;
      if (sx >= 0 &&
          sy >= 0 &&
          sx < source.width - 1 &&
          sy < source.height - 1) {
        output.setPixel(
          x,
          y,
          source.getPixelInterpolate(
            sx,
            sy,
            interpolation: img.Interpolation.linear,
          ),
        );
      }
    }
  }
  return output;
}

Uint8List _centerCropImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image format');
  final image = img.bakeOrientation(decoded);
  const targetRatio =
      AppConstants.faceOutputWidth / AppConstants.faceOutputHeight;
  final cropWidth = math.min(
    image.width.toDouble(),
    image.height * targetRatio,
  );
  final cropHeight = cropWidth / targetRatio;
  final cropped = img.copyCrop(
    image,
    x: ((image.width - cropWidth) / 2).round(),
    y: ((image.height - cropHeight) / 2).round(),
    width: cropWidth.round(),
    height: cropHeight.round(),
  );
  return Uint8List.fromList(
    img.encodeJpg(cropped, quality: AppConstants.faceJpegQuality),
  );
}
