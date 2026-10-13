# FaceMorph

FaceMorph aligns one face photo per day and turns the history into a consistent
timelapse. The Flutter client supports Android and iOS, uses English as its only
interface language, and includes light, dark, and system themes.

## Included

- Google-only Firebase Authentication
- 14-day Premium trial, daily Premium quota, and weekly free quota
- Front-camera live eye/mouth alignment score with directional guidance, ML Kit
  rotation/crop/scale normalization, and a personal first-frame reference
- Profile calendar, animated preview, and local MP4 generation/sharing
- Gallery selfie import plus date-preserving ZIP photo backup import/export
- Daily local notifications at 20:00
- Explore Friends/Global feeds, public/private photo visibility, following, and likes
- Store-backed monthly product `oneframe_premium_monthly`
- Firestore rules, indexes, Bunny.net image storage, and secure purchase verification
  Cloud Functions

## Architecture

The app uses a feature-first MVVM presentation layer over repositories and
stateless Firebase/platform services. Shared theme, localization, and widgets
live under `lib/core`; immutable business models live under `lib/domain`.
The main navigation is Explore, Today, and Profile. Appearance, privacy,
notifications, sign-out, and account deletion are under Profile > Settings;
appearance intentionally offers only Light and Dark modes.

## Firebase

Project: `phototimelapse-20260901` (Europe `eur3` Firestore)

Google Authentication, Android/iOS app registrations, debug/release SHA
fingerprints, Firestore rules, and composite indexes are already configured. New Firebase
projects require a Blaze billing account before Cloud Functions can be activated.

## Bunny.net

Create a Bunny Storage Zone and a Pull Zone pointing to it. Enable Token
Authentication on the Pull Zone. Copy `firebase/functions/.env.example` to
`firebase/functions/.env.local`, then fill in the storage zone, storage hostname,
and CDN URL. Set the Bunny Storage API key and Pull Zone URL Token Authentication
Key as environment variables on the Cloud Functions that use them:

```sh
BUNNY_STORAGE_ACCESS_KEY=...
BUNNY_TOKEN_AUTH_KEY=...
```

The app uploads through authenticated Cloud Functions; the Bunny API key is
never shipped in the Flutter binary. Configure both keys on `deleteAccount`,
`deleteAllPhotos`, `uploadPhoto`, `deletePhoto`, and `enforceCaptureQuota`. Keep
real values out of tracked files. `BUNNY_CDN_BASE_URL` must be the public Pull
Zone URL used to serve the uploaded images.

Give the Functions runtime service account Google Play Android Publisher access
and configure the monthly subscription product in Play Console. Set its
Türkiye price to ₺10 and other storefront base price to USD 1; Google Play
performs local currency conversion and tax handling.

## Verification

```sh
flutter analyze
flutter test
flutter build apk --debug
cd firebase/functions && npm run build
```

Android release signing uses the following environment variables without
storing the keystore in the repository: `KARGALAR_KEYSTORE_PATH`, `KARGALAR_KEYSTORE_PASSWORD`,
`KARGALAR_KEY_ALIAS`, `KARGALAR_KEY_PASSWORD`. Bu değişkenler tanımlıyken
`flutter build appbundle --release` imzalı Play Store paketi üretir.

## Google Play release

The Android release is configured with application ID
`app.facemorph`, minimum SDK 24, and the current Flutter target
SDK 36. Release tasks fail when the upload keystore is missing, so an unsigned
bundle cannot be mistaken for an uploadable artifact. Use
`android/key.properties.example` as the local configuration template; keep
`android/key.properties` and all keystores outside version control.

Run the final checks and build the bundle with explicit release metadata:

```sh
flutter analyze
flutter test
npm --prefix firebase/functions run build
firebase deploy --only hosting,functions
flutter build appbundle --release --build-name=1.0.0 --build-number=1
```

The Hosting deployment publishes the privacy policy at
`/privacy-policy`, terms at `/terms-of-use`, and the external account deletion
resource at `/delete-account`. Enter the deployed privacy and deletion URLs in
Play Console, complete the Data safety and content declarations, enable Play
App Signing, and add the upload and Play signing certificate fingerprints to
the Firebase Android app. Configure `oneframe_premium_monthly` in Play Console
before enabling production purchases; the verification Cloud Function also
needs the Android Publisher role described above.

## License

FaceMorph is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
