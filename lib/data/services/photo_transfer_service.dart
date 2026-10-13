import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../config/app_constants.dart';
import '../../domain/models/daily_photo.dart';
import 'photo_cache_service.dart';

class PhotoTransferException implements Exception {
  const PhotoTransferException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PhotoImportItem {
  const PhotoImportItem({required this.file, required this.capturedAt});

  final File file;
  final DateTime capturedAt;
}

/// Creates a small, date-preserving ZIP backup without keeping all images in RAM.
class PhotoTransferService {
  PhotoTransferService([PhotoCacheService? photoCache])
    : _photoCache = photoCache ?? PhotoCacheService();

  static const _manifestName = 'manifest.json';
  static const _backupVersion = 1;
  final PhotoCacheService _photoCache;

  static DateTime? capturedAtFromFileName(String fileName) {
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:\(\d+\))?(?:\.[^.]+)?$',
    ).firstMatch(fileName);
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    if (day == null || month == null || year == null) return null;
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  Future<DateTime?> capturedAt(File file, {String? fileName}) async {
    DateTime? exifDate;
    try {
      final exif = img.decodeJpgExif(await file.readAsBytes());
      final ifd0 = exif?['ifd0'];
      final value = ifd0 == null
          ? null
          : (ifd0.sub.containsKey('exif')
                    ? ifd0.sub['exif']['DateTimeOriginal']?.toString()
                    : null) ??
                ifd0['DateTime']?.toString();
      exifDate = _capturedAtFromExif(value);
    } catch (_) {
      // Filename dates still work for files without readable EXIF data.
    }
    return exifDate ??
        capturedAtFromFileName(
          fileName ?? file.path.split(Platform.pathSeparator).last,
        );
  }

