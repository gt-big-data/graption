# apps/ios: Graption iOS app

Spec: `docs/GRAPTION_CONTEXT.md` §6 (app) and §14 (workflow). The app has a camera screen and a local saved-transcript demo.
Mac + Xcode required; GraptionCore requires Swift 6.0+.

## Run it (first time, each developer)
1. Xcode → **Settings → Accounts** → **+** → sign in with your Apple ID (free is fine).
2. `cp apps/ios/Config/Local.xcconfig.example apps/ios/Config/Local.xcconfig` and fill in
   `DEVELOPMENT_TEAM` (your 10-character team ID) and `DEV_SUFFIX` (your name). This file is
   gitignored. It exists because two free Apple IDs can't share one bundle ID.
3. Open `apps/ios/Graption.xcodeproj`. Pick a simulator and press ⌘R.
4. On your iPhone: plug in → **Trust** → Settings → Privacy & Security → **Developer Mode** on →
   pick the phone in Xcode → ⌘R. First run only: Settings → General → VPN & Device Management →
   trust your Apple ID. Free-account installs expire after ~7 days; ⌘R again to reinstall.

**Don't** set Team or Bundle Identifier in Xcode's Signing & Capabilities tab. That writes your
personal values into the shared project file. Use `Local.xcconfig`.

Verify from the terminal (no signing needed):
```bash
xcodebuild -project apps/ios/Graption.xcodeproj -scheme Graption \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Structure
```
apps/ios/
├── Graption.xcodeproj     # committed (Xcode 16+ synchronized folders: adding files doesn't edit it)
├── Graption/              # thin app target: entry point + wiring only                  (Platform)
├── Config/
│   ├── Base.xcconfig      # shared settings: bundle ID = edu.gatech.graption.$(DEV_SUFFIX)
│   └── Local.xcconfig     # gitignored, per developer: DEVELOPMENT_TEAM, DEV_SUFFIX (+ TONE_URL/TONE_TOKEN later)
└── Packages/              # planned local Swift packages; almost all code will live here
    ├── GraptionCore/      # event types generated from the schema, Mock* classes        (Platform)
    ├── GraptionVision/    # camera, MediaPipe, FaceTracker, FeatureBuilder, SpeakerModel (Vision)
    ├── GraptionAudio/     # mic, loudness, VAD, WhisperKit, SoundAnalysis               (Audio)
    ├── GraptionFusion/    # ScoreBuffer, Fusion (pick speaker for each caption)         (Platform)
    ├── GraptionNetwork/   # ToneClient WebSocket                                        (Platform)
    └── GraptionUI/        # live captions, highlights, tone chips, sound banners,
                           # past-meetings dashboard with AI summaries      (UI/UX; dashboard: Platform)
```
Add a package with **File → New → Package…** saved into `apps/ios/Packages/`, then add it to the
Graption target under **General → Frameworks, Libraries, and Embedded Content**.

## Before adding real features (unverified)
- MediaPipe's iOS SDK is distributed through CocoaPods (`MediaPipeTasksVision`), probably not SwiftPM,
  so the MediaPipe wrapper may need to live in the app target behind a protocol.
- WhisperKit is SwiftPM (`argmaxinc/WhisperKit`).
- Minimum iOS is 17.0 for now; lower it if a team phone can't run 17. On-device summaries need iOS 26+.

## Rules
- Verify with `xcodebuild` / `swift test`, not "looks right".
- Event types are generated from `schemas/events.schema.json`, not hand-written.
- No secrets in the repo: they go in the gitignored `Local.xcconfig`.

## Caption persistence (issue #29)

`GraptionCore` exposes `SavedCaption`, `SavedSession`, `SessionStore`, `FileSessionStore`,
and `SessionRecorder`. Create a recorder at session start, call `append` with each final
caption as it renders, route tone responses to `applyTone(captionID:tag:modelVersion:)`,
and call `try await end()` when capture ends. Captions save immediately with optional tone;
a late tone updates the same file. If a save fails, keep the recorder and retry `end()`.
Caption offsets use the phone's monotonic session clock; `startedAt` is only a display date.
These are local storage types, not a replacement for the generated event contract.

The default store writes atomic, versioned JSON to `Library/Application Support/Sessions/`
in the app sandbox, excludes it from backups, and uses complete file protection on iOS.
It accepts only transcript records; it has no audio/video field or raw-event save API.
History is newest-first. Corrupt/unsupported files surface a load error.

### Manual acceptance test (simulator or iPhone)

1. Run the **Debug** scheme from Xcode. No tone server, microphone, or models are needed.
2. Tap **Start Fake Session**. Expect three captions from `f1`, `f2`, and **Someone**;
   the first has tone `happy`, the others have no tone. The fake times run from 0 to 7 seconds.
3. Tap **End Session & Save**. A session with **3 captions** appears under Saved sessions.
4. Open it and verify all text, speakers, tone, and start/end times.
5. Stop the app in Xcode or force-quit it in the app switcher. Launch it again without
   uninstalling it or resetting simulator data. The saved session should appear automatically.
6. Open the same transcript and verify the same three captions. Tap **Reload Saved Sessions**
   to exercise a fresh disk read. Repeat with another fake session; both should remain.
7. Repeat in airplane mode to confirm storage is fully offline.

The demo is Debug-only. The existing camera screen is independent: closing it does not
create a caption session yet. Force-quitting an active, unended session does not save it.
Uninstalling the app removes its locally saved sessions.

### Automated verification

```bash
swift test --package-path apps/ios/Packages/GraptionCore
xcodebuild -project apps/ios/Graption.xcodeproj -scheme Graption \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Tests cover persistence through a new store instance, every caption field, the complete
JSON field allowlist, absent tone, late tone, duplicate/repeated saves, empty sessions,
sort order, invalid timings, failed-save retry, and corrupted JSON. They use temporary
folders and synthetic text; they never capture audio.
