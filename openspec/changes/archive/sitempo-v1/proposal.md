# Proposal: sitempo-v1

## Intent

Developers and knowledge workers who spend long hours at a desk suffer from poor posture habits, dehydration, and eye strain. Existing timer apps are either too generic (simple Pomodoro) or too complex (full wellness platforms). sitempo was built to solve this specific problem: a lightweight macOS desktop app that manages **posture routines** (alternating between sitting, standing, stretching, and other activities) with **parallel health reminders** (water, 20-20-20 eye rule), all visible at a glance from the macOS menu bar.

The app is designed for a single user running it locally on macOS, with zero cloud dependencies and full offline operation.

## Scope

### Included

1. **Posture timer engine** -- a 1-second tick timer that walks through a routine's expanded steps (cycle x repeatCount + optional break), auto-advancing and looping indefinitely.
2. **Customizable routines** -- users create routines composed of a cycle (ordered list of activity+duration pairs), a repeat count (1-10), and an optional break step. A default "Sentado / De pie" routine ships out of the box.
3. **Custom activities** -- users define activities with emoji, label, and color (not hardcoded). Seven defaults provided (sitting, standing, stretching, movement, walking, squats, visual rest).
4. **Reminders system** -- runs in parallel to the posture timer. Each reminder fires a native macOS notification at its configured interval (e.g., every 30 min for water). Two defaults: water (30 min) and 20-20-20 eye rule (20 min). Users can add custom reminders.
5. **macOS menu bar integration** -- NSStatusItem showing current activity emoji + countdown timer, updated every second. Clicking it brings the app window to front.
6. **Native macOS notifications** -- via UNUserNotificationCenter through a Flutter MethodChannel bridge. Notifications appear even when the app is in foreground (UNUserNotificationCenterDelegate configured).
7. **Sound alarms** -- Hero system sound on timer start, Glass system sound on step transitions. Uses macOS built-in `/System/Library/Sounds/` via `afplay`.
8. **Interactive timeline** -- visual representation of routine progress showing cycle headers, break separators, current step highlight, completed step strikethrough, and step descriptions.
9. **Step descriptions** -- each step can carry an optional description shown in the timeline when that step is active (e.g., "Anda por agua o estira las piernas").
10. **JSON persistence** -- all user data (custom activities, routines, reminders) stored in `~/.sitempo/` as separate JSON files. Default items are never persisted; only custom items are saved.
11. **Routine editor with live preview** -- full CRUD for routines with drag-to-reorder steps, duration +/- controls (1-120 min), inline activity creation, and a chip-based visual preview of the expanded sequence.
12. **Reminder management** -- list screen with enable/disable toggles, edit/delete for custom reminders, and a creation dialog with emoji picker and interval selector (5-480 min in 5-min increments).

### Not included

- Multi-platform support (macOS only; no iOS, Android, Windows, Linux targets)
- State management library (no Riverpod, Bloc, Provider -- pure StatefulWidget)
- User accounts, sync, or cloud storage
- Analytics or telemetry
- Automated testing (no unit, widget, or integration tests)
- Internationalization (UI is in Rioplatense Spanish only)
- Notification scheduling (notifications fire imperatively, not via scheduled OS triggers)
- Background execution or persistent timer when app is closed

## Approach

### Architecture

The app follows a **flat, pragmatic architecture** appropriate for its scope (single-screen app with two modal editors):

- **`lib/models/`** -- immutable data classes with JSON serialization (`toJson`/`fromJson`), `copyWith`, and static defaults. No external serialization libraries.
- **`lib/services/`** -- six stateless/static service classes handling specific platform concerns:
  - `StatusBarService` -- MethodChannel bridge to NSStatusItem
  - `NotificationService` -- MethodChannel bridge to UNUserNotificationCenter
  - `AlarmService` -- sound playback via macOS `afplay` CLI
  - `RoutineRepository` -- JSON file I/O for routines and activities
  - `ReminderRepository` -- JSON file I/O for reminders
  - `ReminderService` -- stateful tick-based reminder scheduler
- **`lib/screens/`** -- five screen/dialog widgets:
  - `TimerScreen` -- main screen; owns all app state as a StatefulWidget
  - `RoutineEditorScreen` -- full-page routine CRUD
  - `ActivityEditorDialog` -- modal dialog for creating activities
  - `ReminderListScreen` -- full-page reminder list with toggles
  - `ReminderEditorDialog` -- modal dialog for creating/editing reminders
