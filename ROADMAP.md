# Roadmap

## v0.1 developer preview (in progress)
- [x] Swift Package with SwiftUI macOS executable and a separate Foundation engine
- [x] Source/destination selection, alphabetical and size sorting
- [x] Limits by count and logical file bytes, naming pattern and starting index
- [x] Preview, explicit execution confirmation, copy/move, cancellation between files
- [x] No-overwrite checks, hidden files option, recursive mode, test suite
- [ ] Verify full native app UX and ad-hoc bundle on an actual Apple Silicon Mac
- [ ] Observe a green macOS GitHub Actions run and confirm the app launches on a physical Mac

## v0.2 safety and usability
- Persist preferences and recent patterns
- Detailed preview (individual files and their destination), export a CSV manifest
- Durable journal and verified resume for copy and move (including partial copy failures)
- More robust error summaries and per-file retry
- Improve support for deeply nested directory trees and packages

## v0.3 distribution
- [x] Automatic ZIP publication via GitHub Releases on successful main pushes and version tags, with SHA-256 manifest
- [ ] Developer ID signing and Apple notarization if certificates are available
- Italian and English localization, native icon, accessibility review
- Optional multiple output roots and distribution policies

All versions remain free and open source.

## v0.2 development branch
- [x] Naming presets, including the 001 sequence
- [x] Cancellable preview and transfer progress
- [x] On-volume disaster recovery with a persistent journal and conservative rollback
- [x] Native bitmap/ICNS generator
- [x] Slow-disk fast path: no directory re-scan per file
- [x] GitHub release update check, ZIP hash verification, guarded app replacement
- [ ] Green macOS CI, app UX inspection and physical-Mac validation
- [ ] Further recovery robustness against simultaneous filesystem changes

## v0.2 multilingual localization
- [x] Native macOS resources for it, en, de, fr, es, zh-Hans and ja
- [x] Translate interface, previews, recovery and updater
- [x] Bundle translations inside downloadable Apple Silicon ZIP
- [x] Validate key and format placeholder coverage before every build
- [ ] Physical Mac GUI checks for text truncation and per-app language switching
