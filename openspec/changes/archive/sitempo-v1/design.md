# Technical Design: sitempo-v1

## Architecture Overview

Sitempo is a macOS desktop posture timer application built with Flutter targeting macOS, using a native Swift bridge for OS-level integrations (status bar, notifications). The architecture is intentionally simple: no state management package, no DI framework, no routing library. State lives in `StatefulWidget`s, services are static classes, and native communication uses `MethodChannel`.

```
+-----------------------------------------------------------+
|                     macOS Native Layer                     |
|  MainFlutterWindow (NSStatusItem + MethodChannels)         |
|  AppDelegate (UNUserNotificationCenterDelegate)            |
+---------------------------+-------------------------------+
          |  MethodChannel: com.sitempo/statusbar
          |  MethodChannel: com.sitempo/notifications
+---------------------------+-------------------------------+
|                     Flutter Application                    |
|                                                            |
|  +-------+   +----------+   +---------------------------+  |
|  | Models |   | Services |   |         Screens           |  |
|  |--------|   |----------|   |---------------------------|  |
|  |Activity|   |AlarmSvc  |   | TimerScreen (main hub)    |  |
|  |Routine |   |StatusBar |   | RoutineEditorScreen       |  |
|  |Reminder|   |Notif.Svc |   | ActivityEditorDialog      |  |
|  |Routine |   |Reminder  |   | ReminderListScreen        |  |
|  | Step   |   | Service  |   | ReminderEditorDialog      |  |
|  |        |   |RoutineRep|   |                           |  |
|  |        |   |ReminderRp|   |                           |  |
|  +-------+   +----------+   +---------------------------+  |
|                                                            |
+-----------------------------------------------------------+
          |
          v
  ~/.sitempo/  (JSON file persistence)
    routines.json
    activities.json
    reminders.json
```

## Component Design

### Models Layer

#### Activity (`lib/models/activity.dart`)
- **Fields**: `id` (String), `label` (String), `emoji` (String), `colorValue` (int, stored as 0xAARRGGBB), `isDefault` (bool)
- **Computed**: `color` getter that converts `colorValue` to `Color`
- **Serialization**: `toJson()`/`fromJson()` with manual JSON mapping
- **Static data**: 7 default activities (sitting, standing, stretching, movement, walking, squats, visual-rest), 16 available emojis, 8 available colors
- **Relationships**: Referenced by `RoutineStep.activityId` (string-based foreign key, resolved at runtime via `resolveActivity()`)
- **Identity**: `isDefault` flag distinguishes built-in vs user-created activities. Default activities use semantic IDs (`sitting`, `standing`), custom ones use `custom-{timestamp}`

#### Routine (`lib/models/routine.dart`)
- **Fields**: `id` (String), `name` (String), `cycle` (List<RoutineStep>), `repeatCount` (int, default 1), `breakStep` (RoutineStep?, optional), `isDefault` (bool)
- **Computed**: `expandedSteps` flattens `cycle * repeatCount + breakStep` into a linear list. `totalMinutes` sums all expanded step durations
- **Serialization**: `toJson()`/`fromJson()` + static `encode()`/`decode()` for list-level JSON encoding
- **Static data**: 1 default routine ("Sentado / De pie": 45min sitting + 15min standing)
- **Identity**: Same `isDefault` pattern as Activity. Custom IDs use `custom-{timestamp}`

#### RoutineStep (embedded in `lib/models/routine.dart`)
- **Fields**: `activityId` (String), `duration` (Duration, serialized as `durationMinutes` int), `description` (String, optional, omitted from JSON when empty)
- **Not a standalone entity**: No `id`, no persistence of its own. Always nested inside a Routine
- **Resolution**: `resolveActivity(List<Activity>)` performs a runtime lookup by `activityId`, falling back to `Activity.defaults.first` if not found

#### Reminder (`lib/models/reminder.dart`)
- **Fields**: `id` (String), `emoji` (String), `label` (String), `intervalMinutes` (int), `description` (String, optional), `isDefault` (bool), `enabled` (bool, default true)
- **Serialization**: `toJson()`/`fromJson()` + static `encode()`/`decode()` for list-level JSON
- **Static data**: 2 defaults (water every 30min, 20-20-20 rule every 20min), 16 available emojis
- **Identity**: Same `isDefault`/`custom-{timestamp}` pattern

