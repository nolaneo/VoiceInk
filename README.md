# VoiceInkNeo

Personal fork of [VoiceInk](https://github.com/Beingpax/VoiceInk), a voice-to-text app for macOS using on-device transcription via whisper.cpp.

## Building

Requires macOS 14.4+, Xcode, cmake (`brew install cmake`), git.

```bash
./install-local.sh
```

This builds whisper.cpp (first run only, cached after), compiles VoiceInkNeo with ad-hoc signing, and installs to `/Applications/VoiceInkNeo.app`.

After each rebuild, re-add VoiceInkNeo to **System Settings > Privacy & Security > Accessibility** and **Input Monitoring** (ad-hoc signing invalidates TCC grants on every build).

## What's different from upstream

- **No phone-home calls.** Sparkle auto-updater removed entirely (framework, Info.plist keys, SPM dep, all UI). Announcements service removed (fetcher, manager, view, settings toggle). Polar license validation already gated by `LOCAL_BUILD`; all related UI is dead code.
- **Keychain sync disabled by default.** API keys stored in Keychain with `syncable: false` so they don't travel to iCloud Keychain across devices.
- **Fn chord detection.** When Fn is the dictation hotkey and the user chords Fn with another key (e.g. Fn+Backspace for forward-delete), dictation is silently cancelled — no UI, no sound. The user was using Fn as a modifier, not starting dictation.
- **Simplified mini recorder.** Prompt and power-mode buttons removed from the mini recorder pill. Live transcript overlay removed. Just the soundwave.
- **Renamed to VoiceInkNeo.** Bundle ID `com.prakashjoshipax.VoiceInkNeo`, display name, all user-visible strings, Application Support path, Keychain service — fully isolated from any upstream VoiceInk install.
