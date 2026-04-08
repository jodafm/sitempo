# SDD Proposal: sitempo-pwa

**Status**: draft
**Created**: 2026-04-07
**Stack**: Flutter 3.41.6 / Dart 3.11.4 / Swift (macOS) → Flutter Web (PWA)

---

## 1. Intent

Sitempo is currently a macOS-only Flutter app. This limits its audience to desktop users and prevents usage on phones, tablets, or any machine without macOS. A Progressive Web App deployment would make sitempo accessible from any device with a modern browser — installable, offline-capable, and zero-friction to try — while preserving the existing native macOS experience with zero regressions.

The goal is **additive**: web becomes a new target alongside macOS, not a replacement. Both platforms share the same UI codebase; only the 6 platform-touching services diverge behind a clean abstraction layer.

---

## 2. Scope

### In scope

| # | Item | Size |
|---|------|------|
| S1 | Abstract 6 platform-specific services behind interfaces with conditional imports | M |
| S2 | Web implementations for AlarmService (HTML5 Audio / audioplayers) | M |
| S3 | Web implementations for ReminderRepository + RoutineRepository (shared_preferences / localStorage) | S |
| S4 | Web implementation for NotificationService (Web Notifications API) | S |
| S5 | Web implementations for StatusBarService (document.title) + WindowService (no-op) | XS |
| S6 | Fix inline platform code in timer_screen.dart (afplay bypass, HttpClient) and reminder_list_screen.dart (Process.run open) | S |
| S7 | Scaffold Flutter web platform + PWA manifest + service worker configuration | S |
| S8 | Add cross-platform packages: `http`, `shared_preferences`, `audioplayers` (or `just_audio`), `file_picker` | XS |

### Out of scope

- iOS / Android / Windows / Linux targets (macOS + web only).
- Redesigning any UI — Flutter renders identically on web; no layout changes needed.
- Backend / server-side components — sitempo remains fully client-side.
- User accounts, cloud sync, or multi-device data sharing.
- Custom sound import on web (deferred — requires IndexedDB blob storage, disproportionate to initial PWA launch).
- Offline-first with background sync — basic offline via service worker cache is in scope; sophisticated sync is not.

---

## 3. Approach

### 3.1 Abstraction Pattern: Abstract Class + Conditional Import

Each platform-specific service becomes a trio:

```
lib/services/
  alarm_service.dart              ← abstract interface + conditional import
  alarm_service_native.dart       ← macOS implementation (current logic, untouched)
  alarm_service_web.dart          ← web implementation (new)
```

The conditional import mechanism:

```dart
// alarm_service.dart
import 'alarm_service_stub.dart'
  if (dart.library.io) 'alarm_service_native.dart'
  if (dart.library.html) 'alarm_service_web.dart';
```

This is the standard Flutter pattern for platform divergence. Zero `kIsWeb` checks leak into UI code. The Dart compiler tree-shakes the unused platform at build time.

**Why not `kIsWeb` guards**: Scattering runtime checks across the codebase creates a maintenance nightmare. Every new platform feature requires hunting through all files. Conditional imports centralize the decision at the import boundary — the compiler resolves it, not the developer at runtime.

**Why not a DI container / service locator**: The app currently uses static service classes with no DI. Introducing GetIt or Riverpod just for platform abstraction is over-engineering. Conditional imports achieve the same result with zero new dependencies and zero architecture changes.

### 3.2 Service-by-Service Strategy

#### AlarmService (CRITICAL — highest complexity)

- **Native**: Current `Process.run('afplay', ...)` + `osascript` + filesystem logic moves to `alarm_service_native.dart` unchanged.
- **Web**: `audioplayers` package for cross-platform audio playback. System sounds become bundled assets under `web/assets/sounds/`. Looping alarm uses `AudioPlayer.setReleaseMode(ReleaseMode.loop)`. Sound import deferred (out of scope for initial PWA).
- **Risk**: Browser AudioContext requires a user gesture to unlock. Timer start is a gesture (OK). Background reminder alarm is NOT — mitigated by showing a visual alert modal (already exists) and attempting audio as best-effort.

#### ReminderRepository + RoutineRepository (HIGH — data persistence)

- **Native**: Current `dart:io` File I/O moves to `*_native.dart` unchanged.
- **Web**: `shared_preferences` package (web implementation uses localStorage). JSON serialization is identical — only the read/write transport changes. Same `loadAll()` / `saveAll()` API shape.
- **Risk**: localStorage has 5-10MB limit. Routine/reminder JSON is tiny (< 50KB typical). No concern.

#### NotificationService (HIGH — user-facing feature)

- **Native**: Current MethodChannel → UNUserNotificationCenter moves to `notification_service_native.dart` unchanged.
- **Web**: Web Notifications API via `dart:js_interop` or `web` package. Permission model maps 1:1: `granted`/`denied`/`default` ≈ `notDetermined`. `Notification(title, {body: body})` for display.
- **Risk**: Requires HTTPS in production (localhost exempt for dev). Many browsers block notifications by default — permission flow already handled in the app.

