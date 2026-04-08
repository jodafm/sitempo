# Specification: sitempo v2.0.0

## REQ-001: Timer Engine

### Description
The timer engine drives a countdown for the current routine step using absolute timestamps (`_targetEnd`) to survive macOS sleep. Step transitions are gated or automatic depending on routine configuration. When gated, the engine pauses, triggers a looping alarm, and waits for user confirmation before advancing. Reset clears all alarm state and confirmation state.

### Requirements
- MUST track remaining time using an absolute `DateTime _targetEnd` computed as `DateTime.now().add(_remaining)` on start/resume.
- MUST compute remaining on each tick as `_targetEnd!.difference(DateTime.now())` instead of decrementing a counter.
- MUST advance the step when `diff.inSeconds <= 0`.
- MUST tick the `ReminderService` on every timer tick while running.
- MUST update the macOS status bar after each tick.
- MUST play `Hero.aiff` via `afplay` on start/resume.
- MUST set `_targetEnd = null` on pause; MUST NOT cancel `_remaining` (it is preserved for resume).
- MUST disable the routine selector dropdown while running.
- MUST disable the "Skip" button when the timer is not running.
- MUST display a progress arc computed as `1.0 - (remaining.inSeconds / step.duration.inSeconds)`.
- MUST display step index as "Paso X de N" where N is the total expanded step count.
- MUST display the step description below the step counter when the step's description is non-empty.

**Auto-advance mode** (`routine.autoAdvance == true`):
- MUST play the routine's `transitionSound` via `Process.run('afplay', [path])` on transition.
- MUST immediately set the next step, reset remaining, and restart the periodic timer without pausing.
- MUST increment `_completedCycles` when the last step is passed.

**Confirmation-gate mode** (`routine.autoAdvance == false`):
- MUST stop the timer, set `_isRunning = false`, `_awaitingConfirmation = true`, and record the pending next step index.
- MUST start a looping alarm using the routine's `transitionSound`.
- MUST call `WindowService.bringToFront()` to focus the app window.
- MUST animate the timer ring with a red pulsing glow (AnimationController repeating 800ms).
- MUST replace the activity label area with the alarm header ("PASO COMPLETADO").
- MUST replace normal controls with alarm controls showing a "Continuar" button.
- On `_confirmTransition`: MUST stop the looping alarm, reset the animation, play the transition sound once, advance the step, set `_isRunning = true`, restart the timer.
- On `_reset`: MUST stop the looping alarm, reset the animation, and clear `_awaitingConfirmation`.

### Scenarios

#### Scenario 1: Normal tick — time remaining
```
Given the timer is running with _targetEnd 5 minutes from now
When the tick fires
Then _remaining = _targetEnd.difference(now)
And the status bar updates with the new remaining time
```

#### Scenario 2: Auto-advance step transition
```
Given autoAdvance=true, timer on step 1 with diff.inSeconds <= 0
When the tick fires
Then _advanceStep plays transitionSound once
And step index increments
And remaining resets to next step's duration
And timer restarts immediately (no pause)
```

#### Scenario 3: Confirmation-gate transition
```
Given autoAdvance=false, timer on step 1 with diff.inSeconds <= 0
When the tick fires
Then timer pauses (_isRunning=false)
And _awaitingConfirmation=true
And looping alarm starts with transitionSound
And WindowService.bringToFront() is called
And red pulse animation starts
And alarm header and Continuar button appear
```

#### Scenario 4: User confirms transition
```
Given _awaitingConfirmation=true
When user presses "Continuar"
Then looping alarm stops
And pulse animation stops and resets
And transitionSound plays once
And step advances to _pendingStepIndex
And timer restarts
```

#### Scenario 5: Reset from any state
```
Given the timer is in any state including awaitingConfirmation
When user presses "Reiniciar"
Then looping alarm stops (AlarmService.stopLoopingAlarm())
And pulse animation stops and resets
And step index becomes 0
And remaining becomes the first step's full duration
And _completedCycles resets to 0
And ReminderService.reset() is called
And StatusBarService.clear() is called
```

#### Scenario 6: Pause and resume
```
Given the timer is running
When the user presses "Pausar"
Then _targetEnd is set to null
And the periodic timer is cancelled
And _isRunning becomes false

Given the timer is paused
When the user presses "Iniciar"
Then _targetEnd = DateTime.now().add(_remaining)
And a periodic 1-second timer starts
And Hero.aiff plays
And _isRunning becomes true
```

---

## REQ-002: Routine Model

