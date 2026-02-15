# Sound Effects System

## Context

The app has three sound effect files (`aproach.wav`, `dip.wav`, `shimmer.wav`) from Epidemic Sound sitting untracked in the repo root. They need to be integrated as a modular, reusable sound system with clear semantic meaning — not just raw file playback. The sounds should reinforce the app's UX without being excessive.

## Sound Semantics

| Sound | File | Meaning | Example uses |
|-------|------|---------|-------------|
| **Approach** | `approach.wav` | Neutral attention — something arrived or needs input | Notifications, break suggestions, timebox reminders |
| **Dip** | `dip.wav` | Negative/destructive — something was removed or rejected | Cancel/discard session, validation errors |
| **Shimmer** | `shimmer.wav` | Positive — something good happened | Session completed, activity created |

## Plan

### Phase 1: Infrastructure

**1. Move sound files into app resources**
- Create `PresentApp/Resources/Sounds/`
- Copy and rename: `aproach.wav` → `approach.wav`, keep `dip.wav`, keep `shimmer.wav`
- Remove originals from repo root

**2. Update `project.yml` to bundle resources**
- Add `resources:` section under the Present target so XcodeGen copies the sounds into the app bundle

```yaml
targets:
  Present:
    ...
    sources:
      - path: PresentApp
        excludes:
          - "Resources/**"
    resources:
      - path: PresentApp/Resources
```

**3. Create `SoundManager` — `PresentApp/Sound/SoundManager.swift`**
- `@MainActor` singleton (matches `NotificationManager` pattern)
- `SoundEffect` enum: `.approach`, `.dip`, `.shimmer` — maps to filenames
- Single `play(_ effect: SoundEffect)` method using `NSSound` (lightweight, macOS-native, no AVFoundation import needed)
- Respects its own `soundEffectsEnabled` preference toggle (separate from notification sounds)
- Fire-and-forget — non-blocking playback

```swift
@MainActor
final class SoundManager {
    static let shared = SoundManager()

    enum SoundEffect: String {
        case approach
        case dip
        case shimmer
    }

    func play(_ effect: SoundEffect) {
        guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") else { return }
        NSSound(contentsOf: url, byReference: true)?.play()
    }
}
```

### Phase 2: Documentation

**4. Update `.claude/claude.md`** — add a Sound Design section:
- The three sounds and their semantic meaning
- Principle: sound reinforces UX but is not excessive — **not every interaction gets a sound**
- Sounds are reserved for **meaningful state transitions**, not routine clicks or navigation
- Good candidates: session lifecycle events (complete, cancel), timer milestones, things that need attention
- Bad candidates: button clicks, tab switches, selection changes, hover states, opening/closing panels
- Always use `SoundManager.shared.play(.effect)` — never load audio files directly

### Phase 3: Settings toggle

**5. Add `soundEffectsEnabled` preference key** to `PreferenceKey` enum in PresentCore
**6. Add toggle in `NotificationSettingsTab`** — "Play UI sound effects" (separate from existing notification sound toggle)
**7. `SoundManager.play()` checks this preference** before playing

### Phase 4: Wire sounds into meaningful state transitions only

**8. Integrate sounds in `AppState` — intentional, not excessive:**
- `handleTimerCompletion()` → `.shimmer` (timer finished — the key positive moment)
- `cancelSession()` → `.dip` (discarded work — significant negative action)
- `suggestBreak()` → `.approach` (needs attention — break decision needed)

**Not wired (intentionally):**
- `startSession()` — routine action, no sound needed
- `pauseSession()` / `resumeSession()` — frequent toggles, sound would be annoying
- `stopSession()` — already triggers `handleTimerCompletion` for timed sessions; for open-ended work sessions, stopping is routine, not celebratory

### Phase 5: Verification

- `xcodebuild -scheme Present -destination 'platform=macOS' build`
- Launch app, trigger each sound via code paths
- Verify sounds play and preference toggle mutes them

## Files to create/modify

| File | Action |
|------|--------|
| `PresentApp/Sound/SoundManager.swift` | Create |
| `PresentApp/Resources/Sounds/approach.wav` | Create (move from root) |
| `PresentApp/Resources/Sounds/dip.wav` | Create (move from root) |
| `PresentApp/Resources/Sounds/shimmer.wav` | Create (move from root) |
| `project.yml` | Modify — add resources section |
| `.claude/claude.md` | Modify — add Sound Design section |
| `Sources/PresentCore/Models/Preference.swift` | Modify — add soundEffectsEnabled key |
| `PresentApp/Views/Settings/SettingsView.swift` | Modify — add UI sound effects toggle |
| `PresentApp/ViewModels/AppState.swift` | Modify — add sound triggers |

## Decisions

- **Separate toggles**: UI sound effects get their own toggle in Settings, independent of notification sounds
- **Wire in now**: Integrate sounds into existing actions in this change
- **Intentional use**: Sounds only on meaningful state transitions, never on routine interactions
