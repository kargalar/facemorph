import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/app_constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../domain/models/video_settings.dart';
import 'video_preview_screen.dart';
import 'view_models/preview_view_model.dart';

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({
    required this.viewModel,
    this.initialPhotoSeconds,
    super.key,
  });
  final PreviewViewModel viewModel;
  final double? initialPhotoSeconds;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen>
    with SingleTickerProviderStateMixin {
  late final _frames = [...widget.viewModel.photos]
    ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
  late final _images = [
    for (final frame in _frames)
      frame.source.startsWith('http')
          ? CachedNetworkImageProvider(frame.source) as ImageProvider
          : FileImage(File(frame.source)),
  ];
  late final AnimationController _playback;
  late final TextEditingController _seconds;
  final _form = GlobalKey<FormState>();
  late VideoSettings _settings;
  int _cachedIndex = -1;

  @override
  void initState() {
    super.initState();
    final initialSeconds =
        widget.initialPhotoSeconds ?? AppConstants.videoDefaultPhotoSeconds;
    _seconds = TextEditingController(text: '$initialSeconds');
    _settings = VideoSettings(photoSeconds: initialSeconds);
    _playback = AnimationController(
      vsync: this,
      duration: _settings.duration(_frames.isEmpty ? 1 : _frames.length),
    )..addListener(_warmNext);
    if (_frames.length > 1) _playback.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warmNext();
  }

  int get _index =>
      (_playback.value * _frames.length).floor().clamp(0, _frames.length - 1);

  void _warmNext() {
    if (!mounted || _frames.isEmpty || _index == _cachedIndex) return;
    _cachedIndex = _index;
    for (var offset = 0; offset < 3; offset++) {
      unawaited(
        precacheImage(_images[(_index + offset) % _images.length], context),
      );
    }
  }

  void _updateSettings() {
    if (!_form.currentState!.validate()) return;
    final playing = _playback.isAnimating;
    setState(() {
      _settings = VideoSettings(
        photoSeconds: double.parse(_seconds.text.replaceAll(',', '.')),
        smoothTransition: _settings.smoothTransition,
      );
      _playback.stop();
      _playback.duration = _settings.duration(_frames.length);
      _playback.value = 0;
      if (playing) _playback.repeat();
    });
  }

  @override
  void dispose() {
    _playback.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (_frames.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(strings.noPhotos)),
      );
    }
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text(strings.preview)),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                children: [
                  SizedBox(
                    height: (constraints.maxHeight * 0.48).clamp(160.0, 500.0),
                    child: AspectRatio(
                      aspectRatio: 4 / 5,
                      child: AnimatedBuilder(
                        animation: _playback,
                        builder: (context, _) {
                          final index = _index;
                          final blend =
                              _playback.value * _frames.length - index;
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              _photo(index),
                              if (_settings.smoothTransition &&
                                  index + 1 < _frames.length)
                                Opacity(
                                  opacity: blend.clamp(0, 1),
                                  child: _photo(index + 1),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _playback,
                    builder: (context, _) => Column(
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          DateFormat(
                            'd MMMM yyyy',
                            strings.locale.languageCode,
                          ).format(_frames[_index].capturedAt),
                        ),
                        Slider(
                          value: _playback.value,
                          onChanged: _frames.length < 2
                              ? null
                              : (value) {
                                  _playback.stop();
                                  _playback.value = value;
                                  setState(() {});
                                },
                        ),
                        IconButton.filled(
                          tooltip: _playback.isAnimating
                              ? strings.pausePreview
                              : strings.playJourney,
                          onPressed: _frames.length < 2
                              ? null
                              : () => setState(() {
                                  if (_playback.isAnimating) {
                                    _playback.stop();
                                  } else {
                                    _playback.repeat();
                                  }
                                }),
                          icon: Icon(
                            _playback.isAnimating
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListenableBuilder(
                    listenable: widget.viewModel,
                    builder: (context, _) => Column(
                      children: [
                        Form(
                          key: _form,
                          child: TextFormField(
                            controller: _seconds,
                            enabled: !widget.viewModel.exporting,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: strings.photoDuration,
                              helperText: strings.photoDurationHint,
                              border: const OutlineInputBorder(),
                            ),
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: (value) {
                              final seconds = double.tryParse(
                                (value ?? '').replaceAll(',', '.'),
                              );
                              if (seconds == null ||
                                  !seconds.isFinite ||
                                  seconds < AppConstants.videoMinPhotoSeconds ||
                                  seconds > AppConstants.videoMaxPhotoSeconds) {
                                return strings.invalidPhotoDuration;
                              }
                              return null;
                            },
                            onChanged: (_) => _updateSettings(),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(strings.smoothTransition),
                          subtitle: Text(strings.smoothTransitionHint),
                          value: _settings.smoothTransition,
                          onChanged: widget.viewModel.exporting
                              ? null
                              : (value) => setState(() {
                                  _settings = VideoSettings(
                                    photoSeconds: _settings.photoSeconds,
                                    smoothTransition: value,
                                  );
                                }),
                        ),
                        Text(
                          strings.videoDuration(
                            _settings.duration(_frames.length).inMilliseconds /
                                1000,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strings.livePreviewHint,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed:
                              widget.viewModel.exporting || _frames.length < 2
                              ? null
                              : _export,
                          icon: widget.viewModel.exporting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.ios_share_rounded),
                          label: Text(
                            widget.viewModel.exporting
                                ? strings.exportingVideo
                                : strings.exportVideo,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _photo(int index) => ClipRRect(
    borderRadius: BorderRadius.circular(AppConstants.photoBorderRadius),
    clipBehavior: Clip.antiAlias,
    child: ColoredBox(
      color: Colors.black,
      child: Image(
        image: _images[index],
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      ),
    ),
  );

  Future<void> _export() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _playback.stop());
    final file = await widget.viewModel.export(_settings);
    if (!mounted) return;
    final strings = AppStrings.of(context);
    try {
      if (file == null) throw StateError('Video export failed');
      var savedToDownloads = true;
      try {
        await widget.viewModel.saveToDownloads(file);
      } catch (_) {
        savedToDownloads = false;
      }
      if (!mounted) return;
      if (!savedToDownloads) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.videoSaveToDownloadsFailed)),
        );
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPreviewScreen(
            file: file,
            savedToDownloads: savedToDownloads,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.exportFailed)));
    }
  }
}