### Description
A routine is a named sequence of steps (`cycle`) that repeats `repeatCount` times, optionally followed by a single break step. v2 adds `autoAdvance` to control gate behavior and `transitionSound` to configure the sound played on step transitions.

### Requirements
- MUST contain at least one `RoutineStep` in `cycle`.
- MUST have a `repeatCount >= 1`; default is 1 if not specified in JSON.
- MAY include a single optional `breakStep` appended after all cycle repetitions.
- MUST compute `expandedSteps` as: cycle repeated `repeatCount` times, then `breakStep` appended if present.
- MUST compute `totalMinutes` as the sum of all expanded step durations in minutes.
- MUST serialize durations in whole minutes (`durationMinutes` field).
- MUST deserialize missing `repeatCount` as 1, missing `breakStep` as null, missing `autoAdvance` as `false`, missing `transitionSound` as `'Glass.aiff'`.
- MUST preserve `isDefault` flag through serialization/deserialization; default is `false`.
- MUST use `id` to match existing routines when saving; if `id` is not found, treat as new.
- MUST fall back to `Activity.defaults.first` when a step's `activityId` cannot be resolved.
- SHALL carry one default routine ("Sentado / De pie") with id `'default'`, cycle [sitting 45min, standing 15min], `repeatCount=1`, no break, `autoAdvance=false`, `transitionSound='Glass.aiff'`.
- MUST persist `autoAdvance` and `transitionSound` in JSON.

**New fields in v2:**
- `autoAdvance` (bool, default `false`): when `true`, step transitions happen without user confirmation.
- `transitionSound` (String, default `'Glass.aiff'`): filename of the sound played on step transitions, resolved via `AlarmService.resolveSoundPath`.

### Scenarios

#### Scenario 1: Expand with repeatCount = 2 and break
```
Given a routine with cycle [A(10min), B(5min)], repeatCount=2, breakStep C(15min)
When expandedSteps is computed
Then the result is [A, B, A, B, C]
And totalMinutes is 45
```

#### Scenario 2: Auto-advance default
```
Given a routine deserialized from JSON without the autoAdvance field
Then autoAdvance is false
And transitionSound is 'Glass.aiff'
```

#### Scenario 3: Activity resolution fallback
```
Given a RoutineStep with activityId "unknown-id"
When resolveActivity is called with the available activities list
Then Activity.defaults.first is returned
```

---

## REQ-003: Custom Activities

### Description
Activities are typed posture/movement archetypes with an emoji, label, and color. Seven defaults ship with the app; users can create additional custom activities.

### Requirements
- MUST include 7 built-in default activities: Sentado (🪑), De pie (🧍), Estiramiento (🙆), Movimiento (⚡), Caminata (🚶), Sentadillas (🏋️), Descanso visual (👀).
- MUST mark default activities with `isDefault = true`.
- MUST allow creation of custom activities with a name, one emoji from a fixed palette of 16, and one color from a fixed palette of 8.
- MUST generate custom activity IDs as `'custom-{millisecondsSinceEpoch}'`.
- MUST NOT allow saving with an empty name (validation: trimmed label must be non-empty).
- MUST persist only custom activities to disk; defaults are always provided in-code.
- MUST merge defaults + custom on load: defaults first, then non-default IDs from file.
- SHALL expose a fixed emoji palette: 🪑 🧍 🙆 🏋️ 🚶 ⚡ 👀 🧘 💪 🏃 🚴 🤸 ☕ 💧 🎯 🖥️
- SHALL expose a fixed color palette (8 ARGB values): blue, orange, green, red, teal, purple, yellow, pink.

### Scenarios

#### Scenario 1: Create custom activity
```
Given the user opens the activity editor with no pre-existing activity
And enters "Yoga" as the name, selects 🧘 emoji and purple color
When the user taps "Crear"
Then an Activity is returned with label="Yoga", emoji="🧘", colorValue=0xFFAB47BC, isDefault=false
And its id is prefixed with "custom-"
```

#### Scenario 2: Load activities — first run
```
Given activities.json does not exist in ~/.sitempo/
When loadActivities() is called
Then Activity.defaults (7 items) is returned
```

#### Scenario 3: Save activities
```
Given the activities list contains 7 defaults + 2 custom activities
When saveActivities() is called
Then only the 2 custom activities are written to disk (isDefault == false filter)
```

---

## REQ-004: Menu Bar Integration

### Description
The macOS system menu bar shows the current activity emoji and countdown timer. Clicking the menu bar item brings the app window to the foreground.

