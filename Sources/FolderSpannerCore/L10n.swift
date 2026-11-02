import Foundation

/// The Italian development language is the fallback for every user-visible message.
/// The same .lproj tables are copied into the native .app bundle by build-app.sh.
public enum L10n {
    private static var activeBundle: Bundle {
        if Bundle.main.path(forResource: "it", ofType: "lproj") != nil { return .main }
        return .module
    }

    public static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        let format = activeBundle.localizedString(forKey: key, value: key, table: "Localizable")
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: .current, arguments: arguments)
    }

    /// Test helper: resolve an exact language without changing system preferences.
    public static func value(_ key: String, language: String) -> String {
        guard let directory = Bundle.module.path(forResource: language, ofType: "lproj"),
              let specific = Bundle(path: directory) else { return key }
        return specific.localizedString(forKey: key, value: key, table: "Localizable")
    }
}
