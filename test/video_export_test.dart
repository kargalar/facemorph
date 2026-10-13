import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';
import 'package:phototimelapse/core/l10n/app_strings.dart';
import 'package:phototimelapse/data/services/video_export_service.dart';
import 'package:phototimelapse/domain/models/daily_photo.dart';
import 'package:phototimelapse/domain/models/video_settings.dart';
import 'package:phototimelapse/ui/features/preview/preview_screen.dart';
import 'package:phototimelapse/ui/features/preview/view_models/preview_view_model.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  testWidgets('preview needs no export and passes edited settings to export', (
    tester,
  ) async {
    final service = _RecordingExportService();
    final directory = Directory.systemTemp.createTempSync(
      'oneframe_preview_test_',
    );
    final file = File('${directory.path}/photo.jpg')
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 32, height: 40)));
    final viewModel = PreviewViewModel([
      for (var day = 2; day > 0; day--)
        DailyPhoto(
          id: '$day',
          ownerId: 'test',
          ownerName: 'test',
          ownerAvatarUrl: null,
          imageUrl: file.path,
          capturedAt: DateTime(2026, 1, day),
          isPublic: false,
          likeCount: 0,
        ),
    ], service);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStringsDelegate()],
        home: PreviewScreen(viewModel: viewModel),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(service.settings, isNull);
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextFormField), '0,01');
    await tester.pump();
    expect(find.text('Video duration: 0.02 s'), findsOneWidget);
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), '0');
    await tester.pump();
    await tester.ensureVisible(find.text('Create and share video'));
    await tester.tap(find.text('Create and share video'));
    await tester.pump();
    expect(service.settings, isNull);
    expect(find.text('Enter a duration between 0.01 and 1.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '0,01');
    await tester.pump();
    await tester.ensureVisible(find.text('Create and share video'));
    await tester.tap(find.text('Create and share video'));
    await tester.pump();
    expect(service.settings!.photoSeconds, 0.01);
    expect(service.settings!.smoothTransition, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    viewModel.dispose();
    directory.deleteSync(recursive: true);
  });

  test('durations are validated and photo boundaries keep every frame', () {
    for (final invalid in [
      0.0,
      -1.0,
      0.009,
      1.01,
      double.nan,
      double.infinity,
    ]) {
      expect(() => VideoSettings(photoSeconds: invalid), throwsArgumentError);
    }
    for (final seconds in [0.01, 0.03, 0.2, 0.22, 1.0]) {
      final settings = VideoSettings(photoSeconds: seconds);
      expect(
        settings.photoSeconds * settings.frameRate,
        closeTo((settings.photoSeconds * settings.frameRate).round(), 0.00001),
      );
      expect(settings.frameRate, inInclusiveRange(30, 100));
      expect(settings.duration(3).inMilliseconds, (seconds * 3000).round());
    }
    expect(VideoSettings(photoSeconds: 0.225).photoSeconds, 0.23);
  });

  test(
    'FFmpeg preserves duration, final frame and blends only when enabled',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'oneframe_video_test_',
      );
      try {
        for (var index = 0; index < 3; index++) {
          final frame = img.Image(width: 32, height: 40);
          img.fill(
            frame,
            color: index == 0
                ? img.ColorRgb8(255, 0, 0)
                : img.ColorRgb8(0, 0, 255),
          );
          await File(
            '${directory.path}/frame_${index.toString().padLeft(6, '0')}.jpg',
          ).writeAsBytes(img.encodeJpg(frame));
        }
        for (final seconds in [0.01, 0.2, 0.22]) {
          for (final smooth in [false, true]) {
            final settings = VideoSettings(
              photoSeconds: seconds,
              smoothTransition: smooth,
            );
            final output = '${directory.path}/output.mp4';
            final result = await Process.run('ffmpeg', [
              '-v',
              'error',
              '-y',
              '-framerate',
              '1000/${settings.photoDuration.inMilliseconds}',
              '-i',
              '${directory.path}/frame_%06d.jpg',
              '-vf',
              VideoExportService.videoFilter(settings),
              '-t',
              '${settings.photoSeconds * 2}',
              '-c:v',
              'mpeg4',
              '-q:v',
              '5',
              '-r',
              '${settings.frameRate}',
              output,
            ]);
            expect(result.exitCode, 0, reason: '${result.stderr}');
            final decoded = await Process.run('ffmpeg', [
              '-v',
              'error',
              '-i',
              output,
              '-vf',
              'scale=1:1',
              '-f',
              'rawvideo',
              '-pix_fmt',
              'rgb24',
              '-',
            ], stdoutEncoding: null);
            expect(decoded.exitCode, 0, reason: '${decoded.stderr}');
            final pixels = decoded.stdout as List<int>;
            expect(
              pixels.length ~/ 3,
              (seconds * 2 * settings.frameRate).round(),
            );
            expect(pixels[0], greaterThan(220));
            expect(pixels[pixels.length - 1], greaterThan(220));
            if (seconds == 0.2) {
              final midpoint = 3 * (seconds * settings.frameRate / 2).round();
              expect(
                pixels[midpoint],
                smooth ? inInclusiveRange(90, 170) : greaterThan(220),
              );
              expect(
                pixels[midpoint + 2],
                smooth ? inInclusiveRange(90, 170) : lessThan(30),
              );
            }
          }
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
    skip: Platform.environment['ONEFRAME_TEST_FFMPEG'] != '1'
        ? 'Set ONEFRAME_TEST_FFMPEG=1 with desktop FFmpeg installed.'
        : false,
  );
}

class _RecordingExportService extends VideoExportService {
  VideoSettings? settings;

  @override
  Future<File> export(
    List<DailyPhoto> photos, {
    required VideoSettings settings,
  }) async {
    this.settings = settings;
    throw const VideoExportException('Test export failure');
  }
}