### Requirements
- MUST register an `NSStatusItem` with variable length on app launch.
- MUST display initial title as `"🪑 --:--"` when the timer has not started.
- MUST update the status bar title to `"<emoji> <MM:SS>"` via the `com.sitempo/statusbar` method channel on every timer tick and step transition.
- MUST clear the status bar back to `"🪑 --:--"` on timer reset or routine selection change.
- MUST bring the main window to front when the status bar item is clicked (`NSApp.activate` + `makeKeyAndOrderFront`).
- MUST execute all NSStatusItem mutations on the main thread.
- MUST format time as `MM:SS` with zero-padded minutes and seconds (e.g., `"04:30"`).

### Scenarios

#### Scenario 1: Status bar update during run
```
Given the timer is running, current activity is "De pie" (🧍), remaining is 14:30
When the tick fires
Then statusItem.button.title becomes "🧍 14:30"
```

#### Scenario 2: Status bar cleared on reset
```
Given the timer has been running
When the user resets the timer
Then statusItem.button.title reverts to "🪑 --:--"
```

#### Scenario 3: Click to focus
```
Given the app window is in the background
When the user clicks the status bar item
Then NSApp activates and the main window comes to front
```

---

## REQ-005: Tasks (Reminders)

### Description
Tasks (formerly "Reminders") are user-defined timed notifications that fire in-app modals while the timer is running. The UI uses the label "Tareas". The list defaults to empty. Tasks support repeat, custom alert sounds, time windows, webhook integration, and auto-delete on completion.

### Requirements — Notification Service
- MUST communicate via the `com.sitempo/notifications` Flutter method channel.
- MUST request UNUserNotification authorization for `.alert` and `.sound` on app first load.
- MUST provide `checkPermission()` via MethodChannel returning the current authorization status string.
- MUST show notifications even when the app is in the foreground.
- MUST fire each notification with a unique UUID identifier to prevent deduplication.
- MUST include `body` in the notification content (empty string if none provided).

### Requirements — Reminder Service
- MUST tick only enabled reminders that are not already in `_completedIds`.
- MUST skip reminders outside their active time window (`isInTimeWindow()` returns false).
- MUST maintain per-reminder elapsed second counters.
- MUST fire a reminder when `elapsed >= intervalMinutes * 60` seconds.
- MUST reset the elapsed counter for a reminder to 0 immediately after firing.
- MUST fire both an OS notification (`NotificationService.show`) and the `onFire` callback on fire.
- MUST NOT repeat a non-repeating reminder after it fires (add to `_completedIds` immediately on fire).
- MUST reset all elapsed counters and clear `_completedIds` on `ReminderService.reset()`.
- MUST expose `syncCompletedIds(Set<String>)` for synchronizing completed state from the task list screen.

### Requirements — Task Model (Reminder)
- `id`: unique string, generated as `'custom-{millisecondsSinceEpoch}'` for user-created tasks.
- `emoji`: one of 16 available emojis.
- `label`: non-empty string (required).
- `intervalMinutes`: 1–480, the firing interval.
- `description`: optional string.
- `enabled`: bool, default `true`.
- `repeat`: bool, default `true`. When `false`, task fires once and is completed.
- `alertCount`: int (0–20), default 3. Number of times the alert sound plays during the modal. 0 means no sound.
- `alertSound`: String, default `'Glass.aiff'`. Filename resolved via `AlarmService.resolveSoundPath`.
- `startTime`: optional `HH:mm` string. If set, task will not fire before this time.
- `endTime`: optional `HH:mm` string. If set, task will not fire after this time.
- `webhookUrl`: optional URL string. If set, a POST is fired on "triggered" and "completed" events.
- `autoDelete`: bool, default `false`. If `true`, the task is permanently removed from the list when completed.
- `isDefault`: bool, default `false`. No default tasks exist in v2.

### Requirements — Default Tasks
- MUST default to an empty task list (`Reminder.defaults = []`).
- MUST NOT include any pre-defined tasks.

### Scenarios

#### Scenario 1: Reminder fires at interval
```
Given an enabled task with intervalMinutes=30 and startTime=null
And the timer has been running for exactly 1800 ticks
When the 1800th tick is processed
Then elapsed >= 1800
And a notification fires via NotificationService.show
And onFire callback is called, adding the task to the modal queue
And elapsed resets to 0
```

#### Scenario 2: Non-repeating task fires once
```
Given an enabled task with repeat=false
When the task fires
Then it is added to _completedIds immediately
And it will not fire again unless reset
```

#### Scenario 3: Time window enforcement
```
Given a task with startTime="09:00" and endTime="17:00"
When tick() is called at 08:55
Then the task is skipped (isInTimeWindow returns false)

When tick() is called at 09:01
Then the task's elapsed counter increments normally
```

