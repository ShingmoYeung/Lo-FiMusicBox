import Foundation

/// 把哔哩哔哩直播间页面地址解析为可被 `AVPlayer` 原生播放的 HLS(m3u8) 直链。
///
/// **为什么需要它**：B 站直播不是一个固定的音视频文件，而是网页里用 flv.js(MSE)
/// 播放的 HTTP-FLV 流。原生 `AVPlayer` 不支持 HTTP-FLV，但 B 站同时提供 HLS(fmp4/ts)，
/// `AVPlayer` 原生支持 HLS。因此"解析直播间 → 取 HLS → 交给 AVPlayer"比内嵌 WebView 更稳定、
/// 更省资源，也契合应用的原生体验目标。
///
/// **解析链路**（实测无需登录 / cookie / wbi 签名）：
/// 1. `room_init?id=<入口号>` → 拿真实 `room_id` 与 `live_status`；
/// 2. `getRoomPlayInfo(protocol=0,1&format=0,1,2&codec=0,1)` → 拿 `playurl`；
/// 3. 在 `http_hls` 协议里优先挑 `fmp4 + avc`（AVPlayer 兼容最好），
///    回退 `ts + avc`，再回退任意 HLS 流；
/// 4. 拼接 `host + base_url + extra` 得到完整 m3u8 直链。
struct BilibiliStreamResolver {
    /// 解析过程中可能出现的错误，均带中文描述，便于在 UI/检测里直接展示。
    enum ResolveError: LocalizedError {
        case invalidRoomURL
        case roomNotLive
        case noPlayableStream
        case badResponse

        var errorDescription: String? {
            switch self {
            case .invalidRoomURL: LocalizedStrings.text("station.health.message.bilibili.invalid_room")
            case .roomNotLive: LocalizedStrings.text("station.health.message.bilibili.room_not_live")
            case .noPlayableStream: LocalizedStrings.text("station.health.message.bilibili.no_stream")
            case .badResponse: LocalizedStrings.text("station.health.message.bilibili.bad_response")
            }
        }
    }

    /// 解析结果。
    struct Resolved {
        /// 可直接交给 AVPlayer 的 HLS 直链。
        var hlsURL: URL
        /// 真实房间号（便于日志/复用）。
        var roomID: Int
    }

    var session: URLSession = .shared

    /// 把直播间入口地址解析为 HLS 直链。
    func resolve(roomEntry url: URL) async throws -> Resolved {
        let entryID = try Self.extractRoomID(from: url)
        let roomInfo = try await fetchRoomInit(entryID: entryID)
        guard roomInfo.liveStatus == AppConstants.Bilibili.liveStatusLive else {
            throw ResolveError.roomNotLive
        }
        let hlsURL = try await fetchHLS(roomID: roomInfo.roomID)
        return Resolved(hlsURL: hlsURL, roomID: roomInfo.roomID)
    }

    /// 从直播间 URL 中提取房间号：取路径里的第一段纯数字，例如
    /// `https://live.bilibili.com/27519423?...` → `27519423`。
    static func extractRoomID(from url: URL) throws -> Int {
        for segment in url.path.split(separator: "/") {
            if let id = Int(segment) {
                return id
            }
        }
        throw ResolveError.invalidRoomURL
    }

    /// 第 1 步：room_init 拿真实房间号与开播状态。
    private func fetchRoomInit(entryID: Int) async throws -> (roomID: Int, liveStatus: Int) {
        var components = URLComponents(string: AppConstants.Bilibili.roomInitAPI)!
        components.queryItems = [URLQueryItem(name: "id", value: String(entryID))]
        let data = try await get(components.url!)

        let root = try JSONDecoder.bilibili.decode(BiliRoomInitRoot.self, from: data)
        guard root.code == 0, let info = root.data else {
            throw ResolveError.badResponse
        }
        return (info.roomID, info.liveStatus)
    }

