# VoiceInk — Build & Architecture Notes

Notes from a fresh read of the repo. Aimed at someone who wants to build it from source, run it independently (no phone-home), and hack on it.

---

## 1. Building

### Prerequisites
- macOS 14.4+
- Xcode (latest) with Command Line Tools
- `git`, `xcodebuild`, `swift` on `PATH`

### Quick start (no Apple Developer account)

```bash
make local
open ~/Downloads/VoiceInk.app
```

`make local` does the following:

1. Clones `whisper.cpp` into `~/VoiceInk-Dependencies/whisper.cpp` and runs `./build-xcframework.sh` to produce `whisper.xcframework` (cached — subsequent builds skip this).
2. Builds VoiceInk Debug with:
   - Ad-hoc signing (`CODE_SIGN_IDENTITY="-"`, `CODE_SIGNING_REQUIRED=NO`)
   - `LocalBuild.xcconfig` overriding bundle ID / team settings
   - `VoiceInk.local.entitlements` (stripped — no iCloud, no keychain groups)
   - `SWIFT_ACTIVE_COMPILATION_CONDITIONS` includes **`LOCAL_BUILD`** — this flag is checked in several source files to skip license validation and iCloud sync
3. Copies `VoiceInk.app` to `~/Downloads/VoiceInk.app`, strips quarantine xattrs.

### Other Makefile targets
- `make build` — normal signed Debug build (needs a team identity)
- `make dev` — build + run
- `make run` — launch already-built app
- `make clean` — removes `~/VoiceInk-Dependencies`
- `make check` — verifies toolchain

### Limitations of local builds (by design)
- No iCloud dictionary sync
- No Sparkle auto-updates (should be disabled — see §3)
- License checks are compiled out entirely

---

## 2. Running independently

**After `make local`, the license path is already neutralized.** The `LOCAL_BUILD` flag gates out all Polar license calls in `VoiceInk/Models/LicenseViewModel.swift:24-28`.

Two automatic network calls still remain even in local builds:

| # | Call | Source | Trigger |
|---|------|--------|---------|
| 1 | Sparkle auto-update → `https://beingpax.github.io/VoiceInk/appcast.xml` | `VoiceInk/Info.plist` (`SUFeedURL`, `SUEnableAutomaticChecks`) + `VoiceInk/VoiceInk.swift:373-404` (`UpdaterViewModel`) | Launch + every 24h |
| 2 | Announcements → `https://beingpax.github.io/VoiceInk/announcements.json` | `VoiceInk/Services/AnnouncementsService.swift:13-16`, started from `VoiceInk.swift:283` | 5s after launch + every 4h |

Either disable at runtime:

```bash
defaults write com.prakashjoshipax.voiceink autoUpdateCheck -bool false
defaults write com.prakashjoshipax.voiceink enableAnnouncements -bool false
```

…or (recommended for a truly independent build) gate both behind `#if !LOCAL_BUILD` in source so they can never fire.

AI-enhancement providers (OpenAI / Anthropic / Groq / Deepgram / ElevenLabs / Soniox / Mistral / OpenRouter / Gemini / Cerebras / Ollama / Custom) only talk to the network when the user has entered an API key **and** triggers enhancement. They're not phone-home.

---

## 3. Architectural map

### 3.1 Entry point & lifecycle
- **`VoiceInk.swift`** — `@main` SwiftUI `App`. `WindowGroup` for the main window (950×730, hidden title bar, frame autosave `VoiceInkMainWindowFrame`) + `MenuBarExtra` for the menu-bar icon. Switches between `OnboardingView` and `ContentView` based on onboarding state. Also owns `UpdaterViewModel` (Sparkle wrapper) and starts `AnnouncementsService`.
- **`AppDelegate.swift`** — handles dock re-open, drag-and-drop audio file opens (routes to the Transcribe tab), and keeps the app alive when the last window is closed.
- **`MenuBarManager.swift`** — toggles `NSApp.activationPolicy` between `.accessory` and `.regular` for "menu bar only" mode, opens/hides the main window, posts `.navigateToDestination` for deep links.
- **`WindowManager.swift`** — singleton tracking main + onboarding `NSWindow`s by identifier, weak refs with fallback recovery, applies styling.