#### Scenario 4: Completed task skipped
```
Given a task id "task-1" is in _completedIds
When tick() is called
Then the task is skipped entirely (no elapsed increment)
```

---

## REQ-006: Routine Editor

### Description
The routine editor allows creating and editing routines. It supports a multi-step cycle, configurable repeat count (1–10), an optional break step, per-step descriptions, a preview of the expanded sequence, and v2 transition configuration (autoAdvance checkbox, transitionSound picker).

### Requirements
- MUST require a non-empty trimmed name to save.
- MUST require at least one cycle step to save.
- MUST initialize new routines with name "Mi rutina", steps [sitting 45min, standing 15min], repeatCount=1, no break, autoAdvance=false, transitionSound='Glass.aiff'.
- MUST allow adding, removing (minimum 1 step), and reordering (up/down) cycle steps.
- MUST enforce step duration range: 1 to 120 minutes (inclusive), clamped on +/- controls.
- MUST enforce repeat count range: 1 to 10 (inclusive), clamped on +/- controls.
- MUST allow toggling the break step on/off via a Switch control.
- MUST default the break step to activity "stretching" for 5 minutes when first enabled.
- MUST allow setting per-step description text (optional, multi-line).
- MUST allow creating a new activity inline from the activity dropdown via "Crear actividad" option.
- MUST propagate newly created activities to the parent screen via `onActivityCreated` callback.
- MUST generate id as `'custom-{millisecondsSinceEpoch}'` for new routines; MUST preserve original id for edited routines.
- MUST display a live preview showing the expanded step sequence with chips and total minutes.
- MUST include a "Transición entre pasos" section with:
  - An "Avance automático" checkbox (controls `autoAdvance`).
  - A "Sonido de transición" sound picker.
- The sound picker MUST show the 3 system sounds (Glass, Hero, Sosumi).
- The sound picker MUST show custom imported sounds from `~/.sitempo/sounds/` below a divider.
- The sound picker MUST include an "Importar sonido..." option that triggers `AlarmService.importSound()` via osascript.
- MUST save `autoAdvance` and `transitionSound` in the returned Routine.

### Scenarios

#### Scenario 1: Save new routine with auto-advance
```
Given the editor has autoAdvance=true and transitionSound="Hero.aiff"
When the user taps "Guardar"
Then the returned Routine has autoAdvance=true and transitionSound="Hero.aiff"
```

#### Scenario 2: Sound picker shows system + custom sounds
```
Given ~/.sitempo/sounds/ contains "mytune.mp3"
When the transition sound picker opens
Then it shows: Glass, Hero, Sosumi, [divider], mytune, [divider], Importar sonido...
```

#### Scenario 3: Save rejected — empty name
```
Given the editor has an empty name field
When the user taps "Guardar"
Then no Routine is returned (Navigator.pop is not called)
```

#### Scenario 4: Preview updates live
```
Given repeatCount=3, cycle=[A 10min, B 5min], break=C 15min
When the preview renders
Then it shows chips A→B→A→B→A→B···C
And total is "60 min total"
```

---

## REQ-007: Interactive Timeline

### Description
The timeline showing expanded routine steps is accessible via a bottom sheet opened by the timeline icon button in the main screen footer. It is no longer displayed inline on the main screen.

### Requirements
- MUST be displayed in a modal bottom sheet (not inline on the main screen).
- MUST be opened by tapping the timeline icon button (list_alt icon) in the main screen footer.
- MUST display all `expandedSteps` in sequential order.
- MUST visually distinguish three step states:
  - **Completed** (index < currentStepIndex): strikethrough text, check icon, dimmed opacity.
  - **Current** (index == currentStepIndex): activity color, live countdown, description shown if non-empty.
  - **Future** (index > currentStepIndex): dimmed, static duration in minutes.
- MUST insert a cycle header ("Ciclo X de N" or "Ciclo" if repeatCount == 1) before every `cycleLength`-th step that is not a break step.
- MUST insert a "— Descanso —" header before the break step.
- MUST show current cycle number and total routine minutes in the top-right.
- MUST animate step container size changes with a 250ms duration.
- MUST show the step description inline under the current step, indented, italic, in activity color.
- SHOULD display a "Se repite" indicator at the bottom.

### Scenarios

#### Scenario 1: Timeline opens in bottom sheet
```
Given the timer screen is visible
When the user taps the list_alt icon button in the footer
Then a modal bottom sheet opens containing the timeline
```

#### Scenario 2: Current step rendering
```
Given the timer is on step index 2 with 8:45 remaining
Then step at index 2 shows: activity color text, live countdown "08:45",
description if present, highlighted background with border
```