#### StatusBarService (LOW — cosmetic fallback)

- **Native**: Current MethodChannel → NSStatusItem unchanged.
- **Web**: Update `document.title` with timer state (e.g. `"⏱ 12:34 – Sentado | sitempo"`). No system tray equivalent exists in browsers. This is a graceful degradation, not a functional equivalent.

#### WindowService (LOW — no-op on web)

- **Native**: Current MethodChannel → NSApp.activate unchanged.
- **Web**: `window.focus()` — severely restricted by browser security (only works from user gesture). Becomes effectively a no-op. Acceptable: web users already have the tab open.

### 3.3 Inline Platform Code Fixes

| Location | Current | Fix |
|----------|---------|-----|
| `timer_screen.dart:171` | `Process.run('afplay', ...)` directly | Route through `AlarmService.playTransition()` — this is a bug regardless of web |
| `timer_screen.dart:1113` | `dart:io HttpClient` for webhooks | Replace with `http` package (`package:http`) — works on both platforms |
| `reminder_list_screen.dart:61-64` | `Process.run('open', ...)` for System Preferences | Platform-conditional: native keeps current behavior, web shows a snackbar explaining how to enable notifications in browser settings |

### 3.4 PWA Configuration

1. **Scaffold**: `flutter create --platforms web .` — adds `web/` directory without touching existing code.
2. **Manifest**: Configure `web/manifest.json` with app name, theme color, icons, `"display": "standalone"` for native-like experience.
3. **Service Worker**: Flutter's default service worker caches app shell for offline launch. No custom SW logic needed for initial release.
4. **Icons**: Generate PWA icon set from existing app icon (192x192, 512x512 minimum).

### 3.5 Implementation Order

Ordered to minimize broken intermediate states and enable incremental testing:

1. Scaffold web platform + add packages to pubspec.yaml
2. Abstract repositories (no UI impact, pure data layer)
3. Abstract AlarmService (highest complexity, most callers) + fix timer_screen.dart bypass
4. Abstract NotificationService
5. Abstract StatusBarService + WindowService (trivial)
6. Fix remaining inline platform code (HttpClient, Process.run open)
7. PWA manifest + service worker + icons
8. Integration test on Chrome

---

## 4. Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **AudioContext requires user gesture** | HIGH | Timer start is a user gesture — unlocks audio. Background reminder alarm may be silently blocked. Mitigation: always show visual alert modal (already exists); audio is best-effort enhancement. |
| **Web Notifications require HTTPS** | MEDIUM | Deploy behind HTTPS (standard for any PWA). localhost exempt for development. |
| **Sound import not feasible on web** | MEDIUM | Deferred to future iteration. Web users get bundled system sounds only. Native users keep full import capability. Clear scope boundary. |
| **Conditional import complexity** | MEDIUM | Pattern is well-established in Flutter ecosystem. Each service is small (< 100 lines). The trio structure (abstract + native + web) is self-documenting. |
| **No menu bar equivalent on web** | LOW | StatusBarService degrades to document.title update. Cosmetic, not functional. Users won't miss what they never had. |
| **localStorage 5MB limit** | LOW | App data is < 50KB. Not a concern unless users somehow create thousands of routines. |
| **Window.focus() restricted on web** | LOW | WindowService becomes no-op. Notifications + visual alerts compensate. |
| **12 new files in services/** | LOW | Each file is small and single-purpose. The alternative (one file with kIsWeb checks) is worse for maintenance. |

---

## 5. Effort Estimate

| Item | Estimate | Confidence |
|------|----------|------------|
| S1 — Service abstraction layer (6 interfaces) | **S** (~1-2 hr) | High |
| S2 — AlarmService web implementation | **M** (~2-3 hr) | Medium |
| S3 — Repository web implementations (x2) | **S** (~1-2 hr) | High |
| S4 — NotificationService web implementation | **S** (~1 hr) | High |
| S5 — StatusBar + Window web implementations | **XS** (~30 min) | High |
| S6 — Inline platform code fixes | **S** (~1 hr) | High |
| S7 — Web scaffold + PWA manifest | **S** (~1 hr) | High |
| S8 — Package additions | **XS** (~15 min) | High |
| **Overall** | **L** (~8-11 hr) | Medium |

Confidence is Medium overall because AlarmService web (S2) has the most unknowns around browser audio policies and the audioplayers package's web maturity.

---

## 6. Recommended Next Steps

1. **Spec phase**: Write delta specs with acceptance criteria for each service abstraction and the PWA configuration. Key scenarios: audio playback on web (first play, background play, looping), notification permission flow on web, data persistence round-trip via localStorage.
2. **Design phase**: Detail the abstract class contracts for all 6 services, the conditional import wiring, and the PWA manifest configuration. Decide between `audioplayers` vs `just_audio` for web audio.
3. **Tasks phase**: Break into atomic tasks following the implementation order in section 3.5. Each task should be independently testable.