    /// 第 2 步：getRoomPlayInfo 拿 playurl，并挑出最合适的 HLS 直链。
    private func fetchHLS(roomID: Int) async throws -> URL {
        var components = URLComponents(string: AppConstants.Bilibili.playInfoAPI)!
        components.queryItems = [
            URLQueryItem(name: "room_id", value: String(roomID)),
            URLQueryItem(name: "protocol", value: AppConstants.Bilibili.protocolParameter),
            URLQueryItem(name: "format", value: AppConstants.Bilibili.formatParameter),
            URLQueryItem(name: "codec", value: AppConstants.Bilibili.codecParameter),
            URLQueryItem(name: "qn", value: String(AppConstants.Bilibili.preferredQuality)),
            URLQueryItem(name: "platform", value: AppConstants.Bilibili.platformParameter),
            URLQueryItem(name: "ptype", value: AppConstants.Bilibili.pageTypeParameter)
        ]
        let data = try await get(components.url!)

        let root = try JSONDecoder.bilibili.decode(BiliPlayInfoRoot.self, from: data)
        guard root.code == 0,
              let playurl = root.data?.playurlInfo?.playurl else {
            throw ResolveError.badResponse
        }
        guard let url = Self.selectHLS(from: playurl) else {
            throw ResolveError.noPlayableStream
        }
        return url
    }

    /// 从 playurl 中选出最合适的 HLS 直链：
    /// 优先 `fmp4 + avc` → 回退 `ts + avc` → 再回退任意 HLS 编码的第一条。
    static func selectHLS(from playurl: BiliPlayURL) -> URL? {
        guard let hls = playurl.stream.first(
            where: { $0.protocolName == AppConstants.Bilibili.hlsProtocolName }
        ) else {
            return nil
        }

        func makeURL(_ codec: BiliCodec) -> URL? {
            guard let info = codec.urlInfo.first else { return nil }
            return URL(string: info.host + codec.baseUrl + info.extra)
        }

        func pick(format formatName: String, codec codecName: String) -> URL? {
            guard let format = hls.format.first(where: { $0.formatName == formatName }),
                  let codec = format.codec.first(where: { $0.codecName == codecName }) else {
                return nil
            }
            return makeURL(codec)
        }

        if let url = pick(
            format: AppConstants.Bilibili.preferredFormatName,
            codec: AppConstants.Bilibili.preferredCodecName
        ) {
            return url
        }
        if let url = pick(
            format: AppConstants.Bilibili.fallbackFormatName,
            codec: AppConstants.Bilibili.preferredCodecName
        ) {
            return url
        }
        for format in hls.format {
            for codec in format.codec {
                if let url = makeURL(codec) {
                    return url
                }
            }
        }
        return nil
    }

    /// 统一的 GET 请求：带桌面 UA 与 Referer，校验 2xx。
    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(
            url: url,
            timeoutInterval: AppConstants.Bilibili.requestTimeoutSeconds
        )
        request.setValue(
            AppConstants.Bilibili.webUserAgent,
            forHTTPHeaderField: AppConstants.Bilibili.userAgentHeaderName
        )
        request.setValue(
            AppConstants.Bilibili.refererValue,
            forHTTPHeaderField: AppConstants.Bilibili.refererHeaderName
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw ResolveError.badResponse
        }
        return data
    }
}

private extension JSONDecoder {
    /// 统一用 snake_case → camelCase，省去逐字段写 CodingKeys。
    static var bilibili: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

// MARK: - 接口响应模型（仅声明用得到的字段）

private struct BiliRoomInitRoot: Decodable {
    let code: Int
    let data: BiliRoomInitData?
}

private struct BiliRoomInitData: Decodable {
    let roomID: Int
    let liveStatus: Int

    enum CodingKeys: String, CodingKey {
        // room_id 经 convertFromSnakeCase 变成 roomId，这里显式映射到 roomID 以符合命名习惯。
        case roomID = "roomId"
        case liveStatus
    }
}

private struct BiliPlayInfoRoot: Decodable {
    let code: Int
    let data: BiliPlayInfoData?
}

private struct BiliPlayInfoData: Decodable {
    let playurlInfo: BiliPlayURLInfo?
}

private struct BiliPlayURLInfo: Decodable {
    let playurl: BiliPlayURL?
}

struct BiliPlayURL: Decodable {
    let stream: [BiliStream]
}

struct BiliStream: Decodable {
    let protocolName: String
    let format: [BiliFormat]
}

struct BiliFormat: Decodable {
    let formatName: String
    let codec: [BiliCodec]
}

struct BiliCodec: Decodable {
    let codecName: String
    let baseUrl: String
    let urlInfo: [BiliURLInfo]
}

struct BiliURLInfo: Decodable {
    let host: String
    let extra: String
}
