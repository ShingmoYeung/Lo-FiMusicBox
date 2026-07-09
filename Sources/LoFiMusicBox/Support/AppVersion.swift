import Foundation

/// 从运行中的 bundle 读取营销版本。
/// 打包后的 `.app` 由 `scripts/package-macos-app.sh` 写入 Info.plist；
/// `swift run` 调试时若没有 CFBundle 字段，则回退到开发占位版本，避免比较逻辑崩溃。
enum AppVersion {
    static var marketingVersion: String {
        let info = Bundle.main.infoDictionary
        if let short = info?["CFBundleShortVersionString"] as? String,
           !short.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return short
        }
        return AppConstants.UpdateCheck.developmentFallbackMarketingVersion
    }

    /// 比较两个营销版本号。返回值：`lhs < rhs` 为负，相等为 0，`lhs > rhs` 为正。
    /// 只比较数字段（major.minor.patch…）；忽略前导 `v`/`V` 与预发布后缀（`-beta` 等）。
    static func compareMarketingVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = numericComponents(of: lhs)
        let right = numericComponents(of: rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }

    static func isRemoteNewer(local: String, remote: String) -> Bool {
        compareMarketingVersions(local, remote) < 0
    }

    private static func numericComponents(of raw: String) -> [Int] {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("v") {
            value = String(value.dropFirst())
        }
        if let dash = value.firstIndex(of: "-") {
            value = String(value[..<dash])
        }
        if let plus = value.firstIndex(of: "+") {
            value = String(value[..<plus])
        }
        return value.split(separator: ".").map { segment in
            Int(segment.filter(\.isNumber)) ?? 0
        }
    }
}