### Services Layer

#### AlarmService (`lib/services/alarm_service.dart`)
- **Pattern**: Static class, no state, no dependencies
- **Responsibility**: Play macOS system sounds via `afplay` subprocess
- **Methods**: `playTransition()` plays Glass.aiff (step change), `playStart()` plays Hero.aiff (timer start)
- **Communication**: `dart:io` `Process.run()` to spawn `afplay` with a system sound file path
- **Note**: Fire-and-forget async calls. No error handling if sound file missing or `afplay` fails

#### StatusBarService (`lib/services/status_bar_service.dart`)
- **Pattern**: Static class, no state
- **Responsibility**: Update macOS menu bar status item with current timer info
- **Channel**: `com.sitempo/statusbar`
- **Methods**: `update({time, emoji})` sets status bar text, `clear()` resets to default placeholder
- **Contract**: Sends `Map<String, String>` with keys `time` and `emoji`

#### NotificationService (`lib/services/notification_service.dart`)
- **Pattern**: Static class, no state
- **Responsibility**: Request notification permission and show macOS notifications
- **Channel**: `com.sitempo/notifications`
- **Methods**: `requestPermission()` returns bool, `show({title, body})` fires a notification
- **Contract**: `requestPermission` takes no args, returns bool. `show` sends `Map<String, String>` with `title` and `body`

#### ReminderService (`lib/services/reminder_service.dart`)
- **Pattern**: Instance class (the only non-static service). Holds mutable state
- **Responsibility**: Tick-based engine that tracks elapsed seconds per reminder and fires notifications when interval is reached
- **State**: `_reminders` (current list), `_elapsedSeconds` (Map<String, int> tracking seconds since last fire per reminder ID)
- **Methods**: `load()` sets reminders and initializes counters (uses `putIfAbsent` to preserve existing counts). `tick()` increments all enabled reminders by 1 second, fires notification when threshold reached, resets counter. `reset()` zeros all counters
- **Dependency**: Calls `NotificationService.show()` directly (static call, no injection)
- **Tick source**: Called every second from `TimerScreen._tick()`. Only ticks while timer is running

#### RoutineRepository (`lib/services/routine_repository.dart`)
- **Pattern**: Static class, no state
- **Responsibility**: Load/save activities and routines from `~/.sitempo/` JSON files
- **Files**: `~/.sitempo/routines.json`, `~/.sitempo/activities.json`
- **Load strategy**: If file missing or empty, return defaults. Otherwise, load saved data, filter out items with default IDs, then merge: `[...defaults, ...customOnly]`
- **Save strategy**: Only persists custom (non-default) items. Defaults are always reconstructed from code
- **Directory**: Auto-creates `~/.sitempo/` on first save via `_ensureDir()`

#### ReminderRepository (`lib/services/reminder_repository.dart`)
- **Pattern**: Static class, no state
- **Responsibility**: Load/save reminders from `~/.sitempo/reminders.json`
- **Load strategy**: Same defaults-first pattern but with a twist: for default reminders that exist in saved data, it preserves the saved `enabled` state (merges user toggle preference into the default template)
- **Save strategy**: Persists ALL reminders (both default and custom) because it needs to track the `enabled` toggle state of defaults. This differs from RoutineRepository which only saves custom items

### Screens Layer

#### TimerScreen (`lib/screens/timer_screen.dart`) - Main Hub
- **Role**: Primary screen, root of the app. Contains ALL timer logic, state, and navigation
- **State**: `_routines`, `_activities`, `_reminders` (data lists), `_selectedRoutineIndex`, `_currentStepIndex`, `_remaining` (Duration countdown), `_timer` (dart:async Timer), `_isRunning`, `_completedCycles`, `_loading`, `_reminderService` (instance)
- **Timer mechanics**: 1-second periodic `Timer`. Each tick: decrements `_remaining`, calls `_reminderService.tick()`, updates status bar. When `_remaining` hits 0: advances to next step (or wraps to step 0, incrementing `_completedCycles`), plays transition sound
- **Navigation**: Push to `RoutineEditorScreen` (returns `Routine?`), push to `ReminderListScreen` (returns `List<Reminder>?`). Uses imperative `Navigator.push()` with result
- **UI components**: Routine selector (PopupMenuButton dropdown), activity label (emoji + name), timer ring (custom `CustomPainter` arc), controls (start/pause, reset, skip), timeline (vertical step list with cycle/break headers)
- **Data flow**: Loads all data in `initState()` via `Future.wait()`. Saves after edits. Manages reminder service lifecycle

