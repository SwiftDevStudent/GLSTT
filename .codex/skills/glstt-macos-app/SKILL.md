---
name: glstt-app
description: Use when working on the GLSTT app. Captures the repo root, target/scheme, macOS utility shape, iPhone in-app dictation path, Apple Speech stack, and the requirement to use XcodeBuildMCP instead of shell xcodebuild.
---

# GLSTT App

Use this skill for changes to the `GLSTT` app.

## Project Facts

- Repo root: `/Users/naftali/Developer/GLSTT/GLSTT`
- Project: `GLSTT.xcodeproj`
- Main target: `GLSTT`
- Share extension target: `GLSTTAudioFileExtension`
- Scheme: `GLSTT`
- App type:
  - macOS menu bar utility with a floating HUD
  - iPhone in-app dictation experience
  - shared audio-file transcription path with a share extension handoff

## Build Workflow

- Do not use shell `xcodebuild` in this repo.
- Use `mcp__xcodebuildmcp__` for builds, cleans, launches, simulator sessions, and session defaults.
- When the user wants a macOS build they can open from Spotlight, install the current build with `script/install_latest_macos_build.sh` instead of leaving it in DerivedData. The script replaces `/Applications/GLSTT.app`, registers it with Launch Services, and accepts `--launch` to open the installed copy.
- Normal Xcode macOS builds also run the target build phase script `script/install_built_macos_app.sh`, which skips non-macOS builds and archives, then replaces and registers `/Applications/GLSTT.app`.
- Keep Launch Services and Spotlight pointed at a single app bundle. The standard launchable copy is `/Applications/GLSTT.app`; remove or unregister duplicate `GLSTT.app` bundles from `~/Applications`, `/tmp`, and DerivedData when they appear.
- The target install build phase intentionally sets `ENABLE_USER_SCRIPT_SANDBOXING = NO` for `GLSTT`; Xcode's script sandbox blocks `ditto` from recursively reading the built `.app` bundle.
- If Xcode displays raw `project.pbxproj` text, verify project validity with `plutil`/`xcodebuild -list`, then check Xcode's Code Review mode. `View > Hide Code Review` restores the normal project editor tabs when Code Review is the cause.
- The macOS app now has a built-in updater:
  - configure `GLSTT_UPDATE_FEED_URL` in target build settings
  - host a JSON feed described in `docs/auto-update.md`
  - publish `.zip` archives plus SHA-256 hashes

## Required Upstream Skills

- Use these installed skills when they apply:
  - `swiftui-pro`
  - `swiftui-view-refactor`
  - `swiftui-ui-patterns`
  - `swift-concurrency-pro`
  - `swift-concurrency-expert` for strict-concurrency fixes
  - `build-macos-apps:appkit-interop` for AppKit bridges
  - `build-ios-apps:swiftui-ui-patterns` for iPhone/iPad SwiftUI screens
  - `sosumi` for Apple docs and platform-behavior checks
- The SwiftUI data-flow default for this repo is:
  - `@Observable` shared models
  - `@State` ownership in the owning view
  - `@Environment` / `@Bindable` passing
  - avoid `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, and `@EnvironmentObject` unless a real compatibility constraint requires them

## Product Constraints

- Preserve the macOS utility-app structure:
  - hidden Dock icon
  - menu bar control surface
  - non-activating HUD panel
- Keep the iPhone path in-app only unless the user explicitly asks for system-wide text insertion.
- Speech transcription should stay on Apple's local stack:
  - `SpeechAnalyzer`
  - `DictationTranscriber` when contextual bias is needed
  - `AssetInventory`
  - `AnalysisContext.contextualStrings`
- Long audio files should be transcribed in the main app process, not inside the extension. The extension copies audio into the app group container and opens `glstt://transcribe-audio`.
- Audio-file transcription supports file picker, drag-and-drop, queueing, text output files, and in-app timestamp segment display.
- Respect Apple’s contextual bias guidance:
  - short terms
  - ideally one-to-two-word phrases
  - no more than 100 contextual phrases per session
- If stronger biasing is needed later, consider `SFSpeechLanguageModel`.

## Architecture Guidance

- Keep pure logic isolated and testable:
  - hotkey state machine
  - transcript assembly
  - insertion strategy planning
  - vocabulary import/parsing
- Keep AppKit bridges narrow:
  - keyboard monitoring
  - HUD panel hosting
  - Accessibility insertion
- Prefer smaller shared stores/services over bloated app models, and keep SwiftUI scenes split into focused view files.
- If cross-app insertion or global key capture stops working, check sandbox/signing/privacy settings before rewriting app logic.
- If dictation gets stuck with "A dictation session is already in progress", use or preserve the app-level Stop Current Session action. It must cancel `SpeechAnalyzer`, clear the speech controller, file recording/transcription work, HUD state, and reset the hotkey state machine.
