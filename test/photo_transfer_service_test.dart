import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:phototimelapse/data/services/photo_transfer_service.dart';

void main() {
  test('reads a capture date and duplicate suffix from a file name', () {
    expect(
      PhotoTransferService.capturedAtFromFileName('2026-08-07'),
      DateTime(2026, 8, 7),
    );
    expect(
      PhotoTransferService.capturedAtFromFileName('2026-08-07.jpg'),
      DateTime(2026, 8, 7),
    );
    expect(
      PhotoTransferService.capturedAtFromFileName('2026-08-07(1).jpg'),
      DateTime(2026, 8, 7),
    );
    expect(
      PhotoTransferService.capturedAtFromFileName('2026-08-07(2).jpg'),
      DateTime(2026, 8, 7),
    );
    expect(
      PhotoTransferService.capturedAtFromFileName('2026-02-31.jpg'),
      isNull,
    );
    expect(
      PhotoTransferService.capturedAtFromFileName('IMG_20240720.jpg'),
      isNull,
    );
    expect(PhotoTransferService.capturedAtFromFileName('photo.jpg'), isNull);
    expect(PhotoTransferService.isSupportedImage('photo.PNG'), isTrue);
    expect(PhotoTransferService.isSupportedImage('photo.webp'), isFalse);
  });

  test(
    'reads the capture date from JPEG EXIF before using the file name',
    () async {
      final directory = await Directory.systemTemp.createTemp('photo_dates_');
      final file = File('${directory.path}/photo.jpg');
      final image = img.Image(width: 2, height: 2)
        ..exif.exifIfd['DateTimeOriginal'] = '2026:08:07 12:34:56';
      await file.writeAsBytes(img.encodeJpg(image));

      expect(
        await PhotoTransferService().capturedAt(
          file,
          fileName: '2026-01-01.jpg',
        ),
        DateTime(2026, 8, 7, 12, 34, 56),
      );
      await directory.delete(recursive: true);
    },
  );
}