- **`macos/Runner/`** -- Swift native layer:
  - `MainFlutterWindow` -- sets up NSStatusItem, registers two MethodChannels (statusbar + notifications)
  - `AppDelegate` -- configures UNUserNotificationCenterDelegate for foreground notifications

### Patterns

- **No state management library**: `TimerScreen` is the single source of truth. All state lives in `_TimerScreenState` and is passed down via constructor parameters or received back via Navigator results. This is intentional for a single-screen app.
- **Static repositories**: `RoutineRepository` and `ReminderRepository` use static methods and file paths derived from `$HOME`. No dependency injection.
- **Default/custom merge pattern**: All three entity types (Activity, Routine, Reminder) ship with `isDefault` defaults that are always present. Persistence only saves custom items. On load, defaults are merged with saved custom items, preserving user modifications to default items' mutable fields (e.g., reminder enabled state).
- **Flutter-to-native bridge**: Two `MethodChannel`s (`com.sitempo/statusbar` and `com.sitempo/notifications`) handle platform integration. The Swift side registers handlers in `MainFlutterWindow.awakeFromNib()`.
- **Timer architecture**: A single `Timer.periodic(1 second)` drives both the posture countdown and reminder ticks. The `ReminderService` maintains per-reminder elapsed-second counters and fires notifications when thresholds are reached.

### UI

- Dark theme with custom background (`#1A1A2E`) and accent color (`#6C9BFF`)
- Material 3 with custom styling throughout
- Fixed window size (440x820) with a minimum of 380x650
- Custom `_TimerRingPainter` (CustomPainter) for the circular progress indicator
- All UI text in Rioplatense Spanish

## Key Decisions

1. **No state management library** -- For a single-screen app with one timer and two modal editors, StatefulWidget is sufficient. Adding Provider/Bloc/Riverpod would be over-engineering. The tradeoff is that `TimerScreen` is a large widget (~700 lines) that owns all state.

2. **Static repositories over dependency injection** -- The app has exactly one data directory (`~/.sitempo/`), one user, and no test suite. Static methods eliminate boilerplate with no practical downside at this scale.

3. **MethodChannel over FFI or plugins** -- For two simple native features (status bar text + notifications), MethodChannel is the simplest bridge. No third-party plugin dependencies were introduced.

4. **`afplay` for sounds over AVAudioPlayer** -- Using macOS system CLI avoids another MethodChannel and native code. The tradeoff is no volume control and a spawned process per sound, but for infrequent alarm sounds this is negligible.

5. **Separate JSON files over SQLite** -- Three small JSON files (`routines.json`, `activities.json`, `reminders.json`) in `~/.sitempo/` are simpler than a database for a dataset that will never exceed a few KB.

6. **Persistence of custom items only** -- Default activities, routines, and reminders are defined in code. Only user-created items are persisted. This keeps the JSON files minimal and allows defaults to be updated in code without migration logic.

7. **Single timer driving both systems** -- One `Timer.periodic(1s)` ticks both the posture countdown and the `ReminderService`. This avoids timer drift between systems and simplifies start/pause/reset logic.

8. **Spanish-only UI** -- The app was built for personal use. No i18n framework was added. All strings are inline in Rioplatense Spanish.

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| No tests | Regressions go undetected | App is small enough for manual testing; adding widget tests is a natural next step |
| Large `TimerScreen` widget (~700 LOC) | Hard to maintain as features grow | Extract state to a dedicated controller or adopt a state management solution if scope increases |
| `afplay` process spawn for sounds | Minor resource overhead | Sounds fire infrequently (on start + transitions); negligible in practice |
| No background execution | Timer stops if app is closed | This is a desktop app meant to stay open; macOS keeps it running in the dock |
| `$HOME` environment variable dependency | Could fail in sandboxed contexts | macOS Flutter desktop apps run unsandboxed by default; `$HOME` is always available |
| No data migration strategy | Schema changes could break saved JSON | Current data model is simple; `fromJson` uses defaults for missing fields, providing forward compatibility |
| Timer drift over long periods | 1-second `Timer.periodic` may accumulate drift | Acceptable for posture reminders where seconds-level precision is not critical |

## Rollback Plan

The app has no external dependencies, no backend, and no shared state:

1. **Code rollback**: `git revert` or `git reset` to any prior commit
2. **Data rollback**: Delete `~/.sitempo/` directory to return to defaults
3. **Clean uninstall**: Delete the app bundle + `~/.sitempo/`

No database migrations, no API contracts, no remote state to worry about.
