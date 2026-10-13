import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_constants.dart';
import 'core/l10n/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/firebase_app_repository.dart';
import 'data/services/face_alignment_service.dart';
import 'data/services/firebase_data_service.dart';
import 'data/services/auth_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/photo_cache_service.dart';
import 'data/services/purchase_service.dart';
import 'data/services/photo_transfer_service.dart';
import 'data/services/theme_service.dart';
import 'data/services/video_export_service.dart';
import 'firebase_options.dart';
import 'ui/app/app_router.dart';
import 'ui/app/app_view_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final preferences = await SharedPreferences.getInstance();
  final themeService = ThemeService(preferences);
  final notificationService = NotificationService(preferences);
  final purchaseService = PurchaseService();
  final alignmentService = FaceAlignmentService(preferences: preferences);
  final photoCacheService = PhotoCacheService();
  await notificationService.initialize();

  final repository = FirebaseAppRepository(
    AuthService(),
    FirebaseDataService(),
  );
  final viewModel = AppViewModel(
    repository,
    purchaseService,
    photoCacheService,
    preferences,
    notificationService,
  );
  await viewModel.initialize();

  runApp(
    PhotoTimelapseApp(
      viewModel: viewModel,
      themeService: themeService,
      notificationService: notificationService,
      alignmentService: alignmentService,
      videoExportService: VideoExportService(photoCacheService),
      photoTransferService: PhotoTransferService(photoCacheService),
    ),
  );
}

class PhotoTimelapseApp extends StatefulWidget {
  const PhotoTimelapseApp({
    required this.viewModel,
    required this.themeService,
    required this.notificationService,
    required this.alignmentService,
    required this.videoExportService,
    required this.photoTransferService,
    super.key,
  });

  final AppViewModel viewModel;
  final ThemeService themeService;
  final NotificationService notificationService;
  final FaceAlignmentService alignmentService;
  final VideoExportService videoExportService;
  final PhotoTransferService photoTransferService;

  @override
  State<PhotoTimelapseApp> createState() => _PhotoTimelapseAppState();
}

class _PhotoTimelapseAppState extends State<PhotoTimelapseApp> {
  late final router = createAppRouter(
    viewModel: widget.viewModel,
    themeService: widget.themeService,
    notificationService: widget.notificationService,
    alignmentService: widget.alignmentService,
    videoExportService: widget.videoExportService,
    photoTransferService: widget.photoTransferService,
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.themeService,
    builder: (context, _) => MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: widget.themeService.mode,
      supportedLocales: const [Locale('en')],
      localeListResolutionCallback: (locales, supportedLocales) =>
          resolveAppLocale(locales),
      localizationsDelegates: const [
        AppStringsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      routerConfig: router,
    ),
  );
}
