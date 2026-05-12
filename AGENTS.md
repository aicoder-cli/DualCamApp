# AGENTS.md - AI Agent Context

> This file provides structured context for AI agents working on this project.

## Project Identity

```yaml
name: DualCameraRecorder
type: iOS Application
language: Swift (SwiftUI)
platform: iOS 15.0+
purpose: Dual-camera video recording with customizable layouts
```

## Quick Facts

- **Architecture**: MVVM with ObservableObject pattern
- **Key Frameworks**: AVFoundation, SwiftUI, Combine
- **Unique Feature**: AVCaptureMultiCamSession for simultaneous front/back camera capture
- **UI Style**: Clean glassmorphism design with gradient accents

## File Structure

```
DualCameraRecorder/
├── App/
│   └── DualCameraRecorderApp.swift     # @main entry point
├── Managers/
│   ├── CameraManager.swift             # AVCaptureSession management
│   ├── VideoRecorder.swift             # AVAssetWriter recording
│   └── LayoutManager.swift             # Layout state & calculations
├── Views/
│   ├── ContentView.swift               # Main view composition
│   ├── CameraPreviewView.swift         # Preview layers & overlays
│   └── LayoutSelectorView.swift        # Layout picker UI
├── Resources/
│   └── Assets.xcassets/
└── Info.plist                          # Camera permissions
```

## Core Components

### CameraManager
- Manages `AVCaptureMultiCamSession`
- Handles dual camera setup (front + back)
- Provides `AVCaptureVideoPreviewLayer` for both cameras
- Key property: `isSessionRunning`, `frontCameraReady`, `backCameraReady`

### VideoRecorder
- Uses `AVAssetWriter` for video composition
- Records both camera streams simultaneously
- Saves to photo library on completion
- Key method: `startRecording()`, `stopRecording()`

### LayoutManager
- Defines 6 layout types via `LayoutType` enum
- Calculates frame positions for front camera overlay
- Supports drag-to-reposition
- Key method: `switchLayout(to:)`, `getFrontCameraLayout()`

## Layout Types

| Type | Description |
|------|-------------|
| `pictureInPicture` | Back full screen, front small window |
| `sideBySide` | 50/50 horizontal split |
| `topBottom` | 50/50 vertical split |
| `diagonal` | Front and back in diagonal corners |
| `focusBack` | Back dominant, front small |
| `focusFront` | Front dominant, back small |

## Key Design Decisions

1. **Separate Managers**: Camera, Recording, and Layout are decoupled
2. **Observable Pattern**: All managers use `@Published` for reactive UI updates
3. **Custom Preview Layer**: Uses `UIViewRepresentable` to bridge `AVCaptureVideoPreviewLayer` to SwiftUI
4. **Glassmorphism**: Extensive use of `.ultraThinMaterial` and subtle borders

## Permissions Required

```xml
NSCameraUsageDescription      - Dual camera recording
NSMicrophoneUsageDescription  - Audio recording
NSPhotoLibraryAddUsageDescription - Save videos to album
```

## Build Configuration

- **Bundle ID**: `com.dualcamera.recorder`
- **Team**: Must be set in Xcode (CODE_SIGN_STYLE = Automatic)
- **Device**: Requires physical iPhone (multi-cam not supported in simulator)

## Common Tasks

### Adding a New Layout
1. Add case to `LayoutType` enum in `LayoutManager.swift`
2. Add icon mapping in `LayoutType.icon`
3. Implement frame calculation in `getFrontCameraLayout()`
4. Add preview in `LayoutPreviewMini`

### Modifying UI Style
- Colors: Defined in `Design` enum in `ContentView.swift`
- Glass effect: `Color.white.opacity(0.08)` + `.ultraThinMaterial`
- Accent: Blue-purple gradient `#667eea → #764ba2`
- Record button: `#F2404C`

### Debugging Camera Issues
- Check `CameraManager.errorMessage`
- Verify `hasMultiCameraSupport` (requires iPhone XS or later)
- Test on physical device (simulator will show placeholder)

## Dependencies

- No external Swift Package Manager dependencies
- Pure iOS SDK implementation

## Testing Notes

- Unit tests: Not currently implemented
- UI tests: Not currently implemented
- Manual testing required on physical device for camera features

## Known Limitations

- Requires iPhone with multi-camera support (XS and later)
- Maximum resolution limited by device hardware
- Battery consumption is high during dual-camera recording

## Related Files

- `promo-video.html` - Marketing animation (HTML/React)
- `prototype.html` - Interactive prototype for design review
- `promo-preview.gif` - Generated preview of marketing animation