### 3.2 Recording pipeline
- **`CoreAudioRecorder.swift`** (~900 lines) — AUHAL (Audio Unit HAL) recorder. Does **not** change the system default input device. Converts the device's native format to **16-bit PCM, 16 kHz, mono WAV**. Uses pre-allocated `Int16*` / `Float32*` buffers to avoid malloc on the real-time callback thread. Thread-safe metering via `NSLock`. Supports mid-recording device switching (e.g. hot-plugged mic). Emits chunks via `onAudioChunk` closure for streaming backends.
- **`Recorder.swift`** — `@MainActor` `ObservableObject` wrapping `CoreAudioRecorder`. Offloads setup to a serial `audioSetupQueue`. Polls audio meters every 17 ms. Pauses other media before recording via `PlaybackController` and `MediaController`.
- **`PlaybackController.swift`** — uses `mediaremote-adapter` SPM package to pause/resume playing apps. Falls back to posting the hardware Play/Pause key (`NX_KEYTYPE_PLAY = 16`) for apps that ignore MediaRemote (e.g. Plexamp).

### 3.3 Transcription subsystem — `VoiceInk/Transcription/`
Strategy pattern around a `TranscriptionService` protocol.

**Core orchestration**
- `VoiceInkEngine.swift` — top-level orchestrator, owns `RecordingState` (`.idle` / `.recording` / `.transcribing` / `.enhancing`), holds `TranscriptionServiceRegistry` and the `TranscriptionPipeline`.
- `TranscriptionPipeline.swift` — post-recording flow: transcribe → filter → format → word-replace → prompt-detect → AI-enhance → save → paste → dismiss.
- `TranscriptionServiceRegistry.swift` — factory resolving the right service for the user-selected model.

**Batch services** (`Transcription/Batch/`)
- `LocalTranscriptionService` — whisper.cpp via `LibWhisper` + `WhisperContext` (Swift `actor`).
- `ParakeetTranscriptionService` — on-device NVIDIA Parakeet model.
- `NativeAppleTranscriptionService` — Apple Speech framework.
- `CloudTranscriptionService` / `OpenAICompatibleTranscriptionService` — Groq, Deepgram, Soniox, custom OpenAI-compatible endpoints.
- `CustomModelManager` — user-imported local models.

**Whisper integration** (`Transcription/Core/Whisper/`)
- `LibWhisper.swift` — C bindings (`import whisper`), wraps context in an actor.
- `WhisperModelManager.swift` — downloads/caches `.bin` models from Hugging Face.
- `VADModelManager.swift` — optional silero-vad voice-activity detection.
- `WhisperModelWarmupCoordinator.swift` + `ModelPrewarmService` — pre-load model on wake-from-sleep.
- `WhisperPrompt.swift` — initial-prompt priming.

**Streaming services** (`Transcription/Streaming/`)
- `StreamingTranscriptionProvider` protocol (`connect` → `sendAudioChunk` → `commit` → `disconnect`), yielding `StreamingTranscriptionEvent`s (`sessionStarted` / `partial` / `committed` / `error`) through `AsyncStream`.
- Providers: Deepgram, ElevenLabs, Soniox, Mistral, Parakeet.

**Processing** (`Transcription/Processing/`)
- `TranscriptionOutputFilter` (strips `[BLANK_AUDIO]` etc.)
- `WhisperTextFormatter` (capitalization/punctuation)
- `WordReplacementService` (SwiftData-backed user replacements)
- `FillerWordManager` (um/uh/like removal)

### 3.4 Models layer (SwiftData)
Located in `VoiceInk/Models/`. Dual `ModelContainer`:
- **`default.store`** — `Transcription` records (text, duration, audio URL, status, timestamps, power-mode context). **Not** CloudKit-synced.
- **`dictionary.store`** — `VocabularyWord`, `WordReplacement`. CloudKit-synced in production, local-only when `LOCAL_BUILD` is set.

Non-`@Model` types in the same folder: `TranscriptionModel` / `PredefinedModels` (available models metadata), `CustomPrompt` / `AIPrompts` / `PromptTemplates` (AI enhancement templates with `{{context}}`, `{{transcription}}`, `{{clipboard}}`, `{{screen_capture}}` interpolation).

A one-shot `DictionaryMigrationService` moves old UserDefaults-based dictionaries into SwiftData.

