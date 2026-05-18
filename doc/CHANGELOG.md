# Changelog

## 2026-05-18 - Rear focal length control

### Added

- Added a preview-level rear focal length entry that expands into prototype-matched zoom chips and a continuous slider.
- Added device-derived rear focal capability filtering so unavailable zoom chips are hidden on devices with fewer rear lenses.
- Added physical rear-lens switch-over based chip selection, such as 0.5× / 1× / 3× on 3× tele devices while preserving the full supported slider range.
- Added localized lens status copy for Ultra Wide, Wide, Telephoto, and Digital crop states.

### Changed

- Persisted the last selected rear focal length and clamp it to the current device's supported range when the camera starts.
- Moved the rear focal length entry to the upper-right preview area to avoid overlapping the layout selector.
- Switched rear camera selection to prefer multi-lens virtual rear devices when available, so focal changes can happen through zoom without rebuilding the capture session.

## 2026-05-17 - Sound and haptics feedback

### Added

- Connected the existing Sound & Haptics setting to photo capture, Live Photo shutter, recording start, and recording stop feedback.
- Added a centralized capture feedback service for system haptics and lightweight capture sounds.
- Added synchronized AAC audio to Live Photo motion movies, using the same zero-based timeline as the pre-shutter video buffer.
- Added unit coverage for feedback event mapping, disabled setting behavior, and Live Photo audio timing.

### Changed

- Strengthened capture haptics so real-device feedback is more noticeable during photo capture and video recording.
- Changed Live Photo capture to keep a short pre-shutter motion buffer, capture the still at the shutter moment, and continue recording post-shutter motion.
- Retimed Live Photo audio samples to the same zero-based timeline as motion video while preserving normal video recording's original timestamp path.
- Moved Live Photo shutter haptic feedback to the accepted shutter tap instead of waiting for the Live Photo file to finish saving.
- Preserved full microphone audio at shutter time instead of dropping samples around capture feedback sounds.
- Moved Live Photo still generation, writer setup, and prebuffer media appends off the shutter-time frame processing path, and skipped heavy post-shutter composition until the Live Photo writer is ready to reduce front-camera stalls around capture.

### Verified

- Generic iOS Release build completed successfully without launching the simulator.
- Generic iOS test build completed successfully without launching the simulator.
- Real-device capture validation remains required for hardware sound and haptic behavior.

## 2026-05-17 - Startup loading experience

### Added

- Added a branded startup loading screen while DualCam prepares the camera session.
- Added startup copy that highlights dual-camera preview, flexible layouts, and quick capture.
- Added a dark static iOS launch screen with a smaller dedicated launch logo.

### Changed

- Replaced the simple camera loading overlay with a full-screen DualCam startup experience.
- Kept the startup intro visible briefly so it does not flash past when camera startup is fast.

### Verified

- Generic iOS Release build completed successfully without launching the simulator.
- `Info.plist`, launch asset JSON, and English/Simplified Chinese localization key parity were checked.

## 2026-05-15 - Recorded layout orientation fix

### Fixed

- Fixed recorded output being upside down in picture-in-picture, circle reaction, director stack, and diagonal cut layouts while preserving the on-screen layout positions in saved videos.

### Verified

- Real-device recording was confirmed after the compositor orientation adjustment.

## 2026-05-14 - Works review and local-only capture library

### Added

- Added a DualCam-only Works review flow from the camera bottom-right entry, replacing the system photo library picker.
- Added a local Works index with thumbnails, video/photo filtering, empty states, read-error states, detail previews, sharing, and reserved “more” actions.
- Added in-app language-aware copy for the Works list, preview detail, local-save confirmation, and related error states.

### Changed

- Changed capture output to stay in the DualCam Works collection first instead of automatically saving every capture to the system Photos library.
- Updated the camera Works entry to show only a recent thumbnail or an empty-album glyph without a text label.
- Updated the Works detail page to use a custom navigation bar layout with flat “Works” and “…” actions, plus a larger custom preview stage instead of embedding the system video player directly in the main preview.
- Moved detail-page reserved-action and local-save messages into the detail page so they no longer appear on the Works list.

### Fixed

- Prevented one unreadable video thumbnail from making the whole Works page fail to load.
- Fixed Works detail navigation controls being hidden or styled incorrectly on real devices.

### Verified

- Localized strings were linted successfully.
- Generic iOS Simulator and generic iOS builds completed successfully after the Works updates.

## 2026-05-13 - Recording smoothness and capture reliability optimization

### Fixed

- Fixed saved photos and videos being exported sideways; captured media now matches the portrait preview orientation.
- Fixed partial black frames during layout switches, especially when switching between horizontal and vertical split layouts.
- Fixed discontinuous audio in normal video recording by decoupling audio append from heavy video composition work.
- Fixed front camera freezes during 60fps recording by updating the latest front/back frame cache before composition throttling.
- Fixed first-seconds recording stutter by prewarming the compositor before official recording starts.

### Improved

- Added user-selectable shooting frame rates, including 24fps, 30fps, and 60fps.
- Added active camera format selection for 720p 60fps-capable multi-camera formats.
- Added in-app effective frame-rate and downgrade-reason display so users can see whether 60fps is actually active.
- Optimized normal video composition by replacing the previous UIImage/UIGraphics hot path with direct rendering into `CVPixelBuffer` output buffers.
- Switched the normal video recording pixel-buffer path to BGRA-compatible buffers for more efficient Core Graphics rendering.
- Used VideoToolbox-backed source image conversion before falling back to Core Image.
- Split front video, back video, audio capture, video processing, and media writing work across more appropriate queues.
- Added stable 60fps video cadence handling to reduce uneven frame pacing in recorded MP4 files.
- Cached recording layout snapshots instead of recomputing them on every camera sample callback.

### Verified

- Real-device 60fps capture was verified on “小胡的 iPhone”.
- Camera debug state showed front and back cameras both measuring about 60fps.
- Recorded MP4 timing analysis showed stable 60fps presentation timestamps after optimization.
- Audio continuity was verified after the writer queue changes.
- Front-camera freeze regression was verified fixed after moving frame-cache updates ahead of composition throttling.
- Layout-switch partial black-screen regression was verified normal after the cleanup build.
- Final cleanup build was installed on device and regression-tested successfully.

### Cleaned up

- Removed temporary recording performance diagnostics and `recording_performance_debug.txt` file output.
- Removed temporary `frame_rate_debug.txt` file output while keeping the in-app effective frame-rate display.
- Removed locally pulled diagnostic MP4 and log files from the working tree.
