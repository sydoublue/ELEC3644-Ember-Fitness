# Ember Fitness — ELEC3644 Group 5

Short, adaptive bodyweight workouts for when you don't have time for a full session.
Native iOS app in **SwiftUI (iOS 17+)**. There is no account, and all data stays on the device.

---

## 1. Run it

1. Install **Xcode 16 or newer** (Xcode 26 also turns on the Apple Intelligence coach).
2. Open `Ember.xcodeproj`.
3. Select the **Ember** target → *Signing & Capabilities* → choose your **Team**.
   Change the bundle ID `com.ember.fitness` to one you own, e.g. `com.<yourname>.ember`.
4. Pick an iPhone (real device or simulator) and press **⌘R**.
5. Press **⌘U** to run the unit tests: the rule engine, feedback bias, coach intent parser and body-scan analyser.

> **Simulator note:** everything works except the camera. Body Scan shows a "See a sample result" button, clearly labelled as sample data, so you can still demo the result screen. Use a real iPhone for the live scan.

---

## 2. What's in the proposal, and where it lives

| Proposal | Implementation |
|---|---|
| §2.1 Quick Setup: feeling (5 levels), 5–30 min slider (10 default), optional *More* (place, discomfort), remembers last choices | `Views/Workout/SetupView.swift`, `EmberStore.suggestedSetup()` |
| §2.2 Generate: the 6-step rule table, deterministic | `Engine/WorkoutGenerator.swift` (pure struct, unit-tested) |
| §2.2 Self-massage / stretch at the end when discomfort is reported | 7 recovery items (`ExerciseLibrary.recovery`), added as an optional last 60 s |
| §2.2 Category fallback + "pop-up to notify user" | Empty categories are dropped and a warning banner appears on the Plan screen |
| §2.3 Session: timer, next exercise, skip, "I'm good, skip the break", "Need more rest" (+15 s, once per break) | `Engine/SessionPlayer.swift`, `Views/Workout/ActiveSessionView.swift` |
| §2.3 *Future* Replace feature | **Built**: ↻ button on every plan row (same category, still respects place and discomfort) |
| §2.4 Feedback: too easy / about right / too hard (±1 level), discomfort pre-selected next time | `FeedbackView.swift`, `Feedback.suggestedNextDifficulty` |
| §2.5 Activity Log: in-app and outside activities, chronological, custom types | `Views/Log/LogView.swift`, `AddActivityView.swift` |
| §2.5 *Future* charts | **Built**: Insights tab (7-day bars, category donut, difficulty-over-time line) |
| §2.6 On-device data, no login | `Store/EmberStore.swift`: a single JSON file in Application Support with file protection |
| §3 Settings: reset data, Watch / HealthKit "not connected" | `Views/Settings/SettingsView.swift` |
| §4 Data flow `SetupInput → WorkoutPlan → Session → Feedback → Activity` | Same type names in `Models/Models.swift` |

---

## 3. New features added on top

### 🤖 AI Body Scan (on-device, Apple Vision)
`AI/BodyScan/`
- The front camera and `VNDetectHumanBodyPoseRequest` track 19 joints live and draw a skeleton overlay.
- The scan has 3 steps with voice guidance:
  1. **Stand tall**: shoulder tilt, hip tilt and head tilt (median over 3 s).
  2. **Arms overhead**: reach angle for each arm, plus the difference between them.
  3. **3 squats**: a **live rep counter**, squat depth (hip drop ÷ leg length), knee tracking (knee gap ÷ ankle gap) and side shift.
- `BodyScanAnalyzer` turns the measurements into findings (e.g. "Knees drift inward"), a movement score, the **best exercises for you**, and focus categories.
- **Build my workout** sends the focus and recommended moves into the same rule engine, which gives them priority.
- No frames are stored or uploaded. The scan is described as guidance, not a medical assessment.

### 💬 Ember Coach (an AI agent)
`AI/Coach/`
- You can type things like *"15 min in my dorm, I'm tired and my knees hurt"*.
- `IntentParser` pulls out the time, energy, place, discomfort and focus. It is deterministic and unit-tested.
- The agent then calls the WorkoutGenerator as its tool and replies with a **plan card** that has *Start* and *View plan* buttons.
- On devices with **Apple Intelligence (iOS 26)**, replies are written by Apple's on-device Foundation Model. Everywhere else the coach uses built-in replies, so it works offline on every iPhone.
- Ask *"how do I do a push-up?"* and you get the steps plus an exercise card. Ask *"how am I doing this week?"* and you get a summary of your log.
- If you mention pain, dizziness or an injury, the coach adds a note to stop and see a professional.

