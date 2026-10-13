import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../data/services/face_alignment_service.dart';
import '../../app/app_view_model.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    required this.viewModel,
    required this.alignmentService,
    super.key,
  });

  final AppViewModel viewModel;
  final FaceAlignmentService alignmentService;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  FaceAlignmentResult? _alignmentResult;
  FacePose? _livePose;
  bool _processing = false;
  bool _cameraInitializing = false;
  bool _imageAnalysisInProgress = false;
  bool _frontFlashEnabled = false;
  bool _trackFacialFeatures = true;
  bool _showFrontFlash = false;
  int _cameraGeneration = 0;
  DateTime? _lastImageAnalysisAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
  }

  Future<void> _initializeCamera() async {
    if (_cameraInitializing ||
        !mounted ||
        _alignmentResult != null ||
        _controller != null) {
      return;
    }
    _cameraInitializing = true;
    final generation = ++_cameraGeneration;
    if (mounted) setState(() => _error = null);

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('noCamera', 'No camera available');
      }
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );
      await controller.initialize();
      if (!mounted || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      setState(() {});
      await _startFaceStream(controller);
    } catch (error) {
      if (mounted && generation == _cameraGeneration) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (generation == _cameraGeneration) _cameraInitializing = false;
    }
  }

  Future<void> _startFaceStream(CameraController controller) async {
    if (!controller.value.isInitialized || controller.value.isStreamingImages) {
      return;
    }
    try {
      await controller.startImageStream(
        (image) => _analyzeCameraImage(controller, image),
      );
    } on CameraException {
      // Live alignment is helpful, but it must not block taking a photo.
    }
  }

  Future<void> _analyzeCameraImage(
    CameraController controller,
    CameraImage image,
  ) async {
    final now = DateTime.now();
    if (_imageAnalysisInProgress ||
        _processing ||
        !mounted ||
        !identical(_controller, controller) ||
        (_lastImageAnalysisAt != null &&
            now.difference(_lastImageAnalysisAt!) <
                AppConstants.faceLiveAnalysisInterval)) {
      return;
    }
    _lastImageAnalysisAt = now;
    _imageAnalysisInProgress = true;
    try {
      final pose = await widget.alignmentService.analyzeCameraImage(
        image: image,
        camera: controller.description,
        deviceOrientation: controller.value.deviceOrientation,
      );
      if (mounted && identical(_controller, controller) && !_processing) {
        setState(() => _livePose = pose);
      }
    } finally {
      _imageAnalysisInProgress = false;
    }
  }

  Future<void> _disposeCamera() async {
    ++_cameraGeneration;
    final controller = _controller;
    _controller = null;
    _cameraInitializing = false;
    _imageAnalysisInProgress = false;
    _lastImageAnalysisAt = null;
    if (mounted) setState(() {});
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // The controller may already be closing during an app lifecycle change.
    }
    try {
      await controller.dispose();
    } catch (_) {
      // Disposal is best effort; a newer controller can still be initialized.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_disposeCamera());
    } else if (state == AppLifecycleState.resumed && _alignmentResult == null) {
      unawaited(_initializeCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeCamera());
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _processing ||
        _alignmentResult != null) {
      return;
    }
    setState(() {
      _processing = true;
      _error = null;
      _livePose = null;
    });
    FaceAlignmentResult? alignedResult;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      if (_frontFlashEnabled) {
        if (mounted) setState(() => _showFrontFlash = true);
        await Future<void>.delayed(AppConstants.frontFlashDuration);
      }
      final picture = await controller.takePicture();
      alignedResult = await widget.alignmentService.alignWithMetadata(
        picture.path,
        mirrorImage: true,
      );
      await _disposeCamera();
      if (mounted) {
        setState(() => _alignmentResult = alignedResult);
      }
    } on FaceNotFoundException {
      if (mounted) setState(() => _error = AppStrings.of(context).noFace);
    } on CameraException {
      if (mounted) {
        setState(() => _error = AppStrings.of(context).cameraPermission);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppStrings.of(context).captureFailed);
      }
    } finally {
      final discardedFile = _alignmentResult == null
          ? alignedResult?.file
          : null;
      try {
        if (discardedFile != null && await discardedFile.exists()) {
          await discardedFile.delete();
        }
      } catch (_) {}
      if (mounted &&
          _alignmentResult == null &&
          identical(_controller, controller)) {
        await _startFaceStream(controller);
      }
      if (mounted) {
        setState(() {
          _showFrontFlash = false;
          _processing = false;
        });
      }
    }
  }

  Future<void> _retry() async {
    if (_processing) return;
    setState(() {
      _alignmentResult = null;
      _livePose = null;
      _error = null;
    });
    await _disposeCamera();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (mounted) await _initializeCamera();
  }

  Future<void> _save() async {
    final result = _alignmentResult;
    if (result == null) return;
    final isFirstReference = !widget.alignmentService.hasCaptureReference;
    if (isFirstReference) {
      final feedback = widget.alignmentService.feedbackFor(result.pose);
      if (feedback.score < AppConstants.alignmentReferenceMinimumScore ||
          !result.pose.hasLandmarks) {
        setState(
          () => _error = AppStrings.of(context).alignmentReferenceRequired,
        );
        return;
      }
    }
    setState(() => _processing = true);
    try {
      await widget.viewModel.savePhoto(result.file);
      if (isFirstReference) {
        await widget.alignmentService.saveReference(result.pose);
      }
      if (mounted) context.go('/today');
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(
          () => _error = AppStrings.of(context).saveFailedForCode(error.code),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = AppStrings.of(
            context,
          ).saveFailedForCode(error.runtimeType.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  String _messageFor(FaceAlignmentIssue issue, AppStrings strings) =>
      switch (issue) {
        FaceAlignmentIssue.noFace => strings.alignmentNoFace,
        FaceAlignmentIssue.faceCamera => strings.alignmentFaceCamera,
        FaceAlignmentIssue.moveLeft => strings.alignmentMoveLeft,
        FaceAlignmentIssue.moveRight => strings.alignmentMoveRight,
        FaceAlignmentIssue.moveUp => strings.alignmentMoveUp,
        FaceAlignmentIssue.moveDown => strings.alignmentMoveDown,
        FaceAlignmentIssue.moveCloser => strings.alignmentMoveCloser,
        FaceAlignmentIssue.moveAway => strings.alignmentMoveAway,
        FaceAlignmentIssue.turnLeft => strings.alignmentTurnLeft,
        FaceAlignmentIssue.turnRight => strings.alignmentTurnRight,
        FaceAlignmentIssue.rotateLeft => strings.alignmentRotateLeft,
        FaceAlignmentIssue.rotateRight => strings.alignmentRotateRight,
        FaceAlignmentIssue.fineTune => strings.alignmentFineTune,
        FaceAlignmentIssue.ready => strings.alignmentReady,
      };

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final controller = _controller;
    final hasReference = widget.alignmentService.reference != null;
    final showFacialFeatures = _trackFacialFeatures;
    final feedback = widget.alignmentService.feedbackFor(
      _livePose,
      compareFacialFeatures: hasReference && _trackFacialFeatures,
    );
    final target = widget.alignmentService.targetReference;
    final hasPreview = _alignmentResult != null;
    final previewOrientation =
        controller?.value.previewPauseOrientation ??
        controller?.value.lockedCaptureOrientation ??
        controller?.value.deviceOrientation;
    final isPreviewLandscape =
        previewOrientation == DeviceOrientation.landscapeLeft ||
        previewOrientation == DeviceOrientation.landscapeRight;
    final displayedFeedback = hasPreview
        ? widget.alignmentService.feedbackFor(
            _alignmentResult!.pose,
            compareFacialFeatures: hasReference,
          )
        : feedback;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            hasPreview
                ? Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppConstants.photoBorderRadius,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: AspectRatio(
                        aspectRatio:
                            AppConstants.faceOutputWidth /
                            AppConstants.faceOutputHeight,
                        child: Image.file(
                          _alignmentResult!.file,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  )
                : (controller?.value.isInitialized ?? false)
                ? Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppConstants.cameraPreviewBorderRadius,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: AspectRatio(
                        // CameraPreview uses the inverse aspect ratio in
                        // portrait mode. Match its own calculation before
                        // giving it tight constraints; otherwise StackFit
                        // expands the texture and stretches the image.
                        aspectRatio: isPreviewLandscape
                            ? controller!.value.aspectRatio
                            : 1 / controller!.value.aspectRatio,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // The camera plugin already mirrors front-camera
                            // previews, matching the guide's pose coordinates.
                            CameraPreview(controller),
                            _FaceGuide(
                              pose: _livePose,
                              target: target,
                              showFacialFeatures: showFacialFeatures,
                              accentColor: feedback.isReady
                                  ? Colors.greenAccent
                                  : Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      _error ?? strings.cameraInitializing,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
            Positioned(
              left: 16,
              top: 10,
              child: IconButton.filledTonal(
                onPressed: context.pop,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            if (!hasPreview)
              Positioned(
                right: 16,
                bottom: 24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CameraActionButton(
                      label: strings.frontFlash,
                      icon: _frontFlashEnabled
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      active: _frontFlashEnabled,
                      onPressed: _processing
                          ? null
                          : () => setState(
                              () => _frontFlashEnabled = !_frontFlashEnabled,
                            ),
                    ),
                    const SizedBox(height: 10),
                    _CameraActionButton(
                      label: strings.trackFacialFeatures,
                      icon: _trackFacialFeatures
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      active: _trackFacialFeatures,
                      onPressed: _processing
                          ? null
                          : () => setState(
                              () =>
                                  _trackFacialFeatures = !_trackFacialFeatures,
                            ),
                    ),
                  ],
                ),
              ),
            Positioned(
              left: 16,
              top: 68,
              child: _AlignmentStatus(
                score: displayedFeedback.score,
                message: _messageFor(displayedFeedback.issue, strings),
                scoreLabel: strings.alignmentScore(displayedFeedback.score),
                ready: displayedFeedback.isReady,
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: Column(
                children: [
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  if (!hasPreview) ...[
                    GestureDetector(
                      onTap: _capture,
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.black,
                          size: 28,
                        ),
                      ),
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: _processing ? null : _retry,
                            child: Text(strings.retry),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: widget.viewModel.busy ? null : _save,
                            child: Text(strings.save),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (_processing)
              const ColoredBox(
                color: Colors.black45,
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            if (_showFrontFlash) const ColoredBox(color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _AlignmentStatus extends StatelessWidget {
  const _AlignmentStatus({
    required this.score,
    required this.message,
    required this.scoreLabel,
    required this.ready,
  });

  final int score;
  final String message;
  final String scoreLabel;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final color = ready ? Colors.greenAccent : Colors.white;
    return Container(
      width: 166,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  color: color,
                  backgroundColor: Colors.white24,
                  strokeWidth: 3,
                ),
                Text(
                  '%$score',
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          SizedBox(
            width: 116,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  scoreLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraActionButton extends StatelessWidget {
  const _CameraActionButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    toggled: active,
    child: IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, size: 25),
      style: IconButton.styleFrom(
        minimumSize: const Size(52, 52),
        backgroundColor: Colors.black.withValues(alpha: active ? 0.68 : 0.38),
        foregroundColor: active ? Colors.white : Colors.white38,
        disabledForegroundColor: Colors.white24,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}

class _FaceGuide extends StatelessWidget {
  const _FaceGuide({
    required this.pose,
    required this.target,
    required this.showFacialFeatures,
    required this.accentColor,
  });

  final FacePose? pose;
  final FaceReference target;
  final bool showFacialFeatures;
  final Color accentColor;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: CustomPaint(
        painter: _FaceGuidePainter(
          target: target,
          pose: pose,
          showFacialFeatures: showFacialFeatures,
          accentColor: accentColor,
        ),
      ),
    ),
  );
}

class _FaceGuidePainter extends CustomPainter {
  const _FaceGuidePainter({
    required this.target,
    required this.pose,
    required this.showFacialFeatures,
    required this.accentColor,
  });

  final FaceReference target;
  final FacePose? pose;
  final bool showFacialFeatures;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final targetPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final livePaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Show the saved contours when available. Before the first reference is
    // saved, use an eye and lip shape instead of an abstract guide line.
    final targetLeftEye = _point(target.leftEyeX, target.leftEyeY, size);
    final targetRightEye = _point(target.rightEyeX, target.rightEyeY, size);
    final targetMouthLeft = _point(target.mouthLeftX, target.mouthLeftY, size);
    final targetMouthRight = _point(
      target.mouthRightX,
      target.mouthRightY,
      size,
    );
    if (target.leftEyeContour.length > 1) {
      _drawContour(canvas, target.leftEyeContour, size, targetPaint);
    } else {
      _drawGenericEye(
        canvas,
        targetLeftEye,
        target.faceWidth * size.width,
        targetPaint,
      );
    }
    if (target.rightEyeContour.length > 1) {
      _drawContour(canvas, target.rightEyeContour, size, targetPaint);
    } else {
      _drawGenericEye(
        canvas,
        targetRightEye,
        target.faceWidth * size.width,
        targetPaint,
      );
    }
    if (target.upperLipContour.length > 1 ||
        target.lowerLipContour.length > 1) {
      _drawContour(canvas, target.upperLipContour, size, targetPaint);
      _drawContour(canvas, target.lowerLipContour, size, targetPaint);
    } else {
      _drawGenericMouth(canvas, targetMouthLeft, targetMouthRight, targetPaint);
    }

    if (!showFacialFeatures) return;

    final current = pose;
    if (current == null) return;
    if (current.hasEyeLandmarks) {
      final leftEye = _point(current.leftEyeX!, current.leftEyeY!, size);
      final rightEye = _point(current.rightEyeX!, current.rightEyeY!, size);
      if (current.leftEyeContour.length > 1) {
        _drawContour(canvas, current.leftEyeContour, size, livePaint);
      } else {
        _drawGenericEye(
          canvas,
          leftEye,
          current.faceWidth * size.width,
          livePaint,
        );
      }
      if (current.rightEyeContour.length > 1) {
        _drawContour(canvas, current.rightEyeContour, size, livePaint);
      } else {
        _drawGenericEye(
          canvas,
          rightEye,
          current.faceWidth * size.width,
          livePaint,
        );
      }
    }
    if (current.hasMouthLandmarks) {
      final mouthLeft = _point(
        current.mouthLeftX ?? current.mouthX!,
        current.mouthLeftY ?? current.mouthY!,
        size,
      );
      final mouthRight = _point(
        current.mouthRightX ?? current.mouthX!,
        current.mouthRightY ?? current.mouthY!,
        size,
      );
      if (current.upperLipContour.length > 1 ||
          current.lowerLipContour.length > 1) {
        _drawContour(canvas, current.upperLipContour, size, livePaint);
        _drawContour(canvas, current.lowerLipContour, size, livePaint);
      } else {
        _drawGenericMouth(canvas, mouthLeft, mouthRight, livePaint);
      }
    }
  }

  static Offset _point(double x, double y, Size size) =>
      Offset(x * size.width, y * size.height);

  static void _drawContour(
    Canvas canvas,
    List<FaceContourPoint> points,
    Size size,
    Paint paint,
  ) {
    if (points.length < 2) return;
    final path = Path()
      ..moveTo(points.first.x * size.width, points.first.y * size.height);
    for (final point in points.skip(1)) {
      path.lineTo(point.x * size.width, point.y * size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  static void _drawGenericEye(
    Canvas canvas,
    Offset center,
    double faceWidth,
    Paint paint,
  ) {
    final eyeWidth = (faceWidth * 0.18).clamp(18.0, 44.0).toDouble();
    final halfWidth = eyeWidth / 2;
    final eyeHeight = (eyeWidth * 0.34).clamp(6.0, 14.0).toDouble();
    final path = Path()
      ..moveTo(center.dx - halfWidth, center.dy)
      ..cubicTo(
        center.dx - eyeWidth * 0.22,
        center.dy - eyeHeight,
        center.dx + eyeWidth * 0.22,
        center.dy - eyeHeight,
        center.dx + halfWidth,
        center.dy,
      )
      ..cubicTo(
        center.dx + eyeWidth * 0.22,
        center.dy + eyeHeight,
        center.dx - eyeWidth * 0.22,
        center.dy + eyeHeight,
        center.dx - halfWidth,
        center.dy,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  static void _drawGenericMouth(
    Canvas canvas,
    Offset left,
    Offset right,
    Paint paint,
  ) {
    final width = (right.dx - left.dx).abs();
    if (width < 2) return;
    final center = Offset((left.dx + right.dx) / 2, (left.dy + right.dy) / 2);
    final upperHeight = (width * 0.25).clamp(4.0, 14.0).toDouble();
    final lowerHeight = (width * 0.20).clamp(3.0, 11.0).toDouble();
    final path = Path()
      ..moveTo(left.dx, center.dy)
      ..cubicTo(
        left.dx + width * 0.25,
        center.dy - upperHeight,
        right.dx - width * 0.25,
        center.dy - upperHeight,
        right.dx,
        center.dy,
      )
      ..cubicTo(
        right.dx - width * 0.25,
        center.dy + lowerHeight,
        left.dx + width * 0.25,
        center.dy + lowerHeight,
        left.dx,
        center.dy,
      )
      ..close();
    canvas.drawPath(path, paint);

    final innerPath = Path()
      ..moveTo(left.dx + width * 0.12, center.dy)
      ..quadraticBezierTo(
        center.dx,
        center.dy + lowerHeight * 0.25,
        right.dx - width * 0.12,
        center.dy,
      );
    canvas.drawPath(innerPath, paint);
  }

  @override
  bool shouldRepaint(_FaceGuidePainter oldDelegate) =>
      oldDelegate.target != target ||
      oldDelegate.pose != pose ||
      oldDelegate.showFacialFeatures != showFacialFeatures ||
      oldDelegate.accentColor != accentColor;
}
