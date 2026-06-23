import Foundation

/// 应用级常量集中在这里，避免业务代码中散落不具名的魔法值。
enum AppConstants {
    enum Identity {
        static let displayName = "Lo-Fi Music Box"
        static let applicationSupportDirectoryName = "Lo-Fi Music Box"
        static let userAgent = "LoFiMusicBox/1.0"
    }

    enum Resource {
        static let bundledStationsFileName = "BundledStations"
        static let jsonFileExtension = "json"
        static let customStationsFileName = "custom-stations.json"
        /// 用户对内置频道的修改保存到该文件，与原始 BundledStations.json 完全分离。
        static let bundledOverridesFileName = "bundled-overrides.json"
        /// 用户隐藏的内置频道 ID 列表。
        static let hiddenBundledIdsFileName = "hidden-bundled-ids.json"
        /// 用户收藏的频道 ID 列表。
        static let favoriteStationIdsFileName = "favorite-station-ids.json"
        /// 各频道的最近可用性检测结果，按 stableIdentifier 索引。
        static let stationHealthFileName = "station-health.json"
        static let bundledStationIdPrefix = "bundled."
        static let customStationIdPrefix = "custom."
    }

    enum Playback {
        static let defaultVolume: Float = 0.3
        static let minimumVolume: Float = 0
        static let maximumVolume: Float = 1
        /// 自动重连相关：直播流地址带 expires，过期后会断流；网络抖动也可能导致停滞。
        /// 看门狗每隔 watchdogIntervalSeconds 检查一次，若"期望在播却已 stallTimeoutSeconds
        /// 没有新播放进度"，判定为中断并触发重连；minReconnectInterval 防止短时间反复重连成环。
        static let progressObserverIntervalSeconds: Double = 2
        static let watchdogIntervalSeconds: TimeInterval = 5
        /// 停滞判定阈值。调大一些，给 AVPlayer 自身的缓冲等待（automaticallyWaitsToMinimizeStalling）
        /// 足够时间吸收短暂网络抖动，只有真正长时间断流才触发硬重连，减少误重连。
        static let stallTimeoutSeconds: TimeInterval = 16
        static let minReconnectIntervalSeconds: TimeInterval = 6
        /// 起播 / 重连时的音量淡入时长与步进间隔：把"卡顿→突兀全音量"变成平滑渐入。
        static let fadeInSeconds: Double = 0.6
        static let fadeStepIntervalSeconds: Double = 0.03
    }

    enum Settings {
        static let preferredVolumeStorageKey = "lofi-music-box-preferred-volume"
        static let lastStationIdentifierStorageKey = "lofi-music-box-last-station-id"
        static let playbackAuraIntensityStorageKey = "lofi-music-box-playback-aura-intensity"
        static let appLanguageStorageKey = "lofi-music-box-app-language"

        /// 可用性检测自动开关的持久化键。
        static let healthAutoCheckEnabledStorageKey = "lofi-music-box-health-auto-check-enabled"
        /// 可用性检测频率（分钟）的持久化键。
        static let healthCheckIntervalMinutesStorageKey = "lofi-music-box-health-check-interval-minutes"
        /// 是否仅在播放空闲时进行检测。
        static let healthCheckOnlyWhenIdleStorageKey = "lofi-music-box-health-check-only-when-idle"
        /// 上次可用性检测的完成时间。
        static let healthLastCheckedAtStorageKey = "lofi-music-box-health-last-checked-at"

        /// 检测频率档位（分钟）。`0` 代表“仅手动”。
        static let healthCheckIntervalChoices: [Int] = [5, 10, 30, 60]
        static let defaultHealthCheckIntervalMinutes: Int = 30
        static let defaultHealthAutoCheckEnabled: Bool = true
        static let defaultHealthCheckOnlyWhenIdle: Bool = true
        static let defaultPlaybackAuraIntensity: PlaybackAuraIntensity = .balanced
    }

    enum StationTypeInference {
        static let hlsFileExtension = ".m3u8"
        static let hlsIsmlMarker = ".isml"
        static let bilibiliHostMarker = "bilibili.com"
    }

