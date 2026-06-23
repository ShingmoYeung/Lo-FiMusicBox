import AVFoundation
import Foundation

@MainActor
final class AVStationPlayer: StationPlayer {
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var stallWatchdog: Timer?
    private var notificationObservers: [NSObjectProtocol] = []
    private var fadeTimer: Timer?
    /// 淡入进度：当前步与总步数，由 advanceFadeStep 逐步推进。
    private var fadeStep = 0
    private var fadeTotalSteps = 1

    /// 目标音量（用户设定）。淡入的终点，以及非淡入场景直接采用的音量。
    private var targetVolume: Float = AppConstants.Playback.defaultVolume

    /// 最近一次"播放进度向前推进"的时间戳，看门狗据此判断是否停滞。
    private var lastProgressAt = Date()
    /// 最近一次触发重连的时间戳，用于防抖避免反复重连成环。
    private var lastReconnectAt = Date.distantPast

    /// 播放被判定中断（直播流过期 / 播放失败 / 长时间停滞）时回调，
    /// 交给上层（`PlaybackCoordinator`）重新解析并重连当前频道。
    var onPlaybackInterrupted: (() -> Void)?

    func load(_ station: Station) async throws {
        try await load(url: station.url)
    }

    /// 按给定 URL 加载播放。
    /// - Parameter fadeIn: 是否淡入。起播 / 重连时淡入，把"卡顿→突兀全音量"变成平滑渐入。
    ///
    /// 关键：复用同一个 `AVPlayer`（`replaceCurrentItem`）而非每次重建播放器，
    /// 避免音频管线重置带来的爆音与额外延迟——这是重连时声音过渡不自然的主因之一。
    func load(url: URL, fadeIn: Bool = true) async throws {
        teardownObservers()
        cancelFade()

        let item = AVPlayerItem(url: url)
        let activePlayer = preparedPlayer(with: item)

        // 淡入：先静音起播；非淡入：直接采用目标音量。
        activePlayer.volume = fadeIn ? 0 : clampedTargetVolume()

        setupObservers(for: item, player: activePlayer)
        lastProgressAt = Date()
        activePlayer.play()

        if fadeIn {
            startFadeIn(on: activePlayer)
        }
    }

    /// 复用已有 `AVPlayer` 换片；首次则新建并配置。
    private func preparedPlayer(with item: AVPlayerItem) -> AVPlayer {
        if let player {
            player.replaceCurrentItem(with: item)
            return player
        }
        let created = AVPlayer(playerItem: item)
        // 让 AVPlayer 用缓冲等待自行吸收短暂网络抖动，减少我们误判停滞而硬重连。
        created.automaticallyWaitsToMinimizeStalling = true
        player = created
        return created
    }

    func play() {
        player?.play()
        // 非淡入恢复时确保音量回到用户目标值（淡入进行中则交给淡入逼近）。
        if fadeTimer == nil {
            player?.volume = clampedTargetVolume()
        }
        lastProgressAt = Date()
    }

    func pause() {
        cancelFade()
        player?.pause()
    }

    func setVolume(_ volume: Float) {
        targetVolume = clamp(volume)
        // 淡入进行中不直接覆盖音量（由淡入逐步逼近 targetVolume）；否则即时生效。
        // 因此协调器在 load 后立即调用 setVolume 同步音量，也不会打断静音起播的淡入。
        if fadeTimer == nil {
            player?.volume = targetVolume
        }
    }

    // MARK: - 音量淡入

    /// 启动淡入。定时器逐帧推进音量；但只有播放器**真正进入 playing（开始出声）**后才推进，
    /// 缓冲等待期间保持静音、不推进，从而把"缓冲卡顿→突兀全音量"变成"出声即平滑渐入"。
    /// 回调显式切回 `MainActor` 后推进，避免依赖运行时对主队列/主 actor 等价性的假设。
    private func startFadeIn(on player: AVPlayer) {
        cancelFade()
        fadeStep = 0
        fadeTotalSteps = max(
            1,
            Int(AppConstants.Playback.fadeInSeconds / AppConstants.Playback.fadeStepIntervalSeconds)
        )
        player.volume = 0
        fadeTimer = Timer.scheduledTimer(
            withTimeInterval: AppConstants.Playback.fadeStepIntervalSeconds,
            repeats: true
        ) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }
            Task { @MainActor [weak self] in
                _ = self?.advanceFadeStep()
            }
        }
    }

    /// 推进一步淡入，返回 true 表示淡入已完成（调用方据此停表）。
    /// 仍在缓冲（未真正出声）时保持静音、不推进，等真正进入 playing 再渐升。
    private func advanceFadeStep() -> Bool {
        guard let player else {
            cancelFade()
            return true
        }
        guard player.timeControlStatus == .playing else { return false }
        fadeStep += 1
        let progress = Float(fadeStep) / Float(fadeTotalSteps)
        player.volume = clampedTargetVolume() * min(1, progress)
        if progress >= 1 {
            cancelFade()
            return true
        }
        return false
    }

    private func cancelFade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
    }

    private func clampedTargetVolume() -> Float { clamp(targetVolume) }

    private func clamp(_ value: Float) -> Float {
        max(AppConstants.Playback.minimumVolume, min(AppConstants.Playback.maximumVolume, value))
    }

    // MARK: - 中断检测与自动重连

    private func setupObservers(for item: AVPlayerItem, player: AVPlayer) {
        // 1) 周期性进度观察：只要时间在推进就刷新 lastProgressAt（直播断流时不再推进）。
        let interval = CMTime(
            seconds: AppConstants.Playback.progressObserverIntervalSeconds,
            preferredTimescale: 1
        )
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lastProgressAt = Date()
            }
        }

        // 2) 播放失败通知：明确失败立即走重连。
        let failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleInterruption()
            }
        }
        notificationObservers = [failObserver]

        // 3) 看门狗：周期性检查"期望在播却长时间无进度"的停滞。
        let watchdog = Timer.scheduledTimer(
            withTimeInterval: AppConstants.Playback.watchdogIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkStall()
            }
        }
        stallWatchdog = watchdog
    }

    /// 看门狗回调：仅在"已请求播放"（rate > 0，含正在缓冲等待）时判定停滞，暂停态不参与。
    /// 短暂抖动会被 AVPlayer 自身缓冲等待恢复（恢复后进度继续推进、刷新 lastProgressAt），
    /// 因此 stalledFor 只在真正长时间断流时才会超过阈值。
    private func checkStall() {
        guard let player, player.rate > 0 else { return }
        let stalledFor = Date().timeIntervalSince(lastProgressAt)
        if stalledFor > AppConstants.Playback.stallTimeoutSeconds {
            handleInterruption()
        }
    }

    private func handleInterruption() {
        // 防抖：两次重连至少间隔 minReconnectIntervalSeconds，避免抖动期间反复重连。
        guard Date().timeIntervalSince(lastReconnectAt)
            > AppConstants.Playback.minReconnectIntervalSeconds else {
            return
        }
        lastReconnectAt = Date()
        onPlaybackInterrupted?()
    }

    private func teardownObservers() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil

        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers = []

        stallWatchdog?.invalidate()
        stallWatchdog = nil
    }
}
