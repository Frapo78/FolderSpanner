# FolderSpanner

**Free, open-source, native macOS file-batching utility for Apple Silicon.**

FolderSpanner divides large file collections into numbered folders. Built with **SwiftUI + Foundation**; no Python runtime, third-party dependencies or analytics.

> **Status: v0.2.0 development preview.** Automated macOS tests and app compilation have passed on the pull request. GitHub publishes an Apple Silicon ZIP after successful tests on `main`. The UI and updater still require hands-on validation on a physical Mac. The app is ad-hoc signed, **not** Developer ID signed or notarized.

## Supported languages

FolderSpanner is localized using native macOS `.lproj/Localizable.strings` resources:

- Italian (`it`, original language and fallback)
- English (`en`)
- German (`de`)
- French (`fr`)
- Spanish (`es`)
- Simplified Chinese (`zh-Hans`)
- Japanese (`ja`)

The app follows your macOS language preference; on supported macOS versions, choose a language specifically for FolderSpanner under **System Settings → General → Language & Region → Applications**. Localization covers the interface, presets, progress, alerts, recovery errors and updater messages. Folder naming *patterns* are deliberately kept stable when the display language changes, avoiding unexpected naming changes during a resumed job. Technical filenames and full paths are never translated.

To validate translated tables before building:

```sh
python3 scripts/check-localizations.py
swift test
```

The packaging script copies every `.lproj` into `FolderSpanner.app/Contents/Resources` so downloaded ZIP releases include all seven languages. No external localization dependencies are required.

## Novità in sviluppo: v0.2

- **Preset nomi:** numerico, tre cifre (001, 002), quattro cifre, Batch, Parte, Cartella, con data, personalizzato.
- **Progresso e Annulla:** la scansione mostra attività indeterminata e avanzamento numerico durante il raggruppamento; spostamento/copia mostrano il contatore file.
- **Disaster Recovery (default ON per spostamenti):** crea un manifesto di ripristino prima del primo movimento; prova un rollback in caso di errore o annullamento; permette ripristino dopo riavvio. Funziona solo tra cartelle dello **stesso volume**. Se spento, non viene allocato il manifesto.
- **Limiti:** guasti fisici, cambiamenti esterni e file mancanti possono rendere impossibile il ripristino esatto. In tal caso il programma non sovrascrive e conserva il manifesto per il recupero manuale.
- **Velocità:** evita elenchi ripetuti della cartella di destinazione ad ogni trasferimento (spostamenti sullo stesso volume normalmente sono rename di metadati).
- **Icona:** bitmap PNG 1024px e ICNS generati nativamente dallo script di build.
- **Aggiornamenti GitHub:** controllo su richiesta, download ZIP da release ufficiale, confronto SHA-256 e verifica del bundle, sostituzione al termine del processo con backup della vecchia app. Serve una directory di installazione scrivibile, per esempio `~/Applications`.

⚠️ Il sistema di aggiornamento usa una firma **ad hoc** e non autentica il produttore: richiede fiducia nell'account GitHub e nel trasporto HTTPS. Non vengono installati aggiornamenti senza consenso esplicito.

## Features in this first version

- Pick a source and destination folder in the native macOS interface.
- Sort by filename A → Z, Z → A, smallest/largest file size.
- Limit each destination folder by file count, size in MiB (labelled MB), or both; `0` disables the corresponding limit, but at least one is required.
- Name output folders using `{n}` or zero-padding such as `Batch_{n:03}`. Choose the starting number, e.g. `2`.
- Choose **Copy** or **Move**. Hidden files and recursive traversal are opt-in.
- **Simulate first:** inspect a summary without changing anything. Explicit confirmation required to transfer.
- No overwrite: existing target filenames are rejected during planning and re-checked during execution.
- With **Disaster Recovery** enabled, interrupted same-volume moves attempt a rollback, and an unfinished recovery journal can be retried after restarting the app.
- Cancel between files, see progress and a status summary.

## Download a compiled app (macOS Apple Silicon)

