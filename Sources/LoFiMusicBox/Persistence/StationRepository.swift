import Foundation

/// 频道仓储，统一管理三层数据：
/// 1. 原始内置频道：随 App 分发的只读资源（`BundledStations.json`）。
/// 2. 用户覆盖与隐藏：保存到 Application Support 目录，App 升级不会丢失。
///    - `bundled-overrides.json`：对内置频道的字段修改（名称/URL/类型/标签）。
///    - `hidden-bundled-ids.json`：被用户隐藏的内置频道 ID 列表。
///    - `favorite-station-ids.json`：用户收藏的频道 ID 列表。
/// 3. 用户自定义频道：保存到 `custom-stations.json`，可任意增删改。
///
/// 可用性检测结果保存在独立的 `station-health.json` 中，按 `stableIdentifier` 索引，
/// 加载后会注入到对应 station 的 `lastHealth` 字段，供 UI 直接读取。
@MainActor
final class StationRepository: ObservableObject {
    /// 已经应用了用户覆盖层的内置频道（不含被隐藏的过滤）。
    @Published private(set) var bundledStations: [Station] = []
    /// 用户自定义频道。
    @Published private(set) var customStations: [Station] = []
    /// 被用户隐藏的内置频道 ID 集合。
    @Published private(set) var hiddenBundledStationIds: Set<String> = []
    /// 用户收藏的频道 ID 集合。
    @Published private(set) var favoriteStationIds: Set<String> = []
    /// 加载或保存过程中的错误描述（仅最近一条），UI 可订阅展示。
    @Published private(set) var loadError: String?

    var dataDirectoryURL: URL {
        customStationsURL.deletingLastPathComponent()
    }

    /// 给播放层和列表 UI 使用的最终可见频道（不包含隐藏的，且 isEnabled）。
    var stations: [Station] {
        let visibleBundled = bundledStations.filter {
            !hiddenBundledStationIds.contains($0.id) && $0.isEnabled
        }
        return visibleBundled + customStations.filter(\.isEnabled)
    }

    /// 给“频道管理”页面使用的全量列表，包括被隐藏的内置频道。
    var allStationsIncludingHidden: [Station] {
        bundledStations + customStations
    }

    func station(matching identifier: String?) -> Station? {
        guard let identifier else { return nil }
        return allStationsIncludingHidden.first { $0.id == identifier }
    }

    func isHidden(stationId: String) -> Bool {
        hiddenBundledStationIds.contains(stationId)
    }

    func hasBundledOverride(stationId: String) -> Bool {
        bundledOverrides.contains { $0.stationId == stationId }
    }

    func isFavorite(stationId: String) -> Bool {
        favoriteStationIds.contains(stationId)
    }

    func toggleFavorite(stationId: String) {
        if favoriteStationIds.contains(stationId) {
            favoriteStationIds.remove(stationId)
        } else {
            favoriteStationIds.insert(stationId)
        }
        saveFavoriteStationIds()
    }

    /// 内置频道的“出厂版本”（未应用任何覆盖），用于“恢复默认”和差异计算。
    func originalBundledStation(stationId: String) -> Station? {
        originalBundledStationsById[stationId]
    }

    // MARK: - 自定义频道

    func addCustomStation(_ station: Station) {
        var customStation = station
        customStation.source = .custom
        if !customStation.stableIdentifier.hasPrefix(AppConstants.Resource.customStationIdPrefix) {
            customStation.stableIdentifier =
                AppConstants.Resource.customStationIdPrefix + UUID().uuidString
        }
        customStations.append(customStation)
        saveCustomStations()
    }

    func updateCustomStation(_ station: Station) {
        guard station.source == .custom else { return }
        guard let index = customStations.firstIndex(where: { $0.id == station.id }) else { return }
        customStations[index] = station
        saveCustomStations()
    }

    func deleteCustomStation(_ station: Station) {
        guard station.source == .custom else { return }
        customStations.removeAll { $0.id == station.id }
        // 自定义频道删除后，相关可用性检测记录也清掉。
        healthRecords.removeValue(forKey: station.id)
        favoriteStationIds.remove(station.id)
        saveCustomStations()
        saveHealthRecords()
        saveFavoriteStationIds()
    }