### 3.5 Power Mode — `VoiceInk/PowerMode/`
Per-app / per-URL transcription profiles. A `PowerModeConfig` bundles: app/URL matchers, AI enhancement toggle + prompt, transcription model + language override, screen-capture flag, auto-send key, a dedicated hotkey, emoji + display name.

- `PowerModeManager` — singleton, persists configs as JSON in UserDefaults.
- `PowerModeSessionManager` — detects frontmost app/URL at recording start and picks the matching mode.
- `ActiveWindowService` — frontmost-app monitoring via Accessibility API.
- `BrowserURLService` — extracts the active tab URL from Safari/Chrome/etc.
- `PowerModeShortcutManager` — registers a distinct global hotkey per mode.

### 3.6 Text injection
- **`CursorPaster.swift`** — primary paste path. Two strategies, user-selectable via `useAppleScriptPaste`:
  1. **CGEvent**: synthesize ⌘V (requires Accessibility trust).
  2. **AppleScript**: pre-compiled `NSAppleScript` — used for custom keyboard layouts like Neo2 where CGEvent sequences misfire.
  Optional clipboard save/restore around the paste, with a configurable delay. `performAutoSend(_:)` posts Return / Shift-Return / ⌘-Return after paste (used by Power Mode profiles).
- **`ClipboardManager.swift`** — thin `NSPasteboard` wrapper; marks writes with `org.nspasteboard.source` + optional transient flag so clipboard managers can ignore them.

### 3.7 Hotkeys — `VoiceInk/HotkeyManager.swift`
Uses the `KeyboardShortcuts` SPM package for the normal named-shortcut path, **plus** global `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` for modifier-only hotkeys (Option / Control / Command / Shift / Fn) and a middle-mouse-button monitor. Three modes:
- **Toggle** — press to start, press to stop.
- **Push-to-talk** — hold to record.
- **Hybrid** — tap to toggle, hold to push-to-talk (based on press duration).

Secondary hotkey managers:
- `MiniRecorderShortcutManager.swift`
- `PowerMode/PowerModeShortcutManager.swift`

### 3.8 AI Enhancement — `VoiceInk/Services/AIEnhancement/`
- `AIService.swift` — provider abstraction over the `LLMkit` SPM package. `AIProvider` enum lists OpenAI, Anthropic, Groq, Gemini, OpenRouter, Mistral, Cerebras, ElevenLabs, Deepgram, Soniox, Ollama (localhost), and Custom with per-provider base URLs and model lists.
- `AIEnhancementService.swift` — orchestration: prompt selection, screen-capture + clipboard context, 1 s rate-limit between requests, request timeout from `EnhancementTimeoutSeconds` UserDefault.
- `AIEnhancementOutputFilter.swift` — post-processes LLM output (strip preamble, fences, etc.).
- `ReasoningConfig.swift` — optional reasoning-token budget for reasoning models.

### 3.9 Services directory (one-line summary)
```
Services/
├── AIEnhancement/…            see §3.8
├── AnnouncementsService         in-app announcements fetcher (PHONES HOME)
├── APIKeyManager                Keychain-backed API key storage
├── AudioDeviceConfiguration     device metadata
├── AudioDeviceManager           input device monitoring & switching
├── AudioFileTranscriptionManager/Service   drag-drop file transcription
├── CustomVocabularyService      dictionary CRUD
├── DictionaryImportExportService  CSV/JSON dictionary I/O
├── DictionaryMigrationService   one-shot UserDefaults→SwiftData migration
├── EnhancementShortcutSettings  hotkey settings for enhancement
├── ImportExportService          full settings backup/restore
├── KeychainService              generic keychain wrapper
├── LastTranscriptionService     last-transcript cache for UI
├── LicenseManager               Polar license state (gated by LOCAL_BUILD)
├── LocalModelProvider           local model loader protocol
├── LogExporter                  debug log export
├── ModelPrewarmService          preload model on wake
├── Obfuscator                   string obfuscation helper
├── OllamaService                localhost Ollama bridge
├── PolarService                 Polar SaaS license API (PHONES HOME, user-initiated)
├── PromptDetectionService       parses LLM output for directives
├── ScreenCaptureService         screen capture for AI context
├── SelectedTextService          reads selected text via Accessibility
├── SupportedMedia               audio MIME/extension checks
├── SystemArchitecture           Intel vs Apple Silicon
├── SystemInfoService            OS / disk / arch info
├── TranscriptionAutoCleanupService  age/size-based history cleanup
├── UserDefaultsManager          convenience wrapper
├── VoiceInkCSVExportService     history CSV export
└── WordCounter                  word counting
```

