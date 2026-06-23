import Foundation

enum LocalizedStrings {
    static func text(_ key: String) -> String {
        activeBundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = text(key)
        return String(format: format, locale: formatLocale, arguments: arguments)
    }

    private static var activeBundle: Bundle {
        guard let languageCode = AppLanguage.currentLocalizationCode else {
            return AppResourceBundle.bundle
        }
        if let path = AppResourceBundle.bundle.path(forResource: languageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        if let path = AppResourceBundle.bundle.path(forResource: languageCode.lowercased(), ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return AppResourceBundle.bundle
    }

    private static var formatLocale: Locale {
        guard let languageCode = AppLanguage.currentLocalizationCode else {
            return .current
        }
        return Locale(identifier: languageCode)
    }
}
