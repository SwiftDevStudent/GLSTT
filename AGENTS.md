# Project Instructions

## Workspace

- The actual git/project root is `/Users/naftali/Developer/GLSTT/GLSTT`.
- The Xcode project is `/Users/naftali/Developer/GLSTT/GLSTT/GLSTT.xcodeproj`.
- The main app target and scheme are both `GLSTT`.

## Build And Test Policy

- Always use Xcode MCP tools for project builds and tests.
- Do not use shell `xcodebuild` for this repo.
- Use `mcp__xcodebuildmcp__` for discovery, defaults, cleans, iOS Simulator builds, and launches.
- When preparing a macOS build that should open from Spotlight, install it with `script/install_latest_macos_build.sh` so `/Applications/GLSTT.app` is replaced and re-registered with Launch Services.
- The `GLSTT` target also has a macOS-only build phase that runs `script/install_built_macos_app.sh`; normal Xcode macOS builds replace `/Applications/GLSTT.app` automatically.
- Keep Spotlight focused on the standard app copy: do not leave extra `GLSTT.app` bundles in `~/Applications`, `/tmp`, or DerivedData. If duplicate launch targets appear, delete/unregister every debug copy and keep only `/Applications/GLSTT.app`.
- The install build phase needs `ENABLE_USER_SCRIPT_SANDBOXING = NO` on the `GLSTT` target because it uses `ditto` to read the built `.app` bundle recursively.
- If Xcode shows `project.pbxproj` as raw text instead of General / Signing & Capabilities tabs, first check whether Code Review is enabled and use `View > Hide Code Review`; the project file may still be valid.

## Required Skills

- Before changing SwiftUI code in this repo, use the installed SwiftUI and concurrency skills that apply:
  - `swiftui-pro`
  - `swiftui-view-refactor`
  - `swiftui-ui-patterns`
  - `swift-concurrency-pro`
  - `swift-concurrency-expert` when strict-concurrency issues appear
- For Apple framework/API questions and platform-behavior research, also use:
  - `sosumi`
- For macOS AppKit bridge work, also use:
  - `build-macos-apps:appkit-interop`
  - `build-macos-apps:swiftui-patterns` when the task is scene/window/UI specific
- For iPhone/iPad SwiftUI work, also use:
  - `build-ios-apps:swiftui-ui-patterns`
- When touching project-local workflow, update `.codex/skills/glstt-macos-app/SKILL.md`.

## App Conventions

- `GLSTT` now has two product surfaces in one target:
  - macOS menu bar utility
  - iPhone in-app dictation UI
- Preserve the macOS utility shape:
  - optional Dock icon for local testing
  - menu bar entry
  - floating non-activating HUD
- Keep the iPhone path in-app only unless the user explicitly asks for system-wide input features.
- Preserve the Apple-local speech path:
  - `SpeechAnalyzer`
  - `DictationTranscriber` or `SpeechTranscriber` when appropriate
  - `AssetInventory`
- Cross-app insertion relies on Accessibility APIs and may require the app sandbox to stay disabled.
- Follow SwiftUI Observation conventions from the installed skills:
  - prefer `@Observable` for shared app models
  - own observables with `@State`
  - pass shared models and services with `@Environment`
  - strongly prefer avoiding `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, and `@EnvironmentObject` unless a genuine legacy/integration constraint forces them

## Implementation Notes

- Prefer small AppKit bridges over broad AppKit rewrites.
- Prefer small shared services/stores over oversized app models.
- Keep hotkey logic, transcript assembly, and insertion planning in pure/testable types where possible.
- For stuck "session already in progress" states, use the app-level Stop Current Session path instead of telling the user to quit/reopen; it should cancel speech analysis, file recording/transcription work, HUD state, and the hotkey latch.
- For vocabulary bias:
  - `AnalysisContext.contextualStrings` is capped to 100 total phrases per session
  - prefer short terms or one-to-two-word phrases
  - if stronger biasing or pronunciation tuning is needed later, consider `SFSpeechLanguageModel`
- When adding new project-specific workflow knowledge, update the local skill at `.codex/skills/glstt-macos-app/SKILL.md`.