#### RoutineEditorScreen (`lib/screens/routine_editor_screen.dart`)
- **Role**: Full-screen editor for creating/editing routines
- **State**: `_nameController`, `_cycleSteps` (List<_EditableStep> mutable wrappers), `_repeatCount`, `_hasBreak`, `_breakStep`
- **Pattern**: Receives `Routine?` (null for new), `List<Activity>`, and `onActivityCreated` callback. Returns `Routine` via `Navigator.pop()`
- **Features**: Add/remove/reorder cycle steps, activity selector dropdown (with inline "create activity" option), duration +/- controls (1-120 min), repeat count (1-10), optional break step, live preview
- **Private classes**: `_EditableStep` (mutable step wrapper), `_PreviewItem` (preview display model)

#### ActivityEditorDialog (`lib/screens/activity_editor_dialog.dart`)
- **Role**: Modal dialog for creating custom activities
- **State**: `_nameController`, `_selectedEmoji`, `_selectedColor`
- **Pattern**: Receives optional `Activity?` for editing. Returns `Activity` via `Navigator.pop()`
- **UI**: Name text field with emoji prefix, emoji grid picker (from `Activity.availableEmojis`), color circle picker (from `Activity.availableColors`)
- **ID generation**: `custom-{timestamp}` for new activities

#### ReminderListScreen (`lib/screens/reminder_list_screen.dart`)
- **Role**: Full-screen list for managing reminders
- **State**: `_reminders` (mutable copy of input list)
- **Pattern**: Receives `List<Reminder>`. Returns modified `List<Reminder>` via `Navigator.pop()` on back navigation (via `PopScope`)
- **Features**: Toggle enabled/disabled, add new (via dialog), edit existing (via dialog), delete custom. Default reminders can only be toggled, not edited or deleted

#### ReminderEditorDialog (`lib/screens/reminder_editor_dialog.dart`)
- **Role**: Modal dialog for creating/editing reminders
- **State**: `_labelController`, `_descController`, `_emoji`, `_intervalMinutes`
- **Pattern**: Receives optional `Reminder?`. Returns `Reminder` via `Navigator.pop()`
- **UI**: Emoji grid picker, label field, interval control (+/- 5 min, range 5-480), description field
- **ID generation**: `custom-{timestamp}` for new reminders

### Native Layer (Swift)

#### MainFlutterWindow (`macos/Runner/MainFlutterWindow.swift`)
- **Extends**: `NSWindow`
- **Responsibilities**: Window setup, status bar item, MethodChannel registration
- **Window config**: 440x820 initial size, 380x650 minimum, centered on screen
- **NSStatusItem**: Created in `setupStatusBar()`, variable-length, default title `"<chair emoji> --:--"`. Click handler activates app and brings window to front
- **MethodChannel contracts**:
  - `com.sitempo/statusbar`:
    - `update` - args: `{time: String, emoji: String}` - sets status item title to `"{emoji} {time}"`
    - `clear` - no args - resets to default `"<chair emoji> --:--"`
  - `com.sitempo/notifications`:
    - `requestPermission` - no args - requests UNUserNotificationCenter authorization for alert+sound, returns bool
    - `show` - args: `{title: String, body: String}` - creates and fires a UNNotificationRequest with UUID identifier, nil trigger (immediate), default sound

#### AppDelegate (`macos/Runner/AppDelegate.swift`)
- **Extends**: `FlutterAppDelegate`, conforms to `UNUserNotificationCenterDelegate`
- **Responsibilities**: App lifecycle, foreground notification display
- **Key behaviors**: `applicationShouldTerminateAfterLastWindowClosed` returns true (app quits when window closes). Sets self as notification center delegate in `applicationDidFinishLaunching`. `userNotificationCenter(_:willPresent:)` enables banner+sound display even when app is in foreground (macOS 11+ uses `.banner`, older uses `.alert`)

## Data Flow

