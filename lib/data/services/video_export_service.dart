import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../config/app_constants.dart';
import 'photo_cache_service.dart';
import '../../domain/models/daily_photo.dart';
import '../../domain/models/video_settings.dart';

class VideoExportException implements Exception {
  const VideoExportException(this.message);
  final String message;

  @override
  String toString() => message;
}

class VideoExportService {
  VideoExportService([PhotoCacheService? photoCache])
    : _photoCache = photoCache ?? PhotoCacheService();

  static const _downloadsChannel = MethodChannel('app.facemorph/file-export');
  static const _maxFrameDownloadAttempts = 3;
  static const _frameRetryDelay = Duration(milliseconds: 300);
  final PhotoCacheService _photoCache;

  Future<File> export(
    List<DailyPhoto> photos, {
    required VideoSettings settings,
  }) async {
    if (photos.length < 2) {
      throw const VideoExportException('At least two frames are required.');
    }
    final temporaryRoot = await getTemporaryDirectory();
    final framesDirectory = Directory(
      '${temporaryRoot.path}${Platform.pathSeparator}oneframe_export_${DateTime.now().microsecondsSinceEpoch}',
    );
    await framesDirectory.create(recursive: true);

    final ordered = [...photos]
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    File? output;
    try {
      final sources = await _photoCache.sourcesForExport(ordered);
      for (
        var start = 0;
        start < ordered.length;
        start += AppConstants.videoDownloadBatchSize
      ) {
        final end = (start + AppConstants.videoDownloadBatchSize).clamp(
          0,
          ordered.length,
        );
        await Future.wait([
          for (var index = start; index < end; index++)
            _writeFrame(sources[index], index, framesDirectory),
        ]);
      }

      final documents = await getApplicationDocumentsDirectory();
      output = File(
        '${documents.path}${Platform.pathSeparator}oneframe_${DateTime.now().microsecondsSinceEpoch}.mp4',
      );
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-framerate',
        '1000/${settings.photoDuration.inMilliseconds}',
        '-i',
        '${framesDirectory.path}${Platform.pathSeparator}frame_%06d.jpg',
        '-vf',
        videoFilter(settings),
        '-t',
        '${settings.photoSeconds * photos.length}',
        '-sws_flags',
        'fast_bilinear',
        '-c:v',
        'mpeg4',
        '-q:v',
        '5',
        '-threads',
        '0',
        '-r',
        '${settings.frameRate}',
        '-movflags',
        '+faststart',
        output.path,
      ]);
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getOutput();
        throw VideoExportException(logs ?? 'Video export failed.');
      }
      return output;
    } catch (_) {
      if (output != null && await output.exists()) {
        await output.delete();
      }
      rethrow;
    } finally {
      if (await framesDirectory.exists()) {
        await framesDirectory.delete(recursive: true);
      }
    }
  }

  Future<void> saveToDownloads(File video) async {
    if (Platform.isAndroid) {
      await _downloadsChannel.invokeMethod<void>('saveToDownloads', {
        'sourcePath': video.path,
        'fileName': video.uri.pathSegments.last,
      });
      return;
    }

    final directory =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    await directory.create(recursive: true);
    await video.copy(
      '${directory.path}${Platform.pathSeparator}${video.uri.pathSegments.last}',
    );
  }

  static String videoFilter(VideoSettings settings) => [
    'scale=${AppConstants.videoOutputWidth}:${AppConstants.videoOutputHeight}:force_original_aspect_ratio=decrease',
    'pad=${AppConstants.videoOutputWidth}:${AppConstants.videoOutputHeight}:(ow-iw)/2:(oh-ih)/2',
    'setsar=1',
    'format=yuv420p',
    // ponytail: crossfade only; landmark warping needs a separate morph renderer.
    if (settings.smoothTransition)
      'framerate=fps=${settings.frameRate}:interp_start=0:interp_end=255:flags=0'
    else
      'fps=${settings.frameRate}',
  ].join(',');

  Future<void> _writeFrame(
    String source,
    int index,
    Directory directory,
  ) async {
    final name = 'frame_${index.toString().padLeft(6, '0')}.jpg';
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    if (!source.startsWith('http')) {
      await File(source).copy(file.path);
      return;
    }

    Object? lastError;
    for (var attempt = 1; attempt <= _maxFrameDownloadAttempts; attempt++) {
      final client = http.Client();
      try {
        final response = await client
            .send(http.Request('GET', Uri.parse(source)))
            .timeout(AppConstants.transferRequestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw VideoExportException(
            'Could not download frame ${index + 1}: ${response.statusCode}',
          );
        }
        final sink = file.openWrite();
        try {
          await response.stream
              .timeout(AppConstants.transferRequestTimeout)
              .pipe(sink);
        } finally {
          await sink.close();
        }
        return;
      } on TimeoutException catch (error) {
        lastError = error;
      } on SocketException catch (error) {
        lastError = error;
      } on http.ClientException catch (error) {
        lastError = error;
      } finally {
        client.close();
      }
      if (attempt < _maxFrameDownloadAttempts) {
        await Future<void>.delayed(_frameRetryDelay);
      }
    }
    throw VideoExportException(
      'Could not download frame ${index + 1} after '
      '$_maxFrameDownloadAttempts attempts: $lastError',
    );
  }
}
