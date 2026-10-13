import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/widgets/photo_image.dart';
import '../../../domain/models/daily_photo.dart';
import '../../app/app_view_model.dart';
import 'photo_actions.dart';

class PhotoDetailScreen extends StatefulWidget {
  const PhotoDetailScreen({
    required this.photo,
    required this.viewModel,
    super.key,
  });

  final DailyPhoto photo;
  final AppViewModel viewModel;

  @override
  State<PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends State<PhotoDetailScreen> {
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final isOwner = widget.photo.ownerId == widget.viewModel.user?.id;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          DateFormat(
            'd MMMM yyyy',
            strings.locale.languageCode,
          ).format(widget.photo.capturedAt),
        ),
        actions: [
          if (isOwner)
            IconButton(
              tooltip: strings.deletePhoto,
              onPressed: _deleting ? null : _confirmDelete,
              icon: _deleting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: PhotoImage(source: widget.photo.source, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final strings = AppStrings.of(context);
    if (!await confirmPhotoDeletion(context) || !mounted) return;

    setState(() => _deleting = true);
    try {
      await widget.viewModel.deletePhoto(widget.photo);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.deletePhotoFailed)));
    }
  }
}
