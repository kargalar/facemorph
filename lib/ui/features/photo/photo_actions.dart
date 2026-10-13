import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../domain/models/daily_photo.dart';
import '../../app/app_view_model.dart';

Future<bool> confirmPhotoDeletion(BuildContext context) async {
  final strings = AppStrings.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(strings.deletePhoto),
          content: Text(strings.deletePhotoWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(strings.deletePhoto),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> confirmAndDeletePhoto({
  required BuildContext context,
  required AppViewModel viewModel,
  required DailyPhoto photo,
}) async {
  if (!await confirmPhotoDeletion(context) || !context.mounted) return;
  try {
    await viewModel.deletePhoto(photo);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).deletePhotoFailed)),
      );
    }
  }
}
