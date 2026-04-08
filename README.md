# sitempo

Posture timer for macOS and Web. Customizable routines, task reminders with webhooks, and configurable alerts.

## Platforms

- **macOS** — native app with menu bar integration, system notifications, and system sounds
- **Web (PWA)** — progressive web app deployable to Vercel or any static host

## Development

### Requirements

- Flutter 3.41.6+
- Dart 3.11.4+
- Xcode (for macOS builds)

### Run locally

```bash
# macOS
flutter run -d macos

# Web
flutter run -d chrome
```

### Build

```bash
# macOS release
flutter build macos --release

# Web
flutter build web
```

### Tests

```bash
flutter test
flutter analyze
```

## Deploy to Vercel

Vercel does not have Flutter installed, so you build locally and deploy the static output.

### First time setup

```bash
npm i -g vercel
vercel login
```

### Deploy

```bash
flutter build web
cd build/web
vercel deploy --prod
```

When prompted on first deploy:
- **Link to existing project?** Yes (if already created) or No to create new
- **Project name**: sitempo
- **Directory**: `./`
- **Want to modify settings?** Yes
  - **Build Command**: leave empty (press enter)
  - **Output Directory**: `.`

### Subsequent deploys

```bash
flutter build web && cd build/web && vercel deploy --prod
```

### Custom domain

In Vercel dashboard: **Settings > Domains > Add** your custom domain.

### Important notes

- `vercel.json` in the repo root only has route config (SPA fallback). No build command — Vercel serves pre-built static files.
- Always build locally before deploying. The `build/web/` directory is gitignored.
- Sound assets (`.m4a`) are bundled in the web build automatically from `assets/sounds/`.

## Install macOS app

```bash
flutter build macos --release
cp -R build/macos/Build/Products/Release/sitempo.app /Applications/
```

## Architecture

- **Models**: `lib/models/` — platform-agnostic data models
- **Services**: `lib/services/` — barrel exports with conditional imports
  - `lib/services/platform/*_native.dart` — macOS implementations (dart:io, MethodChannel)
  - `lib/services/platform/*_web.dart` — web implementations (audioplayers, shared_preferences, Web APIs)
- **Screens**: `lib/screens/` — Flutter UI (shared across platforms, zero dart:io imports)