---

## REQ-008: Sound Alarms

### Description
Sound system supporting three categories: start sound (Hero), configurable transition sounds per routine, looping alarm during confirmation gate, and configurable per-task alert sounds. Custom sounds are importable from the user's filesystem and stored in `~/.sitempo/sounds/`.

### Requirements
- MUST define three system sounds: `Glass.aiff`, `Hero.aiff`, `Sosumi.aiff` (from `/System/Library/Sounds/`).
- MUST play `Hero.aiff` when the timer starts or resumes.
- MUST play the routine's `transitionSound` on every step transition (auto-advance or confirmed).
- MUST invoke sounds via `Process.run('afplay', [path])` — fire-and-forget async.
- MUST implement looping alarm via a Dart `while (_looping)` loop calling `Process.run('afplay', [path])` repeatedly. MUST NOT use `afplay -l` (not supported on modern macOS).
- MUST maintain a separate looping flag `_notifLooping` for task alert sounds to avoid interfering with the transition alarm.
- MUST stop the looping transition alarm via `AlarmService.stopLoopingAlarm()` on confirm or reset.
- MUST stop the notification alert via `AlarmService.stopNotificationAlert()` on modal button press.
- MUST resolve sound paths via `AlarmService.resolveSoundPath(sound)`: check `~/.sitempo/sounds/{sound}` first, fall back to `/System/Library/Sounds/{sound}`.
- MUST support importing custom sounds from any location via `osascript` file picker, copying to `~/.sitempo/sounds/`.
- MUST support audio formats: `.aiff`, `.mp3`, `.wav`, `.m4a`.
- MUST create `~/.sitempo/sounds/` directory on first import if it does not exist.
- MUST expose `loadCustomSounds()` returning filenames sorted alphabetically.
- MUST expose `playPreview(sound)` for previewing sounds in pickers.

### Scenarios

#### Scenario 1: Start sound
```
Given the timer is paused
When the user taps "Iniciar"
Then AlarmService.playStart() is called
And Hero.aiff plays asynchronously
```

#### Scenario 2: Transition sound (configurable)
```
Given a routine with transitionSound="Sosumi.aiff"
When a step transition occurs
Then AlarmService.resolveSoundPath("Sosumi.aiff") resolves to /System/Library/Sounds/Sosumi.aiff
And afplay plays that path
```

#### Scenario 3: Looping alarm
```
Given autoAdvance=false and a step completes
Then AlarmService.startLoopingAlarmWithPath(path) is called
And the sound loops via Dart while loop until stopLoopingAlarm() is called
```

#### Scenario 4: Custom sound import
```
Given the user selects a .mp3 file via osascript picker
Then the file is copied to ~/.sitempo/sounds/filename.mp3
And loadCustomSounds() returns it in the list
And resolveSoundPath("filename.mp3") returns ~/.sitempo/sounds/filename.mp3
```

#### Scenario 5: Task alert sound
```
Given a task with alertCount=3 and alertSound="Glass.aiff"
When the task fires
Then AlarmService.startNotificationAlert(count: 3, sound: "Glass.aiff") is called
And the sound plays 3 times sequentially
And stopNotificationAlert() is called when the user presses a modal button
```

---

## REQ-009: Persistence

### Description
All user data — routines, activities, and tasks — is stored as JSON in `~/.sitempo/`. Custom imported sounds are stored in `~/.sitempo/sounds/`. The directory is created lazily on first save. Default routines/activities are never written to disk. No default tasks exist.

### Requirements
- MUST store all data files in `~/.sitempo/` resolved via `Platform.environment['HOME']`.
- MUST create the `~/.sitempo/` directory recursively on first save if it does not exist.
- MUST create `~/.sitempo/sounds/` directory recursively on first sound import.
- MUST use three separate JSON files: `routines.json`, `activities.json`, `reminders.json`.
- MUST return in-memory defaults when a file does not exist or is empty (no error thrown).
- MUST persist only custom (non-default) routines and activities to disk.
- MUST persist all tasks to disk so that enabled/disabled state is preserved.
- MUST persist `autoAdvance` and `transitionSound` in `routines.json`.
- MUST persist `repeat`, `alertCount`, `alertSound`, `startTime`, `endTime`, `webhookUrl`, `autoDelete` in `reminders.json`.
- MUST write files using `File.writeAsString`.
- SHALL serialize durations as `durationMinutes` (integer minutes).
- MUST NOT write any default tasks to disk; `Reminder.defaults` is an empty list.

### Scenarios

