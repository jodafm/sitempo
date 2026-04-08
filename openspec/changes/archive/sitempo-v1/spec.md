# Specification: sitempo-v1

## REQ-001: Timer Engine

### Description
The timer engine drives a countdown for the current routine step. It ticks every second, advances through steps automatically, supports pause/resume and manual skip, and keeps a count of completed full sequences.

### Requirements
- MUST count down the current step's duration in one-second increments via a `Timer.periodic` of `Duration(seconds: 1)`.
- MUST advance to the next step when `_remaining.inSeconds <= 1` (i.e., when one second or less remains).
- MUST wrap back to step index 0 and increment `_completedCycles` when the last step of the expanded sequence is reached.
- MUST pause by cancelling the periodic timer; state `_isRunning` MUST become `false`.
- MUST resume by creating a new periodic timer; state `_isRunning` MUST become `true`.
- MUST play `Hero.aiff` via `afplay` on start/resume.
- MUST play `Glass.aiff` via `afplay` on every step transition.
- MUST tick the `ReminderService` on every timer tick while running.
- MUST update the macOS status bar after each tick and after each step transition.
- MUST reset to step 0, `_remaining` equal to the first step's duration, `_completedCycles = 0`, and clear the status bar on reset.
- MUST disable the "Skip" button when the timer is not running.
- MUST disable the routine selector dropdown and the "New routine" button while running.
- MUST display a progress arc computed as `1.0 - (remaining.inSeconds / step.duration.inSeconds)`.
- SHOULD display step index as "Paso X de N" where N is the total expanded step count.

### Scenarios

#### Scenario 1: Normal step transition
```
Given the timer is running on step 1 with 1 second remaining
When the next tick fires
Then the timer advances to step 2
And plays Glass.aiff
And resets remaining to step 2's full duration
And updates the status bar with step 2's emoji and new time
```

#### Scenario 2: End-of-sequence wrap
```
Given the timer is on the last expanded step with 1 second remaining
When the next tick fires
Then step index resets to 0
And _completedCycles increments by 1
And Glass.aiff plays
And the status bar shows step 0's emoji and full duration
```

#### Scenario 3: Start/pause toggle
```
Given the timer is paused
When the user presses the play button
Then a periodic 1-second timer starts
And Hero.aiff plays
And _isRunning becomes true

Given the timer is running
When the user presses the pause button
Then the periodic timer is cancelled
And _isRunning becomes false
And no sound plays
```

#### Scenario 4: Manual skip while running
```
Given the timer is running on step 2
When the user presses "Saltar"
Then _advanceStep executes immediately
And Glass.aiff plays
And the timer continues running from the new step
```

#### Scenario 5: Reset
```
Given the timer is in any state
When the user presses "Reiniciar"
Then the timer stops
And step index becomes 0
And remaining becomes the first step's full duration
And _completedCycles resets to 0
And ReminderService.reset() is called
And StatusBarService.clear() is called
```

---

## REQ-002: Routine Model

### Description
A routine is a named sequence of steps (`cycle`) that repeats `repeatCount` times, optionally followed by a single break step. The model computes the full expanded step list for execution.

### Requirements
- MUST contain at least one `RoutineStep` in `cycle`.
- MUST have a `repeatCount >= 1`; default is 1 if not specified in JSON.
- MAY include a single optional `breakStep` appended after all cycle repetitions.
- MUST compute `expandedSteps` as: cycle repeated `repeatCount` times, then `breakStep` appended if present.
- MUST compute `totalMinutes` as the sum of all expanded step durations in minutes.
- MUST serialize durations in whole minutes (`durationMinutes` field).
- MUST deserialize missing `repeatCount` as 1 and missing `breakStep` as null.
- MUST preserve `isDefault` flag through serialization/deserialization; default is `false`.
- MUST use `id` to match existing routines when saving; if `id` is not found, treat as new.
- MUST fall back to `Activity.defaults.first` when a step's `activityId` cannot be resolved.
- SHALL carry one default routine ("Sentado / De pie") with id `'default'`, consisting of `sitting` 45 min and `standing` 15 min, `repeatCount = 1`, no break.

### Scenarios

#### Scenario 1: Expand with repeatCount = 2 and break
```
Given a routine with cycle [A(10min), B(5min)], repeatCount=2, breakStep C(15min)
When expandedSteps is computed
Then the result is [A, B, A, B, C]
And totalMinutes is 45
```

