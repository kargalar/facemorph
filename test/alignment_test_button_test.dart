import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phototimelapse/core/l10n/app_strings.dart';
import 'package:phototimelapse/data/services/photo_cache_service.dart';
import 'package:phototimelapse/data/services/video_export_service.dart';
import 'package:phototimelapse/domain/models/daily_photo.dart';
import 'package:phototimelapse/domain/models/video_settings.dart';
import 'package:phototimelapse/ui/features/home/alignment_test_button.dart';

class _Export extends VideoExportService {
  List<DailyPhoto>? received;

  @override
  Future<File> export(
    List<DailyPhoto> photos, {
    required VideoSettings settings,
  }) async {
    received = photos;
    throw const VideoExportException('Test failure');
  }
}

class _Cache extends PhotoCacheService {
  @override
  Future<File> ensureLocal(DailyPhoto photo) async => File(photo.imageUrl);
}

var alignmentCalls = 0;

Future<File> _align(String sourcePath) async {
  alignmentCalls++;
  return File('$sourcePath.second.jpg');
}

void main() {
  testWidgets('twenty photo test applies its second alignment pass', (
    tester,
  ) async {
    final service = _Export();
    alignmentCalls = 0;
    final photos = List.generate(
      20,
      (index) => DailyPhoto(
        id: '$index',
        ownerId: 'test',
        ownerName: 'test',
        ownerAvatarUrl: null,
        imageUrl: 'stored/$index.jpg',
        capturedAt: DateTime(2026, 1, index + 1),
        isPublic: false,
        likeCount: 0,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStringsDelegate()],
        home: Scaffold(
          body: AlignmentTestButton(
            photos: photos,
            alignPhoto: _align,
            photoCache: _Cache(),
            videoExportService: service,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(OutlinedButton));
    for (
      var attempt = 0;
      attempt < 100 && service.received == null;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump();
    expect(tester.takeException(), isA<VideoExportException>());
    expect(alignmentCalls, 20);
    expect(service.received, hasLength(20));
    expect(
      service.received!.map((photo) => photo.imageUrl),
      orderedEquals(photos.map((photo) => photo.imageUrl)),
    );
    expect(service.received!.every((photo) => photo.localPath != null), isTrue);
  });
}
