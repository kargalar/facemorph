import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../data/services/face_alignment_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/photo_transfer_service.dart';
import '../../data/services/theme_service.dart';
import '../../data/services/video_export_service.dart';
import '../../domain/models/daily_photo.dart';
import '../core/app_shell.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/capture/capture_screen.dart';
import '../features/feed/feed_screen.dart';
import '../features/home/home_screen.dart';
import '../features/preview/preview_screen.dart';
import '../features/preview/view_models/preview_view_model.dart';
import '../features/profile/profile_screen.dart';
import '../features/photo/photo_detail_screen.dart';
import '../features/transfer/photo_transfer_screen.dart';
import '../features/settings/settings_screen.dart';
import 'app_view_model.dart';

GoRouter createAppRouter({
  required AppViewModel viewModel,
  required ThemeService themeService,
  required NotificationService notificationService,
  required FaceAlignmentService alignmentService,
  required VideoExportService videoExportService,
  required PhotoTransferService photoTransferService,
}) => GoRouter(
  initialLocation: '/today',
  refreshListenable: viewModel,
  redirect: (context, state) {
    final onSignIn = state.matchedLocation == '/sign-in';
    if (!viewModel.isAuthenticated) return onSignIn ? null : '/sign-in';
    if (onSignIn) return '/today';
    return null;
  },
  routes: [
    GoRoute(
      path: '/sign-in',
      builder: (context, state) => SignInScreen(viewModel: viewModel),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/explore',
              builder: (context, state) => FeedScreen(viewModel: viewModel),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/today',
              builder: (context, state) => HomeScreen(viewModel: viewModel),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => ProfileScreen(viewModel: viewModel),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => SettingsScreen(
        viewModel: viewModel,
        themeService: themeService,
        notificationService: notificationService,
      ),
    ),
    GoRoute(
      path: '/capture',
      builder: (context, state) => CaptureScreen(
        viewModel: viewModel,
        alignmentService: alignmentService,
      ),
    ),
    GoRoute(
      path: '/preview',
      builder: (context, state) => PreviewScreen(
        viewModel: PreviewViewModel(viewModel.photos, videoExportService),
      ),
    ),
    GoRoute(
      path: '/photo',
      builder: (context, state) {
        final photo = state.extra;
        if (photo is! DailyPhoto) return const SizedBox.shrink();
        return PhotoDetailScreen(photo: photo, viewModel: viewModel);
      },
    ),
    GoRoute(
      path: '/transfer',
      builder: (context, state) => PhotoTransferScreen(
        viewModel: viewModel,
        transferService: photoTransferService,
        alignmentService: alignmentService,
      ),
    ),
  ],
);
