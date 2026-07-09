import Foundation

enum PlaybackAuraIntensity: String, CaseIterable, Identifiable {
    case off
    case subtle
    case balanced
    case rich

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: LocalizedStrings.text("availability.aura.off")
        case .subtle: LocalizedStrings.text("availability.aura.subtle")
        case .balanced: LocalizedStrings.text("availability.aura.balanced")
        case .rich: LocalizedStrings.text("availability.aura.rich")
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case automatic
    case simplifiedChinese
    case traditionalChineseHongKong
    case traditionalChineseTaiwan
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: LocalizedStrings.text("language.automatic")
        case .simplifiedChinese: LocalizedStrings.text("language.zh_hans")
        case .traditionalChineseHongKong: LocalizedStrings.text("language.zh_hk")
        case .traditionalChineseTaiwan: LocalizedStrings.text("language.zh_tw")
        case .english: LocalizedStrings.text("language.en")
        }
    }

    var localizationCode: String? {
        switch self {
        case .automatic: nil
        case .simplifiedChinese: "zh-Hans"
        case .traditionalChineseHongKong: "zh-HK"
        case .traditionalChineseTaiwan: "zh-Hant"
        case .english: "en"
        }
    }

    static var currentLocalizationCode: String? {
        let rawValue = UserDefaults.standard.string(
            forKey: AppConstants.Settings.appLanguageStorageKey
        ) ?? AppLanguage.automatic.rawValue
        return AppLanguage(rawValue: rawValue)?.localizationCode
    }
}

/// 用户偏好设置存储。所有字段都通过 `UserDefaults` 持久化，
/// 修改后会立刻发布给订阅方（@Published），UI 层无需手动刷新。
@MainActor
final class AppSettingsStore: ObservableObject {
    @Published private(set) var preferredVolume: Float
    @Published private(set) var lastStationIdentifier: String?
    @Published private(set) var playbackAuraIntensity: PlaybackAuraIntensity

    /// 是否在后台自动进行频道可用性检测。
    @Published private(set) var healthAutoCheckEnabled: Bool
    /// 可用性检测间隔（分钟）。
    @Published private(set) var healthCheckIntervalMinutes: Int
    /// 是否仅在没有播放时进行检测，避免影响播放体验。
    @Published private(set) var healthCheckOnlyWhenIdle: Bool
    /// 上一次完成的可用性检测时间，仅作 UI 展示。
    @Published private(set) var healthLastCheckedAt: Date?
    @Published private(set) var appLanguage: AppLanguage

    /// 自动检查更新策略（只检查 / 通知，不会自动安装）。
    @Published private(set) var updateCheckPolicy: UpdateCheckPolicy
    @Published private(set) var updateLastCheckedAt: Date?
    @Published private(set) var updateSnoozeUntil: Date?
    @Published private(set) var updateIgnoredVersion: String?
    @Published private(set) var updatePeriodicIntervalHours: Int

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedVolumeNumber = userDefaults.object(
            forKey: AppConstants.Settings.preferredVolumeStorageKey
        ) as? NSNumber
        preferredVolume = AppSettingsStore.clampedVolume(
            storedVolumeNumber?.floatValue ?? AppConstants.Playback.defaultVolume
        )

        lastStationIdentifier = userDefaults.string(
            forKey: AppConstants.Settings.lastStationIdentifierStorageKey
        )

        playbackAuraIntensity = PlaybackAuraIntensity(
            rawValue: userDefaults.string(forKey: AppConstants.Settings.playbackAuraIntensityStorageKey) ?? ""
        ) ?? AppConstants.Settings.defaultPlaybackAuraIntensity

        if userDefaults.object(forKey: AppConstants.Settings.healthAutoCheckEnabledStorageKey) == nil {
            healthAutoCheckEnabled = AppConstants.Settings.defaultHealthAutoCheckEnabled
        } else {
            healthAutoCheckEnabled = userDefaults.bool(
                forKey: AppConstants.Settings.healthAutoCheckEnabledStorageKey
            )
        }

        let storedIntervalNumber = userDefaults.object(
            forKey: AppConstants.Settings.healthCheckIntervalMinutesStorageKey
        ) as? NSNumber
        let resolvedInterval = storedIntervalNumber?.intValue
            ?? AppConstants.Settings.defaultHealthCheckIntervalMinutes
        // 落到合法档位，防止旧版本残留非法值。
        healthCheckIntervalMinutes = AppConstants.Settings.healthCheckIntervalChoices
            .contains(resolvedInterval)
            ? resolvedInterval
            : AppConstants.Settings.defaultHealthCheckIntervalMinutes

        if userDefaults.object(forKey: AppConstants.Settings.healthCheckOnlyWhenIdleStorageKey) == nil {
            healthCheckOnlyWhenIdle = AppConstants.Settings.defaultHealthCheckOnlyWhenIdle
        } else {
            healthCheckOnlyWhenIdle = userDefaults.bool(
                forKey: AppConstants.Settings.healthCheckOnlyWhenIdleStorageKey
            )
        }

        healthLastCheckedAt = userDefaults.object(
            forKey: AppConstants.Settings.healthLastCheckedAtStorageKey
        ) as? Date

