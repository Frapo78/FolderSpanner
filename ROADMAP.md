# Roadmap

## v0.1 developer preview (in progress)
- [x] Swift Package with SwiftUI macOS executable and a separate Foundation engine
- [x] Source/destination selection, alphabetical and size sorting
- [x] Limits by count and logical file bytes, naming pattern and starting index
- [x] Preview, explicit execution confirmation, copy/move, cancellation between files
- [x] No-overwrite checks, hidden files option, recursive mode, test suite
- [ ] Verify full native app UX and ad-hoc bundle on an actual Apple Silicon Mac
- [ ] Observe green macOS CI run

## v0.2 safety and usability
- Persist preferences and recent patterns
- Detailed preview (individual files and their destination), export a CSV manifest
- Durable journal and verified resume for copy and move (including partial copy failures)
- More robust error summaries and per-file retry
- Improve support for deeply nested directory trees and packages

## v0.3 distribution
- Automatic release packaging with immutable checksums
- Developer ID signing and Apple notarization if certificates are available
- Italian and English localization, native icon, accessibility review
- Optional multiple output roots and distribution policies

All versions remain free and open source.
