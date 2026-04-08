# Tasks: sitempo-v1

## Phase 1: Project Setup

- [x] 1.1 Create Flutter macOS project (`flutter create --platforms=macos sitempo`) — `pubspec.yaml`, `lib/main.dart`, `macos/`
- [x] 1.2 Configure window size (440×820) and minimum constraints (380×650), center on screen — `macos/Runner/MainFlutterWindow.swift`
- [x] 1.3 Set macOS entitlements: enable notifications permission (`com.apple.security.network.client` not needed; `UNUserNotification` via Swift delegate) — `macos/Runner/DebugProfile.entitlements`, `macos/Runner/Release.entitlements`
- [x] 1.4 Update `Info.plist` with correct bundle identifier and display name — `macos/Runner/Info.plist`

## Phase 2: Core Models

- [x] 2.1 Implement `Activity` model: fields (`id`, `label`, `emoji`, `colorValue`, `isDefault`), `color` getter, `toJson()`/`fromJson()`, 7 hardcoded defaults, 16-emoji palette, 8-color palette — `lib/models/activity.dart`
- [x] 2.2 Implement `RoutineStep` (embedded in routine): fields (`activityId`, `duration`, `description`), `toJson()`/`fromJson()` with `durationMinutes`, `resolveActivity()` fallback to `Activity.defaults.first` — `lib/models/routine.dart`
- [x] 2.3 Implement `Routine` model: fields (`id`, `name`, `cycle`, `repeatCount`, `breakStep`, `isDefault`), `expandedSteps` computed getter (`cycle × repeatCount + breakStep`), `totalMinutes`, `toJson()`/`fromJson()`, `encode()`/`decode()` list helpers, 1 hardcoded default ("Sentado / De pie") — `lib/models/routine.dart`
- [x] 2.4 Implement `Reminder` model: fields (`id`, `emoji`, `label`, `intervalMinutes`, `description`, `isDefault`, `enabled`), `toJson()`/`fromJson()`, `encode()`/`decode()`, 2 hardcoded defaults (Tomar agua 30 min, Regla 20-20-20 20 min), 16-emoji palette — `lib/models/reminder.dart`

## Phase 3: Services

- [x] 3.1 Implement `AlarmService`: static class, `playStart()` plays `Hero.aiff`, `playTransition()` plays `Glass.aiff`, both via `Process.run('afplay', [path])` fire-and-forget — `lib/services/alarm_service.dart`
- [x] 3.2 Implement `StatusBarService`: static class, `com.sitempo/statusbar` MethodChannel, `update({time, emoji})` and `clear()` methods — `lib/services/status_bar_service.dart`
- [x] 3.3 Implement `NotificationService`: static class, `com.sitempo/notifications` MethodChannel, `requestPermission()` returns `bool`, `show({title, body})` fires a native notification — `lib/services/notification_service.dart`
- [x] 3.4 Implement `ReminderService`: instance class, `_elapsedSeconds` map (per reminder ID), `load(reminders)` with `putIfAbsent` to preserve in-session progress, `tick()` increments enabled reminders and fires on threshold, `reset()` zeros all counters — `lib/services/reminder_service.dart`
- [x] 3.5 Implement `RoutineRepository`: static class, `loadRoutines()` / `saveRoutines()` / `loadActivities()` / `saveActivities()`, defaults-merge-on-load strategy, custom-only persist, `_ensureDir()` lazy directory creation at `~/.sitempo/` — `lib/services/routine_repository.dart`
- [x] 3.6 Implement `ReminderRepository`: static class, `load()` / `save()`, persists ALL reminders (defaults + custom) to preserve `enabled` toggle state, merges default `enabled` state from saved file on load — `lib/services/reminder_repository.dart`

## Phase 4: Native Integration (Swift)

- [x] 4.1 Implement `NSStatusItem` setup in `MainFlutterWindow`: variable-length item, default title `"🪑 --:--"`, click handler calls `NSApp.activate` + `makeKeyAndOrderFront` — `macos/Runner/MainFlutterWindow.swift`
- [x] 4.2 Register `com.sitempo/statusbar` MethodChannel in `MainFlutterWindow.awakeFromNib()`: handle `update` (set `"{emoji} {time}"` on main thread) and `clear` (reset to default) — `macos/Runner/MainFlutterWindow.swift`
- [x] 4.3 Register `com.sitempo/notifications` MethodChannel in `MainFlutterWindow.awakeFromNib()`: handle `requestPermission` (request UNUserNotificationCenter auth for `.alert` + `.sound`, return bool) and `show` (fire `UNNotificationRequest` with UUID identifier, nil trigger, default sound) — `macos/Runner/MainFlutterWindow.swift`
- [x] 4.4 Implement `AppDelegate` as `UNUserNotificationCenterDelegate`: `applicationShouldTerminateAfterLastWindowClosed` returns `true`, set as notification center delegate in `applicationDidFinishLaunching`, `willPresent` returns `.banner + .sound` (macOS 11+) to show notifications in foreground — `macos/Runner/AppDelegate.swift`

