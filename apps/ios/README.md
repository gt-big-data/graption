# apps/ios: Graption iOS app

Spec: `docs/GRAPTION_CONTEXT.md` §6 (app) and §14 (workflow). Right now it's the blank SwiftUI
template ("Hello, world!"). Mac + Xcode required.

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

## MediaPipe Face Landmarker V1

Google's current iOS setup guide supports Swift Package Manager. Use it for this project:

1. In Xcode with Graption.xcodeproj opened, choose **File -> Add Package Dependencies...**.
2. Add `https://github.com/google-ai-edge/mediapipe` and select the `MediaPipeTasksVision`
    product for the `Graption` target. `MediaPipeTasksCommon` is included automatically.
      - There is a chance that MediaPipeTasksVision doesnt get caught, in that case reinstall
      the package setting the dependency Rule to Branch and typing in master in the box to the 
      right. It should show after this
3. Download Google's Face Landmarker model bundle from the [Face Landmarker models]
    (https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker/index#models)
    documentation. Add the downloaded `face_landmarker.task` to the `Graption` target's app
    resources. The file is ignored by git, so every developer downloads it locally.
      - Just drag and drop into the blue folder on xcode - the file name must be the exact same
      and show up under copy bundle resources in build phases when Graption app is targeted.
4. Add `NSCameraUsageDescription` to the app target's Info.plist. The generated Info.plist
    setting can be supplied as `INFOPLIST_KEY_NSCameraUsageDescription` in the target build
    settings.
   - Target: Graption -> Info -> Click plus on the last item in Custom iOS Target Properties
     -> Select: Privacy - Camera Usage Description -> on the right field enter the message 
     (ex. Graption needs camera access to analyze your face.)
5. Build from Xcode once so SPM resolves the package. A physical iPhone is required for the
    live camera result; the simulator cannot provide a useful camera test.
   - All the set up for connecting a device with ICloud needs to be done for this
The older Face Landmarker page also documents CocoaPods, but SPM is the current project setup
path and avoids introducing a `Podfile` and generated workspace into this repository.

V1 implementation contract:

- Capture the back camera with `AVCaptureSession` at 15 fps and pass full frames to
   `FaceLandmarker.detectAsync(image:timestampInMilliseconds:)`.
- Configure `runningMode = .liveStream`, `numFaces = 4`, `outputFaceBlendshapes = true`, and
   `outputFacialTransformationMatrixes = true`.
- Convert each result's normalized landmarks into a bounding rectangle, publish results on the
   main actor, and draw one overlay rectangle per detected face over the preview.
- Keep camera capture and MediaPipe behind the planned `GraptionVision` boundary so the later
   tracker and speaker model can consume the same per-frame results.

Official references: [MediaPipe iOS setup]
(https://developers.google.com/edge/mediapipe/solutions/setup_ios) and [Face Landmarker iOS]
(https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker/ios).

WhisperKit is SwiftPM (`argmaxinc/WhisperKit`).
- WhisperKit is SwiftPM (`argmaxinc/WhisperKit`).
- Minimum iOS is 17.0 for now; lower it if a team phone can't run 17. On-device summaries need iOS 26+.

## Rules
- Verify with `xcodebuild` / `swift test`, not "looks right".
- Event types are generated from `schemas/events.schema.json`, not hand-written.
- No secrets in the repo: they go in the gitignored `Local.xcconfig`.
