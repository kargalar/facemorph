import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../data/services/video_export_service.dart';
import '../../../../domain/models/daily_photo.dart';
import '../../../../domain/models/video_settings.dart';

class PreviewViewModel extends ChangeNotifier {
  PreviewViewModel(List<DailyPhoto> sourcePhotos, this._videoExportService)
    : photos = List.unmodifiable(sourcePhotos);

  final List<DailyPhoto> photos;
  final VideoExportService _videoExportService;
  bool _exporting = false;
  String? _error;

  bool get exporting => _exporting;
  String? get error => _error;

  Future<File?> export(VideoSettings settings) async {
    if (_exporting) return null;
    _exporting = true;
    _error = null;
    notifyListeners();
    try {
      return await _videoExportService.export(photos, settings: settings);
    } catch (error) {
      _error = error.toString();
      return null;
    } finally {
      _exporting = false;
      notifyListeners();
    }
  }

  Future<void> saveToDownloads(File file) =>
      _videoExportService.saveToDownloads(file);
}