### 3.10 Views — `VoiceInk/Views/`
High-level groupings (not enumerating every file):
- `Recorder/` — `MiniRecorderView`, `RecorderPanel`, audio waveform, recording indicator
- `Settings/` — `SettingsView` (models, API keys, shortcuts, permissions tabs)
- `History/` — transcription history, search, playback
- `Dictionary/` — vocabulary & word-replacement UI
- `AI Models/` — model selection, download, Whisper/Parakeet/cloud UIs
- `Onboarding/` — multi-step first-run flow
- `Components/`, `Common/` — reusable UI + extensions
- `Metrics/` — usage stats
- Root views: `ContentView`, `MenuBarView`, `PermissionsView`, `KeyboardShortcutView`, `AudioTranscribeView`

### 3.11 Entitlements
**`VoiceInk.entitlements`** (production):
- App sandbox **disabled**
- `device.audio-input` — microphone
- `automation.apple-events` — AppleScript + Accessibility bridging
- Network client + server
- Screen capture
- User-selected read-only files
- iCloud / CloudKit (container `iCloud.com.prakashjoshipax.VoiceInk`)
- Keychain access group `$(AppIdentifierPrefix)com.prakashjoshipax.VoiceInk`
- Mach exception handler for Sparkle

**`VoiceInk.local.entitlements`** (`LOCAL_BUILD`): same runtime capabilities **minus** iCloud, APS, and keychain groups.

### 3.12 Third-party dependencies (SPM)
From `VoiceInk.xcodeproj/project.pbxproj`:
- `whisper` (whisper.cpp) — transcription
- `Sparkle` — auto-updater
- `KeyboardShortcuts` (sindresorhus) — global hotkeys
- `LaunchAtLogin-Modern` — launch at login
- `mediaremote-adapter` — media play/pause control
- `SelectedTextKit` — selected-text accessibility helper
- `LLMkit` — unified LLM provider abstraction
- `Zip` — settings export/import archives
- `FluidAudio` — audio processing
- `swift-atomics` — lock-free primitives

---

## 4. Interesting design notes

1. **Clean separation of recording from transcription.** `CoreAudioRecorder` is an AUHAL-level, real-time-safe recorder that only produces WAV chunks. `Recorder` handles UI state. `VoiceInkEngine` / `TranscriptionPipeline` handle everything after "stop recording".
2. **Strategy pattern for transcription backends.** A single `TranscriptionService` protocol lets Whisper, Parakeet, Apple Speech, and a dozen cloud providers be swapped at runtime from the user's model selection.
3. **Streaming vs. batch is explicit.** Streaming providers use `AsyncStream<StreamingTranscriptionEvent>`; batch providers just return a final `String`. The pipeline chooses which to use.
4. **Power Mode is the killer feature.** Per-app/per-URL profiles override the global transcription model, language, AI-enhancement prompt, and even the hotkey.
5. **No sandboxing — intentional.** Text injection, Apple Events, Accessibility, and screen capture all need it off.
6. **Dual SwiftData stores** keep transcriptions local while optionally syncing only the dictionary over iCloud — a deliberate privacy split.
7. **Concurrency discipline.** Most observable classes are `@MainActor`; audio I/O sits on a dedicated serial queue; whisper context is a Swift `actor`.
8. **LOCAL_BUILD is first-class.** It's not a hack — the `Makefile`, a dedicated xcconfig, a dedicated entitlements file, and `#if LOCAL_BUILD` conditionals in the Swift source all cooperate to produce a fully functional build without any Apple Developer or Polar infrastructure.

---

## 5. Where to start hacking on key handling

- **`VoiceInk/HotkeyManager.swift`** — global hotkeys, modifier-only detection, toggle / push-to-talk / hybrid modes.
- **`VoiceInk/MiniRecorderShortcutManager.swift`** — mini recorder shortcuts.
- **`VoiceInk/PowerMode/PowerModeShortcutManager.swift`** — per-mode shortcuts.
- **`VoiceInk/CursorPaster.swift`** `performAutoSend(_:)` — synthesized keypresses *output* by the app (auto-send after paste).