        appLanguage = AppLanguage(
            rawValue: userDefaults.string(forKey: AppConstants.Settings.appLanguageStorageKey) ?? ""
        ) ?? .automatic

        updateCheckPolicy = UpdateCheckPolicy(
            rawValue: userDefaults.string(forKey: AppConstants.Settings.updateCheckPolicyStorageKey) ?? ""
        ) ?? AppConstants.Settings.defaultUpdateCheckPolicy

        updateLastCheckedAt = userDefaults.object(
            forKey: AppConstants.Settings.updateLastCheckedAtStorageKey
        ) as? Date

        updateSnoozeUntil = userDefaults.object(
            forKey: AppConstants.Settings.updateSnoozeUntilStorageKey
        ) as? Date

        updateIgnoredVersion = userDefaults.string(
            forKey: AppConstants.Settings.updateIgnoredVersionStorageKey
        )

        let storedUpdateInterval = userDefaults.object(
            forKey: AppConstants.Settings.updatePeriodicIntervalHoursStorageKey
        ) as? NSNumber
        let resolvedUpdateInterval = storedUpdateInterval?.intValue
            ?? AppConstants.Settings.defaultUpdatePeriodicIntervalHours
        updatePeriodicIntervalHours = AppConstants.Settings.updatePeriodicIntervalHourChoices
            .contains(resolvedUpdateInterval)
            ? resolvedUpdateInterval
            : AppConstants.Settings.defaultUpdatePeriodicIntervalHours
    }

    func updatePreferredVolume(_ volume: Float) {
        let clampedVolume = Self.clampedVolume(volume)
        preferredVolume = clampedVolume
        userDefaults.set(clampedVolume, forKey: AppConstants.Settings.preferredVolumeStorageKey)
    }

    func updateLastStationIdentifier(_ stationIdentifier: String?) {
        lastStationIdentifier = stationIdentifier
        userDefaults.set(stationIdentifier, forKey: AppConstants.Settings.lastStationIdentifierStorageKey)
    }

    func updatePlaybackAuraIntensity(_ intensity: PlaybackAuraIntensity) {
        playbackAuraIntensity = intensity
        userDefaults.set(intensity.rawValue, forKey: AppConstants.Settings.playbackAuraIntensityStorageKey)
    }

    func updateHealthAutoCheckEnabled(_ enabled: Bool) {
        healthAutoCheckEnabled = enabled
        userDefaults.set(enabled, forKey: AppConstants.Settings.healthAutoCheckEnabledStorageKey)
    }

    func updateHealthCheckIntervalMinutes(_ minutes: Int) {
        guard AppConstants.Settings.healthCheckIntervalChoices.contains(minutes) else { return }
        healthCheckIntervalMinutes = minutes
        userDefaults.set(minutes, forKey: AppConstants.Settings.healthCheckIntervalMinutesStorageKey)
    }

    func updateHealthCheckOnlyWhenIdle(_ onlyWhenIdle: Bool) {
        healthCheckOnlyWhenIdle = onlyWhenIdle
        userDefaults.set(onlyWhenIdle, forKey: AppConstants.Settings.healthCheckOnlyWhenIdleStorageKey)
    }

    func updateHealthLastCheckedAt(_ date: Date) {
        healthLastCheckedAt = date
        userDefaults.set(date, forKey: AppConstants.Settings.healthLastCheckedAtStorageKey)
    }

    func updateAppLanguage(_ language: AppLanguage) {
        appLanguage = language
        userDefaults.set(language.rawValue, forKey: AppConstants.Settings.appLanguageStorageKey)
    }

    func updateUpdateCheckPolicy(_ policy: UpdateCheckPolicy) {
        updateCheckPolicy = policy
        userDefaults.set(policy.rawValue, forKey: AppConstants.Settings.updateCheckPolicyStorageKey)
    }

    func updateUpdateLastCheckedAt(_ date: Date) {
        updateLastCheckedAt = date
        userDefaults.set(date, forKey: AppConstants.Settings.updateLastCheckedAtStorageKey)
    }

    func updateUpdateSnoozeUntil(_ date: Date?) {
        updateSnoozeUntil = date
        userDefaults.set(date, forKey: AppConstants.Settings.updateSnoozeUntilStorageKey)
    }

    func updateIgnoredUpdateVersion(_ version: String?) {
        updateIgnoredVersion = version
        userDefaults.set(version, forKey: AppConstants.Settings.updateIgnoredVersionStorageKey)
    }

    func clearIgnoredUpdateVersion() {
        updateIgnoredUpdateVersion(nil)
    }

    func updateUpdatePeriodicIntervalHours(_ hours: Int) {
        guard AppConstants.Settings.updatePeriodicIntervalHourChoices.contains(hours) else { return }
        updatePeriodicIntervalHours = hours
        userDefaults.set(hours, forKey: AppConstants.Settings.updatePeriodicIntervalHoursStorageKey)
    }

    private static func clampedVolume(_ volume: Float) -> Float {
        max(
            AppConstants.Playback.minimumVolume,
            min(AppConstants.Playback.maximumVolume, volume)
        )
    }
}
