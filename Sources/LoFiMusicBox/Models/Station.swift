import Foundation

/// 频道协议类型，决定播放层如何取流：
/// - `.bilibili`：先把直播间解析成 HLS 直链（`BilibiliStreamResolver`），再交给 AVFoundation 播放；
/// - `.mp3`/`.m3u8`：直接交给 AVFoundation 播放。
/// 所有类型最终都走原生 `AVPlayer`，无 WebView。
enum StationType: String, Codable, CaseIterable, Identifiable {
    case bilibili
    case mp3
    case m3u8

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bilibili: LocalizedStrings.text("station.type.bilibili")
        case .mp3: LocalizedStrings.text("station.type.mp3")
        case .m3u8: LocalizedStrings.text("station.type.m3u8")
        }
    }

    /// 数显屏右上角用的简短"流类型/协议"徽标。
    /// 哔哩哔哩是直播流（内部以 HLS 播放），用 `LIVE` 既表达直播性质、又区别于点播 HLS；
    /// mp3 / m3u8 直接标各自协议。
    var streamBadge: String {
        switch self {
        case .bilibili: "LIVE"
        case .mp3: "MP3"
        case .m3u8: "HLS"
        }
    }

    /// 根据 URL 字符串猜测类型，用于在“频道管理”页面给用户填好类型默认值。
    static func inferred(from urlString: String) -> StationType {
        let lowercasedURLString = urlString.lowercased()
        if lowercasedURLString.contains(AppConstants.StationTypeInference.bilibiliHostMarker) {
            return .bilibili
        }
        if lowercasedURLString.contains(AppConstants.StationTypeInference.hlsFileExtension)
            || lowercasedURLString.contains(AppConstants.StationTypeInference.hlsIsmlMarker) {
            return .m3u8
        }
        return .mp3
    }
}

/// 频道来源：内置（随 App 分发）或自定义（用户添加）。
/// 内置频道允许用户编辑 / 隐藏，但修改会写入独立覆盖层文件而非原始 JSON，
/// 这样 App 升级带来的内置频道更新不会覆盖用户改动，并且可恢复默认。
enum StationSource: String, Codable {
    case bundled
    case custom

    var displayName: String {
        switch self {
        case .bundled: LocalizedStrings.text("station.source.bundled")
        case .custom: LocalizedStrings.text("station.source.custom")
        }
    }
}

/// 单次可用性检测细节状态。
enum StationHealthStatus: String, Codable {
    case unknown
    case checking
    case available
    case unstable
    case unavailable

    var displayName: String {
        switch self {
        case .unknown: LocalizedStrings.text("station.health.unknown")
        case .checking: LocalizedStrings.text("station.health.checking")
        case .available: LocalizedStrings.text("station.health.display.available")
        case .unstable: LocalizedStrings.text("station.health.unstable")
        case .unavailable: LocalizedStrings.text("station.health.unavailable")
        }
    }

    /// 列表排序优先级：可用 > 不稳定 > 未检测/检测中 > 不可用。
    /// 数字越小越靠前。
    var sortPriority: Int {
        switch self {
        case .available: return 0
        case .unstable: return 1
        case .unknown: return 2
        case .checking: return 3
        case .unavailable: return 4
        }
    }
}

/// 单条频道一次可用性检测的结果快照。
struct StationHealth: Codable, Equatable {
    var status: StationHealthStatus
    var checkedAt: Date?
    var responseTimeMilliseconds: Int?
    var statusCode: Int?
    var contentType: String?
    var message: String?

    static let unknown = StationHealth(
        status: .unknown,
        checkedAt: nil,
        responseTimeMilliseconds: nil,
        statusCode: nil,
        contentType: nil,
        message: nil
    )
}

/// 频道实体。
/// 关键设计：
/// - `id` 改用稳定 `stableIdentifier` 字段，不再依赖 URL，
///   这样用户即使修改 URL，覆盖层、健康记录、隐藏列表的关联仍然有效；
/// - `customTags` 是用户在“频道管理”里手动维护的标签，优先用于显示；
/// - `style1/style2/scene/category` 等老字段保留，向后兼容旧 JSON，
///   并作为 `customTags` 为空时的默认显示来源。
struct Station: Identifiable, Codable, Equatable {
    /// 稳定标识符。内置频道在 BundledStations.json 中预定义；自定义频道在创建时自动生成 UUID。
    var stableIdentifier: String

    var name: String
    var category: String
    var type: StationType
    var url: URL
    var style1: String?
    var style2: String?
    var scene: String?
    var custom: String?
    var customTags: [String]
    var source: StationSource
    var isEnabled: Bool
    var lastHealth: StationHealth?

    var id: String { stableIdentifier }