#### Scenario 2: Expand with repeatCount = 1, no break
```
Given a routine with cycle [A(45min), B(15min)], repeatCount=1, no breakStep
When expandedSteps is computed
Then the result is [A, B]
And totalMinutes is 60
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

#### Scenario 3: Load activities — with custom saved
```
Given activities.json contains one custom activity with id "custom-123"
When loadActivities() is called
Then the result is [7 defaults..., custom-123]
```

#### Scenario 4: Save activities
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

## REQ-005: Native Notifications & Reminders

### Description
Two independent notification mechanisms exist: (1) native macOS UNUserNotification for reminder alerts, and (2) the reminder service that fires timed notifications parallel to the timer.

### Requirements — Notification Service
- MUST communicate via the `com.sitempo/notifications` Flutter method channel.
- MUST request UNUserNotification authorization for `.alert` and `.sound` on app first load.
- MUST show notifications even when the app is in the foreground (willPresent delegate returns `.banner` + `.sound` on macOS 11+, `.alert` + `.sound` on earlier).
- MUST fire each notification with a unique UUID identifier to prevent deduplication.
- MUST include `body` in the notification content (empty string if none provided).
- MUST use `UNNotificationSound.default`.

### Requirements — Reminder Service
- MUST tick only enabled reminders.
- MUST maintain per-reminder elapsed second counters.
- MUST fire a reminder notification when `elapsed >= intervalMinutes * 60` seconds.
- MUST reset the elapsed counter for a reminder to 0 immediately after firing.
- MUST call `ReminderService.tick()` on every timer tick (not independently — only ticks while timer is running).
- MUST reset all elapsed counters to 0 on `ReminderService.reset()`.
- MUST NOT tick disabled reminders (skipped entirely in tick loop).
- MUST reload reminder state immediately when the user saves changes in the reminder list screen.

### Requirements — Default Reminders
- SHALL include 2 default reminders: "Tomar agua" (💧, 30 min) and "Regla 20-20-20" (👀, 20 min).
- MUST mark defaults with `isDefault = true`; enabled state of defaults is persisted but core fields are not overwritten on load.

### Scenarios

#### Scenario 1: Reminder fires at interval
```
Given reminder "Tomar agua" with intervalMinutes=30 and enabled=true
And the timer has been running for exactly 1800 ticks (30 min * 60 sec)
When the 1800th tick is processed
Then elapsed becomes 1800 >= 1800
And a notification fires: title="💧 Tomar agua", body="Hidratate, tomá un vaso de agua"
And elapsed resets to 0
```

#### Scenario 2: Disabled reminder is skipped
```
Given reminder "Regla 20-20-20" with enabled=false
When tick() is called any number of times
Then no notification is fired for that reminder
And its elapsed counter is not incremented
```

#### Scenario 3: Permission request on startup
```
Given the app launches for the first time
When _load() completes
Then NotificationService.requestPermission() is called
And the UNUserNotification authorization dialog appears
```

---

## REQ-006: Routine Editor

### Description
The routine editor allows creating and editing routines. It supports a multi-step cycle, configurable repeat count (1–10), an optional break step, per-step descriptions, and a preview of the expanded sequence.

### Requirements
- MUST require a non-empty trimmed name to save.
- MUST require at least one cycle step to save.
- MUST initialize new routines with name "Mi rutina", steps [sitting 45min, standing 15min], repeatCount=1, no break.
- MUST allow adding, removing (minimum 1 step), and reordering (up/down) cycle steps.
- MUST enforce step duration range: 1 to 120 minutes (inclusive), clamped on +/- controls.
- MUST enforce repeat count range: 1 to 10 (inclusive), clamped on +/- controls.
- MUST allow toggling the break step on/off via a Switch control.
- MUST default the break step to activity "stretching" for 5 minutes when first enabled.
- MUST allow setting per-step description text (optional, multi-line, no length enforced in code).
- MUST allow creating a new activity inline from the activity dropdown within the editor.
- MUST propagate newly created activities to the parent screen via `onActivityCreated` callback.
- MUST generate id as `'custom-{millisecondsSinceEpoch}'` for new routines; MUST preserve original id for edited routines.
- MUST display a live preview showing the expanded step sequence with chips and total minutes.
- SHOULD disable remove-step button when only 1 step remains.
- SHOULD disable reorder arrows at boundaries (up at index 0, down at last index).

### Scenarios

#### Scenario 1: Save new routine
```
Given the editor is open for a new routine
And the user sets name="Ergonomia", adds steps [sitting 30min, standing 20min], repeatCount=2, break=stretching 10min
When the user taps "Guardar"
Then a Routine is returned with id prefixed "custom-"
And expandedSteps = [sitting, standing, sitting, standing, stretching]
And totalMinutes = 110
```

#### Scenario 2: Save rejected — empty name
```
Given the editor has an empty name field
When the user taps "Guardar"
Then no Routine is returned (Navigator.pop is not called)
```

#### Scenario 3: Step duration boundary
```
Given a step has duration 1 minute
When the user taps the minus (-) control
Then the control is disabled and duration remains 1