#### Scenario 1: First run — no files exist
```
Given ~/.sitempo/reminders.json does not exist
When ReminderRepository.load() is called
Then an empty list is returned
```

#### Scenario 2: Save routine with v2 fields
```
Given a routine with autoAdvance=true and transitionSound="Hero.aiff"
When saveRoutines() is called
Then routines.json contains those fields
And loading it back restores autoAdvance=true and transitionSound="Hero.aiff"
```

#### Scenario 3: Save task with all v2 fields
```
Given a task with repeat=false, alertCount=5, alertSound="Sosumi.aiff",
startTime="09:00", endTime="18:00", webhookUrl="https://example.com/hook", autoDelete=true
When ReminderRepository.save() is called
Then reminders.json persists all those fields
```

#### Scenario 4: First run — no routines file
```
Given ~/.sitempo/routines.json does not exist
When loadRoutines() is called
Then Routine.defaults is returned
```

---

## REQ-010: Step Description in Timer Header

### Description
When the current routine step has a non-empty description, it is displayed below the "Paso X de N" counter in the timer screen header area.

### Requirements
- MUST display the step description when `_currentStep.description.isNotEmpty`.
- MUST render description in a smaller italic style (fontSize 13, color white54).
- MUST NOT display anything when description is empty.
- MUST also display the description in the timeline bottom sheet for the current step.

### Scenarios

#### Scenario 1: Description shown
```
Given the current step has description "Andá por agua o estirá las piernas"
When the timer screen renders
Then the description text appears below "Paso X de N"
In italic white54 style
```

#### Scenario 2: No description
```
Given the current step has an empty description
When the timer screen renders
Then no description text appears below "Paso X de N"
```

---

## REQ-011: Confirmation Gate on Step Transition

### Description
When a routine has `autoAdvance=false`, completing a step triggers a confirmation gate: the UI transforms to show alarm state, a looping sound plays, and the window comes to front. The user must press "Continuar" to proceed.

### Requirements
- MUST replace the activity label area with the alarm header showing "⏰ PASO COMPLETADO" in red.
- MUST display "Siguiente: {emoji} {label}" when the pending step is not the start of a new cycle.
- MUST display "¡Ciclo completo! Continuar para reiniciar." when `_pendingIsNewCycle` is true.
- MUST display the next step's description below the activity name if non-empty.
- MUST replace normal controls (play/pause/skip) with a "Continuar" button (red) and a "Reiniciar" text button.
- MUST animate the timer ring with a red pulsing glow using AnimationController (800ms, repeat with reverse).
- MUST use alarm color `Color(0xFFFF6B6B)` for the ring when `_awaitingConfirmation=true`.
- MUST call `AlarmService.startLoopingAlarmWithPath` with the routine's transition sound path.
- MUST call `WindowService.bringToFront()` once when entering alarm state.
- On confirm: MUST stop alarm, stop animation, play transition sound once, advance step, restart timer.
- On reset: MUST stop alarm, stop animation, clear alarm state.

### Scenarios

#### Scenario 1: Alarm header with next step
```
Given autoAdvance=false, step 1 completes, pending step is step 2 (not a new cycle)
Then alarm header shows "⏰ PASO COMPLETADO"
And "Siguiente: {emoji} {label}" for step 2
And the timer ring pulses red
And the looping alarm plays
And the window is brought to front
```

#### Scenario 2: Alarm header at cycle end
```
Given autoAdvance=false, the last step completes
Then alarm header shows "⏰ PASO COMPLETADO"
And "¡Ciclo completo! Continuar para reiniciar."
```

---

## REQ-012: OS Notification Permission Check

### Description
The task list screen checks the current OS notification permission status and shows a banner when notifications are denied. The check re-runs when the app returns to the foreground.

### Requirements
- MUST expose `NotificationService.checkPermission()` via the `com.sitempo/notifications` MethodChannel, returning the authorization status as a string (e.g., `'authorized'`, `'denied'`, `'notDetermined'`).
- MUST call `checkPermission()` on task list screen `initState`.
- MUST re-check permission on `AppLifecycleState.resumed` via `WidgetsBindingObserver`.
- MUST display a banner when `_permissionStatus == 'denied'` with text "Las notificaciones están desactivadas" and an "Activar" button.
- MUST open macOS notification system preferences via `Process.run('open', ['x-apple.systempreferences:com.apple.preference.notifications'])` when "Activar" is tapped.
- MUST gracefully handle errors in `checkPermission()` by returning `'notDetermined'`.

### Scenarios

#### Scenario 1: Denied — banner shown
```
Given the app returns notification status "denied"
When the task list screen renders
Then a banner appears with "Las notificaciones están desactivadas"
And an "Activar" button that opens System Preferences
```