    /// 行内显示用的标签数组：优先使用用户自定义标签，
    /// 没有时回落到内置元数据（style1/style2/scene/custom），过滤空值并去重。
    var effectiveTags: [String] {
        if !customTags.isEmpty {
            return Array(NSOrderedSet(array: customTags)) as? [String] ?? customTags
        }
        let fallback = [style1, style2, scene, custom].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return Array(NSOrderedSet(array: fallback)) as? [String] ?? fallback
    }

    /// 频谱可视化档案：根据频道名称 / 分类 / 标签里的风格关键字，
    /// 推断显示屏动态频谱的能量（幅度）与节奏（速度）。
    /// 说明：当前播放走远程流 + AVPlayer，未接入实时音频 FFT，
    /// 因此频谱按"音乐风格"模拟律动；未匹配到关键字时返回中性默认值。
    var spectrumProfile: (energy: Double, tempo: Double) {
        let haystack = ([name, category] + effectiveTags)
            .joined(separator: " ")
            .lowercased()

        func matches(_ keywords: [String]) -> Bool {
            keywords.contains { haystack.contains($0) }
        }

        // 高能：电子 / 节拍 / 游戏 / 动感。
        if matches([
            "electronic", "synth", "beats", "beat", "dance", "edm", "techno",
            "drum", "bass", "game", "energetic", "电子", "节拍", "游戏", "动感"
        ]) {
            return (energy: 1.0, tempo: 1.4)
        }
        // 中高：爵士 / 嘻哈 / 律动 / 咖啡馆。
        if matches([
            "jazz", "hip", "groove", "funk", "cafe", "café", "piano",
            "爵士", "咖啡", "钢琴", "律动"
        ]) {
            return (energy: 0.78, tempo: 1.0)
        }
        // 低缓：lofi / 雨声 / 助眠 / 氛围 / 舒缓。
        if matches([
            "lofi", "lo-fi", "chill", "sleep", "rain", "calm", "ambient",
            "relax", "study", "雨", "睡", "助眠", "氛围", "舒缓", "学习", "放松"
        ]) {
            return (energy: 0.5, tempo: 0.65)
        }
        return (energy: 0.72, tempo: 0.95)
    }

    init(
        stableIdentifier: String = UUID().uuidString,
        name: String,
        category: String,
        type: StationType,
        url: URL,
        style1: String? = nil,
        style2: String? = nil,
        scene: String? = nil,
        custom: String? = nil,
        customTags: [String] = [],
        source: StationSource = .custom,
        isEnabled: Bool = true,
        lastHealth: StationHealth? = nil
    ) {
        self.stableIdentifier = stableIdentifier
        self.name = name
        self.category = category
        self.type = type
        self.url = url
        self.style1 = style1
        self.style2 = style2
        self.scene = scene
        self.custom = custom
        self.customTags = customTags
        self.source = source
        self.isEnabled = isEnabled
        self.lastHealth = lastHealth
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case type
        case url
        case style1
        case style2
        case scene
        case custom
        case customTags
        case source
        case isEnabled
        case lastHealth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // JSON 中既允许显式 id，也兼容旧版无 id 数据（自动补 UUID）。
        stableIdentifier = (try container.decodeIfPresent(String.self, forKey: .id))
            ?? UUID().uuidString
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(String.self, forKey: .category)
        type = try container.decode(StationType.self, forKey: .type)
        lastHealth = try container.decodeIfPresent(StationHealth.self, forKey: .lastHealth)
        url = try container.decode(URL.self, forKey: .url)
        style1 = try container.decodeIfPresent(String.self, forKey: .style1)
        style2 = try container.decodeIfPresent(String.self, forKey: .style2)
        scene = try container.decodeIfPresent(String.self, forKey: .scene)
        custom = try container.decodeIfPresent(String.self, forKey: .custom)
        customTags = try container.decodeIfPresent([String].self, forKey: .customTags) ?? []
        source = try container.decodeIfPresent(StationSource.self, forKey: .source) ?? .bundled
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stableIdentifier, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(type, forKey: .type)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(style1, forKey: .style1)
        try container.encodeIfPresent(style2, forKey: .style2)
        try container.encodeIfPresent(scene, forKey: .scene)
        try container.encodeIfPresent(custom, forKey: .custom)
        try container.encode(customTags, forKey: .customTags)
        try container.encode(source, forKey: .source)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(lastHealth, forKey: .lastHealth)
    }
}

/// 内置频道用户覆盖层条目：仅持久化用户允许修改的字段，避免污染原始 JSON。
struct BundledStationOverride: Codable, Equatable {
    var stationId: String
    var name: String?
    var url: URL?
    var type: StationType?
    var customTags: [String]?

    /// 把覆盖项应用到原始 station 上，返回合并后的副本。
    func apply(to base: Station) -> Station {
        var merged = base
        if let name { merged.name = name }
        if let url { merged.url = url }
        if let type { merged.type = type }
        if let customTags { merged.customTags = customTags }
        return merged
    }
}