    func exportCustomStations(to url: URL) throws {
        let stationsToExport = customStations.map { station -> Station in
            var copy = station
            copy.source = .custom
            copy.lastHealth = nil
            return copy
        }
        let data = try encoder.encode(stationsToExport)
        try data.write(to: url, options: .atomic)
    }

    func importCustomStations(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let importedStations = try decoder.decode([Station].self, from: data)

        var seenStationIds: Set<String> = []
        customStations = importedStations.map { station in
            normalizedCustomStation(from: station, seenStationIds: &seenStationIds)
        }

        let importedIds = Set(customStations.map(\.id))
        healthRecords = healthRecords.filter { importedIds.contains($0.key) || originalBundledStationsById[$0.key] != nil }
        favoriteStationIds = favoriteStationIds.filter { importedIds.contains($0) || originalBundledStationsById[$0] != nil }
        saveCustomStations()
        saveHealthRecords()
        saveFavoriteStationIds()
    }

    // MARK: - 内置频道覆盖与隐藏

    /// 把用户对内置频道的修改写入覆盖层。会自动只保存与原始版本不同的字段，
    /// 这样后续若 App 出厂版本更新，未被用户改动的字段仍能跟随升级。
    func applyOverrideToBundledStation(updated: Station) {
        guard updated.source == .bundled,
              let original = originalBundledStationsById[updated.id]
        else { return }

        var override = BundledStationOverride(stationId: updated.id)
        if updated.name != original.name { override.name = updated.name }
        if updated.url != original.url { override.url = updated.url }
        if updated.type != original.type { override.type = updated.type }
        if updated.customTags != original.customTags { override.customTags = updated.customTags }

        let isNoChange = override.name == nil
            && override.url == nil
            && override.type == nil
            && override.customTags == nil

        bundledOverrides.removeAll { $0.stationId == updated.id }
        if !isNoChange {
            bundledOverrides.append(override)
        }
        saveBundledOverrides()
        recomputeBundledStations()
    }

    /// 还原内置频道为出厂版本（移除该 ID 的所有覆盖项）。
    func resetBundledStation(stationId: String) {
        bundledOverrides.removeAll { $0.stationId == stationId }
        saveBundledOverrides()
        recomputeBundledStations()
    }

    func hideBundledStation(stationId: String) {
        hiddenBundledStationIds.insert(stationId)
        saveHiddenBundledIds()
    }

    func unhideBundledStation(stationId: String) {
        hiddenBundledStationIds.remove(stationId)
        saveHiddenBundledIds()
    }

    // MARK: - 可用性检测记录

    func updateHealth(for station: Station, health: StationHealth) {
        healthRecords[station.id] = health

        if let index = bundledStations.firstIndex(where: { $0.id == station.id }) {
            bundledStations[index].lastHealth = health
        }
        if let index = customStations.firstIndex(where: { $0.id == station.id }) {
            customStations[index].lastHealth = health
        }

        saveHealthRecords()
    }

    // MARK: - 内部状态

    private var bundledOverrides: [BundledStationOverride] = []
    private var originalBundledStationsById: [String: Station] = [:]
    private var healthRecords: [String: StationHealth] = [:]

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let fileManager: FileManager

    private let customStationsURL: URL
    private let bundledOverridesURL: URL
    private let hiddenBundledIdsURL: URL
    private let favoriteStationIdsURL: URL
    private let stationHealthURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let supportDirectory = Self.makeApplicationSupportDirectory(fileManager: fileManager)
        customStationsURL = supportDirectory
            .appendingPathComponent(AppConstants.Resource.customStationsFileName)
        bundledOverridesURL = supportDirectory
            .appendingPathComponent(AppConstants.Resource.bundledOverridesFileName)
        hiddenBundledIdsURL = supportDirectory
            .appendingPathComponent(AppConstants.Resource.hiddenBundledIdsFileName)
        favoriteStationIdsURL = supportDirectory
            .appendingPathComponent(AppConstants.Resource.favoriteStationIdsFileName)
        stationHealthURL = supportDirectory
            .appendingPathComponent(AppConstants.Resource.stationHealthFileName)

