import Foundation

@MainActor
final class PlaybackCoordinator: ObservableObject {
    @Published private(set) var currentStation: Station?
    @Published private(set) var state: PlaybackState = .idle
    @Published var volume: Float = AppConstants.Playback.defaultVolume {
        didSet {
            currentPlayer?.setVolume(volume)
        }
    }

    var isPlaying: Bool {
        state == .playing
    }

    private let avPlayer = AVStationPlayer()
    private let bilibiliResolver = BilibiliStreamResolver()
    private var currentPlayer: StationPlayer?
    /// 串行化加载任务：连续切台时取消上一个加载，避免旧台的解析结果回来覆盖新台。
    private var loadTask: Task<Void, Never>?

    init() {
        // 播放中断（直播流过期 / 失败 / 长时间停滞）时自动重连：
        // 重新走 play 流程——B 站会重新解析出新的 HLS 直链，普通流则重新拉起连接。
        avPlayer.onPlaybackInterrupted = { [weak self] in
            self?.reconnectCurrentStation()
        }
    }

    /// 自动重连：仅在"本应处于播放态"且有当前频道时重连，避免暂停/失败态被误重连。
    ///
    /// 走"无感重连"路径——刻意**不**调用 `play()`，因此不把状态切到 `.loading`：
    /// 频道未变，UI 显示屏保持"ON AIR"不闪、也不触发唱机换片动画；
    /// 底层 `AVStationPlayer` 会复用同一播放器换流并淡入恢复，听感平滑。
    private func reconnectCurrentStation() {
        guard state == .playing, let station = currentStation else { return }
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            await performLoad(station, isReconnect: true)
        }
    }

    func play(_ station: Station) {
        currentStation = station
        state = .loading

        loadTask?.cancel()
        loadTask = Task { @MainActor in
            await performLoad(station, isReconnect: false)
        }
    }

    /// 解析（B 站）并加载播放当前频道。`play()` 与自动重连共用。
    /// - Parameter isReconnect: 重连时失败**不**立刻判定 `.failed`（避免无感重连时 UI 闪报错），
    ///   保持 `.playing` 交由看门狗下一周期重试；普通加载失败则如实反映为 `.failed`。
    private func performLoad(_ station: Station, isReconnect: Bool) async {
        do {
            // 哔哩哔哩直播：先把直播间解析成 HLS 直链，再交给 AVPlayer 原生播放
            //（取代之前离屏 WKWebView 跑 flv.js 的方案——WebKit 离屏不渲染媒体、对 flv.js 兼容差，
            // 是 B 站台"检测正常却没声音"的根因）。m3u8 / mp3 电台仍直接走 AVPlayer。
            if station.type == .bilibili {
                let resolved = try await bilibiliResolver.resolve(roomEntry: station.url)
                guard !Task.isCancelled else { return }
                try await avPlayer.load(url: resolved.hlsURL)
            } else {
                try await avPlayer.load(station)
            }
            guard !Task.isCancelled else { return }
            currentPlayer = avPlayer
            // 同步用户当前音量到播放器（等待淡入期间不会打断静音起播，由淡入逼近目标）。
            avPlayer.setVolume(volume)
            state = .playing
        } catch {
            guard !Task.isCancelled else { return }
            // 重连失败保持 .playing，交看门狗下一周期重试，避免无感重连时 UI 闪报错。
            if !isReconnect {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func togglePlayPause() {
        switch state {
        case .playing:
            currentPlayer?.pause()
            state = .paused
        case .paused:
            currentPlayer?.play()
            state = .playing
        case .idle, .loading, .failed:
            if let currentStation {
                play(currentStation)
            }
        }
    }

    func stop() {
        currentPlayer?.pause()
        state = .paused
    }

    func updateVolume(_ newVolume: Float) {
        volume = max(
            AppConstants.Playback.minimumVolume,
            min(AppConstants.Playback.maximumVolume, newVolume)
        )
    }

    /// 切换到列表中的下一个频道，超出末尾时回绕到首项。
    /// 如果当前没有播放任何频道，则播放列表的第一项。
    func playNext(in stations: [Station]) {
        advance(in: stations, by: 1)
    }

    /// 切换到列表中的上一个频道，超出首位时回绕到末项。
    func playPrevious(in stations: [Station]) {
        advance(in: stations, by: -1)
    }

    private func advance(in stations: [Station], by step: Int) {
        guard !stations.isEmpty else { return }
        let count = stations.count
        let baseIndex: Int
        if let currentId = currentStation?.id,
           let foundIndex = stations.firstIndex(where: { $0.id == currentId }) {
            baseIndex = foundIndex
        } else {
            baseIndex = 0
        }
        // 用 (a % n + n) % n 保证负数模也能落到 [0, n) 区间。
        let normalizedIndex = ((baseIndex + step) % count + count) % count
        play(stations[normalizedIndex])
    }
}