    /// 哔哩哔哩直播解析相关常量。
    /// B 站直播间是网页（flv.js/MSE 播 HTTP-FLV），不能直接丢给 AVPlayer；
    /// 这里通过官方网页接口把直播间解析成 HLS(m3u8) 直链，再交给 AVPlayer 原生播放。
    /// 实测：以下接口无需登录 / cookie / wbi 签名即可获取 HLS 流。
    enum Bilibili {
        /// 直播间初始化接口：用入口号换取真实 room_id 与开播状态。
        static let roomInitAPI = "https://api.live.bilibili.com/room/v1/Room/room_init"
        /// 取流接口：返回各协议/封装/编码的播放地址。
        static let playInfoAPI = "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo"
        /// 取流请求参数：protocol=0,1（flv+hls）、format=0,1,2（flv/ts/fmp4）、codec=0,1（avc/hevc）。
        static let protocolParameter = "0,1"
        static let formatParameter = "0,1,2"
        static let codecParameter = "0,1"
        /// 画质档（10000=原画）。lofi 直播码率不高，原画也仅 ~0.3MB/s，且确保有 HLS 流可选。
        static let preferredQuality = 10000
        static let platformParameter = "web"
        static let pageTypeParameter = "8"
        /// 接口/流标识。HLS 走 http_hls；优先 fmp4 封装 + avc 编码（AVPlayer 兼容性最好）。
        static let hlsProtocolName = "http_hls"
        static let preferredFormatName = "fmp4"
        static let fallbackFormatName = "ts"
        static let preferredCodecName = "avc"
        /// live_status == 1 表示正在直播。
        static let liveStatusLive = 1
        static let requestTimeoutSeconds: TimeInterval = 8
        /// 用桌面 Safari UA 请求，贴近网页端环境，避免被判定为异常客户端。
        static let webUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        static let refererHeaderName = "Referer"
        static let refererValue = "https://live.bilibili.com/"
        static let userAgentHeaderName = "User-Agent"
    }

    enum StationHealthCheck {
        static let requestTimeoutSeconds: TimeInterval = 8
        static let rangedProbeHeaderName = "Range"
        static let rangedProbeHeaderValue = "bytes=0-1023"
        static let userAgentHeaderName = "User-Agent"
        static let httpHeadMethod = "HEAD"
        static let httpGetMethod = "GET"
        static let successfulStatusCodeRange = 200..<400
        static let hlsManifestMarker = "#EXTM3U"
    }

    enum FocusTimer {
        static let tickIntervalSeconds: TimeInterval = 60
        static let secondsPerMinute: TimeInterval = 60
        static let currentFocusStorageKey = "lofi-music-box-current-focus"
        static let focusHistoryStorageKey = "lofi-music-box-focus-history"
        static let retainedHistoryDays = 90
    }

    enum UserInterface {
        // 主悬浮小组件窗口尺寸：保持紧凑，同时容纳音量控制和频道标签。
        // 高度从 220 提升到 248：给右侧"频道名两行 + 换行标签"和底部"复古控制台"留出呼吸空间。
        static let widgetWindowWidth: CGFloat = 360
        static let widgetWindowHeight: CGFloat = 248
        /// 圆角半径选 16：足够显示软圆角，又能保证 14pt padding 的顶部按钮完全落在
        /// "非圆角直线区域"（x>=r 或 y>=r），绝不会被 clipShape 剪掉。
        static let widgetCornerRadius: CGFloat = 16
        /// 顶部按钮离窗口边缘的距离，必须 >= widgetCornerRadius 才能不被圆角剪。
        static let widgetEdgeInset: CGFloat = 14
        /// 唱机与右侧信息区的水平间距，比通用 mediumSpacing 更宽，避免信息贴着唱机。
        static let vinylInfoSpacing: CGFloat = 18
        /// 主界面信息区行内标签最多直接展示的数量，超出部分用 "+N" 汇总。
        static let maxInlineTags = 5
        static let stationManagerMinimumWidth: CGFloat = 520
        static let stationManagerMinimumHeight: CGFloat = 620
        static let mediumSpacing: CGFloat = 12
        static let smallSpacing: CGFloat = 6
        static let stationRowPadding: CGFloat = 10
        static let stationOverlayPadding: CGFloat = 14
    }
}
