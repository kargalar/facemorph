import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

Locale resolveAppLocale(Iterable<Locale>? deviceLocales) {
  return const Locale('en');
}

class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;
  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings)!;

  String t(String _, String en) => en;
  String get appName => 'FaceMorph';
  String get testTwentyPhotos =>
      t('20 fotoğrafla test et', 'Test with 20 photos');
  String get testNeedsTwentyPhotos => t(
    'Bu test için en az 20 fotoğraf gerekiyor.',
    'At least 20 photos are required for this test.',
  );
  String get captureBeforeImport => t(
    'İçe aktarmadan önce uygulamadan 1 adet referans fotoğrafı çekmen gerekiyor.',
    'Take one reference photo in the app before importing photos.',
  );
  String get tagline =>
      t('Her gün bir kare. Zamanla sen.', 'One frame a day. You, over time.');
  String get continueWithGoogle =>
      t('Google ile devam et', 'Continue with Google');
  String get continueWithEmail =>
      t('E-posta ile devam et', 'Continue with email');
  String get emailAddress => t('E-posta adresi', 'Email address');
  String get password => t('Şifre', 'Password');
  String get signIn => t('Giriş yap', 'Sign in');
  String get createAccount => t('Hesap oluştur', 'Create account');
  String get createNewAccount =>
      t('Yeni hesap oluştur', 'Create a new account');
  String get haveAccount => t('Zaten hesabım var', 'I already have an account');
  String get forgotPassword => t('Şifremi unuttum', 'Forgot password');
  String get showPassword => t('Şifreyi göster', 'Show password');
  String get invalidEmail =>
      t('Geçerli bir e-posta adresi gir.', 'Enter a valid email address.');
  String get passwordTooShort => t(
    'Şifre en az 6 karakter olmalı.',
    'Password must be at least 6 characters.',
  );
  String get invalidCredentials =>
      t('E-posta veya şifre hatalı.', 'The email or password is incorrect.');
  String get emailAlreadyInUse =>
      t('Bu e-posta zaten kullanılıyor.', 'This email is already in use.');
  String get emailAuthFailed => t(
    'E-posta ile giriş tamamlanamadı. Tekrar dene.',
    'Email sign-in could not be completed. Try again.',
  );
  String get networkError =>
      t('Bağlantı kurulamadı. Tekrar dene.', 'Could not connect. Try again.');
  String get passwordResetSent => t(
    'Şifre yenileme bağlantısı e-posta adresine gönderildi.',
    'A password reset link was sent to your email.',
  );
  String get signInFailed => t(
    'Google ile giriş tamamlanamadı. Tekrar dene.',
    'Google sign-in could not be completed. Try again.',
  );
  String get consentPrefix => t('Devam ederek', 'By continuing, you agree to');
  String get consentJoiner => t('ve', 'and');
  String get consentSuffix => t('’nı kabul edersin.', '.');
  String get today => t('Bugün', 'Today');
  String get calendar => t('Takvim', 'Calendar');
  String get explore => t('Keşfet', 'Explore');
  String get profile => t('Profil', 'Profile');
  String get captureToday => t('Bugünün karesini çek', 'Capture today’s frame');
  String get capturedToday =>
      t('Bugünün karesi hazır', 'Today’s frame is ready');
  String alignmentScore(int score) =>
      t('%$score uygun konum', '$score% aligned');
  String get alignmentNoFace =>
      t('Yüzünü kameraya göster', 'Show your face to the camera');
  String get alignmentFaceCamera =>
      t('Yüzünün tamamını kameraya göster', 'Keep your full face in the frame');
  String get alignmentMoveLeft => t('Biraz sola git', 'Move a little left');
  String get alignmentMoveRight => t('Biraz sağa git', 'Move a little right');
  String get alignmentMoveUp => t('Biraz yukarı çık', 'Move a little up');
  String get alignmentMoveDown => t('Biraz aşağı in', 'Move a little down');
  String get alignmentMoveCloser => t('Biraz yaklaş', 'Move a little closer');
  String get alignmentMoveAway =>
      t('Biraz uzaklaş', 'Move a little farther away');
  String get alignmentTurnLeft =>
      t('Başını biraz sola döndür', 'Turn your head a little left');
  String get alignmentTurnRight =>
      t('Başını biraz sağa döndür', 'Turn your head a little right');
  String get alignmentRotateLeft =>
      t('Başını biraz sola eğ', 'Tilt your head a little left');
  String get alignmentRotateRight =>
      t('Başını biraz sağa eğ', 'Tilt your head a little right');
  String get alignmentFineTune => t(
    'Yüzünü kılavuzla biraz daha hizala',
    'Make a small adjustment to match the guide',
  );
  String get alignmentReady =>
      t('Mükemmel, fotoğrafı çekebilirsin', 'Perfect, you can take the photo');
  String get alignmentReferenceRequired => t(
    'İlk fotoğraf için gözlerini ve ağzını kılavuz şekillerine getir; en az %80 seviyesine ulaş.',
    'Place your eyes and mouth on the guide outlines and reach at least 80% for the first reference photo.',
  );
  String get cameraInitializing =>
      t('Kamera hazırlanıyor…', 'Preparing camera…');
  String get frontFlash => t('Ön flaş', 'Front flash');
  String get trackFacialFeatures =>
      t('Göz ve ağız takibi', 'Track eyes and mouth');
  String get processing => t('Yüz hizalanıyor…', 'Aligning your face…');
  String get retry => t('Tekrar dene', 'Try again');
  String get save => t('Kaydet', 'Save');
  String get preview => t('Önizleme', 'Preview');
  String get tryAlignmentAlgorithms =>
      t('Algoritma dene', 'Try alignment algorithms');
  String get alignmentTrialTitle =>
      t('Hizalama algoritmalarını dene', 'Try alignment algorithms');
  String get alignmentTrialHint => t(
    'Aynı fotoğrafları beş farklı yöntemle hizalayıp sonucu video olarak karşılaştır.',
    'Align the same photos with five methods and compare the result as a video.',
  );
  String get photoCountToUse =>
      t('Kullanılacak fotoğraf sayısı', 'Number of photos to use');
  String get selectPhotos => t('Fotoğrafları seç', 'Select photos');
  String alignmentSelectedPhotos(int selected, int total) => t(
    '$selected/$total fotoğraf seçildi',
    '$selected/$total photos selected',
  );
  String get compareAllAlgorithms => t(
    'Tüm algoritmalarla videoları karşılaştır',
    'Compare videos from all algorithms',
  );
  String get algorithmComparisonTitle =>
      t('Algoritma karşılaştırması', 'Algorithm comparison');
  String get algorithmComparisonHint => t(
    'Videoları karşılaştır ve en iyi sonucu veren algoritmayı seç.',
    'Compare the videos and choose the algorithm with the best result.',
  );
  String exportingAllAlgorithms(int current, int total) => t(
    'Algoritma videoları hazırlanıyor… $current/$total',
    'Preparing algorithm videos… $current/$total',
  );
  String get chooseThisAlgorithm =>
      t('Bu algoritmayı seç', 'Choose this algorithm');
  String get videoSavedToDownloadsShort =>
      t('İndirilenlere kaydedildi', 'Saved to Downloads');
  String get videoNotSavedToDownloads =>
      t('İndirilenlere kaydedilemedi', 'Could not save to Downloads');
  String get algorithmEyeAnchor => t('Göz merkezli', 'Eye anchor');
  String get algorithmFaceBox => t('Yüz kutusu', 'Face box');
  String get algorithmEyeDistance => t('Göz mesafesi', 'Eye distance');
  String get algorithmEyeMouth => t('Göz + ağız', 'Eye + mouth');
  String get algorithmBalanced => t('Dengeli landmark', 'Balanced landmarks');
  String get algorithmEyeHeadSize => t('Göz + kafa boyutu', 'Eye + head size');
  String get invalidPhotoCount => t(
    'En az 2, mevcut fotoğraf sayısından fazla olmayan bir sayı gir.',
    'Enter at least 2 and no more than the available photos.',
  );
  String get selectExactPhotoCount => t(
    'Girilen sayı kadar fotoğraf seç.',
    'Select exactly the number of photos entered.',
  );
  String get alignmentTrialNoFace => t(
    'Fotoğraflardan birinde net yüz bulunamadı.',
    'A clear face could not be found in one of the photos.',
  );
  String get alignmentTrialFailed => t(
    'Fotoğraflar hizalanamadı. Tekrar dene.',
    'The photos could not be aligned. Try again.',
  );
  String get aligningSelectedPhotos =>
      t('Fotoğraflar hizalanıyor…', 'Aligning selected photos…');
  String aligningPhotosProgress(int current, int total) => t(
    'Fotoğraflar hizalanıyor… $current/$total',
    'Aligning photos… $current/$total',
  );
  String get cleaningImportedPhotos =>
      t('Geçici dosyalar temizleniyor…', 'Cleaning temporary files…');
  String get pausePreview => t('Duraklat', 'Pause');
  String get photoDuration =>
      t('Fotoğraf başına süre (saniye)', 'Seconds per photo');
  String get photoDurationHint => t(
    '0,01–1 saniye · 0,01 saniyelik adımlar',
    '0.01–1 second · 0.01-second steps',
  );
  String get invalidPhotoDuration => t(
    '0,01 ile 1 arasında bir süre gir.',
    'Enter a duration between 0.01 and 1.',
  );
  String get smoothTransition => t('Yumuşak geçiş', 'Smooth transition');
  String get smoothTransitionHint => t(
    'Fotoğraflar birbirine karışarak geçer.',
    'Blend each photo into the next.',
  );
  String get livePreviewHint => t(
    'Önizleme render gerektirmez. Çok kısa sürelerde akıcılık ekran hızına ve fotoğrafların yüklenmesine bağlıdır.',
    'Preview requires no rendering. At very short durations, smoothness depends on screen refresh rate and image loading.',
  );
  String videoDuration(double seconds) => t(
    'Video süresi: ${seconds.toStringAsFixed(2)} sn',
    'Video duration: ${seconds.toStringAsFixed(2)} s',
  );
  String get exportVideo =>
      t('Videoyu oluştur ve paylaş', 'Create and share video');
  String get exportingVideo => t('Video oluşturuluyor…', 'Creating video…');
  String get exportFailed =>
      t('Video oluşturulamadı.', 'Could not create video.');
  String get videoPreviewTitle => t('Video önizlemesi', 'Video preview');
  String get videoSavedToDownloads => t(
    'Video İndirilenler klasörüne kaydedildi.',
    'Video saved to Downloads.',
  );
  String get videoSaveToDownloadsFailed => t(
    'Video oluşturuldu fakat İndirilenler klasörüne kaydedilemedi.',
    'Video was created but could not be saved to Downloads.',
  );
  String get realigningAllPhotos =>
      t('Tüm fotoğraflar yeniden hizalanıyor…', 'Realigning all photos…');
  String realigningPhotosProgress(int current, int total) => t(
    'Fotoğraflar yeniden hizalanıyor… $current/$total',
    'Realigning photos… $current/$total',
  );
  String get realignAllPhotosDone => t(
    'Algoritma kaydedildi ve tüm fotoğraflar yeniden hizalandı.',
    'Algorithm saved and all photos were realigned.',
  );
  String get importExternalPhotos =>
      t('Birden fazla fotoğraf seç', 'Choose multiple photos');
  String get importPhotoFolder =>
      t('Fotoğraf klasörü seç', 'Choose a photo folder');
  String get importFailed => t(
    'Fotoğraflar içe aktarıma hazırlanamadı. Tekrar dene.',
    'Could not prepare the photos for import. Try again.',
  );
  String get photoTransfer => t('Fotoğrafları taşı', 'Transfer photos');
  String get exportPhotos =>
      t('Fotoğraf yedeğini dışa aktar', 'Export photo backup');
  String get exportingPhotos =>
      t('Fotoğraflar hazırlanıyor…', 'Preparing photos…');
  String get importPhotos =>
      t('Fotoğraf yedeğini içe aktar', 'Import photo backup');
  String get importingPhotos =>
      t('Fotoğraflar içe aktarılıyor…', 'Importing photos…');
  String savingPhotosProgress(int current, int total) => t(
    'Fotoğraflar kaydediliyor… $current/$total',
    'Saving photos… $current/$total',
  );
  String importingPhotosProgress(int current, int total) => t(
    '$current/$total fotoğraf içe aktarılıyor…',
    'Importing photos… $current/$total',
  );
  String readingPhotoDatesProgress(int current, int total) => t(
    'Fotoğraf tarihleri okunuyor… $current/$total',
    'Reading photo dates… $current/$total',
  );
  String analyzingPhotosProgress(int current, int total) => t(
    'Fotoğraflar analiz ediliyor… $current/$total',
    'Analyzing photos… $current/$total',
  );
  String get importReviewTitle => t('İçe aktarmayı incele', 'Review import');
  String get importReviewHint => t(
    'İstemediklerini kaldır, kalanları onayla.',
    'Remove unwanted photos and confirm the rest.',
  );
  String get cancelImport => t('İçe aktarmayı iptal et', 'Cancel import');
  String get cancelImportWarning => t(
    'İçe aktarma iptal edilecek. Seçilen fotoğraflar yüklenmeyecek.',
    'The import will be canceled. Selected photos will not be uploaded.',
  );
  String get keepImporting => t('İçe aktarmaya devam et', 'Keep importing');
  String get confirmCancelImport => t('İptal et', 'Cancel import');
  String approveImport(int count) =>
      t('$count fotoğrafı onayla', 'Approve $count photos');
  String selectedPhotos(int count, int total) =>
      t('$count/$total fotoğraf seçili', '$count/$total photos selected');
  String get importReviewEmpty => t(
    'İçe aktarılabilecek fotoğraf bulunamadı.',
    'No importable photos were found.',
  );
  String get importNoFace =>
      t('Yüz yok · merkez kırpma', 'No face · center crop');
  String get importDateUnknown =>
      t('Tarih tespit edilemedi', 'Date not detected');
  String get importDuplicateDateHint => t(
    'Aynı gün fotoğrafları tek grupta gösterilir. Açıp birini seç.',
    'Photos from the same day are grouped. Open a group and choose one.',
  );
  String sameDayPhotoCount(int count) =>
      t('Bu gün için $count fotoğraf var', '$count photos from this day');
  String get noImagesInFolder => t(
    'Seçilen klasörde desteklenen fotoğraf bulunamadı.',
    'No supported photos were found in the selected folder.',
  );
  String get photoTransferHint => t(
    'FaceMorph ZIP yedeğini taşı veya dışarıdan fotoğrafları otomatik hizalayarak ekle.',
    'Move a FaceMorph ZIP backup or add external photos with automatic alignment.',
  );
  String get photoExported =>
      t('Fotoğraf yedeği hazır.', 'Photo backup is ready.');
  String get photosImported =>
      t('Fotoğraflar içe aktarıldı.', 'Photos imported successfully.');
  String photosImportedCount(int count) => t(
    '$count fotoğraf içe aktarıldı.',
    '$count photos imported successfully.',
  );
  String photosImportResult(int imported, int total) => t(
    '$total fotoğraftan $imported tanesi aktarıldı; diğerlerinde net yüz bulunamadı.',
    '$imported of $total photos were imported; no clear face was found in the others.',
  );
  String get yourJourney => t('Yolculuğun', 'Your journey');
  String get frames => t('kare', 'frames');
  String get streak => t('günlük seri', 'day streak');
  String get thisMonth => t('Bu ay', 'This month');
  String get noPhotos => t(
    'İlk kareni çektiğinde burada görünecek.',
    'Your first frame will appear here.',
  );
  String get playJourney => t('Yolculuğu oynat', 'Play your journey');
  String get globalFeed =>
      t('Dünyadan kareler', 'Frames from around the world');
  String get feedSubtitle => t('En yeni kareler önce', 'Newest frames first');
  String get settings => t('Ayarlar', 'Settings');
  String get friends => t('Arkadaşlar', 'Friends');
  String get global => t('Global', 'Global');
  String get discoverPeople => t('Kişileri keşfet', 'Discover people');
  String get follow => t('Takip et', 'Follow');
  String get following => t('Takipte', 'Following');
  String get followFailed =>
      t('Takip işlemi tamamlanamadı.', 'Could not update following.');
  String get noFriendsFeed => t(
    'Takip ettiğin kişilerin kareleri burada görünecek.',
    'Frames from people you follow will appear here.',
  );
  String get appearance => t('Görünüm', 'Appearance');
  String get light => t('Aydınlık', 'Light');
  String get dark => t('Karanlık', 'Dark');
  String get darkMode => t('Karanlık mod', 'Dark mode');
  String get system => t('Sistem', 'System');
  String get privacy => t('Gizlilik', 'Privacy');
  String get legal => t('Yasal', 'Legal');
  String get privacyPolicy => t('Gizlilik Politikası', 'Privacy Policy');
  String get termsOfUse => t('Kullanım Koşulları', 'Terms of Use');
  String get accountDeletion =>
      t('Hesap silme sayfası', 'Account deletion page');
  String get accountDeletionHint => t(
    'Uygulamaya erişemediğinde hesabını dışarıdan silme talebi gönder.',
    'Request deletion from outside the app if you cannot sign in.',
  );
  String get linkOpenFailed =>
      t('Bağlantı açılamadı.', 'Could not open the link.');
  String get publicPhotos =>
      t('Fotoğraflarımı herkese göster', 'Show my photos publicly');
  String get publicPhotosHint => t(
    'Kapalıyken yeni ve eski karelerin akışta görünmez.',
    'When off, none of your frames appear in the feed.',
  );
  String get reminders => t('Günlük hatırlatıcı', 'Daily reminder');
  String reminderHint(String time) => t(
    'Her gün $time’de nazik bir hatırlatma',
    'A gentle reminder every day at $time',
  );
  String get premium => 'FaceMorph Premium';
  String get premiumActive => t('Premium aktif', 'Premium active');
  String get premiumTrial =>
      t('14 günlük Premium hediyen', 'Your 14-day Premium gift');
  String trialDaysLeft(int count) => t('$count gün kaldı', '$count days left');
  String get premiumBenefits => t(
    'Her gün 1 kare • Sınırsız önizleme • Gelecek özellikler',
    '1 frame daily • Unlimited previews • Future features',
  );
  String get developerTools => t('Geliştirici araçları', 'Developer tools');
  String get premiumTestMode => t('Premium test modu', 'Premium test mode');
  String get premiumTestModeHint => t(
    'Yalnızca bu test hesabında premium durumunu yerel olarak değiştirir.',
    'Locally changes the Premium status for this test account only.',
  );
  String get subscribe => t('Premium’a geç', 'Go Premium');
  String get freePlan =>
      t('Ücretsiz plan: haftada 1 kare', 'Free plan: 1 frame per week');
  String get signOut => t('Çıkış yap', 'Sign out');
  String get deleteAccount => t('Hesabı sil', 'Delete account');
  String get cancel => t('Vazgeç', 'Cancel');
  String get deleteAccountWarning => t(
    'Hesabın ve tüm karelerin kalıcı olarak silinecek. Bu işlem geri alınamaz.',
    'Your account and all frames will be permanently deleted. This cannot be undone.',
  );
  String get deletePhoto => t('Fotoğrafı sil', 'Delete photo');
  String get deletePhotoWarning => t(
    'Bu fotoğraf ve yedeklenmiş dosyası kalıcı olarak silinecek.',
    'This photo and its backed-up file will be permanently deleted.',
  );
  String get deletePhotoFailed => t(
    'Fotoğraf silinemedi. Tekrar dene.',
    'Could not delete the photo. Try again.',
  );
  String get deleteAllPhotos => t('Tüm fotoğrafları sil', 'Delete all photos');
  String get deleteAllPhotosHint => t(
    'Tüm fotoğrafların ve yedekleri kalıcı olarak silinir.',
    'Permanently delete all your photos and their backups.',
  );
  String get deleteAllPhotosWarning => t(
    'Tüm fotoğrafların ve yedeklenmiş dosyaları kalıcı olarak silinecek. Bu işlem geri alınamaz.',
    'All your photos and their backed-up files will be permanently deleted. This cannot be undone.',
  );
  String get deleteAllPhotosFailed => t(
    'Fotoğraflar silinemedi. Tekrar dene.',
    'Could not delete the photos. Try again.',
  );
  String accountActionFailed(String code) => t(
    'Hesap işlemi tamamlanamadı ($code).',
    'Account action failed ($code).',
  );
  String get noFeed =>
      t('Henüz herkese açık kare yok.', 'No public frames yet.');
  String get reminderBody => t(
    'Bugünün karesi seni bekliyor. Birkaç saniye, ömürlük bir anı.',
    'Today’s frame is waiting. A few seconds, a lasting memory.',
  );
  String get captureUnavailable => t(
    'Yeni kare hakkın henüz yenilenmedi.',
    'Your next frame is not available yet.',
  );
  String get noFace => t(
    'Net bir yüz bulunamadı. Işığı artırıp tekrar dene.',
    'No clear face found. Try again with better light.',
  );
  String get saveFailed => t(
    'Fotoğraf kaydedilemedi. Bağlantını kontrol edip tekrar dene.',
    'Could not save the photo. Check your connection and try again.',
  );
  String saveFailedWithCode(String code) => t(
    'Fotoğraf kaydedilemedi ($code). İnternet bağlantını kontrol edip tekrar dene.',
    'Could not save the photo ($code). Check your internet connection and try again.',
  );
  String saveFailedForCode(String code) => switch (code) {
    'permission-denied' || 'unauthorized' => t(
      'Fotoğraf kaydedilemedi: Firebase izinleri bu işlemi reddetti.',
      'Could not save the photo: Firebase permissions rejected the operation.',
    ),
    'unauthenticated' => t(
      'Oturumun sona ermiş. Tekrar giriş yapıp yeniden dene.',
      'Your session expired. Sign in again and retry.',
    ),
    'network-request-failed' || 'unavailable' => saveFailed,
    _ => t(
      'Fotoğraf kaydedilemedi ($code).',
      'Could not save the photo ($code).',
    ),
  };
  String get cameraPermission => t(
    'Fotoğraf çekmek için kamera izni gerekli.',
    'Camera permission is required to take a photo.',
  );
  String get captureFailed => t(
    'Fotoğraf işlenemedi. Daha iyi ışıkta tekrar dene.',
    'The photo could not be processed. Try again in better light.',
  );
  String get purchaseUnavailable => t(
    'Satın alma şu anda kullanılamıyor.',
    'Purchases are currently unavailable.',
  );
  String get restorePurchases =>
      t('Satın alımları geri yükle', 'Restore purchases');
  String get purchaseFailed => t(
    'Premium işlemi tamamlanamadı. Lütfen tekrar dene.',
    'The Premium purchase could not be completed. Try again.',
  );
  String get close => t('Kapat', 'Close');
  String get capturedOn => t('Çekim', 'Captured');
}

class AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const AppStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      const ['tr', 'en'].contains(locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture(AppStrings(locale));

  @override
  bool shouldReload(AppStringsDelegate old) => false;
}