#### Scenario 2: Re-check on resume
```
Given the task list screen is open
When the user returns from System Preferences (app resumes)
Then checkPermission() is called again
And the banner is hidden if status is now "authorized"
```

---

## REQ-013: Task Modal Notifications

### Description
When a task fires, an in-app modal dialog appears with the task's emoji, label, and description. Repeating tasks show "Completada" / "Aún no" buttons; non-repeating tasks show a single "Continuar" button. Multiple simultaneous firings are queued and shown sequentially.

### Requirements
- MUST display a `Dialog` (not an OS notification only) with the task's emoji, label, and optional description.
- MUST show two buttons for repeating tasks: "Aún no" (dismiss, white38) and "Completada" (green).
- MUST show one "Continuar" button (blue) for non-repeating tasks.
- MUST be `barrierDismissible: false` — the user cannot dismiss by tapping outside.
- MUST start the alert sound via `AlarmService.startNotificationAlert(count, sound)` before showing the modal (if `alertCount > 0`).
- MUST stop the alert sound via `AlarmService.stopNotificationAlert()` when any button is pressed.
- MUST enqueue pending reminders in `_pendingReminders` list; MUST show only one modal at a time (`_showingReminderModal` flag).
- MUST show the next queued modal automatically after the current one is dismissed.
- On "Completada" or "Continuar": MUST call `_completeReminder(reminder)` which marks the task done and fires the completion webhook.
- On "Aún no": MUST dismiss the modal without completing the task.

### Scenarios

#### Scenario 1: Repeating task modal
```
Given a repeating task fires with emoji=💧, label="Tomar agua", alertCount=3, alertSound="Glass.aiff"
Then a modal appears with 💧, "Tomar agua", optional description
And Glass.aiff plays 3 times
And buttons "Aún no" and "Completada" appear

When user presses "Completada"
Then the sound stops
And the task is marked complete
And the completion webhook fires if configured
```

#### Scenario 2: Non-repeating task modal
```
Given a non-repeating task fires
Then the modal shows only a "Continuar" button (blue)

When user presses "Continuar"
Then the task is marked complete and will not fire again
```

#### Scenario 3: Queue of multiple tasks
```
Given tasks A and B both fire in the same second
When the modal for A is showing
Then B is in _pendingReminders

When the user dismisses A's modal
Then B's modal appears automatically
```

---

## REQ-014: Webhook Integration

### Description
Each task may have an optional webhook URL. When set, an HTTP POST is fired on "triggered" (when the modal appears) and "completed" (when the user marks it done or presses Continuar) events. Results are reflected in the notification center.

### Requirements
- MUST fire a POST request to `webhookUrl` when `webhookUrl` is non-empty and non-null.
- MUST fire on `event = "triggered"` when the task modal appears.
- MUST fire on `event = "completed"` when the user completes the task.
- MUST send a JSON body: `{ task, emoji, id, event, timestamp }` where `timestamp` is ISO 8601.
- MUST encode the body as UTF-8 using `utf8.encode(jsonEncode(body))`.
- MUST set `Content-Type: application/json; charset=utf-8`.
- MUST use `dart:io` `HttpClient` for the request.
- MUST treat HTTP 2xx responses as success; any other status or exception as error.
- MUST update the corresponding `AppNotification.webhookStatus` from `pending` → `success` or `error`.
- MUST store the HTTP status code as `webhookDetail` on success.
- MUST require `com.apple.security.network.client` entitlement in the macOS sandbox.

### Scenarios

#### Scenario 1: Successful webhook on triggered
```
Given a task with webhookUrl="https://example.com/hook"
When the task fires and the modal appears
Then a POST is sent to https://example.com/hook
With body: { "task": "Tomar agua", "emoji": "💧", "id": "task-1", "event": "triggered", "timestamp": "..." }
And Content-Type: application/json; charset=utf-8
And the notification center entry shows "webhook pending" → "webhook 200"
```

#### Scenario 2: Webhook error
```
Given the webhook URL is unreachable
When the POST is attempted
Then webhookStatus becomes WebhookStatus.error
And the notification center shows "webhook error"
```

---

## REQ-015: Notification Center

### Description
A unified in-app log of task events (triggered and completed) and their webhook results. Accessible via a badge icon in the main screen footer when there are entries. Displayed as a draggable bottom sheet.

