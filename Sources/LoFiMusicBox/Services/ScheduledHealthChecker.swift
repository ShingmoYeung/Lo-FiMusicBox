import Foundation

/// 频道可用性检测的统一入口。
/// - 由 App 启动时根据 `AppSettingsStore` 的配置决定是否启动周期性检测；
/// - 也可以由 UI 手动触发立即检测（例如频道管理页或设置页的按钮）；
/// - 检测结果通过 `StationRepository.updateHealth(for:health:)` 持久化。
@MainActor
final class ScheduledHealthChecker: ObservableObject {
    /// 当前是否有一轮检测正在进行。
    @Published private(set) var isCheckingNow: Bool = false
    /// 当前轮已完成的频道数量，用于 UI 展示进度。
    @Published private(set) var completedCount: Int = 0
    /// 当前轮总频道数。
    @Published private(set) var totalCount: Int = 0

    private let repository: StationRepository
    private let settings: AppSettingsStore
    private let healthService: StationHealthService
    private weak var playback: PlaybackCoordinator?

    /// 周期性调度任务，重新启动时会被取消并重新创建。
    private var schedulingTask: Task<Void, Never>?

    init(
        repository: StationRepository,
        settings: AppSettingsStore,
        playback: PlaybackCoordinator,
        healthService: StationHealthService = StationHealthService()
    ) {
        self.repository = repository
        self.settings = settings
        self.healthService = healthService
        self.playback = playback
    }

    deinit {
        schedulingTask?.cancel()
    }

    /// 根据当前设置启动或重启周期性检测；如果设置为“仅手动”或自动检测关闭，会停止现有任务。
    func reschedule() {
        schedulingTask?.cancel()
        schedulingTask = nil

        guard settings.healthAutoCheckEnabled else { return }
        let intervalMinutes = settings.healthCheckIntervalMinutes
        guard intervalMinutes > 0 else { return }

        let intervalNanoseconds = UInt64(intervalMinutes) * 60 * 1_000_000_000

        schedulingTask = Task { [weak self] in
            guard let self else { return }

            // 启动时若距离上次检测已经超过一个周期，则立即跑一轮，
            // 否则等到下一个周期再跑，避免应用频繁启动导致重复检测。
            if await self.shouldRunImmediatelyOnStart(intervalMinutes: intervalMinutes) {
                await self.runOneRoundIfAllowedByPlayback()
            }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                } catch {
                    return
                }
                if Task.isCancelled { return }
                await self.runOneRoundIfAllowedByPlayback()
            }
        }
    }

    /// 立刻进行一轮检测，无视“仅空闲检测”等配置，用于设置页的手动按钮。
    func runOneRoundNow() async {
        await runOneRound()
    }

    private func shouldRunImmediatelyOnStart(intervalMinutes: Int) async -> Bool {
        guard let last = settings.healthLastCheckedAt else { return true }
        let elapsed = Date().timeIntervalSince(last)
        let intervalSeconds = TimeInterval(intervalMinutes * 60)
        return elapsed >= intervalSeconds
    }

    private func runOneRoundIfAllowedByPlayback() async {
        if settings.healthCheckOnlyWhenIdle, playback?.isPlaying == true {
            // 当前正在播放且用户希望避免干扰，本轮跳过。
            return
        }
        await runOneRound()
    }

    /// 实际跑一轮：把 repository 中所有可见频道串行检测，
    /// 串行而非并发是为了避免短时间向同一台流媒体服务器发起大量握手。
    private func runOneRound() async {
        guard !isCheckingNow else { return }
        let stationsToCheck = repository.allStationsIncludingHidden
        guard !stationsToCheck.isEmpty else {
            settings.updateHealthLastCheckedAt(Date())
            return
        }

        isCheckingNow = true
        completedCount = 0
        totalCount = stationsToCheck.count

        for station in stationsToCheck {
            if Task.isCancelled { break }
            // 标记为“检测中”，让列表立刻有视觉反馈。
            repository.updateHealth(for: station, health: StationHealth(
                status: .checking,
                checkedAt: nil,
                responseTimeMilliseconds: nil,
                statusCode: nil,
                contentType: nil,
                message: LocalizedStrings.text("station.health.message.checking")
            ))

            let health = await healthService.check(station)
            repository.updateHealth(for: station, health: health)
            completedCount += 1
        }

        settings.updateHealthLastCheckedAt(Date())
        isCheckingNow = false
    }
}