  static DateTime? _capturedAtFromExif(String? value) {
    if (value == null) return null;
    final match = RegExp(
      r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(value.trim());
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    final hour = int.tryParse(match.group(4)!);
    final minute = int.tryParse(match.group(5)!);
    final second = int.tryParse(match.group(6)!);
    if ([year, month, day, hour, minute, second].any((part) => part == null)) {
      return null;
    }
    final date = DateTime(year!, month!, day!, hour!, minute!, second!);
    return date.year == year &&
            date.month == month &&
            date.day == day &&
            date.hour == hour &&
            date.minute == minute &&
            date.second == second
        ? date
        : null;
  }

  Future<File> exportPhotos(List<DailyPhoto> photos) async {
    if (photos.isEmpty) {
      throw const PhotoTransferException('There are no photos to export.');
    }

    final temporaryRoot = await getTemporaryDirectory();
    final workDirectory = Directory(
      '${temporaryRoot.path}${Platform.pathSeparator}oneframe_backup_${DateTime.now().microsecondsSinceEpoch}',
    );
    await workDirectory.create(recursive: true);
    final ordered = photos.reversed.toList();
    final client = http.Client();
    final frames = <_BackupFrame>[];
    try {
      for (
        var start = 0;
        start < ordered.length;
        start += AppConstants.transferBatchSize
      ) {
        final end = (start + AppConstants.transferBatchSize).clamp(
          0,
          ordered.length,
        );
        final batch = await Future.wait([
          for (var index = start; index < end; index++)
            _downloadFrame(ordered[index], workDirectory, client),
        ]);
        frames.addAll(batch);
      }

      final manifest = File(
        '${workDirectory.path}${Platform.pathSeparator}$_manifestName',
      );
      await manifest.writeAsString(
        jsonEncode({
          'version': _backupVersion,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'photos': [
            for (final frame in frames)
              {
                'file': 'photos/${frame.fileName}',
                'capturedAt': frame.photo.capturedAt.toUtc().toIso8601String(),
              },
          ],
        }),
        flush: true,
      );

      final documents = await getApplicationDocumentsDirectory();
      final output = File(
        '${documents.path}${Platform.pathSeparator}oneframe_photos_${DateTime.now().millisecondsSinceEpoch}.zip',
      );
      final encoder = ZipFileEncoder();
      encoder.create(output.path, level: ZipFileEncoder.gzip);
      try {
        for (final frame in frames) {
          await encoder.addFile(frame.file, 'photos/${frame.fileName}');
        }
        await encoder.addFile(manifest, _manifestName);
        await encoder.close();
      } catch (_) {
        try {
          await encoder.close();
        } catch (_) {
          // Keep the original export error.
        }
        rethrow;
      }
      return output;
    } finally {
      client.close();
      if (await workDirectory.exists()) {
        await workDirectory.delete(recursive: true);
      }
    }
  }

  Future<List<PhotoImportItem>> importPhotos(File archiveFile) async {
    if (!await archiveFile.exists()) {
      throw const PhotoTransferException('Backup file was not found.');
    }
    final temporaryRoot = await getTemporaryDirectory();
    final extractionDirectory = Directory(
      '${temporaryRoot.path}${Platform.pathSeparator}oneframe_import_${DateTime.now().microsecondsSinceEpoch}',
    );
    await extractionDirectory.create(recursive: true);
    final input = InputFileStream(archiveFile.path);
    var completed = false;
    try {
      final archive = ZipDecoder().decodeStream(input);
      Map<String, dynamic>? manifest;
      final extracted = <String, File>{};
      for (final entry in archive) {
        if (!entry.isFile) continue;
        if (entry.name == _manifestName) {
          final bytes = entry.readBytes();
          if (bytes == null) continue;
          final decoded = jsonDecode(utf8.decode(bytes));
          if (decoded is Map<String, dynamic>) manifest = decoded;
          continue;
        }
        if (!entry.name.startsWith('photos/') ||
            !isSupportedImage(entry.name)) {
          continue;
        }
        final fileName = _safeFileName(entry.name);
        final output = File(
          '${extractionDirectory.path}${Platform.pathSeparator}$fileName',
        );
        final outputStream = OutputFileStream(output.path);
        entry.writeContent(outputStream);
        outputStream.closeSync();
        extracted[entry.name] = output;
      }

      if (manifest?['version'] != _backupVersion ||
          manifest?['photos'] is! List) {
        throw const PhotoTransferException(
          'This is not a FaceMorph photo backup.',
        );
      }

      final items = <PhotoImportItem>[];
      for (final raw in manifest!['photos'] as List) {
        if (raw is! Map<String, dynamic>) continue;
        final archivePath = raw['file'] as String?;
        final capturedAtValue = raw['capturedAt'] as String?;
        if (archivePath == null || capturedAtValue == null) continue;
        final file = extracted[archivePath];
        final capturedAt = DateTime.tryParse(capturedAtValue);
        if (file == null || capturedAt == null) continue;
        items.add(
          PhotoImportItem(file: file, capturedAt: capturedAt.toLocal()),
        );
      }
      if (items.isEmpty) {
        throw const PhotoTransferException('No photos found in the backup.');
      }
      completed = true;
      return items;
    } catch (error) {
      if (error is PhotoTransferException) rethrow;
      throw PhotoTransferException('Could not read the photo backup: $error');
    } finally {
      await input.close();
      if (!completed && await extractionDirectory.exists()) {
        await extractionDirectory.delete(recursive: true);
      }
    }
  }

  Future<void> cleanupImportedPhotos(Iterable<PhotoImportItem> items) async {
    final files = items.map((item) => item.file).toSet();
    for (final file in files) {
      if (await file.exists()) await file.delete();
    }
    final directories = files.map((file) => file.parent).toSet();
    for (final directory in directories) {
      if (await directory.exists() && directory.listSync().isEmpty) {
        await directory.delete();
      }
    }
  }

  Future<_BackupFrame> _downloadFrame(
    DailyPhoto photo,
    Directory directory,
    http.Client client,
  ) async {
    final fileName =
        'FaceMorph_${DateFormat('MM-dd-yyyy_HH-mm').format(photo.capturedAt)}.jpg';
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    final source = photo.isOwned
        ? (await _photoCache.ensureLocal(photo)).path
        : photo.source;
    if (source.startsWith('http')) {
      await _downloadToFile(source, file, client);
    } else {
      await File(source).copy(file.path);
    }
    return _BackupFrame(photo: photo, file: file, fileName: fileName);
  }

  Future<void> _downloadToFile(
    String source,
    File target,
    http.Client client,
  ) async {
    final response = await client
        .send(http.Request('GET', Uri.parse(source)))
        .timeout(AppConstants.transferRequestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PhotoTransferException(
        'Could not download photo: ${response.statusCode}',
      );
    }
    final sink = target.openWrite();
    try {
      await response.stream
          .timeout(AppConstants.transferRequestTimeout)
          .pipe(sink);
    } finally {
      await sink.close();
    }
  }

  static bool isSupportedImage(String path) {
    final name = path.toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png');
  }

  static String _safeFileName(String archivePath) {
    final name = archivePath.split('/').last;
    if (name.isEmpty || name == '.' || name == '..') {
      throw const PhotoTransferException('Invalid photo name in backup.');
    }
    return name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }
}

class _BackupFrame {
  const _BackupFrame({
    required this.photo,
    required this.file,
    required this.fileName,
  });

  final DailyPhoto photo;
  final File file;
  final String fileName;
}
