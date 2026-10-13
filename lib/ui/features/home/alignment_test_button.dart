import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../data/services/face_alignment_service.dart';
import '../../../data/services/photo_cache_service.dart';
import '../../../data/services/video_export_service.dart';
import '../../../domain/models/daily_photo.dart';
import '../../../domain/models/video_settings.dart';
import '../preview/video_preview_screen.dart';

class AlignmentTestButton extends StatefulWidget {
  const AlignmentTestButton({
    required this.photos,
    required this.alignPhoto,
    required this.photoCache,
    required this.videoExportService,
    super.key,
  });

  final List<DailyPhoto> photos;
  final Future<File> Function(String sourcePath) alignPhoto;
  final PhotoCacheService photoCache;
  final VideoExportService videoExportService;

  @override
  State<AlignmentTestButton> createState() => _AlignmentTestButtonState();
}

class _AlignmentTestButtonState extends State<AlignmentTestButton> {
  static const _photoCount = 20;
  bool _busy = false;
  int _completed = 0;

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _run() async {
    if (_busy) return;
    final strings = AppStrings.of(context);
    if (widget.photos.length < _photoCount) {
      _message(strings.testNeedsTwentyPhotos);
      return;
    }
    final shuffled = [...widget.photos]..shuffle();
    final selected = shuffled.take(_photoCount).toList()
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    setState(() {
      _busy = true;
      _completed = 0;
    });
    final alignedFiles = <File>[];
    var stage = 'second-alignment';
    void report(Object error, StackTrace stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'FaceMorph alignment test',
          context: ErrorDescription('stage=$stage'),
        ),
      );
    }

    try {
      final frames = <DailyPhoto>[];
      for (final photo in selected) {
        if (!mounted) return;
        stage = 'second alignment ${frames.length + 1}/$_photoCount';
        final source = await widget.photoCache.ensureLocal(photo);
        final aligned = await widget.alignPhoto(source.path);
        alignedFiles.add(aligned);
        frames.add(photo.copyWith(localPath: aligned.path));
        if (mounted) setState(() => _completed = frames.length);
      }
      if (!mounted) return;
      stage = 'video-export';
      final video = await widget.videoExportService.export(
        frames,
        settings: VideoSettings(smoothTransition: false),
      );
      var saved = true;
      stage = 'save-to-downloads';
      try {
        await widget.videoExportService.saveToDownloads(video);
      } catch (error, stack) {
        report(error, stack);
        saved = false;
        _message(strings.videoSaveToDownloadsFailed);
      }
      if (!mounted) return;
      stage = 'video-preview';
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              VideoPreviewScreen(file: video, savedToDownloads: saved),
        ),
      );
    } on FaceNotFoundException catch (error, stack) {
      report(error, stack);
      _message(strings.alignmentTrialNoFace);
    } catch (error, stack) {
      report(error, stack);
      _message(strings.exportFailed);
    } finally {
      for (final file in alignedFiles) {
        if (await file.exists()) await file.delete();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : _run,
          icon: const Icon(Icons.science_outlined),
          label: Text(
            !_busy
                ? strings.testTwentyPhotos
                : _completed == _photoCount
                ? strings.exportingVideo
                : '${strings.aligningSelectedPhotos} $_completed/$_photoCount '
                      '(%${(_completed * 100 / _photoCount).round()})',
          ),
        ),
        if (_busy)
          LinearProgressIndicator(
            value: _completed == _photoCount ? null : _completed / _photoCount,
          ),
      ],
    );
  }
}
