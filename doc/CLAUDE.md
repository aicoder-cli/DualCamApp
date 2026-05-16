# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

DualCamApp is a native iOS app built with SwiftUI and AVFoundation. It previews front and back cameras simultaneously, offers several split-screen/picture-in-picture layouts, and records a composited MP4 that is saved to the user's photo library.

Requirements from the project metadata and README:
- Xcode 15+
- Swift 5.0
- iOS 15.0+
- A real iOS device is needed to validate multi-camera capture; the simulator is useful for UI/build checks but cannot exercise camera hardware behavior.

## Commands

Run commands from the repository root (`code/DualCamApp/`); the Xcode project lives under `code/`.

```bash
# Open in Xcode
open code/DualCamApp.xcodeproj

# Inspect targets and schemes
xcodebuild -list -project code/DualCamApp.xcodeproj

# Build the app target for iOS
xcodebuild -project code/DualCamApp.xcodeproj \
  -scheme DualCamApp \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  build

# Build for the iOS simulator when only checking compile/UI code
xcodebuild -project code/DualCamApp.xcodeproj \
  -scheme DualCamApp \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build

# Clean build artifacts
xcodebuild -project code/DualCamApp.xcodeproj \
  -scheme DualCamApp \
  clean
```

The project includes a unit test target and `code/DualCamApp.xctestplan`. There is no SwiftPM package, SwiftLint config, or SwiftFormat config.

```bash
# Run all tests once a test target exists
xcodebuild test -project code/DualCamApp.xcodeproj \
  -scheme DualCamApp \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# Run a single test once a test target exists
xcodebuild test -project code/DualCamApp.xcodeproj \
  -scheme DualCamApp \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:DualCamAppTests/TestClass/testMethod
```

## Architecture

- `code/DualCamApp/App/DualCamApp.swift` is the SwiftUI app entry point. It hosts `ContentView`, hides the status bar, and forces dark mode.
- `code/DualCamApp/Views/ContentView.swift` is the composition root for runtime state. It owns `CameraManager`, `LayoutManager`, and `VideoRecorder` as `@StateObject`s, starts capture on appear, stops capture on disappear, and coordinates the preview, recording controls, layout toolbar, settings sheet, loading state, and error banner.
- `code/DualCamApp/Managers/CameraManager.swift` is the AVFoundation capture layer. It is `@MainActor`, manages separate front and back `AVCaptureSession`s, exposes their `AVCaptureVideoPreviewLayer`s to SwiftUI, requests camera/microphone permissions, and provides camera controls such as torch, zoom, and focus. It also exposes front/back sample-buffer handlers for recording integrations.
- `code/DualCamApp/Managers/LayoutManager.swift` owns the layout model. `LayoutType` defines the available layouts, while `LayoutManager` publishes the current layout, drag/scale transforms, and container size, then computes `CameraLayoutInfo` for each camera preview.
- `code/DualCamApp/Views/CameraPreviewView.swift` bridges `AVCaptureVideoPreviewLayer` into SwiftUI with `UIViewRepresentable`. `DualCameraPreviewContainer` lays out the live previews using `CameraManager` and `LayoutManager`; the front camera overlay handles drag gestures.
- `code/DualCamApp/Views/LayoutSelectorView.swift` renders layout selection UI. Both the expanded selector and bottom toolbar iterate over `LayoutType.allCases`, so new layout cases appear in the UI when the enum and icon are updated.
- `code/DualCamApp/Managers/VideoRecorder.swift` wraps `AVAssetWriter` for recording. It targets a 1920x1080 H.264 MP4 with AAC audio, keeps front/back frame buffers, composites frames according to `LayoutType`, writes to Documents, and saves the result with `PHPhotoLibrary`.

## Cross-cutting implementation notes

- Layout behavior is duplicated between live preview calculations in `LayoutManager` and recorded-video drawing methods in `VideoRecorder`. When adding or changing a `LayoutType`, keep both paths in sync so the saved video matches the on-screen preview.
- Camera and recorder objects are main-actor observable state, but video sample buffers arrive from AVFoundation delegate queues. Be careful with actor isolation and avoid doing heavy frame composition on the main thread.
- Permission strings live in `code/DualCamApp/Info.plist` for camera, microphone, and photo-library saving. Any new hardware or privacy-sensitive feature needs the corresponding plist usage key and matching `InfoPlist.strings` entries.
- The app's primary behavior depends on hardware camera sessions, so compile success is not enough for camera/recording changes; verify on a physical device when changing capture, torch, focus, recording, or photo-library save behavior.

## Localization requirements

Treat localization as part of every feature, not as a follow-up cleanup task.

- The app supports in-app language selection via `AppLanguage` and `@AppStorage("appLanguageCode")`. Default behavior is Follow System; only list languages that have real translations.
- All new user-visible UI text must use localization keys in `code/DualCamApp/Resources/en.lproj/Localizable.strings` and `code/DualCamApp/Resources/zh-Hans.lproj/Localizable.strings`. Do not add hard-coded display strings in SwiftUI views, managers, alerts, errors, onboarding, settings, empty states, or debug text shown to users.
- Non-SwiftUI strings, especially `errorMessage` values from managers, should use `L10n.string(...)` so they follow the in-app language setting.
- `LayoutType`, `CaptureMode`, and similar enums should keep stable technical identifiers; expose localized title/description keys separately instead of using `rawValue` as display copy.
- Any new privacy permission key must include an English default in `Info.plist` and localized values in both `en.lproj/InfoPlist.strings` and `zh-Hans.lproj/InfoPlist.strings`.
- When adding a feature, include localization updates in the same change: English and Simplified Chinese strings, any new enum display copy, any new permission copy, and UI checks for both languages.
- After adding or changing localized text, run `plutil -lint` on all changed `.strings` files and build both generic iOS and iOS Simulator targets when possible.
