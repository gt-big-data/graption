# apps/ios: Graption iOS app

Spec: `docs/GRAPTION_CONTEXT.md` §6 (app) and §14 (workflow). Right now it's a debug screen:
**Start listening** prints speech segments (A1) and shows sound alerts (A3). Mac + Xcode required.

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