**[GitHub Releases — ZIP builds](https://github.com/Frapo78/FolderSpanner/releases)**

- Every successful push to `main` publishes a **Development Preview** release containing `FolderSpanner-macOS-arm64-<tag>.zip` and `SHA256SUMS.txt`.
- A Git tag in the form `vX.Y.Z` publishes a versioned release (only create version tags after reviewing and testing the build).
- Both workflows run `swift test`, build the native ARM64 executable on the `macos-26` Apple Silicon runner, validate the ad-hoc signature, and verify ZIP integrity.
- To install: download the ZIP from Releases, double-click to extract, then move `FolderSpanner.app` into Applications. Because this app is not yet Apple notarized, macOS may block the first launch; use the documented security override in System Settings if you trust the release.
- Check `SHA256SUMS.txt` against the downloaded ZIP with `shasum -a 256 -c SHA256SUMS.txt` in the download directory. The checksum helps detect download corruption but is **not** a trusted-code signature.
- Builds are free and do not include third-party dependencies. If tests/build fail, a release is **not** published.

### Tagging a reviewed version

```sh
git tag v0.1.0
git push origin v0.1.0
```

A tag build uses `CFBundleShortVersionString` from the version number. Development builds are identified in their ZIP and release names by unique run IDs.

## Run from source (macOS 13+, Apple Silicon)

Requires Xcode / Xcode Command Line Tools with Swift 5.9+.

```sh
git clone https://github.com/Frapo78/FolderSpanner.git
cd FolderSpanner
swift test
bash scripts/build-app.sh
open dist/FolderSpanner.app
```

`build-app.sh` creates an **ad-hoc signed** local app (not Apple-notarized). macOS may require manual approval to open apps built outside the App Store. The bundle is placed in `dist/` and can be copied to `/Applications` if desired. CI generates ZIP assets in the [Releases](https://github.com/Frapo78/FolderSpanner/releases) section after successful builds. A regular push creates a prerelease; a semver tag creates a versioned release.

## Example: Split a large folder into numbered batches

Suppose you have a directory containing 450 files and want to distribute them into subfolders holding at most 200 files each.

- **Source folder:** `/my/path/to/dir/bigdir/`
- **Destination root:** `/my/path/to/dest/`
- Select both locations with the folder pickers, then click **Preset tre cifre** (three-digit names).
- **Rules:** maximum files per folder `200`, maximum size `0` (unlimited), name pattern `{n:03}`, starting number `1`, sorting `Nome A → Z`.
- Click **Anteprima** to review the planned batches without modifying files. When ready, choose **Copia** or **Sposta** and explicitly confirm.

For 450 files, the resulting layout will be:

```text
/my/path/to/dest/
├── 001/    # 200 files
├── 002/    # 200 files
└── 003/    #  50 files
```

These are illustrative paths: replace them with existing directories on your own machine. No actual file is moved or copied during the preview.

## Important limitations and safety

- **Backup first.** Copy/move operations are not transactionally reversible. Cross-volume moves can involve copying then deleting files.
- A planning preview is a snapshot: changes made externally between planning and execution may cause an operation to stop. Existing targets will not be replaced.
- Recursive mode flattens files into numbered target folders. Duplicate basenames in the same batch stop planning rather than silently rename files. Symlinks and common macOS app/package bundles are not traversed.
- For copied files, repeating an interrupted batch is not yet an automatic resume workflow; existing copies produce a collision. Move resumability is supported by re-scanning the remaining source files and occupied destination folders.
- Files larger than the configured maximum size stop planning with an error; size caps are strictly respected.
- Existing output folders containing subfolders or symlinks are rejected for reuse. Empty names, invalid numbering patterns and a target nested inside the source are rejected.
- Multiple independent destination roots, durable recovery for interrupted copies, drag-and-drop and notarized distribution are future work.

## Development

```sh
swift test
swift build
```

Core logic lives in `Sources/FolderSpannerCore`, UI in `Sources/FolderSpanner`, tests in `Tests/FolderSpannerCoreTests`. Contributions welcome; see [CONTRIBUTING.md](CONTRIBUTING.md) and [ROADMAP.md](ROADMAP.md).

## License

MIT. See [LICENSE](LICENSE).
