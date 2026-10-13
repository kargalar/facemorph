import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../config/app_constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/widgets/photo_image.dart';
import '../../../data/services/face_alignment_service.dart';
import '../../../data/services/photo_transfer_service.dart';
import '../../app/app_view_model.dart';
import '../../core/app_shell.dart';

typedef _PhotoSource = ({File? file, String name, bool temporary, String? uri});

const _photoFolderChannel = MethodChannel('app.facemorph/photo-folder');
const _reviewTileMaxWidth = 180.0;

class PhotoTransferScreen extends StatefulWidget {
  const PhotoTransferScreen({
    required this.viewModel,
    required this.transferService,
    required this.alignmentService,
    super.key,
  });

  final AppViewModel viewModel;
  final PhotoTransferService transferService;
  final FaceAlignmentService alignmentService;

  @override
  State<PhotoTransferScreen> createState() => _PhotoTransferScreenState();
}

class _PhotoTransferScreenState extends State<PhotoTransferScreen> {
  bool _busy = false;
  bool _exportOperation = false;
  String? _error;

  bool _canImport() {
    if (widget.alignmentService.hasCaptureReference) return true;
    setState(() => _error = AppStrings.of(context).captureBeforeImport);
    return false;
  }

  Future<void> _export() async {
    if (_busy || widget.viewModel.photos.isEmpty) return;
    setState(() {
      _busy = true;
      _exportOperation = true;
      _error = null;
    });
    try {
      final file = await widget.transferService.exportPhotos(
        widget.viewModel.photos,
      );
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          title: AppStrings.of(context).appName,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy || !_canImport()) return;
    setState(() {
      _busy = true;
      _exportOperation = false;
      _error = null;
    });
    final imported = <PhotoImportItem>[];
    File? materializedArchive;
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (picked == null) return;
      final archive = await _materializePickedFile(picked);
      if (picked.path == null) materializedArchive = archive;
      imported.addAll(await widget.transferService.importPhotos(archive));
      await widget.viewModel.saveImportedPhotos(imported);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).photosImportedCount(imported.length),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      await widget.transferService.cleanupImportedPhotos(imported);
      if (materializedArchive != null && await materializedArchive.exists()) {
        await materializedArchive.delete();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importExternalFiles() => _selectAndReview(() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
    );
    return Future.wait([for (final file in picked) _materializeImage(file)]);
  });

  Future<void> _importFolder() => _selectAndReview(() async {
    final strings = AppStrings.of(context);
    if (Platform.isAndroid) {
      final picked = await _photoFolderChannel.invokeMethod<List<dynamic>>(
        'pickPhotoFolder',
      );
      if (picked == null) return const [];
      final files = [
        for (final item in picked)
          if (item is Map && item['uri'] is String && item['name'] is String)
            (
              file: null,
              name: item['name'] as String,
              temporary: true,
              uri: item['uri'] as String,
            ),
      ];
      if (files.isEmpty) {
        throw PhotoTransferException(strings.noImagesInFolder);
      }
      return files;
    }

    final path = await FilePicker.getDirectoryPath();
    if (path == null) return const [];
    final files = <_PhotoSource>[];
    await for (final entity in Directory(
      path,
    ).list(recursive: true, followLinks: false)) {
      if (entity is File &&
          PhotoTransferService.isSupportedImage(entity.path)) {
        files.add((
          file: entity,
          name: entity.uri.pathSegments.last,
          temporary: false,
          uri: null,
        ));
      }
    }
    if (files.isEmpty) {
      throw PhotoTransferException(strings.noImagesInFolder);
    }
    return files;
  });

  Future<void> _selectAndReview(
    Future<List<_PhotoSource>> Function() pick,
  ) async {
    if (_busy || !_canImport()) return;
    setState(() {
      _busy = true;
      _exportOperation = false;
      _error = null;
    });
    var sources = <_PhotoSource>[];
    try {
      sources = await pick();
      if (sources.isEmpty) return;
      if (!mounted) return;
      final importedCount = await Navigator.of(context).push<int>(
        MaterialPageRoute(
          builder: (_) => _PhotoImportReviewScreen(
            sources: sources,
            viewModel: widget.viewModel,
            transferService: widget.transferService,
            alignmentService: widget.alignmentService,
          ),
        ),
      );
      if (mounted && importedCount != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).photosImportedCount(importedCount),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PhotoTransferException
              ? error.message
              : AppStrings.of(context).importFailed,
        );
      }
    } finally {
      for (final source in sources.where((source) => source.temporary)) {
        if (source.file != null && await source.file!.exists()) {
          await source.file!.delete();
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_PhotoSource> _materializeImage(PlatformFile picked) async {
    final path = picked.path;
    if (path != null) {
      return (file: File(path), name: picked.name, temporary: false, uri: null);
    }
    return (
      file: await _materializePickedFile(picked),
      name: picked.name,
      temporary: true,
      uri: null,
    );
  }

  Future<File> _materializePickedFile(PlatformFile picked) async {
    final path = picked.path;
    if (path != null) return File(path);
    final bytes = await picked.readAsBytes();
    final directory = await getTemporaryDirectory();
    final extension = picked.extension ?? 'tmp';
    final file = File(
      '${directory.path}${Platform.pathSeparator}oneframe_import_${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final hasPhotos = widget.viewModel.photos.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(strings.photoTransfer)),
      body: ConstrainedPage(
        child: ListView(
          children: [
            Text(
              strings.photoTransferHint,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 22),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.viewModel.photos.length} ${strings.frames}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(strings.photoTransferHint),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _busy || !hasPhotos ? null : _export,
                      icon: const Icon(Icons.upload_rounded),
                      label: Text(strings.exportPhotos),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _importExternalFiles,
                      icon: const Icon(Icons.photo_library_rounded),
                      label: Text(strings.importExternalPhotos),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _importFolder,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: Text(strings.importPhotoFolder),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _import,
                      icon: const Icon(Icons.download_rounded),
                      label: Text(strings.importPhotos),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 18),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                _exportOperation
                    ? strings.exportingPhotos
                    : strings.importingPhotos,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImportReviewItem {
  _ImportReviewItem({
    required this.file,
    required this.name,
    required this.capturedAt,
    required this.dateDetected,
  });

  final File file;
  final String name;
  final DateTime capturedAt;
  final bool dateDetected;
  FacePose? pose;
  File? alignedFile;
  bool selected = false;
}

class _PreparedImportSource {
  const _PreparedImportSource({
    required this.source,
    required this.file,
    required this.item,
  });

  final _PhotoSource source;
  final File file;
  final _ImportReviewItem item;
}

class _ImportReviewGroup {
  _ImportReviewGroup(this.key, this.items);

  final String key;
  final List<_ImportReviewItem> items;
}

class _PhotoImportReviewScreen extends StatefulWidget {
  const _PhotoImportReviewScreen({
    required this.sources,
    required this.viewModel,
    required this.transferService,
    required this.alignmentService,
  });

  final List<_PhotoSource> sources;
  final AppViewModel viewModel;
  final PhotoTransferService transferService;
  final FaceAlignmentService alignmentService;

  @override
  State<_PhotoImportReviewScreen> createState() =>
      _PhotoImportReviewScreenState();
}

class _PhotoImportReviewScreenState extends State<_PhotoImportReviewScreen> {
  final _items = <_ImportReviewItem>[];
  final _preparedSources = <_PreparedImportSource>[];
  late final Future<void> _processingTask;
  bool _processing = true;
  bool _readingDates = true;
  bool _aligning = false;
  bool _saving = false;
  bool _cancelRequested = false;
  bool _confirmingCancel = false;
  int _processedCount = 0;
  int _analyzedCount = 0;
  int _alignedCount = 0;
  int _savedCount = 0;
  String? _expandedGroupKey;
  String? _error;
  bool _cleaningUp = false;

  @override
  void initState() {
    super.initState();
    _processingTask = _processSources();
  }

  Future<void> _processSources() async {
    await _readDates();
    if (_cancelRequested) return;
    if (mounted) setState(() => _readingDates = false);

    for (final prepared in _preparedSources) {
      if (_cancelRequested) break;
      try {
        prepared.item.pose = await widget.alignmentService.analyzePhoto(
          prepared.file.path,
        );
      } catch (_) {
        prepared.item.selected = false;
      } finally {
        _analyzedCount++;
        if (mounted &&
            (_analyzedCount % AppConstants.transferBatchSize == 0 ||
                _analyzedCount == _preparedSources.length)) {
          setState(() {});
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _processing = false;
      if (_items.isEmpty) _error = AppStrings.of(context).importReviewEmpty;
    });
  }

  Future<void> _readDates() async {
    for (final source in widget.sources) {
      if (_cancelRequested) break;
      File? sourceFile = source.file;
      try {
        if (sourceFile == null && source.uri != null) {
          final path = await _photoFolderChannel.invokeMethod<String>(
            'materializePhoto',
            {'uri': source.uri, 'name': source.name},
          );
          if (path != null) sourceFile = File(path);
        }
        if (sourceFile == null) {
          continue;
        }
        final capturedAt = await widget.transferService.capturedAt(
          sourceFile,
          fileName: source.name,
        );
        final item = _ImportReviewItem(
          file: sourceFile,
          name: source.name,
          capturedAt: capturedAt ?? DateTime.now(),
          dateDetected: capturedAt != null,
        );
        final duplicate =
            item.dateDetected &&
            _items.any((other) => _sameDetectedDate(other, item));
        if (!duplicate) item.selected = true;
        if (duplicate) {
          for (final other in _items) {
            if (_sameDetectedDate(other, item)) other.selected = false;
          }
        }
        _preparedSources.add(
          _PreparedImportSource(source: source, file: sourceFile, item: item),
        );
        _items.add(item);
      } catch (_) {
        // One unreadable or unrelated image must not cancel the whole import.
      } finally {
        _processedCount++;
        if (mounted &&
            (_processedCount % AppConstants.transferBatchSize == 0 ||
                _processedCount == widget.sources.length)) {
          setState(() {});
        }
      }
    }
  }

  Future<void> _confirmCancel() async {
    if (_confirmingCancel || _saving) return;
    _confirmingCancel = true;
    final strings = AppStrings.of(context);
    final cancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.cancelImport),
        content: Text(strings.cancelImportWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.keepImporting),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.confirmCancelImport),
          ),
        ],
      ),
    );
    _confirmingCancel = false;
    if (cancel != true || !mounted) return;
    _cancelRequested = true;
    await _processingTask;
    await _cleanupReviewFiles();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmImport() async {
    if (_processing || _saving) return;
    final selectedItems = [
      for (final item in _items)
        if (item.selected && item.pose != null) item,
    ];
    if (selectedItems.isEmpty) return;
    setState(() {
      _saving = true;
      _aligning = true;
      _alignedCount = 0;
      _savedCount = 0;
      _cleaningUp = false;
      _error = null;
    });
    try {
      final alignedItems = <PhotoImportItem>[];
      // ponytail: serialize memory-heavy image alignment; use a small batch
      // only if profiling proves the extra RAM is safe and worth the speed.
      for (final item in selectedItems) {
        alignedItems.add(await _alignSelectedItem(item));
        if (mounted) setState(() => _alignedCount = alignedItems.length);
      }
      if (mounted) setState(() => _aligning = false);
      await widget.viewModel.saveImportedPhotos(
        alignedItems,
        onProgress: (completed, _) {
          if (mounted) setState(() => _savedCount = completed);
        },
      );
      if (mounted) setState(() => _cleaningUp = true);
      await _cleanupReviewFiles();
      if (mounted) Navigator.of(context).pop(selectedItems.length);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _aligning = false;
          _cleaningUp = false;
          _error = error is PhotoTransferException
              ? error.message
              : AppStrings.of(context).saveFailed;
        });
      }
    }
  }

  Future<PhotoImportItem> _alignSelectedItem(_ImportReviewItem item) async {
    final alignedFile = await widget.alignmentService.align(item.file.path);
    item.alignedFile = alignedFile;
    return PhotoImportItem(file: alignedFile, capturedAt: item.capturedAt);
  }

  Future<void> _cleanupReviewFiles() =>
      widget.transferService.cleanupImportedPhotos([
        for (final prepared in _preparedSources)
          if (prepared.source.temporary)
            PhotoImportItem(
              file: prepared.file,
              capturedAt: prepared.item.capturedAt,
            ),
        for (final item in _items)
          if (item.alignedFile != null)
            PhotoImportItem(
              file: item.alignedFile!,
              capturedAt: item.capturedAt,
            ),
      ]);

  int get _selectedCount => _items.where((item) => item.selected).length;

  List<_ImportReviewGroup> get _reviewGroups {
    final groups = <String, _ImportReviewGroup>{};
    for (final item in _items) {
      final date = item.capturedAt;
      final key = item.dateDetected
          ? '${date.year}-${date.month}-${date.day}'
          : 'unknown:${item.file.path}';
      groups
          .putIfAbsent(key, () => _ImportReviewGroup(key, []))
          .items
          .add(item);
    }
    return groups.values.toList(growable: false);
  }

  List<({_ImportReviewGroup group, _ImportReviewItem item, bool collapsed})>
  get _visibleReviewEntries {
    final entries =
        <
          ({_ImportReviewGroup group, _ImportReviewItem item, bool collapsed})
        >[];
    for (final group in _reviewGroups) {
      if (group.items.length == 1 || _expandedGroupKey != group.key) {
        final item = group.items.firstWhere(
          (item) => item.selected,
          orElse: () => group.items.first,
        );
        entries.add((
          group: group,
          item: item,
          collapsed: group.items.length > 1,
        ));
        continue;
      }
      for (final item in group.items) {
        entries.add((group: group, item: item, collapsed: false));
      }
    }
    return entries;
  }

  bool get _hasDuplicateDates {
    final dates = <int>{};
    for (final item in _items) {
      if (!item.dateDetected) continue;
      final date = item.capturedAt;
      if (!dates.add(
        DateTime(date.year, date.month, date.day).millisecondsSinceEpoch,
      )) {
        return true;
      }
    }
    return false;
  }

  bool _sameDetectedDate(_ImportReviewItem first, _ImportReviewItem second) =>
      first.dateDetected &&
      second.dateDetected &&
      DateUtils.isSameDay(first.capturedAt, second.capturedAt);

  void _setItemSelected(_ImportReviewItem item, bool selected) {
    final sameDateItems = [
      for (final other in _items)
        if (_sameDetectedDate(item, other)) other,
    ];
    final selectedSameDateItems = sameDateItems
        .where((other) => other.selected)
        .length;
    if (!selected &&
        item.selected &&
        sameDateItems.length > 1 &&
        selectedSameDateItems == 1) {
      return;
    }
    setState(() {
      if (selected && sameDateItems.length > 1) {
        for (final other in sameDateItems) {
          other.selected = identical(other, item);
        }
        _expandedGroupKey = null;
      } else {
        item.selected = selected;
      }
    });
  }

  void _toggleGroup(_ImportReviewGroup group) {
    if (_processing || _saving) return;
    setState(() {
      _expandedGroupKey = _expandedGroupKey == group.key ? null : group.key;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmCancel());
      },
      child: Scaffold(
        appBar: AppBar(title: Text(strings.importReviewTitle)),
        body: ConstrainedPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.importReviewHint,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 14),
              if (_processing) ...[
                LinearProgressIndicator(
                  value: widget.sources.isEmpty
                      ? null
                      : (_readingDates
                            ? _processedCount / widget.sources.length
                            : _preparedSources.isEmpty
                            ? null
                            : _analyzedCount / _preparedSources.length),
                ),
                const SizedBox(height: 8),
                Text(
                  _readingDates
                      ? strings.readingPhotoDatesProgress(
                          _processedCount,
                          widget.sources.length,
                        )
                      : strings.analyzingPhotosProgress(
                          _analyzedCount,
                          _preparedSources.length,
                        ),
                ),
                const SizedBox(height: 14),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    strings.selectedPhotos(_selectedCount, _items.length),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              if (_saving) ...[
                LinearProgressIndicator(
                  value: _cleaningUp || _selectedCount == 0
                      ? null
                      : _aligning
                      ? _alignedCount / _selectedCount
                      : _savedCount / _selectedCount,
                ),
                const SizedBox(height: 8),
                Text(
                  _cleaningUp
                      ? strings.cleaningImportedPhotos
                      : _aligning
                      ? strings.aligningPhotosProgress(
                          _alignedCount,
                          _selectedCount,
                        )
                      : strings.savingPhotosProgress(
                          _savedCount,
                          _selectedCount,
                        ),
                ),
                const SizedBox(height: 12),
              ],
              if (_hasDuplicateDates)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    strings.importDuplicateDateHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Expanded(
                child: _items.isEmpty
                    ? Center(
                        child: _processing
                            ? const CircularProgressIndicator()
                            : Text(_error ?? strings.importReviewEmpty),
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: _reviewTileMaxWidth,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.78,
                            ),
                        itemCount: _visibleReviewEntries.length,
                        itemBuilder: (context, index) {
                          final entry = _visibleReviewEntries[index];
                          return entry.collapsed
                              ? _buildReviewGroupTile(context, entry.group)
                              : _buildReviewTile(context, entry.item);
                        },
                      ),
              ),
              if (!_processing && _items.isNotEmpty) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _saving || _selectedCount == 0
                      ? null
                      : _confirmImport,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(strings.approveImport(_selectedCount)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReviewGroupTile(BuildContext context, _ImportReviewGroup group) {
    final strings = AppStrings.of(context);
    final item = group.items.firstWhere(
      (item) => item.selected,
      orElse: () => group.items.first,
    );
    final dateText = item.dateDetected
        ? DateFormat(
            'd MMM yyyy',
            strings.locale.languageCode,
          ).format(item.capturedAt)
        : strings.importDateUnknown;
    return Semantics(
      label: '$dateText, ${strings.sameDayPhotoCount(group.items.length)}',
      button: true,
      child: GestureDetector(
        onTap: () => _toggleGroup(group),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PhotoImage(
              source: item.file.path,
              cacheWidth:
                  (_reviewTileMaxWidth *
                          MediaQuery.of(context).devicePixelRatio)
                      .round(),
            ),
            ColoredBox(color: Colors.black26),
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(190),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.collections_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strings.sameDayPhotoCount(group.items.length),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateText,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (item.selected)
              const Positioned(
                top: 6,
                right: 6,
                child: Icon(Icons.check_circle_rounded, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewTile(BuildContext context, _ImportReviewItem item) {
    final strings = AppStrings.of(context);
    final feedback = widget.alignmentService.feedbackFor(item.pose);
    final isReady = item.pose != null && feedback.isReady;
    final dateText = item.dateDetected
        ? DateFormat(
            'd MMM yyyy',
            strings.locale.languageCode,
          ).format(item.capturedAt)
        : strings.importDateUnknown;
    return Semantics(
      label: '$dateText, ${item.name}',
      selected: item.selected,
      button: true,
      child: GestureDetector(
        onTap: _processing || _saving
            ? null
            : () => _setItemSelected(item, !item.selected),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PhotoImage(
              source: item.file.path,
              cacheWidth:
                  (_reviewTileMaxWidth *
                          MediaQuery.of(context).devicePixelRatio)
                      .round(),
            ),
            Positioned(
              top: 6,
              left: 6,
              right: 6,
              child: Align(
                alignment: Alignment.topLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color:
                        (isReady
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).colorScheme.errorContainer)
                            .withAlpha(235),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.alignmentScore(feedback.score),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isReady
                                ? Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer
                                : Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                          ),
                        ),
                        if (item.pose == null)
                          Text(
                            strings.importNoFace,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!item.selected)
              ColoredBox(
                color: Theme.of(context).colorScheme.scrim.withAlpha(150),
                child: const Center(
                  child: Icon(Icons.remove_circle_outline_rounded, size: 34),
                ),
              ),
            Positioned(
              top: 2,
              right: 2,
              child: Checkbox(
                value: item.selected,
                onChanged: (value) {
                  if (!_processing && !_saving && value != null) {
                    _setItemSelected(item, value);
                  }
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ColoredBox(
                color: Colors.black54,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (!item.dateDetected) ...[
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.amberAccent,
                              size: 13,
                            ),
                            const SizedBox(width: 3),
                          ],
                          Expanded(
                            child: Text(
                              dateText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: item.dateDetected
                                    ? Colors.white
                                    : Colors.amberAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
