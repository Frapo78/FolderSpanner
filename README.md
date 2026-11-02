# FolderSpanner

**Free, open-source, native macOS file-batching utility for Apple Silicon.**

FolderSpanner divides large file collections into numbered folders. Built with **SwiftUI + Foundation**; no Python runtime, third-party dependencies or analytics.

> **Status: v0.1.0 developer preview.** The core has automated tests. macOS app packaging and UI must be validated on an Apple Silicon Mac and by GitHub Actions before any stable release. No signed/notarized release is published yet.

## Features in this first version

- Pick a source and destination folder in the native macOS interface.
- Sort by filename A → Z, Z → A, smallest/largest file size.
- Limit each destination folder by file count, size in MiB (labelled MB), or both; `0` disables the corresponding limit, but at least one is required.
- Name output folders using `{n}` or zero-padding such as `Batch_{n:03}`. Choose the starting number, e.g. `2`.
- Choose **Copy** or **Move**. Hidden files and recursive traversal are opt-in.
- **Simulate first:** inspect a summary without changing anything. Explicit confirmation required to transfer.
- No overwrite: existing target filenames are rejected during planning and re-checked during execution.
- For interrupted **moves**, re-scan to fill partially populated folders; already moved files are no longer in the source.
- Cancel between files, see progress and a status summary.

## Run from source (macOS 13+, Apple Silicon)

Requires Xcode / Xcode Command Line Tools with Swift 5.9+.

```sh
git clone https://github.com/Frapo78/FolderSpanner.git
cd FolderSpanner
swift test
bash scripts/build-app.sh
open dist/FolderSpanner.app
```

`build-app.sh` creates an **ad-hoc signed** local app (not Apple-notarized). macOS may require manual approval to open apps built outside the App Store. The bundle is placed in `dist/` and can be copied to `/Applications` if desired. CI produces a zipped build artifact on successful runs; these are not stable releases.

## Example: Commodore Amiga TOSEC ADF

- Source: `/Volumes/RETRO256/RETRO/AMIGA/Games/[ADF]/Commodore Amiga - Games - [ADF] (TOSEC 2012-02-27)`
- Target root: `/Volumes/RETRO256/RETRO/AMIGA/Games/[ADF]`
- Click **Preset Amiga (da 2)** (then select the two folders).
- Rules: max files `200`, max MB `0`, pattern `{n}`, starting number `2`.
- Click **Simula**, review the grouping, then confirm **Sposta file**.

Folder `1` will not be touched by these settings.

## Important limitations and safety

- **Backup first.** Copy/move operations are not transactionally reversible. Cross-volume moves can involve copying then deleting files.
- A planning preview is a snapshot: changes made externally between planning and execution may cause an operation to stop. Existing targets will not be replaced.
- Recursive mode flattens files into numbered target folders. Duplicate basenames in the same batch stop planning rather than silently rename files. Symlinks and common macOS app/package bundles are not traversed.
- For copied files, repeating an interrupted batch is not yet an automatic resume workflow; existing copies produce a collision. Move resumability is supported by re-scanning the remaining source files and occupied destination folders.
- Files larger than the configured maximum size stop planning with an error; size caps are strictly respected.
- Existing output folders containing subfolders or symlinks are rejected for reuse. Empty names, invalid numbering patterns and a target nested inside the source are rejected.
- Multiple independent destination roots, persistent operation journals, drag-and-drop and notarized distribution are future work.

## Development

```sh
swift test
swift build
```

Core logic lives in `Sources/FolderSpannerCore`, UI in `Sources/FolderSpanner`, tests in `Tests/FolderSpannerCoreTests`. Contributions welcome; see [CONTRIBUTING.md](CONTRIBUTING.md) and [ROADMAP.md](ROADMAP.md).

## License

MIT. See [LICENSE](LICENSE).
