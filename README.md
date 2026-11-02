# FolderSpanner

**Free, open-source, native macOS file-batching utility for Apple Silicon.**

FolderSpanner divides large file collections into numbered folders. Built with **SwiftUI + Foundation**; no Python runtime, third-party dependencies or analytics.

> **Status: v0.2.0 development preview.** Automated macOS tests and app compilation have passed on the pull request. GitHub publishes an Apple Silicon ZIP after successful tests on `main`. The UI and updater still require hands-on validation on a physical Mac. The app is ad-hoc signed, **not** Developer ID signed or notarized.

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
- For interrupted **moves**, re-scan to fill partially populated folders; already moved files are no longer in the source.
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
