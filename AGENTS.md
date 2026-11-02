# Repository development guidelines

- This is an MIT-licensed native SwiftUI macOS application targeting Apple Silicon.
- Keep the Foundation-based file planner and transfer functions independent of the UI.
- Never silently overwrite any destination item or make filesystem changes during a preview.
- Always require a user confirmation before copy or move operations.
- Use temporary folders in tests, never real personal files or external drives.
- Distinguish confirmed tested behavior from planned behavior in documentation.
- Keep dependency-free Swift Package builds and the ad-hoc `.app` packaging script working.
- Make safety changes testable before adding UX polish or new features.
