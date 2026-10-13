import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../config/app_constants.dart';

class PhotoImage extends StatelessWidget {
  const PhotoImage({
    required this.source,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.cacheWidth,
    super.key,
  });

  final String source;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.person_outline_rounded, size: 38)),
    );
    Widget child;
    if (source.isEmpty) {
      child = placeholder;
    } else if (source.startsWith('http')) {
      child = CachedNetworkImage(
        imageUrl: source,
        fit: fit,
        memCacheWidth: cacheWidth,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      );
    } else {
      child = Image.file(
        File(source),
        fit: fit,
        cacheWidth: cacheWidth,
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    return ClipRRect(
      borderRadius:
          borderRadius ?? BorderRadius.circular(AppConstants.photoBorderRadius),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