### Timer Tick Flow
```
Timer.periodic(1s) -> _tick()
  |-> _reminderService.tick()
  |     |-> for each enabled reminder:
  |           elapsed++ -> if elapsed >= interval*60:
  |             reset counter -> NotificationService.show() -> MethodChannel -> Swift -> UNNotificationRequest
  |-> if remaining <= 1s:
  |     _advanceStep() -> AlarmService.playTransition() -> Process.run('afplay')
  |                     -> _updateStatusBar()
  |-> else:
        remaining -= 1s -> _updateStatusBar() -> StatusBarService.update() -> MethodChannel -> Swift -> NSStatusItem
```

### Routine Edit Flow
```
TimerScreen -> Navigator.push(RoutineEditorScreen)
  |-> user edits cycle/repeat/break
  |-> Navigator.pop(Routine)
  |-> TimerScreen: update _routines list, reset step index
  |-> RoutineRepository.saveRoutines() -> ~/.sitempo/routines.json (custom only)
```

### Activity Creation Flow
```
RoutineEditorScreen -> showDialog(ActivityEditorDialog)
  |-> user picks emoji, color, name
  |-> Navigator.pop(Activity)
  |-> onActivityCreated callback -> TimerScreen adds to _activities
  |-> RoutineRepository.saveActivities() -> ~/.sitempo/activities.json (custom only)
```

### Reminder Management Flow
```
TimerScreen -> Navigator.push(ReminderListScreen)
  |-> user toggles/adds/edits/deletes
  |-> Navigator.pop(List<Reminder>)
  |-> TimerScreen: update _reminders, reload _reminderService
  |-> ReminderRepository.save() -> ~/.sitempo/reminders.json (all reminders)
```

## Persistence Strategy

### File Structure
```
~/.sitempo/
  routines.json    # Custom routines only (non-default)
  activities.json  # Custom activities only (non-default)
  reminders.json   # ALL reminders (defaults + custom, because enabled state must persist)
```

### What Gets Persisted
- **Activities**: Only custom (user-created) activities. Default activities are always reconstructed from `Activity.defaults` in code
- **Routines**: Only custom routines. Default routine is always reconstructed from `Routine.defaults`
- **Reminders**: ALL reminders, because the `enabled` toggle state of default reminders needs to persist

### Merge Strategy (Load)
1. If file missing or empty: return hardcoded defaults
2. If file exists: decode saved data, then:
   - **Activities/Routines**: Filter out saved items whose IDs match default IDs. Return `[...defaults, ...customOnly]`. This means edits to default items are NOT preserved (they reset on load)
   - **Reminders**: For each default, check if saved data has a matching ID and merge the `enabled` state. Then append custom reminders: `[...mergedDefaults, ...customOnly]`

### Merge Strategy (Save)
- **Activities/Routines**: Filter to `!isDefault` before writing. Defaults are never persisted
- **Reminders**: Write everything as-is (no filtering)

### File Format
All files are JSON arrays at the root level. No schema versioning. No migration strategy.

## Architecture Decisions

### ADR-001: No State Management Package

**Decision**: Use `StatefulWidget` with `setState()` for all state management. No Provider, Riverpod, Bloc, or other packages.

**Context**: Sitempo is a single-purpose desktop app with a small widget tree (5 screens/dialogs total). The primary state (timer, step index, remaining duration) is local to `TimerScreen`. Data is loaded once at startup and modified through imperative navigation returns.

**Consequences**:
- All timer state, data lists, and service references live in `_TimerScreenState` (37 lines of state + derived getters)
- Navigation uses `Navigator.push()` with typed results instead of shared state
- Activity creation requires a callback (`onActivityCreated`) threaded from `TimerScreen` through `RoutineEditorScreen`
- No reactive updates: after editing, screens return data via `Navigator.pop()` and the parent manually updates state
- Adding a second screen that needs timer state (e.g., a dashboard) would require refactoring to shared state

### ADR-002: Static Service Classes

**Decision**: Services (AlarmService, StatusBarService, NotificationService, RoutineRepository, ReminderRepository) are static classes with static methods. No instances, no dependency injection.

**Context**: These services are thin wrappers around platform APIs (MethodChannel, Process.run, File I/O). They have no internal state (except ReminderService, which is the exception and IS instantiated).

**Consequences**:
- Zero boilerplate: call `AlarmService.playTransition()` anywhere
- Not mockable for testing without dependency injection or a mocking framework that supports static methods
- ReminderService breaks the pattern by being an instance class because it holds tick state (`_elapsedSeconds` map). This is the correct choice since it needs per-session mutable state
- Swapping implementations (e.g., different sound backend) requires editing the static class directly

