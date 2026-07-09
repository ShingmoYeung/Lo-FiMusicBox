import Foundation

/// 用户选择的自动检查更新策略（只决定「何时检查」，不表示会自动安装）。
enum UpdateCheckPolicy: String, CaseIterable, Identifiable {
    case off
    case onLaunch
    case periodic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: LocalizedStrings.text("update.policy.off")
        case .onLaunch: LocalizedStrings.text("update.policy.on_launch")
        case .periodic: LocalizedStrings.text("update.policy.periodic")
        }
    }
}

/// GitHub Releases `latest` 接口的精简解码模型。
struct GitHubLatestRelease: Decodable, Equatable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let publishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }

    /// 去掉前导 `v` 后的营销版本，用于与本地 CFBundleShortVersionString 比较。
    var marketingVersion: String {
        var value = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("v") {
            value = String(value.dropFirst())
        }
        return value
    }
}

enum UpdateCheckOutcome: Equatable {
    case upToDate(currentVersion: String)
    case updateAvailable(release: GitHubLatestRelease)
    case failed(message: String)
}

struct UpdateCheckService {
    var timeout: TimeInterval = AppConstants.UpdateCheck.requestTimeoutSeconds
    var session: URLSession = .shared

    func checkLatestRelease(
        localMarketingVersion: String = AppVersion.marketingVersion
    ) async -> UpdateCheckOutcome {
        guard let url = URL(string: AppConstants.UpdateCheck.latestReleaseAPIURL) else {
            return .failed(message: LocalizedStrings.text("update.error.invalid_endpoint"))
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(
            AppConstants.UpdateCheck.acceptHeaderValue,
            forHTTPHeaderField: AppConstants.UpdateCheck.acceptHeaderName
        )
        request.setValue(
            AppConstants.Identity.runtimeUserAgent,
            forHTTPHeaderField: AppConstants.UpdateCheck.userAgentHeaderName
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed(message: LocalizedStrings.text("update.error.bad_response"))
            }
            guard (200..<300).contains(http.statusCode) else {
                return .failed(
                    message: LocalizedStrings.text("update.error.http_status", http.statusCode)
                )
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let release = try decoder.decode(GitHubLatestRelease.self, from: data)

            if AppVersion.isRemoteNewer(local: localMarketingVersion, remote: release.marketingVersion) {
                return .updateAvailable(release: release)
            }
            return .upToDate(currentVersion: localMarketingVersion)
        } catch let urlError as URLError {
            return .failed(message: Self.networkFailureMessage(for: urlError))
        } catch {
            return .failed(message: LocalizedStrings.text("update.error.parse_failed"))
        }
    }

    private static func networkFailureMessage(for error: URLError) -> String {
        switch error.code {
        case .timedOut:
            return LocalizedStrings.text("update.error.timeout")
        case .notConnectedToInternet:
            return LocalizedStrings.text("update.error.offline")
        case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed:
            return LocalizedStrings.text("update.error.unreachable")
        default:
            return LocalizedStrings.text("update.error.network_generic")
        }
    }
}
