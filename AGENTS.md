# Repository development guidelines

- This is an MIT-licensed native SwiftUI macOS application targeting Apple Silicon.
- Keep the Foundation-based file planner and transfer functions independent of the UI.
- Never silently overwrite any destination item or make filesystem changes during a preview.
- Always require a user confirmation before copy or move operations.
- Use temporary folders in tests, never real personal files or external drives.
- Distinguish confirmed tested behavior from planned behavior in documentation.
- Keep dependency-free Swift Package builds and the ad-hoc `.app` packaging script working.
- Make safety changes testable before adding UX polish or new features.

- Every change to `main` must keep the automatic macOS preview release workflow healthy; never publish failed tests or a failed build.
- Release ZIPs contain the native `.app` and a SHA-256 manifest, and must clearly disclose ad-hoc signing and the lack of Apple notarization.

- Do not claim guaranteed disaster recovery after disk failures or external edits. Rollback is same-volume and may require manual intervention; preserve the manifest on conflicts.
- Keep developer backups during in-app updates and never install without explicit consent, checksum and bundle identity verification.

- All new user-visible strings must be translated in every `Sources/FolderSpannerCore/Resources/*.lproj/Localizable.strings` table; preserve format argument specifiers and run `python3 scripts/check-localizations.py`.
- Keep filename patterns and user-selected paths stable regardless of UI locale. Italian is the fallback language.