Given a step has duration 120 minutes
When the user taps the plus (+) control
Then the control is disabled and duration remains 120
```

#### Scenario 4: Preview updates live
```
Given repeatCount=3, cycle=[A 10min, B 5min], break=C 15min
When the preview renders
Then it shows: A→B→A→B→A→B···C (break chip distinct)
And total is "60 min total"
```

---

## REQ-007: Interactive Timeline

### Description
The timeline panel on the main timer screen shows all expanded routine steps with visual state distinctions for completed, current, and future steps, plus cycle and break section headers.

### Requirements
- MUST display all `expandedSteps` in sequential order.
- MUST visually distinguish three step states:
  - **Completed** (index < currentStepIndex): strikethrough text, check icon, dimmed opacity (white24).
  - **Current** (index == currentStepIndex): activity color for text/border, activity emoji in circle, live countdown replacing static duration, description shown if non-empty.
  - **Future** (index > currentStepIndex): dimmed (white38), static duration in minutes.
- MUST insert a cycle header ("Ciclo X de N" or "Ciclo" if repeatCount == 1) before every `cycleLength`-th step that is not a break step.
- MUST insert a "— Descanso —" header before the break step (last step, when breakStep is set).
- MUST show a "Ciclo N · X min" label in the top-right of the timeline showing current cycle number and total routine minutes.
- MUST animate step container size changes with a 250ms duration.
- MUST show the step description inline under the current step label, indented, italic, in activity color.
- SHOULD display "Se repite" indicator at the bottom of the timeline.

### Scenarios

#### Scenario 1: Current step rendering
```
Given the timer is on step index 2 with 8:45 remaining
Then step at index 2 shows: activity color text, live countdown "08:45", description if present, highlighted background with border
```

#### Scenario 2: Completed step rendering
```
Given step index 0 has been passed
Then step 0 shows: strikethrough label, check icon, white24 color, transparent background
```

#### Scenario 3: Cycle header insertion
```
Given a routine with cycle=[A, B], repeatCount=2 (expandedSteps=[A, B, A, B])
Then a "Ciclo 1 de 2" header appears before index 0
And a "Ciclo 2 de 2" header appears before index 2
```

#### Scenario 4: Break header insertion
```
Given a routine with repeatCount=1, cycle=[A, B], breakStep=C
(expandedSteps=[A, B, C])
Then a "— Descanso —" header appears before index 2 (the break step)
```

---

## REQ-008: Sound Alarms

### Description
The app plays macOS system sounds for timer events using the `afplay` command-line tool.

### Requirements
- MUST play `/System/Library/Sounds/Hero.aiff` when the timer starts or resumes.
- MUST play `/System/Library/Sounds/Glass.aiff` on every step transition (automatic or manual skip).
- MUST invoke sounds via `Process.run('afplay', [path])` — fire-and-forget async.
- MUST NOT play any sound on pause or reset.
- SHALL NOT block the UI thread (sounds play asynchronously).

### Scenarios

#### Scenario 1: Start sound
```
Given the timer is paused
When the user taps "Iniciar"
Then AlarmService.playStart() is called
And Hero.aiff plays asynchronously
```

#### Scenario 2: Transition sound
```
Given the timer auto-advances from step 1 to step 2
Then AlarmService.playTransition() is called
And Glass.aiff plays asynchronously

Given the user manually skips a step
Then AlarmService.playTransition() is called identically
```

#### Scenario 3: No sound on reset
```
Given the timer is running
When the user taps "Reiniciar"
Then no afplay call is made
```

---

## REQ-009: Persistence

### Description
All user data — routines, activities, and reminders — is stored as JSON in `~/.sitempo/`. The directory is created lazily on first save. Defaults are never written to disk; they are always provided in-code and merged with saved data on load.

### Requirements
- MUST store all files in `~/.sitempo/` resolved via `Platform.environment['HOME']`.
- MUST create the `~/.sitempo/` directory recursively on first save if it does not exist.
- MUST use three separate JSON files: `routines.json`, `activities.json`, `reminders.json`.
- MUST return in-memory defaults when a file does not exist or is empty (no error thrown).
- MUST merge on load: defaults always first, then user-added non-default items appended.
- MUST persist only custom (non-default) routines and activities to disk; defaults are reconstructed from code on load.
- MUST persist all reminders (defaults + custom) to disk so that enabled/disabled state of defaults is preserved.
- MUST merge default reminders on load: for each default, restore saved `enabled` state if present; append custom reminders afterward.
- MUST write files synchronously from the Flutter isolate using `File.writeAsString`.
- SHALL serialize durations as `durationMinutes` (integer minutes).

### Scenarios

#### Scenario 1: First run — no files exist
```
Given ~/.sitempo/routines.json does not exist
When loadRoutines() is called
Then Routine.defaults ([{id:"default", ...}]) is returned
And no file is created (lazy creation on save only)
```

#### Scenario 2: Save custom routine
```
Given the user creates a new routine with id "custom-1234"
When saveRoutines() is called with [default, custom-1234]
Then routines.json contains only [custom-1234] (isDefault filter)
And the default routine is NOT written to disk
```

#### Scenario 3: Load with saved data present
```
Given routines.json contains [custom-1234]
When loadRoutines() is called
Then result is [Routine.defaults[0], custom-1234]
```

#### Scenario 4: Default reminder enabled state preserved
```
Given reminders.json contains [{id:"water", enabled:false}, {id:"20-20-20", enabled:true}]
When ReminderRepository.load() is called
Then Reminder "water" is returned with enabled=false (overrides in-code default of true)
And Reminder "20-20-20" is returned with enabled=true
And all other default fields (emoji, label, intervalMinutes) come from in-code definition
```

#### Scenario 5: Directory creation on save
```
Given ~/.sitempo/ does not exist
When saveRoutines() is called
Then the directory is created recursively
And routines.json is written successfully
```