### 🎬 Visual demos: animation + YouTube
- **Every exercise has its own animated figure** (`Media/FigureMotions.swift`). The figures are drawn in code, so they work offline, need no copyrighted images and respect Reduce Motion.
- **YouTube demos** on every exercise screen (`Media/YouTube.swift`):
  - Without a key, the app opens a YouTube search for that exercise inside Ember.
  - With a **YouTube Data API key** (Settings → Video demos), it shows a scrollable row of video thumbnails, and tapping one plays it **inside the app** through the official embed player.
  - You can also set `YOUTUBE_API_KEY` as a build setting so the key is built into the app.
- During a workout, the **How to** button pauses the timer and opens the demo.

### ✨ Polish
- A home dashboard with a weekly goal ring, a streak counter, the Daily Pick, a one-tap **Quick start**, and a note on how last session's feedback changed today's workout.
- Voice cues (they lower your music's volume rather than stopping it), haptics, a 3-2-1 countdown, a "switch sides" cue, and the screen stays awake during a workout.
- Onboarding, an optional daily reminder (local notification), dark mode, Dynamic Type-friendly rounded fonts, and VoiceOver labels.

---

## 4. Architecture

```
Ember/
├─ App/            EmberApp, RootView (tabs), AppRouter (cross-tab navigation)
├─ Models/         Enums, Exercise, ExerciseLibrary (45 moves), SetupInput / WorkoutPlan / Session / Feedback / Activity
├─ Engine/         WorkoutGenerator (rule engine), SessionPlayer (timer state machine), CueSpeaker (voice + haptics)
├─ Store/          EmberStore (@Observable, JSON persistence, stats)
├─ AI/BodyScan/    PoseCamera (AVFoundation + Vision), BodyPose, BodyScanAnalyzer + controller, views
├─ AI/Coach/       LocalAI (Foundation Models wrapper), CoachAgent + IntentParser, CoachView
├─ Media/          Animated figure engine, YouTube search + embedded player
├─ DesignSystem/   Theme (ember palette, adaptive light/dark), reusable components
└─ Views/          Home, Workout (Setup → Plan → Active → Feedback), Log + Insights, Settings, Onboarding
EmberTests/        XCTest: generator rules & determinism, store bias, intent parsing, scan analysis
```

- **State:** the Observation framework (`@Observable`), with one `EmberStore` injected through the environment.
- **Testability:** `WorkoutGenerator`, `IntentParser` and `BodyScanAnalyzer` are pure and contain no UI code.

---

## 5. Getting it on the App Store

1. **Apple Developer Program** membership (US$99/yr) is required to publish.
2. In Xcode, set a unique **bundle ID** and your **Team**, and leave *Automatically manage signing* on.
3. In **App Store Connect**, go to *Apps → +* → New App, using the same bundle ID. Choose the primary category **Health & Fitness**.
4. **App Privacy**: choose **"Data Not Collected"**. Ember has no servers, no analytics and no account. `PrivacyInfo.xcprivacy` is already included.
5. **Privacy Policy URL** is required. A one-page policy is enough, along these lines: "All data stays on your device. The camera is used live for Body Scan and nothing is recorded or uploaded. Optional YouTube demos are loaded from YouTube."
6. **Screenshots**: 6.9" (iPhone 16 Pro Max) is required. Capture Home, Plan, Active, Body Scan result and Coach.
7. **Archive**: select *Any iOS Device* → *Product → Archive* → *Distribute App → App Store Connect*. Then test with **TestFlight** first.
8. **Review notes**: mention that Body Scan needs a full-body camera view, and that the app gives general fitness guidance, not medical advice. The in-app disclaimers cover guideline 1.4.1.
9. Export compliance is already declared (`ITSAppUsesNonExemptEncryption = NO`).

**Suggested listing**
- *Name:* Ember: Quick Workouts
- *Subtitle:* Short workouts that adapt to you
- *Keywords:* quick workout,bodyweight,dorm,hotel,home workout,posture,body scan,ai coach,hiit,stretch
- *Description:* "Only have 10 minutes? Tell Ember how you feel and how long you've got, and it builds a short bodyweight workout for your dorm, hotel room or living room. Mark sore knees or wrists and it works around them. Rate each session and the next one adapts. Scan your posture and movement with your camera, entirely on-device, to find the exercises that suit you best. Log your gym sessions, runs and matches too, all in one private timeline. No account needed."

---

## 6. Known limits / future work
- The YouTube in-app player depends on the video owner allowing embedding. Every video also has an **Open in YouTube** button.
- Body Scan uses a 2D camera, so lighting, loose clothing and camera angle affect the measurements. It is meant for exercise suggestions only.
- HealthKit / Apple Watch, iCloud sync and widgets are the natural next steps.
