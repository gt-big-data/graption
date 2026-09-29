# apps/ios: Graption iOS app (not scaffolded yet)

Spec: `docs/GRAPTION_CONTEXT.md` §6 (app) and §14 (workflow). Nothing here builds yet; this is the plan.

## Planned structure

```
apps/ios/
├── project.yml            # XcodeGen spec; Graption.xcodeproj is GENERATED and gitignored
├── Graption/              # thin app target: entry point + wiring only            (Platform)
├── Config/                # Secrets.xcconfig (gitignored): TONE_URL, TONE_TOKEN
└── Packages/              # local Swift packages; almost all code lives here
    ├── GraptionCore/      # event types generated from the schema, Mock* classes  (Platform)
    ├── GraptionVision/    # camera, MediaPipe, FaceTracker, FeatureBuilder, SpeakerModel (Vision)
    ├── GraptionAudio/     # mic, loudness, VAD, WhisperKit, SoundAnalysis         (Audio)
    ├── GraptionFusion/    # ScoreBuffer, Fusion (pick speaker for each caption)   (Platform)
    ├── GraptionNetwork/   # ToneClient WebSocket                                  (Platform)
    └── GraptionUI/        # live captions, highlights, tone chips, sound banners,
                           # past-meetings dashboard with AI summaries             (UI/UX; dashboard: Platform)
```

Why packages: each team works in its own folder (no Xcode project-file merge conflicts), and
`swift test` runs without a simulator.

## Before scaffolding (unverified)
- MediaPipe's iOS SDK is distributed through CocoaPods (`MediaPipeTasksVision`), probably not SwiftPM,
  so the MediaPipe wrapper may need to live in the app target behind a protocol.
- WhisperKit is SwiftPM (`argmaxinc/WhisperKit`).
- Minimum iOS version depends on the oldest team iPhone. On-device summaries need iOS 26+.

## Rules
- Verify with `xcodebuild` / `swift test`, not "looks right".
- Event types are generated from `schemas/events.schema.json`, not hand-written.
- No secrets in the repo: they go in the gitignored `.xcconfig`.
