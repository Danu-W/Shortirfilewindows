# Shortir File (Flutter)

Cross-platform product foundation for macOS, Windows, Android, and iOS. The existing SwiftUI Mac app is kept separately in `../ShortirFile/` while this version is developed.

## Current foundation

- Indonesian and English interface, light/dark appearance, local folder selection, photo/document filtering, and moving selected files into a new folder.
- Optional Supabase email/password account flow. Set the public Supabase URL and publishable key with `--dart-define` when running/building.
- Supabase migration for per-account language settings and read-only client access to server-managed subscription entitlements. Language is synchronized when signed in; subscription status is checked at startup, after sign-in, and when the app returns to the foreground.
- Subscription purchases are not live yet. The database intentionally prevents a client app from granting itself Pro. Xendit credentials and verified server-side payment notifications must be configured before charging customers.

## Free plan limits

Accounts without an active `pro` entitlement (including local use without Supabase configured) are on the Free plan: at most 100 files per sort and 3 completed sorts per calendar month. Pro accounts (`billing_entitlements.status` is `active` or `grace_period` and not expired) skip both limits, and a banner in the workspace shows the remaining Free quota with an Upgrade shortcut.

Usage counters are stored per account/device in `shared_preferences`, so they survive app restarts but reset on reinstall or when local app data is cleared. Move enforcement to a server-side quota before treating Free limits as a billing control.

## Tooling

Flutter 3.47.8 and Dart 3.13.7 are now installed at `~/Downloads/flutter` and on the interactive zsh `PATH`. Native runner folders for macOS, Windows, Android, and iOS are included in this project. Check setup with:

```sh
flutter doctor -v
flutter pub get
flutter run -d macos
```

Dependencies are resolved in the local cache. This environment cannot resolve external package hosts, so fresh dependency downloads and Android Gradle downloads require working network access. Android SDK Command-line Tools and licenses are installed. CocoaPods 1.17.0 is installed through Homebrew; the interactive shell loads Homebrew from `/opt/homebrew/bin`. `flutter doctor -v` still reports that Xcode needs its first-run components. Windows desktop builds require a Windows machine with Visual Studio's Desktop development with C++ workload.

## Windows CI build

`.github/workflows/windows-build.yml` builds the Windows release on `windows-latest` without a local Windows machine. Add these repository secrets under Settings > Secrets and variables > Actions:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

The workflow runs `flutter analyze`, then `flutter build windows --release`, and uploads `shortir-file-windows-x64.zip` plus its SHA-256 file. Trigger it by pushing to `main`/`master` (changes under `lib/`, `windows/`, `assets/`, `pubspec.*`, or the workflow itself), opening a pull request, or running **Windows build** manually from the Actions tab. The publishable key is a public client value; never add a service-role or Xendit secret to the app.

## Windows deep links

The Windows runner registers `shortirfile://` under `HKCU\Software\Classes\shortirfile` on launch, then forwards incoming links to the running instance. Supabase email confirmation and password-recovery redirects therefore open the app on Windows, the same way they do on macOS. The scheme is registered on first launch, so launch the portable app once before testing an email link; if the app folder is moved, launch it once from the new path to update the registry entry. The portable build does not clean up the registry key on removal; delete `HKCU\Software\Classes\shortirfile` manually if desired.

## Supabase setup

1. Create a Supabase project and apply `supabase/migrations/202610270001_initial_account_entitlements.sql`.
2. In Authentication > URL Configuration, add `shortirfile://login-callback/` to Redirect URLs. The Mac app registers this scheme and requests it for signup confirmation links.
3. Run locally with:

```sh
flutter run -d macos --dart-define-from-file=.supabase.local.json
```

Only the publishable client key belongs in the app. Never embed a Supabase service-role key or Xendit secret key in the client.

## Product and billing roadmap

1. Validate local file access, directory permissions, and moves on each operating system. Mobile systems use user-selected folders and may not expose unrestricted filesystem access.
2. Sync harmless account preferences (language) and subscription entitlement by Supabase user ID. Keep users' files on-device in the first release; cloud file backup would need a separate storage design and explicit opt-in.
3. Configure Xendit invoices and verified server notifications. A trusted server updates `billing_entitlements`; all signed-in devices read the same entitlement row.
4. Add cancellation, restore purchase, account deletion, privacy policy, and store review flows before public launch.

The Dart source passes static analysis. A macOS build was attempted but is blocked in this environment when Xcode invokes Swift Package Manager (`sandbox-exec: sandbox_apply: Operation not permitted`). An Android APK build was attempted but could not download Gradle because `services.gradle.org` is unreachable here. Run the builds on a machine with the required network access and a fully initialized Xcode installation.
