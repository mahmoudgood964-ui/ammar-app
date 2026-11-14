# عَمِّر | AMMIR — Native Mobile

This folder contains the Capacitor-based native delivery layer for Android and iOS. It packages the existing AMMIR application files locally; it does not replace the production web application or change the Supabase schema.

## Native application identity

- Display name: عَمِّر | AMMIR
- Android application ID / iOS bundle ID: com.ammir.app
- Native runtime: Capacitor 8.6.2
- Web application: existing root index.html, ammar-marketplace.js and ammir-identity.css
- App assets: generated from the approved AMMIR mark in assets/logo.svg

## Native capabilities wired in

- Native camera and photo-library capture, attached to existing image file inputs so the current upload workflow is preserved.
- Native share sheet for invitation and project links.
- External web destinations open in the system browser surface rather than replacing the app.
- Native Android back-button handling.
- Native status bar, launch splash and safe-area support.
- Device network-state detection with a visible offline notice.
- Light haptic feedback on primary controls.

The app uses Supabase for live records, authentication, storage and Realtime. The native package bundles the application shell and front-end assets locally, but project data and account operations still require a network connection. The offline banner is not an offline database or a promise of background synchronization.

## Build locally

Requires Node.js 22+, Android Studio / Android SDK for Android, and macOS with Xcode for iOS.

Run from the mobile folder:

    npm install
    npm run build:web
    npx cap add android
    npx cap add ios
    npx capacitor-assets generate --android --iconBackgroundColor "#102f29" --splashBackgroundColor "#102f29"
    npx capacitor-assets generate --ios --iconBackgroundColor "#102f29" --splashBackgroundColor "#102f29"
    npx cap sync
    npm run prepare:android
    npm run prepare:ios

Then open android in Android Studio or ios/App/App.xcodeproj in Xcode.

## GitHub Actions outputs

The workflow at .github/workflows/ammir-native-build.yml builds:

- Android debug APK: signed with the standard debug key, suitable for device QA and direct test installation.
- Android release AAB: unsigned, suitable for build validation only until a production upload key is configured.
- iOS Simulator app: suitable for Simulator testing, not directly installable on a physical iPhone.

## iPhone distribution requirements

A physical-device IPA and TestFlight / App Store submission require the owner's Apple Developer account, bundle-ID ownership, signing certificate, provisioning profile and App Store Connect setup. Those credentials are intentionally not stored in this repository or in source code. The iOS project and build workflow are prepared, but no unsigned simulator archive is represented as an iPhone-installable IPA.

Apple review also evaluates whether the product offers meaningful app-specific value beyond a repackaged website. The native camera, sharing, system navigation and network-aware behavior are integrated, but approval is never guaranteed; a final device QA pass and complete App Store metadata / reviewer access are still required.

## Notes

- No Supabase migration or production database write is performed by this mobile layer.
- The deferred bank payment milestone workflow is untouched.
- Production remains at https://ammar-app.vercel.app

## Continuous build verification

The repository workflow builds both platform targets on changes to this folder or on manual dispatch:

- `ammir-android-builds`: Android debug APK for install testing and an unsigned release AAB for packaging validation.
- `ammir-ios-simulator`: iOS Simulator app archive for simulator validation only.

A successful CI build validates compilation and artifact packaging. It does not replace device-level testing of camera permissions, file uploads and downloads, Realtime behavior, push notifications, offline operation, or account recovery.

## Release acceptance checklist

Before public release, record a separate pass/fail result for each item:

1. Android physical-device install, first launch, update/install-over-existing, and launcher icon.
2. Android camera and photo-library permissions, capture, upload, preview, and deletion.
3. iPhone/iPad physical-device signing, installation, safe-area layout, camera/photo library, and sharing.
4. Owner and provider accounts: registration, confirmation, sign-in, password recovery, and sign-out.
5. Project file access with two unrelated accounts, including denied cross-project downloads.
6. Realtime messages, notifications, delivery/read receipts, and reconnect after network loss.
7. 360px, 390px, and tablet/desktop layouts; Arabic and English content; weak network behavior.
8. Store distribution signing, privacy disclosures, screenshots, support URL, and reviewer credentials.

Do not mark an item complete based only on a simulator or synthetic database test. Keep real-device and two-account acceptance evidence alongside the release record.
