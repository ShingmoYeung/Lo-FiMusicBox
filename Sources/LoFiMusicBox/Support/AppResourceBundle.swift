import Foundation

enum AppResourceBundle {
    private static let bundleName = "LoFiMusicBox_LoFiMusicBox.bundle"

    static var bundle: Bundle {
        if let bundle = resolveBundle() {
            return bundle
        }

        assertionFailure("未找到 SwiftPM 资源包：\(bundleName)")
        return .main
    }

    private static func resolveBundle() -> Bundle? {
        let candidates = candidateBundleURLs()
        for url in candidates {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return nil
    }

    private static func candidateBundleURLs() -> [URL] {
        var urls: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent(bundleName, isDirectory: true))
        }

        urls.append(Bundle.main.bundleURL.appendingPathComponent(bundleName, isDirectory: true))
        urls.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName, isDirectory: true))
        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            urls.append(executableDirectory.appendingPathComponent(bundleName, isDirectory: true))
        }

        return urls
    }
}
