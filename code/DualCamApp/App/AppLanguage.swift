import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case korean = "ko"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .english, .simplifiedChinese, .traditionalChinese, .korean:
            return Locale(identifier: rawValue)
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system:
            return "language.system"
        case .english:
            return "language.english"
        case .simplifiedChinese:
            return "language.simplifiedChinese"
        case .traditionalChinese:
            return "language.traditionalChinese"
        case .korean:
            return "language.korean"
        }
    }

    static func from(_ rawValue: String) -> AppLanguage {
        AppLanguage(rawValue: rawValue) ?? .system
    }
}

enum L10n {
    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let value = localizedString(forKey: key)
        guard !arguments.isEmpty else { return value }
        return String(format: value, locale: AppLanguage.from(currentLanguageCode).locale, arguments: arguments)
    }

    private static var currentLanguageCode: String {
        UserDefaults.standard.string(forKey: SettingsKey.appLanguageCode) ?? AppLanguage.system.rawValue
    }

    private static func localizedString(forKey key: String) -> String {
        let language = AppLanguage.from(currentLanguageCode)
        guard language != .system,
              let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return Bundle.main.localizedString(forKey: key, value: key, table: nil)
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