### Requirements
- MUST maintain an in-memory `_notificationLog` list of `AppNotification` entries.
- MUST add an entry when a task fires (`taskTriggered`, blue, message "Tarea disparada").
- MUST add an entry when a task is completed (`taskCompleted`, green, message "Tarea completada").
- MUST show the notification center icon button in the main screen footer only when `_notificationLog` is not empty.
- MUST display a badge on the icon showing the total count of notifications.
- MUST open as a `DraggableScrollableSheet` bottom sheet (initialSize 0.5, min 0.3, max 0.85).
- MUST display each entry with: type icon (colored), emoji, label, message, timestamp (HH:mm:ss).
- MUST display a webhook badge inline with the label when `webhookStatus` is set:
  - `pending`: neutral badge, text "webhook..."
  - `success`: green badge, text "webhook {statusCode}"
  - `error`: red badge, text "webhook error"
- MUST provide a "Limpiar" button that clears all entries and dismisses the sheet.
- MUST insert new entries at position 0 (newest first).

### Scenarios

#### Scenario 1: Notification center badge appears
```
Given no tasks have fired
Then the notification center icon is not visible in the footer

Given a task fires
Then the notification center icon appears with badge count 1
```

#### Scenario 2: Entry with webhook badge
```
Given a task with webhookUrl fires and completes with HTTP 200
Then the notification center shows two entries (triggered + completed)
Each with a green "webhook 200" badge
```

#### Scenario 3: Clear entries
```
Given the notification center has 5 entries
When the user taps "Limpiar"
Then all entries are removed
And the bottom sheet dismisses
And the notification icon disappears from the footer
```

---

## REQ-016: Window Focus Service

### Description
The app can bring itself to the front programmatically, used when a confirmation gate is triggered and user attention is needed.

### Requirements
- MUST expose `WindowService.bringToFront()` as a Dart static method on the `com.sitempo/statusbar` MethodChannel.
- MUST handle the `bringToFront` case in Swift by calling `NSApp.activate(ignoringOtherApps: true)` and `mainWindow?.makeKeyAndOrderFront(nil)`.
- MUST call `WindowService.bringToFront()` when entering the confirmation-gate alarm state.

### Scenarios

#### Scenario 1: Window brought to front on alarm
```
Given the app window is in the background
And a step transition triggers the confirmation gate (autoAdvance=false)
When _advanceStep executes
Then WindowService.bringToFront() is called
And the macOS window activates and comes to front
```

---

## REQ-017: Task List Screen

### Description
The task list screen ("Tareas") displays all tasks with checkbox-based completion state. Tasks can be completed from the list (firing webhooks), uncompleted, edited, and deleted. All tasks are editable regardless of origin.

### Requirements
- MUST use the title "Tareas" in the app bar.
- MUST display a checkbox (circle icon) for each task — filled green check for completed, empty circle for pending.
- MUST display a "Completada" green label badge inline with the task label when completed.
- MUST apply strikethrough decoration to completed task labels.
- MUST reduce opacity of disabled tasks to 0.5.
- MUST allow completing a task by tapping the checkbox icon, calling `widget.onComplete` callback.
- MUST allow un-completing a task by tapping the checkbox again (removes from `_completedIds`).
- MUST allow editing any task (no `isDefault` restriction) via a popup menu "Editar" option.
- MUST allow deleting any task via a popup menu "Eliminar" option.
- MUST show "Sin tareas" placeholder when the list is empty.
- MUST return updated `(List<Reminder>, Set<String>)` tuple via `Navigator.pop` when popped.
- MUST show the notification permission banner when OS permission is denied (see REQ-012).
- MUST provide an "+" icon button to add new tasks via `ReminderEditorDialog`.
- MUST display emoji, interval ("Cada X min"), and optional description in each card subtitle.
- Completing from the list MUST fire the webhook if configured (via `onComplete` callback which calls `_completeReminder`).

### Scenarios

#### Scenario 1: Complete from list
```
Given the task list shows task "Tomar agua" uncompleted
When the user taps the checkbox
Then the checkbox becomes a filled green circle
And the label gets strikethrough
And the "Completada" badge appears
And onComplete is called (which fires the webhook if configured)
```

#### Scenario 2: Uncomplete from list
```
Given the task list shows task "Tomar agua" as completed
When the user taps the filled green checkbox
Then the checkbox reverts to an empty circle
And the task is removed from _completedIds
And the ReminderService syncs the change on screen pop
```

#### Scenario 3: All tasks editable
```
Given a task exists (regardless of isDefault value)
When the user opens the popup menu
Then "Editar" and "Eliminar" options are available for all tasks
```

#### Scenario 4: Empty state
```
Given the task list is empty
When the task list screen renders
Then "Sin tareas" text is shown centered
```
