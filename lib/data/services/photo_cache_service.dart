import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../config/app_constants.dart';
import '../../domain/models/daily_photo.dart';

class PhotoCacheException implements Exception {
  const PhotoCacheException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PhotoCacheService {
  static const _directoryName = 'photos';
  static const _localUploadMarker = 'local-upload';
  static const _maxAttempts = 3;
  static const _retryDelay = Duration(milliseconds: 300);
  final _inFlight = <String, Future<File>>{};

  Future<List<DailyPhoto>> prepareOwnPhotos(List<DailyPhoto> photos) async {
    final prepared = <DailyPhoto>[];
    for (
      var start = 0;
      start < photos.length;
      start += AppConstants.transferBatchSize
    ) {
      final end = (start + AppConstants.transferBatchSize).clamp(
        0,
        photos.length,
      );
      prepared.addAll(
        await Future.wait(photos.sublist(start, end).map(_prepareOwnPhoto)),
      );
    }
    return prepared;
  }

  Future<List<String>> sourcesForExport(List<DailyPhoto> photos) async {
    final sources = <String>[];
    for (
      var start = 0;
      start < photos.length;
      start += AppConstants.transferBatchSize
    ) {
      final end = (start + AppConstants.transferBatchSize).clamp(
        0,
        photos.length,
      );
      sources.addAll(
        await Future.wait(photos.sublist(start, end).map(_sourceForExport)),
      );
    }
    return sources;
  }

  Future<File> ensureLocal(DailyPhoto photo) async {
    final key = '${photo.ownerId}|${photo.id}|${photo.imageUrl}';
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _ensureLocal(photo);
    _inFlight[key] = future;
    unawaited(
      future.then<void>(
        (_) => _inFlight.remove(key),
        onError: (Object _, StackTrace _) => _inFlight.remove(key),
      ),
    );
    return future;
  }

  Future<File> _ensureLocal(DailyPhoto photo) async {
    final existingPath = photo.localPath;
    if (existingPath != null) {
      final existing = File(existingPath);
      if (await _isUsable(existing)) return existing;
    }

    final target = await _targetFile(photo.ownerId, photo.id);
    final marker = File('${target.path}.source');
    if (await _isUsable(target)) {
      if (!await marker.exists()) return target;
      final markerValue = await marker.readAsString();
      if (markerValue == _localUploadMarker) {
        await marker.writeAsString(photo.imageUrl, flush: true);
        return target;
      }
      if (markerValue == photo.imageUrl) {
        return target;
      }
    }

    if (photo.imageUrl.isEmpty) {
      throw const PhotoCacheException('Photo has no source URL.');
    }
    if (!photo.imageUrl.startsWith('http')) {
      final source = File(photo.imageUrl);
      if (!await _isUsable(source)) {
        throw const PhotoCacheException('Local photo file is missing.');
      }
      await source.copy(target.path);
      await marker.writeAsString(_localUploadMarker, flush: true);
      return target;
    }

    await _download(photo.imageUrl, target, marker);
    return target;
  }

  Future<void> cacheOwnPhoto({
    required File source,
    required String ownerId,
    required DateTime capturedAt,
  }) async {
    final target = await _targetFile(
      ownerId,
      '${ownerId}_${_dayKey(capturedAt)}',
    );
    await source.copy(target.path);
    await File(
      '${target.path}.source',
    ).writeAsString(_localUploadMarker, flush: true);
  }

  Future<void> deleteLocal(DailyPhoto photo) async {
    final target = await _targetFile(photo.ownerId, photo.id);
    for (final file in [
      target,
      File('${target.path}.source'),
      File('${target.path}.part'),
    ]) {
      if (await file.exists()) await file.delete();
    }
  }

  Future<DailyPhoto> _prepareOwnPhoto(DailyPhoto photo) async {
    try {
      final file = await ensureLocal(photo);
      return photo.copyWith(localPath: file.path);
    } catch (_) {
      // The UI can still show the cloud fallback while the cache retries on a
      // later Firestore update or during export.
      return photo;
    }
  }

  Future<String> _sourceForExport(DailyPhoto photo) async {
    if (!photo.isOwned) return photo.source;
    return (await ensureLocal(photo)).path;
  }

  Future<File> _targetFile(String ownerId, String photoId) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}$_directoryName${Platform.pathSeparator}${_safe(ownerId)}',
    );
    await directory.create(recursive: true);
    return File(
      '${directory.path}${Platform.pathSeparator}${_safe(photoId)}.jpg',
    );
  }

  Future<void> _download(String source, File target, File marker) async {
    final partial = File('${target.path}.part');
    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      final client = http.Client();
      try {
        final response = await client
            .send(http.Request('GET', Uri.parse(source)))
            .timeout(AppConstants.transferRequestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw PhotoCacheException(
            'Could not download photo: ${response.statusCode}',
          );
        }
        final sink = partial.openWrite();
        try {
          await response.stream
              .timeout(AppConstants.transferRequestTimeout)
              .pipe(sink);
        } finally {
          await sink.close();
        }
        if (await target.exists()) await target.delete();
        await partial.rename(target.path);
        await marker.writeAsString(source, flush: true);
        return;
      } on TimeoutException catch (error) {
        lastError = error;
      } on SocketException catch (error) {
        lastError = error;
      } on http.ClientException catch (error) {
        lastError = error;
      } finally {
        client.close();
        if (await partial.exists()) await partial.delete();
      }
      if (attempt < _maxAttempts) {
        await Future<void>.delayed(_retryDelay);
      }
    }
    throw PhotoCacheException(
      'Could not cache photo after $_maxAttempts attempts: $lastError',
    );
  }

  static Future<bool> _isUsable(File file) async {
    return await file.exists() && await file.length() > 0;
  }

  static String _safe(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  static String _dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