        loadOriginalBundledStations()
        loadBundledOverrides()
        loadHiddenBundledIds()
        loadFavoriteStationIds()
        loadCustomStations()
        loadHealthRecords()
        recomputeBundledStations()
        injectHealthIntoCustomStations()
    }

    // MARK: - 加载

    private func loadOriginalBundledStations() {
        guard let url = AppResourceBundle.bundle.url(
            forResource: AppConstants.Resource.bundledStationsFileName,
            withExtension: AppConstants.Resource.jsonFileExtension
        ) else {
            loadError = "未找到内置频道资源文件"
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let raw = try decoder.decode([Station].self, from: data).map { station -> Station in
                var station = station
                station.source = .bundled
                if !station.stableIdentifier.hasPrefix(AppConstants.Resource.bundledStationIdPrefix) {
                    // 没有显式 ID 的旧 JSON，按名称生成可重复的稳定 ID。
                    let slug = station.name
                        .lowercased()
                        .replacingOccurrences(of: " ", with: "-")
                    station.stableIdentifier =
                        AppConstants.Resource.bundledStationIdPrefix + slug
                }
                return station
            }
            originalBundledStationsById = Dictionary(uniqueKeysWithValues: raw.map { ($0.id, $0) })
        } catch {
            loadError = "读取内置频道失败：\(error.localizedDescription)"
        }
    }

    private func loadBundledOverrides() {
        guard fileManager.fileExists(atPath: bundledOverridesURL.path) else { return }
        do {
            let data = try Data(contentsOf: bundledOverridesURL)
            bundledOverrides = try decoder.decode([BundledStationOverride].self, from: data)
        } catch {
            loadError = "读取内置频道覆盖层失败：\(error.localizedDescription)"
            bundledOverrides = []
        }
    }

    private func loadHiddenBundledIds() {
        guard fileManager.fileExists(atPath: hiddenBundledIdsURL.path) else { return }
        do {
            let data = try Data(contentsOf: hiddenBundledIdsURL)
            let array = try decoder.decode([String].self, from: data)
            hiddenBundledStationIds = Set(array)
        } catch {
            loadError = "读取隐藏频道列表失败：\(error.localizedDescription)"
            hiddenBundledStationIds = []
        }
    }

    private func loadFavoriteStationIds() {
        guard fileManager.fileExists(atPath: favoriteStationIdsURL.path) else { return }
        do {
            let data = try Data(contentsOf: favoriteStationIdsURL)
            let array = try decoder.decode([String].self, from: data)
            favoriteStationIds = Set(array)
        } catch {
            loadError = "读取收藏频道列表失败：\(error.localizedDescription)"
            favoriteStationIds = []
        }
    }

    private func loadCustomStations() {
        guard fileManager.fileExists(atPath: customStationsURL.path) else { return }
        do {
            let data = try Data(contentsOf: customStationsURL)
            customStations = try decoder.decode([Station].self, from: data).map { station -> Station in
                var station = station
                station.source = .custom
                if !station.stableIdentifier.hasPrefix(AppConstants.Resource.customStationIdPrefix) {
                    station.stableIdentifier =
                        AppConstants.Resource.customStationIdPrefix + UUID().uuidString
                }
                return station
            }
        } catch {
            loadError = "读取自定义频道失败：\(error.localizedDescription)"
            customStations = []
        }
    }

    private func loadHealthRecords() {
        guard fileManager.fileExists(atPath: stationHealthURL.path) else { return }
        do {
            let data = try Data(contentsOf: stationHealthURL)
            healthRecords = try decoder.decode([String: StationHealth].self, from: data)
        } catch {
            loadError = "读取可用性检测记录失败：\(error.localizedDescription)"
            healthRecords = [:]
        }
    }

    // MARK: - 写盘

    private func saveCustomStations() {
        do {
            try ensureSupportDirectoryExists()
            let stationsToSave = customStations.map { station -> Station in
                var copy = station
                copy.lastHealth = nil // 可用性检测记录写到独立文件，避免重复。
                return copy
            }
            let data = try encoder.encode(stationsToSave)
            try data.write(to: customStationsURL, options: .atomic)
        } catch {
            loadError = "保存自定义频道失败：\(error.localizedDescription)"
        }
    }

    private func saveBundledOverrides() {
        do {
            try ensureSupportDirectoryExists()
            let data = try encoder.encode(bundledOverrides)
            try data.write(to: bundledOverridesURL, options: .atomic)
        } catch {
            loadError = "保存内置频道覆盖层失败：\(error.localizedDescription)"
        }
    }

    private func saveHiddenBundledIds() {
        do {
            try ensureSupportDirectoryExists()
            let data = try encoder.encode(Array(hiddenBundledStationIds).sorted())
            try data.write(to: hiddenBundledIdsURL, options: .atomic)
        } catch {
            loadError = "保存隐藏频道列表失败：\(error.localizedDescription)"
        }
    }

    private func saveFavoriteStationIds() {
        do {
            try ensureSupportDirectoryExists()
            let data = try encoder.encode(Array(favoriteStationIds).sorted())
            try data.write(to: favoriteStationIdsURL, options: .atomic)
        } catch {
            loadError = "保存收藏频道列表失败：\(error.localizedDescription)"
        }
    }

    private func saveHealthRecords() {
        do {
            try ensureSupportDirectoryExists()
            let data = try encoder.encode(healthRecords)
            try data.write(to: stationHealthURL, options: .atomic)
        } catch {
            loadError = "保存可用性检测记录失败：\(error.localizedDescription)"
        }
    }

    private func ensureSupportDirectoryExists() throws {
        let directory = customStationsURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - 合并计算

    private func recomputeBundledStations() {
        let overridesById = Dictionary(uniqueKeysWithValues: bundledOverrides.map { ($0.stationId, $0) })
        let merged = originalBundledStationsById.values
            .sorted(by: { $0.name.localizedCompare($1.name) == .orderedAscending }) // 默认按名称排序
            .map { original -> Station in
                var station = original
                if let override = overridesById[original.id] {
                    station = override.apply(to: station)
                }
                station.lastHealth = healthRecords[station.id]
                return station
            }
        // 但我们希望内置频道保持 BundledStations.json 中的原始顺序而非按字典排序，
        // 因此回到原始 JSON 中的顺序：
        bundledStations = preservingOriginalOrder(of: merged)
    }

    private func preservingOriginalOrder(of merged: [Station]) -> [Station] {
        let mergedById = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
        guard let url = AppResourceBundle.bundle.url(
            forResource: AppConstants.Resource.bundledStationsFileName,
            withExtension: AppConstants.Resource.jsonFileExtension
        ),
        let data = try? Data(contentsOf: url),
        let originalArray = try? decoder.decode([Station].self, from: data) else {
            return merged
        }
        return originalArray.compactMap { raw -> Station? in
            // raw.id 可能不带稳定 ID（极旧的 JSON），fallback 跟 loadOriginalBundledStations 同逻辑。
            var resolvedId = raw.stableIdentifier
            if !resolvedId.hasPrefix(AppConstants.Resource.bundledStationIdPrefix) {
                let slug = raw.name.lowercased().replacingOccurrences(of: " ", with: "-")
                resolvedId = AppConstants.Resource.bundledStationIdPrefix + slug
            }
            return mergedById[resolvedId]
        }
    }

    private func injectHealthIntoCustomStations() {
        for index in customStations.indices {
            let id = customStations[index].id
            customStations[index].lastHealth = healthRecords[id]
        }
    }

    private func normalizedCustomStation(from station: Station, seenStationIds: inout Set<String>) -> Station {
        var station = station
        station.source = .custom
        station.lastHealth = nil

        if !station.stableIdentifier.hasPrefix(AppConstants.Resource.customStationIdPrefix)
            || seenStationIds.contains(station.stableIdentifier) {
            station.stableIdentifier = AppConstants.Resource.customStationIdPrefix + UUID().uuidString
        }
        seenStationIds.insert(station.stableIdentifier)
        return station
    }

    private static func makeApplicationSupportDirectory(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        return baseURL
            .appendingPathComponent(AppConstants.Identity.applicationSupportDirectoryName, isDirectory: true)
    }
}