### ADR-003: MethodChannel over FFI

**Decision**: Use Flutter `MethodChannel` for all native macOS communication (status bar, notifications).

**Context**: The app needs two native capabilities: NSStatusItem (menu bar) and UNUserNotificationCenter. Both require Objective-C/Swift APIs not available in Dart.

**Consequences**:
- Two named channels: `com.sitempo/statusbar` and `com.sitempo/notifications`
- Communication is async, string-based method names, Map<String, dynamic> arguments
- All channel setup happens in `MainFlutterWindow.awakeFromNib()` (single registration point)
- Type safety is manual: argument parsing with `as?` casts on the Swift side, no code generation
- Adding a new native feature means adding another method to an existing channel or creating a new one

### ADR-004: afplay for System Sounds

**Decision**: Use `Process.run('afplay', [path])` to play macOS system sounds instead of a Flutter audio package.

**Context**: The app only needs to play two simple system alert sounds (Glass.aiff for transitions, Hero.aiff for start). These are built-in macOS sounds at known paths under `/System/Library/Sounds/`.

**Consequences**:
- Zero dependencies: no audio plugin package needed
- macOS-only: hardcoded paths to system sound files
- Each sound spawns a new process (lightweight for short system sounds)
- No volume control, no mixing, no custom sounds (without changing to a real audio library)
- If Apple moves or removes these sound files in a future macOS version, playback silently fails

### ADR-005: Expanded Steps Pattern (cycle x repeat + break)

**Decision**: Routines define a `cycle` (list of steps) + `repeatCount` + optional `breakStep`. At runtime, `expandedSteps` flattens this into a linear sequence: `cycle * repeatCount + breakStep`.

**Context**: Users need to define repeating work patterns (e.g., 3 rounds of sit/stand before a break). Storing the expanded sequence would be redundant and hard to edit. Storing the compact form (cycle + repeat + break) is more natural for editing.

**Consequences**:
- `expandedSteps` is computed on every access (getter, no caching). For typical routines (2-5 cycle steps, 1-10 repeats), this is trivially cheap
- The timer operates on the flat expanded list: `_currentStepIndex` indexes into `expandedSteps`
- The timeline UI uses the expanded list but groups visually by cycle using modular arithmetic (`i % cycleLength`)
- The editor works with the compact form (`cycle` + `repeatCount` + `breakStep`), never the expanded form
- After the entire expanded sequence completes, the timer wraps to index 0 and increments `_completedCycles`. The sequence repeats indefinitely

### ADR-006: Parallel Reminder Ticking

**Decision**: Reminders tick independently on the same 1-second timer as the main routine timer. Each reminder has its own elapsed-seconds counter.

**Context**: Reminders (drink water, 20-20-20 rule) operate on different intervals than routine steps. They need to fire regardless of which routine step is active.

**Consequences**:
- `ReminderService.tick()` is called every second from `TimerScreen._tick()`, meaning reminders only count while the timer is running (paused = no reminders)
- Each reminder has an independent counter in `_elapsedSeconds` map, keyed by reminder ID
- Counters reset to 0 when a reminder fires, starting a new interval
- `ReminderService.reset()` zeros ALL counters (called when timer is reset, not when paused)
- `load()` uses `putIfAbsent` for counters, meaning reloading reminders mid-session preserves existing progress

### ADR-007: JSON File Persistence

**Decision**: Use plain JSON files in `~/.sitempo/` for all persistence. No SQLite, no shared preferences, no cloud sync.

**Context**: The data model is simple (lists of small objects), the app is single-user desktop, and there's no need for queries, relations, or concurrent access.

**Consequences**:
- Three files: `routines.json`, `activities.json`, `reminders.json`
- Full file rewrite on every save (no incremental updates). Acceptable for small data sizes
- No schema versioning or migration. If the model changes, old files may fail to parse (manual `as?` null checks provide some forward compatibility)
- Directory auto-created on first save (`~/.sitempo/`)
- Defaults-merge-on-load pattern means default items are never persisted (except reminders), ensuring code changes to defaults propagate immediately
- No backup, no corruption recovery. A malformed JSON file falls back to defaults silently (empty string check)