## Phase 5: Screens & UI

- [x] 5.1 Implement `TimerScreen` state: fields for `_routines`, `_activities`, `_reminders`, `_selectedRoutineIndex`, `_currentStepIndex`, `_remaining`, `_timer`, `_isRunning`, `_completedCycles`, `_loading`, `_reminderService`; `initState()` loads all data via `Future.wait()` and calls `NotificationService.requestPermission()` — `lib/screens/timer_screen.dart`
- [x] 5.2 Implement timer engine in `TimerScreen`: `_startTimer()` / `_pauseTimer()` with `Timer.periodic(1s)`, `_tick()` (decrement remaining, call `_reminderService.tick()`, advance step at ≤1s), `_advanceStep()` (wrap to 0 + increment `_completedCycles` at end), `_resetTimer()` (reset state + `ReminderService.reset()` + `StatusBarService.clear()`) — `lib/screens/timer_screen.dart`
- [x] 5.3 Implement `TimerScreen` UI layout: routine selector `PopupMenuButton`, activity emoji + label display, progress arc `CustomPainter` (computed as `1.0 - remaining/total`), "Paso X de N" indicator, start/pause + reset + skip controls with disabled states — `lib/screens/timer_screen.dart`
- [x] 5.4 Implement interactive timeline in `TimerScreen`: vertical list of all `expandedSteps` with completed/current/future visual states (strikethrough, activity color, dimmed opacity), cycle headers ("Ciclo X de N"), break header ("— Descanso —"), live countdown on current step, `AnimatedContainer` size transitions (250ms) — `lib/screens/timer_screen.dart`
- [x] 5.5 Implement navigation from `TimerScreen` to `RoutineEditorScreen` (imperative `Navigator.push`, handle returned `Routine?`, call `RoutineRepository.saveRoutines()`) and to `ReminderListScreen` (handle returned `List<Reminder>?`, call `ReminderRepository.save()`, reload `_reminderService`) — `lib/screens/timer_screen.dart`
- [x] 5.6 Implement `RoutineEditorScreen`: mutable `_EditableStep` wrappers, add/remove/reorder steps (up/down arrows, min 1 step), activity dropdown with inline "create activity" option, duration +/- controls (clamped 1-120 min), repeat count +/- (clamped 1-10), break step toggle (Switch, defaults to stretching 5min), per-step description field, `onActivityCreated` callback propagation, new routine ID as `custom-{timestamp}` — `lib/screens/routine_editor_screen.dart`
- [x] 5.7 Implement live preview panel in `RoutineEditorScreen`: `_PreviewItem` display model, chips showing expanded step sequence (break chip visually distinct), total minutes label — `lib/screens/routine_editor_screen.dart`
- [x] 5.8 Implement `ActivityEditorDialog`: name text field (with emoji prefix), emoji grid picker from `Activity.availableEmojis`, color circle picker from `Activity.availableColors`, validate non-empty trimmed name, return `Activity` via `Navigator.pop()`, ID as `custom-{timestamp}` — `lib/screens/activity_editor_dialog.dart`
- [x] 5.9 Implement `ReminderListScreen`: mutable list copy, toggle `enabled` per reminder, add new via `ReminderEditorDialog`, edit existing (custom only), delete custom reminders (defaults show toggle only), return modified list via `PopScope` + `Navigator.pop()` — `lib/screens/reminder_list_screen.dart`
- [x] 5.10 Implement `ReminderEditorDialog`: emoji grid picker, label field, interval +/- control (5 min step, clamped 5-480 min), description field, return `Reminder` via `Navigator.pop()`, ID as `custom-{timestamp}` — `lib/screens/reminder_editor_dialog.dart`

## Phase 6: Polish & Distribution

- [x] 6.1 Generate app icon at all required macOS sizes (16, 32, 64, 128, 256, 512, 1024) via Python script — `scripts/generate_icon.py`, `macos/Runner/Assets.xcassets/AppIcon.appiconset/`
- [x] 6.2 Build release binary (`flutter build macos --release`) — `build/macos/Build/Products/Release/sitempo.app`
- [x] 6.3 Create distributable DMG from release build — distribution artifact
